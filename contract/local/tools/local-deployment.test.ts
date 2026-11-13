import assert from 'node:assert/strict';
import test from 'node:test';
import {
  deploymentOptions,
  runDeploymentStages,
  localEnvironment,
  protocolEnvironment,
  parseProtocol,
  parseVault,
  parseBootstrap,
  publishManifests,
  type PublicationIO,
} from './local-deployment.js';
import { accounts } from './local.js';

const address = accounts[0].address;
const rawProtocol = {
  token0: accounts[0].address,
  token1: accounts[1].address,
  decimals0: 6,
  decimals1: 18,
  v2Factory: address,
  v3Factory: address,
  v2Router: address,
  router: address,
  positionManager: address,
  pair: address,
  lowPool: address,
  highPool: address,
  canonicalPool: address,
};
const rawVault = {
  ...rawProtocol,
  chainId: 31337,
  vault: address,
  control: address,
  oracle: address,
  executor: address,
  v2Adapter: address,
  lowAdapter: address,
  highAdapter: address,
  strategyMath: address,
  componentFactory: address,
  v2Pool: address,
};

test('部署参数保留原选项，拒绝未知参数', () => {
  assert.deepEqual(deploymentOptions([]), { uninitialized: false, resetConfirmed: false });
  assert.deepEqual(deploymentOptions(['--uninitialized', '--reset-confirmed']), {
    uninitialized: true,
    resetConfirmed: true,
  });
  assert.throws(() => deploymentOptions(['--mainnet']));
});
test('默认依次准备、预热、部署、配置、预览并初始化', async () => {
  const calls: string[] = [];
  await runDeploymentStages(false, async (stage) => {
    calls.push(stage);
  });
  assert.deepEqual(calls, ['prepare', 'preheat', 'deploy', 'configure', 'preview', 'bootstrap']);
});
test('未初始化模式仍执行配置与数量预览，仅跳过 Bootstrap', async () => {
  const calls: string[] = [];
  await runDeploymentStages(true, async (stage) => {
    calls.push(stage);
  });
  assert.deepEqual(calls, ['prepare', 'preheat', 'deploy', 'configure', 'preview']);
});
test('任何阶段失败都停止后续操作，不自动重试', async () => {
  const calls: string[] = [];
  await assert.rejects(
    runDeploymentStages(false, async (stage) => {
      calls.push(stage);
      if (stage === 'deploy') throw new Error('forge exited 1');
    }),
    /阶段 deploy 失败/,
  );
  assert.deepEqual(calls, ['prepare', 'preheat', 'deploy']);
});
test('本地配置将三个发送者和每阶段清单传给既有脚本', () => {
  const env = localEnvironment(
    accounts.map((a) => a.address),
    ['deployer-key', 'admin-key', 'manager-key'],
    {
      protocol: 'protocol.json',
      vault: 'vault.json',
      bootstrap: 'bootstrap.json',
    },
  );
  assert.equal(env.ADMIN_PRIVATE_KEY, 'admin-key');
  assert.equal(env.MANAGER, accounts[2].address);
  assert.equal(env.BOOTSTRAP_SENDER, accounts[2].address);
  assert.equal(env.DEPLOYMENT_FILE, 'vault.json');
  assert.equal(env.TWAP_WINDOW_SECONDS, '120');
  const protocol = protocolEnvironment(parseProtocol(rawProtocol));
  assert.equal(protocol.CANONICAL_POOL, rawProtocol.canonicalPool);
  assert.equal(protocol.V2_POOL, rawProtocol.pair);
  assert.equal(protocol.DUST_TOLERANCE0, '10');
  assert.equal(protocol.DUST_TOLERANCE1, '10000000000000');
});
test('校验协议与业务清单绑定，保留 JSON 数量精度', () => {
  const protocol = parseProtocol(rawProtocol);
  assert.equal(parseVault(rawVault, protocol).v2Adapter, address);
  assert.deepEqual(parseBootstrap({ amount0: '1000000000000000000001', amount1: '2' }), [
    '1000000000000000000001',
    '2',
  ]);
  assert.throws(() => parseProtocol({ ...rawProtocol, router: 'wrong' }));
  assert.throws(() => parseVault({ ...rawVault, canonicalPool: accounts[2].address }, protocol));
  assert.throws(() => parseVault({ ...rawVault, chainId: 1 }, protocol));
  assert.throws(() => parseBootstrap({ amount0: 1, amount1: '2' }));
  assert.throws(() => parseBootstrap({ amount0: '0', amount1: '2' }));
});
test('清单转换只保留白名单字段，不将部署者或未知字段当作合约地址', () => {
  const protocol = parseProtocol({ ...rawProtocol, ignored: 'untrusted' });
  const vault = parseVault({ ...rawVault, deployer: address, ignored: 'untrusted' }, protocol);
  assert.equal('ignored' in protocol, false);
  assert.equal('deployer' in vault, false);
  assert.equal('chainId' in vault, false);
  assert.equal('ignored' in vault, false);
});

function memoryIO(originals: [string | undefined, string | undefined], failOn?: string) {
  const values = new Map<string, Buffer>();
  for (const [i, text] of originals.entries())
    if (text !== undefined) values.set(String(i), Buffer.from(text));
  let failed = false;
  const io: PublicationIO = {
    read: (path) => values.get(path),
    write: (path, data) => {
      values.set(path, Buffer.from(data));
    },
    rename: (from, to) => {
      if (to === failOn && !failed) {
        failed = true;
        throw new Error('rename failed');
      }
      const data = values.get(from);
      assert(data);
      values.set(to, data);
      values.delete(from);
    },
    remove: (path) => {
      values.delete(path);
    },
  };
  return { io, values };
}
test('成功后发布同一份公开清单，并清理临时文件', () => {
  const { io, values } = memoryIO(['old-contract', 'old-frontend']);
  publishManifests(['0', '1'], 'new', io);
  assert.equal(values.get('0')?.toString(), 'new');
  assert.equal(values.get('1')?.toString(), 'new');
  assert.equal(values.size, 2);
});
test('第二份清单发布失败时恢复两份旧配置', () => {
  const { io, values } = memoryIO(['old-contract', 'old-frontend'], '1');
  assert.throws(() => publishManifests(['0', '1'], 'new', io), /已恢复旧配置/);
  assert.equal(values.get('0')?.toString(), 'old-contract');
  assert.equal(values.get('1')?.toString(), 'old-frontend');
  assert.equal(values.size, 2);
});
test('首次部署发布失败时删除新文件，不留下半份配置', () => {
  const { io, values } = memoryIO([undefined, undefined], '1');
  assert.throws(() => publishManifests(['0', '1'], 'new', io));
  assert.equal(values.size, 0);
});
