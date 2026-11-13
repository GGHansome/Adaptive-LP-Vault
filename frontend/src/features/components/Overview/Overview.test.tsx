import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, expect, it, vi } from 'vitest';
import { Overview } from './Overview';
import { deployment, snapshotFixture } from '../../test/fixtures';
afterEach(cleanup);
it('预言机不健康时隐藏无效价格、估值和市场状态', () => {
  render(
    <Overview
      data={snapshotFixture(false)}
      deployment={deployment}
      events={[]}
      eventsLoading={false}
      onPortfolio={vi.fn()}
      onRebalance={vi.fn()}
    />,
  );
  expect(screen.getByText('预言机不可用，暂不展示估值')).toBeInTheDocument();
  expect(screen.queryByText('极端偏离')).not.toBeInTheDocument();
  expect(screen.getAllByText('不可用', { exact: true }).length).toBeGreaterThanOrEqual(3);
});
it('事件查询失败时保留公共资产与策略展示', () => {
  render(
    <Overview
      data={snapshotFixture()}
      deployment={deployment}
      eventsLoading={false}
      eventsError="日志 RPC 失败"
      onPortfolio={vi.fn()}
      onRebalance={vi.fn()}
    />,
  );
  expect(screen.getByText('最近活动读取失败')).toBeInTheDocument();
  expect(screen.getByText('资产分布')).toBeInTheDocument();
  expect(screen.getByText('策略与价格信号')).toBeInTheDocument();
});
