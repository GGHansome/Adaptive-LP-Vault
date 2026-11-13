import { Alert, Typography } from 'antd';
import { useLocation, useNavigate } from 'react-router-dom';
import type { ReactNode } from 'react';
import { deployment, deploymentError } from '../../../config/web3';
import { Shell, type NavItem } from '../../../shared/components/Shell';
import { TransactionNotice } from '../../../shared/components/TransactionNotice';
import {
  transactionStageLabels,
  useTransactionStore,
} from '../../../shared/store/transactionStore';
import { retryTransactionConfirmation } from '../../../shared/web3/transaction';
import { useShellSelector, useBlockStatusSelector } from './server-store/selector';
import { useWalletMutation } from './server-store/mutation';

function BlockStatus() {
  const { data } = useBlockStatusSelector();
  return (
    <Typography.Text type="secondary">{data ? `区块 #${data}` : '等待链上连接'}</Typography.Text>
  );
}
export function ShellContainer({ children }: { children: ReactNode }) {
  const { connection, access } = useShellSelector();
  const tx = useTransactionStore((state) => state.transaction);
  const wallet = useWalletMutation();
  const location = useLocation();
  const navigate = useNavigate();
  const a = access.data;
  const items: NavItem[] = [
    { path: '/overview', label: '流动性总览' },
    { path: '/portfolio', label: '我的资产' },
    { path: '/rebalance', label: '策略再平衡' },
    ...(a?.guardian || a?.manager ? [{ path: '/guardian', label: '安全控制' }] : []),
    ...(a?.manager ? [{ path: '/manager', label: '运行管理' }] : []),
    ...(a?.admin || a?.pendingAdmin ? [{ path: '/admin', label: '角色与权限' }] : []),
  ];
  return (
    <Shell
      items={items}
      path={location.pathname}
      onNavigate={navigate}
      address={connection.address}
      connected={connection.isConnected}
      wrongChain={connection.isConnected && connection.chainId !== (deployment?.chainId ?? 31337)}
      connecting={wallet.connecting}
      onConnect={wallet.connect}
      onDisconnect={wallet.disconnect}
      onSwitch={wallet.switchChain}
      status={<BlockStatus />}
      transaction={
        tx && (
          <TransactionNotice
            label={tx.label}
            stage={transactionStageLabels[tx.stage]}
            hash={tx.hash}
            error={tx.error}
            account={tx.identity.split(':').at(-1)}
            onRetry={
              tx.stage === 'unconfirmed' ? () => void retryTransactionConfirmation() : undefined
            }
          />
        )
      }
    >
      {deploymentError ? (
        <Alert type="error" title="部署配置无效" description={deploymentError} />
      ) : !deployment ? (
        <Alert
          type="info"
          showIcon
          title="本地环境尚未部署"
          description="请先启动 npm run chain，再执行 npm run local:deploy 和 npm run abi。部署后刷新页面即可连接真实链上数据。"
        />
      ) : (
        children
      )}
    </Shell>
  );
}
