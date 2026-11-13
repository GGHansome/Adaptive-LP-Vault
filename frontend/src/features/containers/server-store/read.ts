import { decodeEventLog, erc20Abi, parseAbiItem, type Address, type PublicClient } from 'viem';
import { vaultAbi, controlAbi, oracleAbi, adapterAbi } from '../../../contracts';
import type { Deployment } from '../../../config/types';
import type {
  AccountAssets,
  Access,
  EventRow,
  Governance,
  RoleMember,
  VaultSnapshot,
} from '../../types';
import { parameterNames, roleHashes } from './constants';

export async function validateDeployment(c: PublicClient, m: Deployment) {
  if ((await c.getChainId()) !== m.chainId) throw new Error('RPC 网络与部署配置不匹配');
  const [checkpoint, code] = await Promise.all([
    c.getBlock({ blockNumber: BigInt(m.deploymentBlock) }),
    c.getCode({ address: m.vault }),
  ]);
  if (checkpoint.hash !== m.deploymentBlockHash || !code || code === '0x')
    throw new Error('本地链已重置或部署不存在，请重新部署并刷新页面');
  const blockNumber = await c.getBlockNumber();
  const bindings = await Promise.all(
    (['vaultControl', 'canonicalOracle', 'token0', 'token1'] as const).map((functionName) =>
      c.readContract({ address: m.vault, abi: vaultAbi, functionName, blockNumber }),
    ),
  );
  if (
    bindings.some(
      (v, i) => v.toLowerCase() !== [m.control, m.oracle, m.token0, m.token1][i].toLowerCase(),
    )
  )
    throw new Error('部署清单与合约绑定不匹配');
  return true;
}
export async function readParameters(c: PublicClient, m: Deployment) {
  const blockNumber = await c.getBlockNumber();
  const values = await Promise.all(
    parameterNames.map((functionName) =>
      c.readContract({
        address: m.vault,
        abi: vaultAbi,
        functionName,
        blockNumber,
      }),
    ),
  );
  return Object.fromEntries(parameterNames.map((name, i) => [name, values[i]]));
}
export async function readSnapshot(
  c: PublicClient,
  m: Deployment,
  params: VaultSnapshot['params'],
): Promise<VaultSnapshot> {
  const block = await c.getBlock();
  const blockNumber = block.number;
  const [initialized, activeVenue, assets, oracle, plan, pause, lastChange, configs] =
    await Promise.all([
      c.readContract({ address: m.vault, abi: vaultAbi, functionName: 'initialized', blockNumber }),
      c.readContract({ address: m.vault, abi: vaultAbi, functionName: 'activeVenue', blockNumber }),
      c.readContract({
        address: m.vault,
        abi: vaultAbi,
        functionName: 'assetSnapshot',
        blockNumber,
      }),
      c.readContract({ address: m.oracle, abi: oracleAbi, functionName: 'snapshot', blockNumber }),
      c.readContract({
        address: m.vault,
        abi: vaultAbi,
        functionName: 'lastExecutedPlan',
        blockNumber,
      }),
      c.readContract({
        address: m.control,
        abi: controlAbi,
        functionName: 'pauseState',
        blockNumber,
      }),
      c.readContract({
        address: m.vault,
        abi: vaultAbi,
        functionName: 'lastPositionChangeAt',
        blockNumber,
      }),
      Promise.all(
        [1, 2, 3].map((venue) =>
          c.readContract({
            address: m.control,
            abi: controlAbi,
            functionName: 'getConfig',
            args: [venue],
            blockNumber,
          }),
        ),
      ),
    ]);
  const config = configs.find((v) => v.venue === activeVenue);
  if (activeVenue && !config) throw new Error('当前仓位缺少适配器配置');
  const position =
    activeVenue && config
      ? await c.readContract({
          address: config.adapter,
          abi: adapterAbi,
          functionName: 'snapshot',
          blockNumber,
        })
      : undefined;
  let nav: bigint | undefined, idleBps: bigint | undefined;
  if (oracle.healthy) {
    const [totalQuote, idleQuote] = await Promise.all(
      [assets.total0, assets.idle0].map((value) =>
        c.readContract({
          address: m.oracle,
          abi: oracleAbi,
          functionName: 'quoteToken0InToken1',
          args: [value, oracle.twapTick, false],
          blockNumber,
        }),
      ),
    );
    nav = assets.total1 + totalQuote;
    idleBps = nav ? (10000n * (assets.idle1 + idleQuote)) / nav : 0n;
  }
  return {
    initialized,
    activeVenue,
    assets,
    oracle,
    plan,
    pause,
    lastChange,
    configs,
    position,
    nav,
    idleBps,
    params,
    blockTime: Number(block.timestamp),
    blockNumber,
  };
}
export async function readAccount(
  c: PublicClient,
  m: Deployment,
  address: Address,
): Promise<AccountAssets> {
  const blockNumber = await c.getBlockNumber();
  const [balance0, balance1, shares, allowance0, allowance1] = await Promise.all([
    c.readContract({
      address: m.token0,
      abi: erc20Abi,
      functionName: 'balanceOf',
      args: [address],
      blockNumber,
    }),
    c.readContract({
      address: m.token1,
      abi: erc20Abi,
      functionName: 'balanceOf',
      args: [address],
      blockNumber,
    }),
    c.readContract({
      address: m.vault,
      abi: vaultAbi,
      functionName: 'balanceOf',
      args: [address],
      blockNumber,
    }),
    c.readContract({
      address: m.token0,
      abi: erc20Abi,
      functionName: 'allowance',
      args: [address, m.vault],
      blockNumber,
    }),
    c.readContract({
      address: m.token1,
      abi: erc20Abi,
      functionName: 'allowance',
      args: [address, m.vault],
      blockNumber,
    }),
  ]);
  return { balance0, balance1, shares, allowance0, allowance1 };
}
export async function readAccess(
  c: PublicClient,
  m: Deployment,
  address: Address,
): Promise<Access> {
  const blockNumber = await c.getBlockNumber();
  const [membership, pending] = await Promise.all([
    Promise.all(
      Object.values(roleHashes).map((role) =>
        c.readContract({
          address: m.control,
          abi: controlAbi,
          functionName: 'hasRole',
          args: [role, address],
          blockNumber,
        }),
      ),
    ),
    c.readContract({
      address: m.control,
      abi: controlAbi,
      functionName: 'pendingDefaultAdmin',
      blockNumber,
    }),
  ]);
  return {
    admin: membership[0],
    manager: membership[1],
    guardian: membership[2],
    keeper: membership[3],
    pendingAdmin: pending[0].toLowerCase() === address.toLowerCase(),
  };
}
export async function readGovernance(c: PublicClient, m: Deployment): Promise<Governance> {
  const block = await c.getBlock();
  const blockNumber = block.number;
  const [pendingAdmin, adminDelay, pendingDelay] = await Promise.all([
    c.readContract({
      address: m.control,
      abi: controlAbi,
      functionName: 'pendingDefaultAdmin',
      blockNumber,
    }),
    c.readContract({
      address: m.control,
      abi: controlAbi,
      functionName: 'defaultAdminDelay',
      blockNumber,
    }),
    c.readContract({
      address: m.control,
      abi: controlAbi,
      functionName: 'pendingDefaultAdminDelay',
      blockNumber,
    }),
  ]);
  return {
    pendingAdmin: { address: pendingAdmin[0], acceptAt: pendingAdmin[1] },
    adminDelay,
    pendingDelay: { delay: pendingDelay[0], effectiveAt: pendingDelay[1] },
    blockTime: Number(block.timestamp),
  };
}
export async function readEvents(c: PublicClient, m: Deployment): Promise<EventRow[]> {
  const blockNumber = await c.getBlockNumber();
  const from = blockNumber > 500n ? blockNumber - 500n : 0n;
  const logs = await c.getLogs({
    address: [m.vault, m.control],
    fromBlock: from > BigInt(m.deploymentBlock) ? from : BigInt(m.deploymentBlock),
    toBlock: blockNumber,
  });
  return logs
    .flatMap((log) => {
      try {
        const event = decodeEventLog({
          abi: [...vaultAbi, ...controlAbi],
          data: log.data,
          topics: log.topics,
        });
        return [
          {
            key: `${log.transactionHash}-${log.logIndex}`,
            name: event.eventName,
            block: String(log.blockNumber),
            hash: log.transactionHash!,
          },
        ];
      } catch {
        return [];
      }
    })
    .reverse()
    .slice(0, 12);
}
export async function readMembers(c: PublicClient, m: Deployment): Promise<RoleMember[]> {
  const blockNumber = await c.getBlockNumber();
  const candidates = new Set<Address>();
  for (let from = BigInt(m.deploymentBlock); from <= blockNumber; from += 500n) {
    const logs = await c.getLogs({
      address: m.control,
      event: parseAbiItem(
        'event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)',
      ),
      fromBlock: from,
      toBlock: from + 499n > blockNumber ? blockNumber : from + 499n,
    });
    for (const log of logs) if (log.args.account) candidates.add(log.args.account);
  }
  return Promise.all(
    [...candidates].map(async (address) => ({
      address,
      roles: await Promise.all(
        Object.entries(roleHashes).map(async ([role, hash]) => ({
          role,
          has: await c.readContract({
            address: m.control,
            abi: controlAbi,
            functionName: 'hasRole',
            args: [hash, address],
            blockNumber,
          }),
        })),
      ),
    })),
  );
}
