import { Layout, Button, Tag, Menu, Breadcrumb, Flex, Typography, Grid, Tooltip } from 'antd';
import {
  ApartmentOutlined,
  AppstoreOutlined,
  WalletOutlined,
  SwapOutlined,
  SafetyCertificateOutlined,
  SettingOutlined,
  TeamOutlined,
  LinkOutlined,
} from '@ant-design/icons';
import { short } from '../../utils/format';
import type { ShellProps } from './interface';
import './Shell.css';
const icons = {
  '/overview': <AppstoreOutlined />,
  '/portfolio': <WalletOutlined />,
  '/rebalance': <SwapOutlined />,
  '/guardian': <SafetyCertificateOutlined />,
  '/manager': <SettingOutlined />,
  '/admin': <TeamOutlined />,
};
export function Shell(p: ShellProps) {
  const screens = Grid.useBreakpoint();
  const compact = !screens.lg;
  return (
    <Layout className="app-shell">
      <Layout.Sider
        className="app-sidebar"
        aria-label="主导航侧边栏"
        width={248}
        collapsedWidth={64}
        collapsed={compact}
        trigger={null}
      >
        <Flex vertical gap="large" className="sidebar-content">
          <Flex align="center" justify={compact ? 'center' : undefined} gap="small">
            <span className="brand-icon" aria-label="Adaptive LP Vault">
              <ApartmentOutlined />
            </span>
            {!compact && (
              <>
                <div>
                  <Typography.Text className="brand-text">adaptive</Typography.Text>
                  <span className="brand-sub">LIQUIDITY PROTOCOL</span>
                </div>
                <Tag>v1</Tag>
              </>
            )}
          </Flex>
          {!compact && (
            <Typography.Text className="sidebar-caption">
              工作空间 · LOCAL ENVIRONMENT
            </Typography.Text>
          )}
          <nav aria-label="主导航" className="sidebar-navigation">
            <Menu
              theme="dark"
              mode="inline"
              selectedKeys={[p.path]}
              onClick={({ key }) => p.onNavigate(key)}
              items={p.items.map((item) => ({
                key: item.path,
                title: item.label,
                icon: icons[item.path as keyof typeof icons],
                label: (
                  <Button className="nav-button" type="text" tabIndex={compact ? -1 : 0}>
                    {item.label}
                  </Button>
                ),
              }))}
            />
          </nav>
          <Flex vertical align={compact ? 'center' : undefined} gap="small">
            {compact ? (
              <Tooltip title="Anvil 本地网络 · 31337" placement="right">
                <Tag color="green">本地</Tag>
              </Tooltip>
            ) : (
              <>
                <Tag color="green">Anvil 本地网络 · 31337</Tag>
                <Typography.Text className="sidebar-caption">
                  真实合约 · 测试资产
                  <br />
                  仅用于开发和功能验证
                </Typography.Text>
                <Typography.Text className="sidebar-caption">ADAPTIVE LP VAULT</Typography.Text>
              </>
            )}
          </Flex>
        </Flex>
      </Layout.Sider>
      <Layout className="main-layout">
        <Layout.Header className="app-header">
          <Flex justify="space-between" align="center" wrap gap="middle">
            <Breadcrumb
              items={[
                { title: '工作空间' },
                { title: p.items.find((item) => item.path === p.path)?.label ?? '资产管理' },
              ]}
            />
            <Flex align="center" wrap gap="small">
              {!compact && p.status}
              <Tag color="green">本地测试</Tag>
              {p.connected ? (
                <>
                  <Button
                    aria-label={short(p.address)}
                    onClick={p.onDisconnect}
                    icon={<WalletOutlined />}
                  >
                    {short(p.address)}
                  </Button>
                  {p.wrongChain && (
                    <Button type="primary" onClick={p.onSwitch}>
                      切换网络
                    </Button>
                  )}
                </>
              ) : (
                <Button
                  aria-label="连接钱包"
                  type="primary"
                  icon={<LinkOutlined />}
                  loading={p.connecting}
                  onClick={p.onConnect}
                >
                  连接钱包
                </Button>
              )}
            </Flex>
          </Flex>
        </Layout.Header>
        <Layout.Content className="app-content">
          <main>{p.children}</main>
        </Layout.Content>
        <Layout.Footer>
          <Flex justify="space-between" wrap gap="small">
            <Typography.Text type="secondary">Adaptive LP Vault · 双资产流动性管理</Typography.Text>
            <Typography.Text type="secondary">数据来自链上，交易结果以合约执行为准</Typography.Text>
          </Flex>
        </Layout.Footer>
      </Layout>
      {p.transaction}
    </Layout>
  );
}
