import { act, cleanup, renderHook } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { App } from 'antd';
import type { ReactNode } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { vaultAbi } from '../../../contracts';
import { useTransactionStore } from '../../../shared/store/transactionStore';
import { address, deployment, snapshotFixture } from '../../test/fixtures';
import { useRebalanceMutation } from '../RebalanceContainer/server-store/mutation';
import { useVaultWrite } from './write';

const rpc = vi.hoisted(() => ({
  estimateContractGas: vi.fn(),
  simulateContract: vi.fn(),
  waitForTransactionReceipt: vi.fn(),
}));
const wallet = vi.hoisted(() => ({
  getAddresses: vi.fn(),
  getChainId: vi.fn(),
  writeContract: vi.fn(),
}));
const preview = vi.hoisted(() => ({ read: vi.fn() }));
const getConnection = () => ({ address, chainId: deployment.chainId });
vi.mock('wagmi', () => ({
  useConnection: () => getConnection(),
  useWalletClient: () => ({ data: wallet }),
  usePublicClient: () => rpc,
}));
vi.mock('wagmi/actions', () => ({ getConnection: () => getConnection() }));
vi.mock('../../../config/web3', () => ({
  get deployment() {
    return deployment;
  },
  wagmiConfig: {},
}));
vi.mock('./queries', () => ({ useDeploymentValidation: () => ({ client: rpc, valid: true }) }));
vi.mock('../RebalanceContainer/server-store/selector', () => ({
  readRebalancePreview: preview.read,
}));

const candidate = { plan: snapshotFixture().plan, requiresSwap: true, direction: 2, at: 123 };
let client: QueryClient;
function wrapper({ children }: { children: ReactNode }) {
  return (
    <QueryClientProvider client={client}>
      <App>{children}</App>
    </QueryClientProvider>
  );
}
beforeEach(() => {
  vi.resetAllMocks();
  client = new QueryClient();
  useTransactionStore.setState({ busy: false, activeId: undefined, transaction: undefined });
  preview.read.mockResolvedValue(candidate);
  wallet.getAddresses.mockResolvedValue([address]);
  wallet.getChainId.mockResolvedValue(deployment.chainId);
  wallet.writeContract.mockResolvedValue(`0x${'1'.repeat(64)}`);
  rpc.waitForTransactionReceipt.mockResolvedValue({ status: 'success' });
  rpc.estimateContractGas.mockResolvedValue(1_337_806n);
  rpc.simulateContract.mockImplementation(async (args: unknown) => ({ request: args }));
});
afterEach(() => {
  cleanup();
  client.clear();
});

function renderSwap() {
  const { result } = renderHook(useRebalanceMutation, { wrapper });
  return () => result.current.execute(candidate, { amountIn: '1125', minOut: '0' });
}

it('换币再平衡将估算上浮 20% 并取整，以相同的 Gas 上限模拟并提交', async () => {
  const send = renderSwap();
  await act(async () => send());
  const input = {
    address: deployment.vault,
    abi: vaultAbi,
    functionName: 'rebalanceWithSwap',
    args: [candidate.plan.planHash, 2, 1125n * 10n ** 18n, 0n, 243],
    account: address,
  };
  expect(rpc.estimateContractGas).toHaveBeenCalledExactlyOnceWith(expect.objectContaining(input));
  for (const method of [rpc.simulateContract, wallet.writeContract]) {
    expect(method).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({ ...input, gas: 1_605_368n }),
    );
  }
});

it('带 Gas 上限的模拟若失败，不打开钱包或查询回执', async () => {
  const send = renderSwap();
  rpc.simulateContract.mockImplementationOnce(async ({ gas }: { gas?: bigint }) => {
    if (gas === 1_605_368n) throw new Error('模拟失败');
    return { request: { gas } };
  });
  await act(async () => {
    await expect(send()).rejects.toThrow('模拟失败');
  });
  expect(wallet.writeContract).not.toHaveBeenCalled();
  expect(rpc.waitForTransactionReceipt).not.toHaveBeenCalled();
  expect(useTransactionStore.getState().busy).toBe(false);
});

const deposit = {
  label: '存款',
  address: deployment.vault,
  abi: vaultAbi,
  functionName: 'deposit',
  args: [1_000_000n, 10n ** 18n, 1n, address],
};

it('存款无需单独配置，也使用上浮 20% 的 Gas 上限模拟并提交', async () => {
  const { result } = renderHook(useVaultWrite, { wrapper });
  await act(async () => result.current.send('assets', deposit));
  const input = { ...deposit, account: address };
  expect(rpc.estimateContractGas).toHaveBeenCalledExactlyOnceWith(expect.objectContaining(input));
  for (const method of [rpc.simulateContract, wallet.writeContract]) {
    expect(method).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({ ...input, gas: 1_605_368n }),
    );
  }
});

it('多笔签名的流程会按各笔交易重新估算，而不是沿用第一笔的 Gas 上限', async () => {
  const { result } = renderHook(useVaultWrite, { wrapper });
  const approval = { ...deposit, label: '份额授权', functionName: 'approve', args: [address, 1n] };
  rpc.estimateContractGas.mockResolvedValueOnce(42_001n).mockResolvedValueOnce(500_002n);
  await act(async () =>
    result.current.run('assets', async (send) => {
      await send(approval);
      await send(deposit);
    }),
  );
  expect(rpc.estimateContractGas.mock.calls.map(([call]) => call.functionName)).toEqual([
    'approve',
    'deposit',
  ]);
  expect(wallet.writeContract.mock.calls.map(([call]) => call.gas)).toEqual([50_402n, 600_003n]);
});

it('写链前估算失败会停止模拟和提交，并恢复按钮可用', async () => {
  const { result } = renderHook(useVaultWrite, { wrapper });
  rpc.estimateContractGas.mockRejectedValueOnce(new Error('估算失败'));
  await act(async () => {
    await expect(result.current.send('assets', deposit)).rejects.toThrow('估算失败');
  });
  expect(rpc.simulateContract).not.toHaveBeenCalled();
  expect(wallet.writeContract).not.toHaveBeenCalled();
  expect(useTransactionStore.getState().busy).toBe(false);
});
