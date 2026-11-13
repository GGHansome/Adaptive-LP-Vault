import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, expect, it, vi } from 'vitest';
import { Rebalance } from './Rebalance';
import type { RebalanceProps } from './interface';
import { deployment, snapshotFixture } from '../../test/fixtures';

afterEach(cleanup);

function props(): RebalanceProps {
  const data = snapshotFixture();
  return {
    data,
    deployment,
    preview: {
      plan: { ...data.plan, targetVenue: 0, marketRegime: 3, tickLower: 0, tickUpper: 0 },
      requiresSwap: false,
      direction: 0,
      at: data.blockTime,
    },
    loading: false,
    ready: true,
    busy: false,
    cooldown: 55,
    expired: false,
    allowedSwap: true,
    onRefresh: vi.fn(),
    onExecute: vi.fn(async () => {}),
    onSwap: vi.fn(async () => {}),
  };
}

it('极端偏离撤至 IDLE 可在冷却期内执行普通再平衡', () => {
  render(<Rebalance {...props()} />);
  expect(screen.getByRole('button', { name: '执行普通再平衡' })).toBeEnabled();
  expect(screen.getByRole('button', { name: '模拟并执行换币再平衡' })).toBeDisabled();
  expect(screen.getByText('撤至 IDLE 豁免冷却；重新入场仍需冷却')).toBeInTheDocument();
});

it('重新入场仍需等待冷却结束', () => {
  const p = props();
  p.data.activeVenue = 0;
  p.preview!.plan.targetVenue = 2;
  p.preview!.plan.marketRegime = 0;
  const { rerender } = render(<Rebalance {...p} />);
  expect(screen.getByRole('button', { name: '执行普通再平衡' })).toBeDisabled();
  rerender(<Rebalance {...p} cooldown={0} />);
  expect(screen.getByRole('button', { name: '执行普通再平衡' })).toBeEnabled();
});

it('非 IDLE 的普通迁移和换币迁移均受冷却限制', () => {
  const p = props();
  p.preview!.plan.targetVenue = 1;
  p.preview!.plan.marketRegime = 2;
  const { rerender } = render(<Rebalance {...p} />);
  expect(screen.getByRole('button', { name: '执行普通再平衡' })).toBeDisabled();
  p.preview!.requiresSwap = true;
  p.preview!.direction = 1;
  rerender(<Rebalance {...p} />);
  expect(screen.getByRole('button', { name: '模拟并执行换币再平衡' })).toBeDisabled();
  rerender(<Rebalance {...p} cooldown={0} />);
  expect(screen.getByRole('button', { name: '模拟并执行换币再平衡' })).toBeEnabled();
});

it('撤仓豁免仍受暂停、预览有效期及钱包就绪状态约束', () => {
  const p = props();
  const { rerender } = render(<Rebalance {...p} expired />);
  expect(screen.getByRole('button', { name: '执行普通再平衡' })).toBeDisabled();
  rerender(<Rebalance {...p} ready={false} />);
  expect(screen.getByRole('button', { name: '执行普通再平衡' })).toBeDisabled();
  p.data.pause.plainRebalancePaused = true;
  rerender(<Rebalance {...p} />);
  expect(screen.getByRole('button', { name: '执行普通再平衡' })).toBeDisabled();
});

it('当前已为 IDLE 时不提供撤仓冷却豁免', () => {
  const p = props();
  p.data.activeVenue = 0;
  render(<Rebalance {...p} />);
  expect(screen.getByRole('button', { name: '执行普通再平衡' })).toBeDisabled();
  expect(screen.queryByText('撤至 IDLE 豁免冷却；重新入场仍需冷却')).not.toBeInTheDocument();
});
