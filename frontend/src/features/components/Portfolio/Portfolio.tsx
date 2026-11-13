import { useState } from 'react';
import { Alert, Button, Card, Space, Tabs, Statistic, Row, Col, Flex, Typography } from 'antd';
import { ActionForm } from '../../../shared/components/ActionForm';
import { KeyValues } from '../../../shared/components/KeyValues';
import { PageTitle } from '../../../shared/components/PageTitle';
import { TwoColumns } from '../../../shared/components/TwoColumns';
import { amount } from '../../../shared/utils/format';
import type { PortfolioProps } from './interface';

export function Portfolio(p: PortfolioProps) {
  const m = p.deployment;
  const [actionError, setActionError] = useState<string>();
  async function approve(token: 0 | 1) {
    setActionError(undefined);
    try {
      await p.onApprove(token);
    } catch (error) {
      setActionError(error instanceof Error ? error.message : '授权失败');
    }
  }
  const deposit = (
    <ActionForm
      title="双资产存款"
      description="按活跃仓位本金比例转入实际需要的数量，剩余资产保留在钱包。先授权，再预览，最后确认存款。"
      fields={[
        { name: 'amount0', label: `${m.symbol0} 最大投入`, initial: '100', type: 'number' },
        { name: 'amount1', label: `${m.symbol1} 最大投入`, initial: '100', type: 'number' },
        { name: 'receiver', label: '份额接收地址', initial: p.address, type: 'address' },
        {
          name: 'slippage',
          label: '份额滑点容忍（基点）',
          initial: '50',
          type: 'number',
          hint: '50 基点 = 0.5%；最低输出由模拟结果向下计算。',
        },
      ]}
      onValuesChange={(v) =>
        p.onDepositChange({
          amount0: v.amount0,
          amount1: v.amount1,
          receiver: v.receiver,
          slippage: v.slippage,
        })
      }
      notice={p.reason}
      disabled={!p.ready || p.busy || !!p.reason || !p.depositPreview || p.depositPreviewLoading}
      busy={p.busy}
      submit="确认存款"
      onSubmit={p.onDeposit}
    >
      <Card size="small">
        <Typography.Text type="secondary">按当前本金比例估算</Typography.Text>
        <br />
        <Typography.Text strong>
          {p.ratio
            ? `${amount(p.ratio[0], m.decimals0)} ${m.symbol0} + ${amount(p.ratio[1], m.decimals1)} ${m.symbol1}`
            : '暂不可用'}
        </Typography.Text>
      </Card>
      <Space wrap>
        {([0, 1] as const).map((token) => (
          <Button key={token} disabled={!p.ready || p.busy} onClick={() => void approve(token)}>
            授权 {token ? m.symbol1 : m.symbol0}
          </Button>
        ))}
        <Button
          onClick={p.onDepositPreview}
          loading={p.depositPreviewLoading}
          disabled={!p.ready || p.busy || !!p.reason}
        >
          预览存款
        </Button>
      </Space>
      {p.depositPreview && (
        <Alert
          type="success"
          title={`模拟获得 ${amount(p.depositPreview.shares, 18)} ALPV`}
          description={`实际投入 ${amount(p.depositPreview.used0, m.decimals0)} ${m.symbol0} + ${amount(p.depositPreview.used1, m.decimals1)} ${m.symbol1}`}
        />
      )}
    </ActionForm>
  );
  const redeem = (
    <ActionForm
      title="双资产赎回"
      description="赎回不换币。业务暂停或预言机异常时仍可赎回；代他人操作时需要该 owner 给予你份额授权。"
      fields={[
        { name: 'shares', label: '赎回份额（ALPV）', initial: '1', type: 'number' },
        { name: 'owner', label: '份额持有人', initial: p.address, type: 'address' },
        { name: 'receiver', label: '资产接收地址', initial: p.address, type: 'address' },
        { name: 'slippage', label: '双资产输出滑点（基点）', initial: '50', type: 'number' },
      ]}
      onValuesChange={(v) =>
        p.onRedeemChange({
          shares: v.shares,
          owner: v.owner,
          receiver: v.receiver,
          slippage: v.slippage,
        })
      }
      submit="确认赎回"
      busy={p.busy}
      disabled={!p.ready || p.busy || !p.initialized || !p.redeemPreview || p.redeemPreviewLoading}
      onSubmit={p.onRedeem}
    >
      <Button
        onClick={p.onRedeemPreview}
        loading={p.redeemPreviewLoading}
        disabled={!p.ready || p.busy || !p.initialized}
      >
        预览赎回
      </Button>
      {p.redeemPreview && (
        <Alert
          type="success"
          title={`模拟收到 ${amount(p.redeemPreview.out0, m.decimals0)} ${m.symbol0} + ${amount(p.redeemPreview.out1, m.decimals1)} ${m.symbol1}`}
        />
      )}
    </ActionForm>
  );
  return (
    <Flex vertical gap="large">
      <PageTitle
        eyebrow="MY PORTFOLIO"
        title="我的资产"
        description="持有可转让份额，按比例享有 Vault 的双资产权益。"
      />
      {!p.connected ? (
        <Alert showIcon type="info" title="连接钱包后管理你的资产" />
      ) : (
        !p.ready && (
          <Alert showIcon type="warning" title="请连接 Anvil 本地网络并等待账户数据确认" />
        )
      )}
      {p.accountError && (
        <Alert type="error" title="钱包资产读取失败" description={p.accountError} />
      )}
      <Row gutter={[16, 16]}>
        {[
          [`${m.symbol0} 钱包余额`, amount(p.account?.balance0, m.decimals0)],
          [`${m.symbol1} 钱包余额`, amount(p.account?.balance1, m.decimals1)],
          ['我的 ALPV 份额', amount(p.account?.shares, 18)],
        ].map(([title, value]) => (
          <Col xs={24} md={8} key={title}>
            <Card>
              <Statistic title={title} value={value} />
            </Card>
          </Col>
        ))}
      </Row>
      {(p.previewError || actionError) && (
        <Alert
          type="warning"
          showIcon
          title="操作未完成"
          description={p.previewError ?? actionError}
        />
      )}
      <TwoColumns
        left={
          <Tabs
            items={[
              { key: 'deposit', label: '存入资产', children: deposit },
              { key: 'redeem', label: '赎回资产', children: redeem },
            ]}
          />
        }
        right={
          <Flex vertical gap="large">
            <KeyValues
              title="钱包与授权"
              items={[
                { label: `${m.symbol0} 已授权`, value: amount(p.account?.allowance0, m.decimals0) },
                { label: `${m.symbol1} 已授权`, value: amount(p.account?.allowance1, m.decimals1) },
                { label: '份额精度', value: '18 decimals' },
                { label: '支持资产精度', value: `${m.decimals0} / ${m.decimals1} decimals` },
              ]}
            />
            <ActionForm
              title="转让份额"
              fields={[
                { name: 'to', label: '接收地址', type: 'address' },
                { name: 'shares', label: 'ALPV 数量', type: 'number' },
              ]}
              submit="转让 ALPV"
              disabled={!p.ready || p.busy}
              busy={p.busy}
              confirm="份额转让无法撤销，请核对接收地址。"
              onSubmit={(v) => p.onTransfer({ to: v.to, shares: v.shares })}
            />
            <ActionForm
              title="委托赎回授权"
              description="给指定调用者授权你的份额。此权限允许对方赎回并自行指定资产接收地址，请仅授权可信地址。输入 0 撤销授权。"
              fields={[
                { name: 'spender', label: '授权调用者', type: 'address' },
                { name: 'shares', label: 'ALPV 授权数量', type: 'number' },
              ]}
              submit="更新份额授权"
              disabled={!p.ready || p.busy}
              busy={p.busy}
              confirm="被授权地址可以消费这些份额，核对额度和地址后继续。"
              onSubmit={(v) => p.onApproveShares({ spender: v.spender, shares: v.shares })}
            />
            <ActionForm
              title="放弃自己的业务角色"
              description="仅影响当前钱包，不影响份额持有。放弃后需要根管理员重新授予才能恢复。"
              fields={[{ name: 'role', label: 'manager / guardian / keeper' }]}
              submit="放弃当前业务角色"
              disabled={!p.ready || p.busy}
              busy={p.busy}
              danger
              confirm="你将立即失去此角色，恢复需要根管理员重新授权。"
              onSubmit={(v) => p.onRenounce(v.role)}
            />
          </Flex>
        }
      />
    </Flex>
  );
}
