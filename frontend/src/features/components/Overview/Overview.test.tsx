import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, expect, it, vi } from 'vitest';
import { Overview } from './Overview';
import { deployment, snapshotFixture } from '../../test/fixtures';
afterEach(cleanup);
it('按长周期 TWAP 将总净值和每份额净值主显示为 tUSD，并保留 tETH 对照', () => {
  const data = snapshotFixture();
  data.nav = 1_500_000_000_000_000_000n;
  data.oracle.twapPriceToken1 = 500_000_000_000_000_000n;
  render(
    <Overview
      data={data}
      deployment={deployment}
      events={[]}
      eventsLoading={false}
      onPortfolio={vi.fn()}
      onRebalance={vi.fn()}
    />,
  );
  const total = screen.getByRole('group', { name: '资产净值' });
  const perShare = screen.getByRole('group', { name: '每份额净值' });
  expect(total).toHaveTextContent(/3\s*tUSD/);
  expect(perShare).toHaveTextContent(/1\.5\s*tUSD/);
  expect(screen.getByText('约 1.5 tETH')).toBeInTheDocument();
  expect(screen.getByText('约 0.75 tETH')).toBeInTheDocument();
});
it('没有已发行份额时不展示每份额估值', () => {
  const data = snapshotFixture();
  data.assets.totalShares = 0n;
  render(
    <Overview
      data={data}
      deployment={deployment}
      events={[]}
      eventsLoading={false}
      onPortfolio={vi.fn()}
      onRebalance={vi.fn()}
    />,
  );
  expect(screen.getByRole('group', { name: '每份额净值' })).toHaveTextContent('—');
  expect(screen.getByText('尚无已发行份额')).toBeInTheDocument();
});
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
