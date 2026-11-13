import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { Grid } from 'antd';
import { afterEach, expect, it, vi } from 'vitest';
import { Shell } from './Shell';
import type { ShellProps } from './interface';

function props(): ShellProps {
  return {
    children: <h1>页面内容</h1>,
    items: [
      { path: '/overview', label: '流动性总览' },
      { path: '/rebalance', label: '策略再平衡' },
    ],
    path: '/overview',
    onNavigate: vi.fn(),
    connected: false,
    wrongChain: false,
    connecting: false,
    onConnect: vi.fn(),
    onDisconnect: vi.fn(),
    onSwitch: vi.fn(),
    status: <span>区块 #1</span>,
    transaction: null,
  };
}
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});
it('桌面常驻完整 sidebar，点击导航只触发一次页面切换', () => {
  vi.spyOn(Grid, 'useBreakpoint').mockReturnValue({ lg: true });
  const p = props();
  render(<Shell {...p} />);
  expect(screen.getByRole('complementary', { name: '主导航侧边栏' })).toBeVisible();
  expect(screen.getByText('adaptive')).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: '策略再平衡' }));
  expect(p.onNavigate).toHaveBeenCalledExactlyOnceWith('/rebalance');
  expect(screen.queryByRole('button', { name: '打开导航' })).not.toBeInTheDocument();
});
it('窄屏仍有常驻图标导航，可直接切换页面且没有抽屉', () => {
  vi.spyOn(Grid, 'useBreakpoint').mockReturnValue({ lg: false });
  const p = props();
  const { container } = render(<Shell {...p} />);
  expect(screen.getByRole('complementary', { name: '主导航侧边栏' })).toBeVisible();
  expect(container.querySelector('.ant-layout-sider-collapsed')).toBeInTheDocument();
  expect(container.querySelector('.ant-drawer')).not.toBeInTheDocument();
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('menuitem', { name: /策略再平衡/ }));
  expect(p.onNavigate).toHaveBeenCalledExactlyOnceWith('/rebalance');
});
it('保留钱包连接和错误网络下的切换入口', () => {
  vi.spyOn(Grid, 'useBreakpoint').mockReturnValue({ lg: true });
  const p = props();
  const { rerender } = render(<Shell {...p} />);
  fireEvent.click(screen.getByRole('button', { name: '连接钱包' }));
  expect(p.onConnect).toHaveBeenCalledOnce();
  rerender(
    <Shell {...p} connected wrongChain address="0x1111111111111111111111111111111111111111" />,
  );
  fireEvent.click(screen.getByRole('button', { name: '切换网络' }));
  expect(p.onSwitch).toHaveBeenCalledOnce();
});
