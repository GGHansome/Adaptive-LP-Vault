import { beforeEach, expect, it, vi } from 'vitest';
import { useTransactionStore } from '../store/transactionStore';
import {
  executeTransaction,
  retryTransactionConfirmation,
  type ContractCall,
  type TransactionRuntime,
} from './transaction';
const hash = `0x${'1'.repeat(64)}` as const;
const call: ContractCall = {
  label: '存款',
  address: '0x1111111111111111111111111111111111111111',
  abi: [],
  functionName: 'deposit',
};
function runtime(): TransactionRuntime {
  return {
    identity: '31337:instance:account',
    assertIdentity: vi.fn().mockResolvedValue(undefined),
    simulate: vi.fn().mockResolvedValue(vi.fn().mockResolvedValue(hash)),
    receipt: vi.fn().mockResolvedValue({ status: 'success' }),
    confirmed: vi.fn().mockResolvedValue(undefined),
  };
}
beforeEach(() =>
  useTransactionStore.setState({ busy: false, activeId: undefined, transaction: undefined }),
);
it('等待回执期间保持提交锁，确认后才刷新', async () => {
  const r = runtime();
  let confirm!: (value: { status: 'success' }) => void;
  r.receipt = vi.fn(
    () =>
      new Promise<{ status: 'success' }>((resolve) => {
        confirm = resolve;
      }),
  );
  const result = executeTransaction(r, (send) => send(call));
  await vi.waitFor(() => expect(r.receipt).toHaveBeenCalled());
  expect(useTransactionStore.getState().busy).toBe(true);
  expect(useTransactionStore.getState().transaction?.stage).toBe('confirming');
  expect(r.confirmed).not.toHaveBeenCalled();
  confirm({ status: 'success' });
  await result;
  expect(r.confirmed).toHaveBeenCalledWith(call);
  expect(useTransactionStore.getState().transaction?.stage).toBe('confirmed');
  expect(useTransactionStore.getState().busy).toBe(false);
});
it.each(['用户拒签', '模拟失败'])('%s 后恢复操作并保留失败状态', async (message) => {
  const r = runtime();
  if (message === '用户拒签')
    r.simulate = vi.fn().mockResolvedValue(vi.fn().mockRejectedValue(new Error(message)));
  else r.simulate = vi.fn().mockRejectedValue(new Error(message));
  await expect(executeTransaction(r, (send) => send(call))).rejects.toThrow(message);
  expect(useTransactionStore.getState().busy).toBe(false);
  expect(useTransactionStore.getState().transaction).toMatchObject({
    stage: 'failed',
    error: message,
  });
  expect(r.confirmed).not.toHaveBeenCalled();
});
it('回执查询失败保留锁，重新查询成功后才刷新和解锁', async () => {
  const r = runtime();
  r.receipt = vi
    .fn()
    .mockRejectedValueOnce(new Error('RPC 暂时离线'))
    .mockResolvedValue({ status: 'success' });
  await expect(executeTransaction(r, (send) => send(call))).rejects.toThrow('回执查询失败');
  expect(useTransactionStore.getState().transaction?.stage).toBe('unconfirmed');
  expect(useTransactionStore.getState().busy).toBe(true);
  expect(r.confirmed).not.toHaveBeenCalled();
  await retryTransactionConfirmation();
  expect(useTransactionStore.getState().transaction?.stage).toBe('confirmed');
  expect(useTransactionStore.getState().busy).toBe(false);
  expect(r.confirmed).toHaveBeenCalledOnce();
});
it('重复查询仍失败时保持锁，最终回滚后才释放', async () => {
  const r = runtime();
  r.receipt = vi
    .fn()
    .mockRejectedValueOnce(new Error('RPC 暂时离线'))
    .mockRejectedValueOnce(new Error('仍离线'))
    .mockResolvedValue({ status: 'reverted' });
  await expect(executeTransaction(r, (send) => send(call))).rejects.toThrow();
  await retryTransactionConfirmation();
  expect(useTransactionStore.getState().busy).toBe(true);
  await retryTransactionConfirmation();
  expect(useTransactionStore.getState().transaction?.stage).toBe('failed');
  expect(useTransactionStore.getState().busy).toBe(false);
});
it('回滚不刷新缓存，也不标记成功', async () => {
  const r = runtime();
  r.receipt = vi.fn().mockResolvedValue({ status: 'reverted' });
  await expect(executeTransaction(r, (send) => send(call))).rejects.toThrow('交易已回滚');
  expect(r.confirmed).not.toHaveBeenCalled();
});
it('模拟后账户切换会阻止发送钱包交易', async () => {
  const r = runtime(),
    write = vi.fn();
  r.simulate = vi.fn().mockResolvedValue(write);
  r.assertIdentity = vi
    .fn()
    .mockResolvedValueOnce(undefined)
    .mockRejectedValueOnce(new Error('账户或网络已变化'));
  await expect(executeTransaction(r, (send) => send(call))).rejects.toThrow('账户或网络已变化');
  expect(write).not.toHaveBeenCalled();
});
it('已发送交易按原身份跟踪，不依赖切换后的账户', async () => {
  const r = runtime();
  r.receipt = vi.fn(async () => {
    r.identity = 'other-account';
    return { status: 'success' as const };
  });
  await executeTransaction(r, (send) => send(call));
  expect(useTransactionStore.getState().transaction?.identity).toBe('31337:instance:account');
  expect(r.assertIdentity).toHaveBeenCalledTimes(2);
});
it('多笔初始化交易之间不释放锁，下一步失败后可恢复', async () => {
  const r = runtime();
  await expect(
    executeTransaction(r, async (send) => {
      await send({ ...call, label: '授权' });
      expect(useTransactionStore.getState().busy).toBe(true);
      expect(() => useTransactionStore.getState().acquire('other')).toThrow();
      throw new Error('初始化第二步失败');
    }),
  ).rejects.toThrow('初始化第二步失败');
  expect(useTransactionStore.getState().busy).toBe(false);
});
