import { existsSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { isAddress, type Address } from 'viem';

export const deploymentStages = [
  'prepare',
  'preheat',
  'deploy',
  'configure',
  'preview',
  'bootstrap',
] as const;
export type DeploymentStage = (typeof deploymentStages)[number];

export function deploymentOptions(args: string[]) {
  for (const arg of args)
    if (!['--uninitialized', '--reset-confirmed'].includes(arg))
      throw new Error(`未知本地部署参数：${arg}`);
  return {
    uninitialized: args.includes('--uninitialized'),
    resetConfirmed: args.includes('--reset-confirmed'),
  };
}

export async function runDeploymentStages(
  uninitialized: boolean,
  execute: (stage: DeploymentStage) => Promise<void>,
) {
  for (const stage of deploymentStages) {
    if (stage === 'bootstrap' && uninitialized) continue;
    try {
      await execute(stage);
    } catch (cause) {
      throw new Error(
        `本地部署阶段 ${stage} 失败；已广播交易不会自动回滚，旧公开清单保持不变。请检查链状态后重建本地环境。`,
        { cause },
      );
    }
  }
}

const protocolKeys = [
  'token0',
  'token1',
  'v2Factory',
  'v3Factory',
  'v2Router',
  'router',
  'positionManager',
  'pair',
  'lowPool',
  'highPool',
  'canonicalPool',
] as const;
const vaultKeys = [
  'vault',
  'control',
  'oracle',
  'executor',
  'v2Adapter',
  'lowAdapter',
  'highAdapter',
  'strategyMath',
  'componentFactory',
  'token0',
  'token1',
  'v2Factory',
  'v3Factory',
  'router',
  'positionManager',
  'v2Pool',
  'lowPool',
  'highPool',
  'canonicalPool',
] as const;
function addressRecord<K extends string>(value: unknown, keys: readonly K[]): Record<K, Address> {
  if (!value || typeof value !== 'object') throw new Error('部署清单不是 JSON 对象');
  const record = value as Record<string, unknown>;
  for (const key of keys)
    if (
      typeof record[key] !== 'string' ||
      !isAddress(record[key], { strict: false }) ||
      /^0x0{40}$/i.test(record[key])
    )
      throw new Error(`部署清单地址无效：${key}`);
  // The assertion is confined to the validated JSON boundary.
  return Object.fromEntries(keys.map((key) => [key, record[key]])) as Record<K, Address>;
}
export function parseProtocol(value: unknown) {
  const addresses = addressRecord(value, protocolKeys);
  const record = value as Record<string, unknown>;
  for (const key of ['decimals0', 'decimals1'])
    if (![6, 18].includes(Number(record[key]))) throw new Error(`本地代币精度无效：${key}`);
  if (Number(record.decimals0) === Number(record.decimals1))
    throw new Error('本地资产应为 6/18 位精度');
  return { ...addresses, decimals0: Number(record.decimals0), decimals1: Number(record.decimals1) };
}
export type LocalProtocol = ReturnType<typeof parseProtocol>;
export function parseVault(value: unknown, protocol: LocalProtocol) {
  const vault = addressRecord(value, vaultKeys);
  const record = value as Record<string, unknown>;
  if (Number(record.chainId) !== 31337) throw new Error('业务部署清单链 ID 无效');
  for (const key of [
    'token0',
    'token1',
    'v2Factory',
    'v3Factory',
    'router',
    'positionManager',
    'lowPool',
    'highPool',
    'canonicalPool',
  ] as const)
    if (vault[key].toLowerCase() !== protocol[key].toLowerCase())
      throw new Error(`协议绑定不一致：${key}`);
  if (vault.v2Pool.toLowerCase() !== protocol.pair.toLowerCase())
    throw new Error('V2 池绑定不一致');
  return vault;
}
export function parseBootstrap(value: unknown): [string, string] {
  if (!value || typeof value !== 'object') throw new Error('初始化预览无效');
  const record = value as Record<string, unknown>;
  const amounts = [record.amount0, record.amount1];
  if (!amounts.every((v) => typeof v === 'string' && /^[1-9]\d*$/.test(v)))
    throw new Error('初始化数量必须为正整数原始单位字符串');
  return amounts as [string, string];
}

export function localEnvironment(
  addresses: Address[],
  keys: [string, string, string],
  files: { protocol: string; vault: string; bootstrap: string },
): NodeJS.ProcessEnv {
  if (addresses.length !== 7) throw new Error('需要七个本地开发账户');
  return {
    DEPLOYER_PRIVATE_KEY: keys[0],
    ADMIN_PRIVATE_KEY: keys[1],
    MANAGER_PRIVATE_KEY: keys[2],
    DEFAULT_ADMIN: addresses[1],
    MANAGER: addresses[2],
    GUARDIAN: addresses[3],
    KEEPER: addresses[4],
    BOOTSTRAP_SENDER: addresses[2],
    BOOTSTRAP_RECEIVER: addresses[2],
    LOCAL_ACCOUNTS: addresses.join(','),
    LOCAL_PROTOCOL_FILE: files.protocol,
    DEPLOYMENT_FILE: files.vault,
    LOCAL_BOOTSTRAP_FILE: files.bootstrap,
    VAULT_NAME: 'Adaptive Local Vault',
    VAULT_SYMBOL: 'ALPV',
    TWAP_WINDOW_SECONDS: '120',
    SHORT_TWAP_WINDOW_SECONDS: '20',
    MINIMUM_LOCKED_SHARES: '1000000000000000',
    MINIMUM_INITIAL_NAV: '1',
    DEFAULT_ADMIN_DELAY: '60',
    MIN_REBALANCE_COOLDOWN: '15',
    ENTER_MEDIUM_BPS: '30',
    EXIT_MEDIUM_BPS: '15',
    ENTER_HIGH_BPS: '100',
    EXIT_HIGH_BPS: '70',
    ENTER_EXTREME_BPS: '300',
    EXIT_EXTREME_BPS: '200',
    NARROW_RANGE_HALF_WIDTH_STEPS: '100',
    WIDE_RANGE_HALF_WIDTH_STEPS: '50',
    MIN_RECENTER_BPS: '1000',
    MAX_HEALTHY_IDLE_BPS: '500',
    MAX_SWAP_SLIPPAGE_BPS: '300',
    MAX_MIGRATION_LOSS_BPS: '300',
  };
}
export function protocolEnvironment(p: LocalProtocol): NodeJS.ProcessEnv {
  return {
    CANONICAL_POOL: p.canonicalPool,
    V2_POOL: p.pair,
    LOW_FEE_POOL: p.lowPool,
    HIGH_FEE_POOL: p.highPool,
    UNISWAP_V2_FACTORY: p.v2Factory,
    UNISWAP_V3_FACTORY: p.v3Factory,
    ROUTER: p.router,
    POSITION_MANAGER: p.positionManager,
    DUST_TOLERANCE0: p.decimals0 === 6 ? '10' : '10000000000000',
    DUST_TOLERANCE1: p.decimals1 === 6 ? '10' : '10000000000000',
  };
}

export type PublicationIO = {
  read(path: string): Buffer | undefined;
  write(path: string, data: string | Buffer): void;
  rename(from: string, to: string): void;
  remove(path: string): void;
};
const fileIO: PublicationIO = {
  read: (path) => (existsSync(path) ? readFileSync(path) : undefined),
  write: (path, data) => writeFileSync(path, data),
  rename: renameSync,
  remove: (path) => {
    if (existsSync(path)) unlinkSync(path);
  },
};
// Best-effort transactional publication across two files; each individual replacement is atomic.
// A process crash between renames is not an atomic multi-file transaction.
export function publishManifests(paths: string[], json: string, io: PublicationIO = fileIO) {
  const previous = paths.map((path) => io.read(path));
  const temporary = paths.map((path) => `${path}.${process.pid}.tmp`);
  let published = 0;
  try {
    for (const path of temporary) io.write(path, json);
    for (let i = 0; i < paths.length; i++) {
      io.rename(temporary[i], paths[i]);
      published++;
    }
  } catch (cause) {
    const failures: unknown[] = [cause];
    for (let i = 0; i < published; i++) {
      try {
        const old = previous[i];
        if (old === undefined) io.remove(paths[i]);
        else {
          io.write(temporary[i], old);
          io.rename(temporary[i], paths[i]);
        }
      } catch (error) {
        failures.push(error);
      }
    }
    throw new AggregateError(
      failures,
      failures.length === 1
        ? '清单发布失败，已恢复旧配置'
        : '清单发布和恢复均失败，请手动检查两份公开清单',
    );
  } finally {
    for (const path of temporary) io.remove(path);
  }
}
