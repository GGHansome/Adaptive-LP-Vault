import { act, cleanup, renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { Deployment } from '../../../config/types';
import { address, otherAddress, deployment, snapshotFixture } from '../../test/fixtures';
import { useAccountAssets, useVaultAccess, useVaultSnapshot, useVaultEvents } from './queries';
import * as reads from './read';
const environment = vi.hoisted(() => ({
  deployment: undefined as Deployment | undefined,
  address: undefined as `0x${string}` | undefined,
  chainId: 31337,
}));
vi.mock('../../../config/web3', () => ({
  get deployment() {
    return environment.deployment;
  },
}));
vi.mock('wagmi', () => ({
  useConnection: () => ({ address: environment.address, chainId: environment.chainId }),
  usePublicClient: () => ({}),
}));
vi.mock('./read', () => ({
  validateDeployment: vi.fn(),
  readParameters: vi.fn(),
  readSnapshot: vi.fn(),
  readAccount: vi.fn(),
  readAccess: vi.fn(),
  readEvents: vi.fn(),
  readGovernance: vi.fn(),
  readMembers: vi.fn(),
}));
let client: QueryClient;
function wrapper({ children }: { children: ReactNode }) {
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}
beforeEach(() => {
  vi.resetAllMocks();
  environment.deployment = deployment;
  environment.address = address;
  environment.chainId = 31337;
  client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: Infinity } } });
  vi.mocked(reads.validateDeployment).mockResolvedValue(true);
  vi.mocked(reads.readParameters).mockResolvedValue({ minRebalanceCooldown: 60 });
  vi.mocked(reads.readSnapshot).mockResolvedValue(snapshotFixture());
  vi.mocked(reads.readAccount).mockResolvedValue({
    balance0: 1n,
    balance1: 2n,
    shares: 3n,
    allowance0: 4n,
    allowance1: 5n,
  });
  vi.mocked(reads.readAccess).mockResolvedValue({
    admin: true,
    guardian: false,
    manager: false,
    keeper: false,
    pendingAdmin: false,
  });
});
afterEach(() => {
  cleanup();
  client.clear();
});
it('配置缺失时不启动部署、余额或公共快照请求', async () => {
  environment.deployment = undefined;
  renderHook(() => ({ snapshot: useVaultSnapshot(), account: useAccountAssets() }), { wrapper });
  await act(async () => {});
  expect(reads.validateDeployment).not.toHaveBeenCalled();
  expect(reads.readSnapshot).not.toHaveBeenCalled();
  expect(reads.readAccount).not.toHaveBeenCalled();
});
it('账户未就绪或网络错误时禁用账户查询，公共读取仍可成功', async () => {
  environment.chainId = 1;
  const { result } = renderHook(
    () => ({ snapshot: useVaultSnapshot(), account: useAccountAssets(), access: useVaultAccess() }),
    { wrapper },
  );
  await waitFor(() => expect(result.current.snapshot.data).toBeDefined());
  expect(reads.readAccount).not.toHaveBeenCalled();
  expect(reads.readAccess).not.toHaveBeenCalled();
  expect(result.current.access.confirmed).toBe(false);
});
it('切换账户不重新拉取公共快照，也不展示前一个账户余额', async () => {
  const { result, rerender } = renderHook(
    () => ({ snapshot: useVaultSnapshot(), account: useAccountAssets() }),
    { wrapper },
  );
  await waitFor(() => expect(result.current.account.data?.balance0).toBe(1n));
  await waitFor(() => expect(result.current.snapshot.data).toBeDefined());
  const publicReads = vi.mocked(reads.readSnapshot).mock.calls.length;
  let resolve!: (assets: Awaited<ReturnType<typeof reads.readAccount>>) => void;
  vi.mocked(reads.readAccount).mockImplementationOnce(
    () =>
      new Promise((r) => {
        resolve = r;
      }),
  );
  environment.address = otherAddress;
  rerender();
  expect(result.current.account.data).toBeUndefined();
  await waitFor(() => expect(reads.readAccount).toHaveBeenCalledTimes(2));
  await act(async () =>
    resolve({ balance0: 9n, balance1: 0n, shares: 0n, allowance0: 0n, allowance1: 0n }),
  );
  await waitFor(() => expect(result.current.account.data?.balance0).toBe(9n));
  expect(reads.readSnapshot).toHaveBeenCalledTimes(publicReads);
});
it('权限刷新失败立即撤销已确认权限，不把缓存的管理员身份继续用于门禁', async () => {
  const { result } = renderHook(useVaultAccess, { wrapper });
  await waitFor(() => expect(result.current.data?.admin).toBe(true));
  vi.mocked(reads.readAccess).mockRejectedValue(new Error('权限 RPC 失败'));
  await act(async () => {
    await result.current.refetch();
  });
  await waitFor(() => expect(result.current.confirmed).toBe(false));
  expect(result.current.data).toBeUndefined();
});
it('事件失败不会传播到公共快照', async () => {
  vi.mocked(reads.readEvents).mockRejectedValue(new Error('日志读取失败'));
  const { result } = renderHook(
    () => ({ snapshot: useVaultSnapshot(), events: useVaultEvents() }),
    { wrapper },
  );
  await waitFor(() => expect(result.current.events.isError).toBe(true));
  await waitFor(() => expect(result.current.snapshot.data).toBeDefined());
  expect(result.current.snapshot.error).toBeNull();
});
