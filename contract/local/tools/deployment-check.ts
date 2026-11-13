// Isolated real-broadcast regression. Never resets the developer's existing Anvil instance.
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import {
  existsSync,
  readFileSync,
  writeFileSync,
  unlinkSync,
  mkdtempSync,
  chmodSync,
  rmSync,
} from 'node:fs';
import { createServer } from 'node:net';
import { resolve, delimiter } from 'node:path';
import { tmpdir } from 'node:os';
import { setTimeout } from 'node:timers/promises';
import { createPublicClient, http, erc20Abi } from 'viem';
import { foundry } from 'viem/chains';
import { root, accounts, artifact, type Manifest } from './local.js';

const browser = process.argv.includes('--browser');
async function freePort() {
  const server = createServer();
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  assert(address && typeof address !== 'string');
  await new Promise<void>((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
  return address.port;
}
const port = await freePort();
const rpc = `http://127.0.0.1:${port}`;
const client = createPublicClient({
  chain: foundry,
  transport: http(rpc, { retryCount: 0 }),
  pollingInterval: 100,
});
const manifests = [
  resolve(root, 'local/deployments/local.json'),
  resolve(root, '../frontend/src/generated/deployment.json'),
];
const originals = manifests.map((path) => (existsSync(path) ? readFileSync(path) : undefined));
const children: ChildProcess[] = [];
function launch(command: string, args: string[], cwd = root, env: NodeJS.ProcessEnv = {}) {
  const child = spawn(command, args, {
    cwd,
    env: { ...process.env, LOCAL_RPC_URL: rpc, ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  children.push(child);
  let output = '';
  child.stdout?.on('data', (data: Buffer) => {
    output += data.toString();
    process.stdout.write(data);
  });
  child.stderr?.on('data', (data: Buffer) => {
    output += data.toString();
    process.stderr.write(data);
  });
  const completed = new Promise<{ code: number | null; output: string }>((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code) => resolve({ code, output }));
  });
  // Long-lived services may fail before their completion is awaited.
  void completed.catch(() => {});
  return { child, completed };
}
async function run(file: string, args: string[] = [], success = true, env: NodeJS.ProcessEnv = {}) {
  const result = await launch(
    process.execPath,
    ['--import', 'tsx', resolve(root, file), ...args],
    root,
    env,
  ).completed;
  if (success) assert.equal(result.code, 0, `${file} failed`);
  else assert.notEqual(result.code, 0, `${file} should have failed`);
  return result;
}
async function ready(check: () => Promise<unknown>) {
  for (let i = 0; i < 100; i++) {
    try {
      if (await check()) return;
    } catch {
      /* startup */
    }
    await setTimeout(200);
  }
  throw new Error('临时测试服务启动超时');
}
async function verify(initialized: boolean) {
  const raw = readFileSync(manifests[0], 'utf8');
  assert.equal(readFileSync(manifests[1], 'utf8'), raw);
  const m: Manifest = JSON.parse(raw);
  const vaultAbi = artifact('AdaptiveLPVault').abi;
  const call = (functionName: string) =>
    client.readContract({ address: m.vault, abi: vaultAbi, functionName });
  assert.equal(await call('initialized'), initialized);
  assert.equal(await call('activeVenue'), initialized ? 2 : 0);
  const block = await client.getBlock({ blockNumber: BigInt(m.deploymentBlock) });
  assert.equal(block.hash, m.deploymentBlockHash);
  for (const account of accounts.slice(3)) {
    for (const [token, decimals] of [
      [m.token0, m.decimals0],
      [m.token1, m.decimals1],
    ] as const) {
      const balance = await client.readContract({
        address: token,
        abi: erc20Abi,
        functionName: 'balanceOf',
        args: [account.address],
      });
      assert.equal(balance, 100_000_000n * 10n ** BigInt(decimals));
    }
  }
  assert(m.bootstrapAmounts.every((v) => BigInt(v) > 0n));
  for (const key of ['PRIVATE_KEY', 'privateKey', 'mnemonic']) assert(!raw.includes(key));
  return m;
}
try {
  launch('anvil', [
    '--host',
    '127.0.0.1',
    '--port',
    String(port),
    '--chain-id',
    '31337',
    '--block-time',
    '1',
    '--silent',
  ]);
  await ready(async () => (await client.getChainId()) === 31337);
  await run('local/tools/deploy-local.ts');
  const first = await verify(true);
  const before = manifests.map((p) => readFileSync(p, 'utf8'));
  const nonce = await client.getTransactionCount({ address: accounts[0].address });
  const refused = await run('local/tools/deploy-local.ts', [], false);
  assert(refused.output.includes('部署账户已使用'));
  assert.equal(await client.getTransactionCount({ address: accounts[0].address }), nonce);
  assert.deepEqual(
    manifests.map((p) => readFileSync(p, 'utf8')),
    before,
  );
  console.log('PASS 默认真实广播、账户资金和重复部署保护');
  const failingBin = mkdtempSync(resolve(tmpdir(), 'adaptive-failing-forge-'));
  try {
    const executable = resolve(failingBin, 'forge');
    writeFileSync(executable, '#!/bin/sh\nprintf "intentional Foundry failure\\n" >&2\nexit 23\n');
    chmodSync(executable, 0o700);
    const failure = await run('local/tools/deploy-local.ts', ['--reset-confirmed'], false, {
      PATH: `${failingBin}${delimiter}${process.env.PATH ?? ''}`,
    });
    assert(failure.output.includes('阶段 prepare 失败'));
    assert(!failure.output.includes('阶段：preheat'));
    assert.equal(await client.getTransactionCount({ address: accounts[0].address }), nonce);
    assert.deepEqual(
      manifests.map((p) => readFileSync(p, 'utf8')),
      before,
    );
    console.log('PASS Foundry 子进程失败立即停止且保留旧公开清单');
  } finally {
    rmSync(failingBin, { recursive: true, force: true });
  }
  await run('local/tools/deploy-local.ts', ['--uninitialized', '--reset-confirmed']);
  const second = await verify(false);
  assert.notEqual(second.vault, first.vault);
  assert(await client.getCode({ address: first.vault }));
  console.log('PASS 显式新实例、未初始化模式和旧实例保留');
  await run('local/tools/deploy-local.ts', ['--reset-confirmed']);
  await verify(true);
  console.log('PASS 新实例通过共享 Bootstrap 脚本初始化');
  if (browser) {
    const webPort = await freePort();
    const base = `http://127.0.0.1:${webPort}`;
    launch(
      process.execPath,
      [
        resolve(root, '../node_modules/vite/bin/vite.js'),
        '--host',
        '127.0.0.1',
        '--port',
        String(webPort),
        '--strictPort',
        '--mode',
        'deployment-test',
      ],
      resolve(root, '../frontend'),
      { VITE_RPC_URL: rpc },
    );
    await ready(async () => (await fetch(base)).ok);
    const failures: unknown[] = [];
    for (const [file, args] of [
      ['local/tools/e2e.ts', []],
      ['local/tools/e2e.ts', ['--bootstrap']],
      ['local/tools/market-check.ts', []],
    ] as const) {
      try {
        await run(file, [...args], true, { E2E_BASE_URL: base });
      } catch (error) {
        failures.push(error);
      }
    }
    if (failures.length) throw new AggregateError(failures, '应用验收失败，详见各场景日志');
  }
} finally {
  for (const child of children) {
    if (child.exitCode !== null || child.signalCode !== null) continue;
    child.kill('SIGTERM');
    await new Promise<void>((resolve) => child.once('close', () => resolve()));
  }
  for (let i = 0; i < manifests.length; i++) {
    const original = originals[i];
    if (original) writeFileSync(manifests[i], original);
    else if (existsSync(manifests[i])) unlinkSync(manifests[i]);
  }
  console.log('已停止临时服务并恢复原有公开部署清单；开发者现有链未被修改。');
}
