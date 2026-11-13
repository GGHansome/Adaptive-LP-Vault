import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { erc20Abi, toHex } from 'viem';
import {
  root,
  rpc,
  accounts,
  roles,
  publicClient,
  assertAnvil,
  artifact,
  read,
  stringify,
  type Manifest,
} from './local.js';
import {
  deploymentOptions,
  runDeploymentStages,
  localEnvironment,
  protocolEnvironment,
  parseProtocol,
  parseVault,
  parseBootstrap,
  publishManifests,
} from './local-deployment.js';

const options = deploymentOptions(process.argv.slice(2));
await assertAnvil();
if (
  !options.resetConfirmed &&
  (await publicClient.getTransactionCount({ address: accounts[0].address })) > 0
)
  throw new Error(
    '部署账户已使用。请重启干净 Anvil，或显式传入 --reset-confirmed 创建新实例（不会删除旧实例）。',
  );
const start = await publicClient.getBlock();
mkdirSync(resolve(root, 'local/deployments'), { recursive: true });
const directory = mkdtempSync(resolve(root, 'local/deployments/.local-'));
const files = {
  protocol: resolve(directory, 'protocol.json'),
  vault: resolve(directory, 'vault.json'),
  bootstrap: resolve(directory, 'bootstrap.json'),
};
const keys = accounts.slice(0, 3).map((a) => toHex(a.getHdKey().privateKey!)) as [
  string,
  string,
  string,
];
const env = {
  ...process.env,
  FOUNDRY_BROADCAST: resolve(root, 'local/broadcast'),
  ...localEnvironment(
    accounts.map((a) => a.address),
    keys,
    files,
  ),
};
function json(path: string): unknown {
  return JSON.parse(readFileSync(path, 'utf8'));
}
async function forge(script: string, broadcast = true) {
  console.log(`Foundry ${broadcast ? '广播' : '只读预览'}：${script}`);
  const args = ['script', script, '--rpc-url', rpc, '--non-interactive', '--skip', 'test'];
  if (broadcast) args.push('--broadcast', '--slow');
  await new Promise<void>((done, reject) => {
    const child = spawn('forge', args, { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'] });
    // Foundry normally hides env secrets; redact again before forwarding diagnostics.
    let output = '';
    child.stdout.on('data', (data: Buffer) => {
      output += data.toString();
    });
    child.stderr.on('data', (data: Buffer) => {
      output += data.toString();
    });
    let interrupted = false;
    const interrupt = () => {
      interrupted = true;
      child.kill('SIGINT');
    };
    process.once('SIGINT', interrupt);
    process.once('SIGTERM', interrupt);
    child.once('error', reject);
    child.once('close', (code, signal) => {
      process.removeListener('SIGINT', interrupt);
      process.removeListener('SIGTERM', interrupt);
      try {
        for (const key of keys) output = output.replaceAll(key, '[REDACTED]');
        const log = resolve(directory, `${script.split(':')[1]}.log`);
        writeFileSync(log, output);
        // Revert traces can include an entire creation artifact. Keep console output useful;
        // the redacted complete trace is retained next to the temporary manifests.
        process.stdout.write(
          output
            .split('\n')
            .map((line) => (line.length > 500 ? `${line.slice(0, 500)}… [完整内容见日志]` : line))
            .join('\n'),
        );
        if (code === 0 && !signal && !interrupted) done();
        else
          reject(
            new Error(
              `forge ${script} 退出：${interrupted ? '用户中断' : (signal ?? code)}；日志：${log}`,
            ),
          );
      } catch (error) {
        reject(error);
      }
    });
  });
}
await runDeploymentStages(options.uninitialized, async (stage) => {
  console.log(`本地部署阶段：${stage}；临时清单：${directory}`);
  switch (stage) {
    case 'prepare':
      await forge('local/script/PrepareLocal.s.sol:PrepareLocal');
      Object.assign(env, protocolEnvironment(parseProtocol(json(files.protocol))));
      break;
    case 'preheat':
      // This changes the real node only after all pool transactions have been confirmed.
      await publicClient.request({ method: 'evm_increaseTime' as never, params: [121] as never });
      await publicClient.request({ method: 'evm_mine' as never });
      break;
    case 'deploy':
      await forge('script/Deploy.s.sol:DeployAdaptiveLPVault');
      parseVault(json(files.vault), parseProtocol(json(files.protocol)));
      break;
    case 'configure':
      await forge('script/Configure.s.sol:ConfigureAdaptiveLPVault');
      break;
    case 'preview': {
      await forge('local/script/PreviewLocalBootstrap.s.sol:PreviewLocalBootstrap', false);
      const [amount0, amount1] = parseBootstrap(json(files.bootstrap));
      Object.assign(env, { BOOTSTRAP_AMOUNT0: amount0, BOOTSTRAP_AMOUNT1: amount1 });
      break;
    }
    case 'bootstrap':
      await forge('script/Bootstrap.s.sol:BootstrapAdaptiveLPVault');
      break;
  }
});
await assertAnvil();
if ((await publicClient.getBlock({ blockNumber: start.number })).hash !== start.hash)
  throw new Error('部署期间本地链被重置，拒绝发布清单');
const protocol = parseProtocol(json(files.protocol));
const deployment = parseVault(json(files.vault), protocol);
const bootstrapAmounts = parseBootstrap(json(files.bootstrap));
const adapters = [deployment.v2Adapter, deployment.lowAdapter, deployment.highAdapter];
// Foundry writes manifests during simulation too; successful broadcast and independent RPC checks
// are both required before a manifest can become visible to the application.
for (const address of new Set([...Object.values(deployment), protocol.v2Router])) {
  const code = await publicClient.getCode({ address });
  if (!code || code === '0x') throw new Error(`部署结果缺少链上代码：${address}`);
}
const vaultAbi = artifact('AdaptiveLPVault').abi;
const controlAbi = artifact('VaultControl').abi;
if (
  (await read(deployment.vault, vaultAbi, 'vaultControl')).toLowerCase() !==
  deployment.control.toLowerCase()
)
  throw new Error('VaultControl 绑定无效');
if (
  (await read(deployment.vault, vaultAbi, 'swapExecutor')).toLowerCase() !==
  deployment.executor.toLowerCase()
)
  throw new Error('SwapExecutor 绑定无效');
for (const [role, index] of [
  ['MANAGER_ROLE', 2],
  ['GUARDIAN_ROLE', 3],
  ['KEEPER_ROLE', 4],
] as const) {
  const hash = await read(deployment.control, controlAbi, role);
  if (!(await read(deployment.control, controlAbi, 'hasRole', [hash, accounts[index].address])))
    throw new Error(`角色未配置：${role}`);
}
for (let i = 0; i < adapters.length; i++)
  if (
    (await read(deployment.control, controlAbi, 'getAdapter', [i + 1])).toLowerCase() !==
    adapters[i].toLowerCase()
  )
    throw new Error(`适配器未绑定：${i + 1}`);
if (!(await read(deployment.oracle, artifact('CanonicalV3Oracle').abi, 'snapshot')).healthy)
  throw new Error('部署后的预言机不健康');
if ((await read(deployment.vault, vaultAbi, 'initialized')) !== !options.uninitialized)
  throw new Error('Vault 初始化状态与选项不一致');
for (const account of accounts)
  for (const token of [protocol.token0, protocol.token1])
    if ((await read(token, erc20Abi, 'balanceOf', [account.address])) <= 0n)
      throw new Error(`测试账户未获得代币：${account.address}`);
const m: Manifest = {
  chainId: 31337,
  instanceId: `${start.hash}-${deployment.vault}`,
  deploymentBlock: start.number.toString(),
  deploymentBlockHash: start.hash!,
  vault: deployment.vault,
  control: deployment.control,
  oracle: deployment.oracle,
  executor: deployment.executor,
  token0: protocol.token0,
  token1: protocol.token1,
  decimals0: protocol.decimals0,
  decimals1: protocol.decimals1,
  symbol0: await read(protocol.token0, erc20Abi, 'symbol'),
  symbol1: await read(protocol.token1, erc20Abi, 'symbol'),
  v2Factory: protocol.v2Factory,
  v3Factory: protocol.v3Factory,
  v2Router: protocol.v2Router,
  router: protocol.router,
  positionManager: protocol.positionManager,
  pair: protocol.pair,
  lowPool: protocol.lowPool,
  highPool: protocol.highPool,
  canonicalPool: protocol.canonicalPool,
  adapters,
  accounts: Object.fromEntries(roles.map((role, i) => [role, accounts[i].address])),
  bootstrapAmounts,
};
mkdirSync(resolve(root, '../frontend/src/generated'), { recursive: true });
publishManifests(
  [
    resolve(root, 'local/deployments/local.json'),
    resolve(root, '../frontend/src/generated/deployment.json'),
  ],
  stringify(m) + '\n',
);
console.log('本地 Foundry 部署完成（测试资产，无真实价值）。', stringify(m));
