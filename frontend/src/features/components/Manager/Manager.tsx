import { Alert, Button, Flex, Typography } from 'antd';
import { ActionForm } from '../../../shared/components/ActionForm';
import { KeyValues } from '../../../shared/components/KeyValues';
import { PageTitle } from '../../../shared/components/PageTitle';
import { TwoColumns } from '../../../shared/components/TwoColumns';
import { amount, inputAmount } from '../../../shared/utils/format';
import { venues } from '../../types';
import type { ManagerProps } from './interface';
export function Manager(p: ManagerProps) {
  const d = p.data,
    m = p.deployment;
  return (
    <Flex vertical gap="large">
      <PageTitle
        eyebrow="VAULT OPERATIONS"
        title="运行管理"
        description="初始化、固定依赖与运行控制。部署后固定的策略和风控参数仅可查询。"
      />
      {!d.initialized ? (
        <>
          <Alert
            showIcon
            type="warning"
            title="尚未初始化：需要全部适配器绑定有效、健康预言机与合适的双资产初始比例。"
          />
          <TwoColumns
            left={
              <Flex vertical gap="large">
                {[1, 2, 3].map((venue) => (
                  <ActionForm
                    key={venue}
                    title={`配置 ${venues[venue]}`}
                    fields={[
                      {
                        name: 'adapter',
                        label: '适配器地址',
                        type: 'address',
                        initial: m.adapters[venue - 1],
                      },
                    ]}
                    submit="验证并配置绑定"
                    disabled={!p.ready || p.busy}
                    busy={p.busy}
                    onSubmit={(v) => p.onConfigure(venue, v.adapter)}
                  />
                ))}
              </Flex>
            }
            right={
              <ActionForm
                title="一次性 Bootstrap"
                description="预填金额来自本地部署时的实际池比例。行情变化后可能需要重新调整。初始化成功后不可再次执行。"
                fields={[
                  {
                    name: 'amount0',
                    label: `${m.symbol0} 初始数量`,
                    type: 'number',
                    initial: inputAmount(BigInt(m.bootstrapAmounts[0]), m.decimals0),
                  },
                  {
                    name: 'amount1',
                    label: `${m.symbol1} 初始数量`,
                    type: 'number',
                    initial: inputAmount(BigInt(m.bootstrapAmounts[1]), m.decimals1),
                  },
                  { name: 'receiver', label: '份额接收地址', initial: p.address, type: 'address' },
                ]}
                submit="执行 Bootstrap"
                busy={p.busy}
                disabled={!p.ready || p.busy}
                confirm="初始化将转入初始资产、永久锁定一部分份额并执行首次策略建仓。确认参数后继续。"
                onSubmit={(v) =>
                  p.onBootstrap({ amount0: v.amount0, amount1: v.amount1, receiver: v.receiver })
                }
              >
                <Typography.Text type="secondary">
                  初始化会分别请求两次代币授权和一次 Bootstrap 签名。
                </Typography.Text>
              </ActionForm>
            }
          />
        </>
      ) : (
        p.controls
      )}
      <TwoColumns
        left={
          <KeyValues
            title="固定策略参数"
            items={Object.entries(d.params).map(([label, value]) => ({
              label,
              value:
                label === 'minimumLockedShares'
                  ? `${amount(BigInt(value), 18)} ALPV`
                  : String(value),
            }))}
          />
        }
        right={
          <Flex vertical gap="large">
            <KeyValues
              title="不可变组件绑定"
              items={[
                { label: 'Vault', value: <code className="hash-text">{m.vault}</code> },
                { label: 'Control', value: <code className="hash-text">{m.control}</code> },
                { label: 'Oracle', value: <code className="hash-text">{m.oracle}</code> },
                { label: 'Swap Executor', value: <code className="hash-text">{m.executor}</code> },
              ]}
            />
            <Alert
              type="info"
              title="管理功能不包含救援、任意转账、用户本金提取或部署后参数修改。"
            />
            <Button onClick={p.onRefresh}>刷新链上状态</Button>
          </Flex>
        }
      />
    </Flex>
  );
}
