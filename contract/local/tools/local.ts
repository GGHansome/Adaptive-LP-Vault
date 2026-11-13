import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import {
  createPublicClient,
  createWalletClient,
  http,
  type Abi,
  type Address,
  type Hex,
} from 'viem';
import { mnemonicToAccount } from 'viem/accounts';
import { foundry } from 'viem/chains';

export const root = fileURLToPath(new URL('../../', import.meta.url));
export const rpc = process.env.LOCAL_RPC_URL ?? 'http://127.0.0.1:8545';
export function assertLoopback(value: string) {
  const url = new URL(value);
  if (
    !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
    url.protocol !== 'http:' ||
    url.username ||
    url.password ||
    url.search ||
    url.pathname !== '/'
  )
    throw new Error('本地工具仅接受回环 HTTP RPC 地址');
}
assertLoopback(rpc);
export const publicClient = createPublicClient({
  chain: foundry,
  pollingInterval: 100,
  transport: http(rpc, { retryCount: 1 }),
});
// Public Anvil development mnemonic. It must never be funded on any public network.
const mnemonic = 'test test test test test test test test test test test junk';
export const roles = [
  'deployer',
  'admin',
  'manager',
  'guardian',
  'keeper',
  'user',
  'trader',
] as const;
export const accounts = roles.map((_, addressIndex) =>
  mnemonicToAccount(mnemonic, { addressIndex }),
);
export const wallets = accounts.map((account) =>
  createWalletClient({ account, chain: foundry, transport: http(rpc, { retryCount: 0 }) }),
);
export async function assertAnvil() {
  const [chain, version] = await Promise.all([
    publicClient.getChainId(),
    publicClient.request({ method: 'web3_clientVersion' }),
  ]);
  if (chain !== 31337 || !version.toLowerCase().includes('anvil'))
    throw new Error('拒绝操作：必须连接 chainId=31337 的本地 Anvil');
}
export function artifact(name: string): {
  abi: Abi;
  bytecode: {
    object: Hex;
    linkReferences?: Record<string, Record<string, { start: number; length: number }[]>>;
  };
} {
  return JSON.parse(readFileSync(resolve(root, `out/${name}.sol/${name}.json`), 'utf8'));
}
export function official(path: string): { abi: Abi; bytecode: Hex | { object: Hex } } {
  return JSON.parse(
    readFileSync(resolve(root, `lib/uniswap-test-deps/node_modules/${path}`), 'utf8'),
  );
}
export async function send(
  index: number,
  address: Address,
  abi: Abi,
  functionName: string,
  args: readonly unknown[] = [],
) {
  const { request, result } = await publicClient.simulateContract({
    address,
    abi,
    functionName,
    args,
    account: accounts[index],
  });
  const hash = await wallets[index].writeContract(request);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== 'success') throw new Error(`${functionName} reverted: ${hash}`);
  return { hash, result, receipt };
}
export async function read(
  address: Address,
  abi: Abi,
  functionName: string,
  args: readonly unknown[] = [],
  blockNumber?: bigint,
): Promise<any> {
  return publicClient.readContract({ address, abi, functionName, args, blockNumber });
}
export type Manifest = {
  chainId: number;
  instanceId: string;
  deploymentBlock: string;
  deploymentBlockHash: Hex;
  vault: Address;
  control: Address;
  oracle: Address;
  executor: Address;
  token0: Address;
  token1: Address;
  decimals0: number;
  decimals1: number;
  symbol0: string;
  symbol1: string;
  v2Factory: Address;
  v3Factory: Address;
  v2Router: Address;
  router: Address;
  positionManager: Address;
  pair: Address;
  lowPool: Address;
  highPool: Address;
  canonicalPool: Address;
  adapters: Address[];
  accounts: Record<string, Address>;
  bootstrapAmounts: string[];
};
export function manifest(): Manifest {
  const file = resolve(root, 'local/deployments/local.json');
  if (!existsSync(file)) throw new Error('请先执行 npm run local:deploy');
  return JSON.parse(readFileSync(file, 'utf8'));
}
export async function assertDeployment(m: Manifest) {
  await assertAnvil();
  const block = await publicClient.getBlock({ blockNumber: BigInt(m.deploymentBlock) });
  if (block.hash !== m.deploymentBlockHash || !(await publicClient.getCode({ address: m.vault })))
    throw new Error('本地链已重置，请重新部署');
  const { abi } = artifact('AdaptiveLPVault');
  if ((await read(m.vault, abi, 'vaultControl')).toLowerCase() !== m.control.toLowerCase())
    throw new Error('部署绑定不匹配');
}
export function stringify(value: unknown) {
  return JSON.stringify(value, (_, v) => (typeof v === 'bigint' ? v.toString() : v));
}
