// End-to-end test wallet exists only in this Node test harness. No signer is shipped to the application.
import assert from 'node:assert/strict';
import { chromium, expect, type Page } from '@playwright/test';
import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  publicClient,
  manifest,
  assertDeployment,
  assertLoopback,
  artifact,
  accounts,
  send,
  read,
  root,
} from './local.js';
let m = manifest();
const baseUrl = (process.env.E2E_BASE_URL ?? 'http://127.0.0.1:5173').replace(/\/$/, '');
assertLoopback(baseUrl);
await assertDeployment(m);
const snapshot = await publicClient.request({ method: 'evm_snapshot' as never });
const original = readFileSync(resolve(root, 'local/deployments/local.json'), 'utf8');
const originalFrontend = readFileSync(
  resolve(root, '../frontend/src/generated/deployment.json'),
  'utf8',
);
const browser = await chromium.launch({ headless: true });
const failures: string[] = [];
async function open(role: keyof typeof m.accounts, route = '/overview') {
  const address = m.accounts[role];
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  await context.exposeBinding(
    'localWalletRpc',
    async (_, payload: { method: string; params?: unknown[] }) => {
      if (['eth_requestAccounts', 'eth_accounts'].includes(payload.method)) return [address];
      if (payload.method === 'wallet_requestPermissions')
        return [{ parentCapability: 'eth_accounts' }];
      if (['wallet_switchEthereumChain', 'wallet_addEthereumChain'].includes(payload.method))
        return null;
      if (payload.method === 'eth_sendTransaction') {
        const tx = payload.params?.[0] as { from?: string };
        assert.equal(tx.from?.toLowerCase(), address.toLowerCase());
      }
      return publicClient.request({
        method: payload.method as never,
        params: payload.params as never,
      });
    },
  );
  await context.addInitScript({
    content: `window.ethereum={isMetaMask:true,isConnected:()=>true,request:(payload)=>window.localWalletRpc(payload),on(){},removeListener(){}};`,
  });
  const page = await context.newPage();
  page.on('pageerror', (e) => {
    failures.push(e.message);
    console.error('Browser error:', e.message);
  });
  page.on('console', (message) => {
    if (message.type() === 'error') console.error('Browser console:', message.text());
  });
  await page.goto(`${baseUrl}${route}`);
  const connectButton = page.getByRole('button', { name: '连接钱包', exact: true });
  await expect(
    connectButton.or(page.getByRole('button', { name: /0x[0-9a-fA-F]{4}…/ })),
  ).toBeVisible();
  if (await connectButton.isVisible()) await connectButton.click();
  await expect(page.getByRole('button', { name: /0x[0-9a-fA-F]{4}…/ })).toBeVisible();
  await expect(page.getByText('正在验证合约并读取链上状态…')).not.toBeVisible();
  return { page, context };
}
async function confirmed(page: Page, label: string) {
  await expect(page.getByRole('status').filter({ hasText: label })).toContainText('交易已确认', {
    timeout: 30000,
  });
}
async function submitModal(page: Page) {
  await page.getByRole('button', { name: '确认执行', exact: true }).click();
}
try {
  if (process.argv.includes('--bootstrap')) {
    const deploy = spawn(
      process.execPath,
      [
        '--import',
        'tsx',
        resolve(root, 'local/tools/deploy-local.ts'),
        '--uninitialized',
        '--reset-confirmed',
      ],
      { cwd: root, stdio: 'inherit' },
    );
    const code = await new Promise<number | null>((resolve) => deploy.on('exit', resolve));
    assert.equal(code, 0);
    m = manifest();
    await assertDeployment(m);
  }
  const vaultAbi = artifact('AdaptiveLPVault').abi,
    controlAbi = artifact('VaultControl').abi;
  if (!(await read(m.vault, vaultAbi, 'initialized'))) {
    const manager = await open('manager', '/manager');
    await manager.page.getByRole('button', { name: '执行 Bootstrap', exact: true }).click();
    await submitModal(manager.page);
    await confirmed(manager.page, '初始化 Vault');
    assert.equal(await read(m.vault, vaultAbi, 'initialized'), true);
    await manager.context.close();
    console.log('PASS 初始化前模式与浏览器三笔交易完成 Bootstrap');
  }
  const user = await open('user', '/portfolio');
  const p = user.page;
  for (const symbol of [m.symbol0, m.symbol1]) {
    await p.getByRole('button', { name: `授权 ${symbol}`, exact: true }).click();
    await confirmed(p, `授权 ${symbol}`);
  }
  await p.getByRole('button', { name: '预览存款', exact: true }).click();
  await expect(p.getByText(/模拟获得/)).toBeVisible();
  const before = await read(m.vault, vaultAbi, 'balanceOf', [m.accounts.user]);
  await p.getByRole('button', { name: '确认存款', exact: true }).click();
  await confirmed(p, '存款');
  const after = await read(m.vault, vaultAbi, 'balanceOf', [m.accounts.user]);
  assert(after > before);
  console.log('PASS 浏览器钱包双资产授权、预览和存款');
  // Every configured market must execute real swaps; no oracle override or pool mock.
  const positionsBefore = await read(m.adapters[1], artifact('UniswapV3Adapter').abi, 'snapshot');
  const child = spawn(
    process.execPath,
    [
      '--import',
      'tsx',
      resolve(root, 'local/simulator/index.ts'),
      '--rounds',
      '4',
      '--interval',
      '500',
    ],
    { cwd: root, stdio: 'inherit' },
  );
  const exit = await new Promise<number | null>((resolve) => child.on('exit', resolve));
  assert.equal(exit, 0);
  const positionsAfter = await read(m.adapters[1], artifact('UniswapV3Adapter').abi, 'snapshot');
  assert(
    positionsAfter.claimableFee0 > positionsBefore.claimableFee0 ||
      positionsAfter.claimableFee1 > positionsBefore.claimableFee1,
  );
  console.log('PASS 真实持续 Swap 与活跃 V3 仓位费用增长');
  await p.getByRole('tab', { name: '赎回资产' }).click();
  await p.getByRole('button', { name: '预览赎回', exact: true }).click();
  await expect(p.getByText(/模拟收到/)).toBeVisible();
  await p.getByRole('button', { name: '确认赎回', exact: true }).click();
  await confirmed(p, '赎回');
  assert((await read(m.vault, vaultAbi, 'balanceOf', [m.accounts.user])) < after);
  await p.getByRole('button', { name: '策略再平衡', exact: true }).click();
  await p.getByRole('button', { name: '刷新计划预览' }).click();
  await expect(p.getByText(/当前无需调整仓位|候选版本/)).toBeVisible();
  console.log('PASS 双资产赎回与手动策略预览');
  // Real emergency exit followed by Manager recovery gives a valid no-swap re-entry plan.
  await send(2, m.vault, vaultAbi, 'emergencyExitToIdle');
  await send(2, m.control, controlAbi, 'setPauseState', [
    { depositPaused: false, plainRebalancePaused: false, swapRebalancePaused: false },
  ]);
  await p.getByRole('button', { name: '刷新计划预览' }).click();
  await expect(p.getByRole('button', { name: '执行普通再平衡', exact: true })).toBeEnabled({
    timeout: 15000,
  });
  await p.getByRole('button', { name: '执行普通再平衡', exact: true }).click();
  await confirmed(p, '普通再平衡');
  assert.equal(Number(await read(m.vault, vaultAbi, 'activeVenue')), 2);
  console.log('PASS 浏览器手动执行真实普通再平衡');
  await user.context.close();
  const admin = await open('admin', '/admin');
  await expect(admin.page.getByRole('button', { name: '运行管理', exact: true })).not.toBeVisible();
  const grant = admin.page
    .locator('.ant-card')
    .filter({ has: admin.page.getByText('授予业务角色', { exact: true }) })
    .first();
  await grant.getByLabel('目标钱包地址').fill(m.accounts.user);
  await grant.getByRole('button', { name: '授予角色', exact: true }).click();
  await confirmed(admin.page, '授予业务角色');
  const keeperRole = await read(m.control, controlAbi, 'KEEPER_ROLE');
  assert(await read(m.control, controlAbi, 'hasRole', [keeperRole, m.accounts.user]));
  const revoke = admin.page
    .locator('.ant-card')
    .filter({ has: admin.page.getByText('撤销业务角色', { exact: true }) })
    .first();
  await revoke.getByLabel('目标钱包地址').fill(m.accounts.user);
  await revoke.getByRole('button', { name: '撤销角色', exact: true }).click();
  await submitModal(admin.page);
  await confirmed(admin.page, '撤销业务角色');
  assert.equal(await read(m.control, controlAbi, 'hasRole', [keeperRole, m.accounts.user]), false);
  console.log('PASS 根管理员角色授撤与业务权限隔离');
  await admin.context.close();
  const guardian = await open('guardian', '/guardian');
  const checkbox = guardian.page.getByRole('checkbox', { name: '暂停存款', exact: true });
  await checkbox.check();
  await guardian.page.getByRole('button', { name: '提交暂停状态' }).click();
  await confirmed(guardian.page, '更新暂停状态');
  await expect(checkbox).toBeDisabled();
  await guardian.page.getByRole('button', { name: '紧急退出并暂停' }).click();
  await submitModal(guardian.page);
  await confirmed(guardian.page, '紧急退出');
  assert.equal(Number(await read(m.vault, vaultAbi, 'activeVenue')), 0);
  console.log('PASS Guardian 单向暂停与紧急退出');
  await guardian.context.close();
  const exitUser = await open('user', '/portfolio');
  await exitUser.page.getByRole('tab', { name: '赎回资产' }).click();
  await exitUser.page.getByRole('button', { name: '预览赎回', exact: true }).click();
  await expect(exitUser.page.getByText(/模拟收到/)).toBeVisible();
  await exitUser.page.getByRole('button', { name: '确认赎回', exact: true }).click();
  await confirmed(exitUser.page, '赎回');
  console.log('PASS 暂停且 IDLE 状态下仍能正常赎回');
  await exitUser.context.close();
  const manager = await open('manager', '/manager');
  await expect(
    manager.page.getByRole('button', { name: '启用', exact: true }).first(),
  ).toBeVisible();
  await manager.page.setViewportSize({ width: 390, height: 844 });
  await expect(manager.page.getByRole('heading', { name: '运行管理' })).toBeVisible();
  // Ant Design's breakpoint subscription updates asynchronously after a viewport change.
  // Require the same no-overflow invariant after the responsive layout has settled.
  try {
    await expect
      .poll(
        () =>
          manager.page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
        { timeout: 5000 },
      )
      .toBe(true);
  } catch (error) {
    console.error(
      '移动端布局诊断',
      await manager.page.evaluate(() => ({
        viewport: window.innerWidth,
        documentWidth: document.documentElement.scrollWidth,
        overflowing: [...document.querySelectorAll('main *')]
          .filter((element) => element.getBoundingClientRect().right > window.innerWidth)
          .slice(0, 8)
          .map((element) => ({
            tag: element.tagName,
            className: element.className,
            right: element.getBoundingClientRect().right,
          })),
      })),
    );
    throw error;
  }
  await manager.context.close();
  assert.deepEqual(failures, []);
  console.log('PASS Manager 页面、移动端布局及无浏览器运行时异常');
} finally {
  await browser.close();
  await publicClient.request({ method: 'evm_revert' as never, params: [snapshot] as never });
  writeFileSync(resolve(root, 'local/deployments/local.json'), original);
  writeFileSync(resolve(root, '../frontend/src/generated/deployment.json'), originalFrontend);
  console.log('已恢复端到端测试前的本地链快照和部署配置。');
}
