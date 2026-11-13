import { act, cleanup, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, expect, it } from 'vitest';
import { useTransactionStore } from './transactionStore';
beforeEach(() =>
  useTransactionStore.setState({ busy: false, activeId: undefined, transaction: undefined }),
);
afterEach(cleanup);
it('提交锁是原子的，旧任务不能释放新任务的锁', () => {
  const s = useTransactionStore.getState();
  const id = s.acquire('first');
  expect(() => s.acquire('second')).toThrow('已有交易');
  s.release('stale-id');
  expect(useTransactionStore.getState().busy).toBe(true);
  s.release(id);
  const next = s.acquire('second');
  s.update(id, { label: '旧任务', stage: 'failed' });
  s.release(id);
  expect(useTransactionStore.getState().activeId).toBe(next);
});
it('只订阅 busy 的组件不会因签名或确认阶段变化重渲染', () => {
  let renders = 0;
  function BusySubscriber() {
    const busy = useTransactionStore((s) => s.busy);
    renders++;
    return <span>{busy ? '忙碌' : '空闲'}</span>;
  }
  render(<BusySubscriber />);
  let id = '';
  act(() => {
    id = useTransactionStore.getState().acquire('account');
  });
  const baseline = renders;
  act(() => useTransactionStore.getState().update(id, { label: '存款', stage: 'signing' }));
  act(() => useTransactionStore.getState().update(id, { label: '存款', stage: 'confirming' }));
  expect(renders).toBe(baseline);
  expect(screen.getByText('忙碌')).toBeInTheDocument();
  act(() => useTransactionStore.getState().release(id));
  expect(screen.getByText('空闲')).toBeInTheDocument();
});
