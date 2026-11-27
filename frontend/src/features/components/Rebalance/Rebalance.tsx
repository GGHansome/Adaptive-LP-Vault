import { Alert, Button, Card, Flex, Space, Tag, Typography } from 'antd';
import { useState } from 'react';
import { SwapRebalanceForm } from './SwapRebalanceForm';
import { ActionForm } from '../../../shared/components/ActionForm';
import { KeyValues } from '../../../shared/components/KeyValues';
import { PageTitle } from '../../../shared/components/PageTitle';
import { TwoColumns } from '../../../shared/components/TwoColumns';
import { PauseSummary } from '../PauseSummary';
import { regimes, venues } from '../../types';
import type { RebalanceProps } from './interface';

export function Rebalance(p: RebalanceProps) {
  const [revision, setRevision] = useState(0);
  const d = p.data,
    m = p.deployment;
  const idleExit =
    d.activeVenue !== 0 &&
    p.preview?.plan.targetVenue === 0 &&
    p.preview.plan.marketRegime === 3 &&
    !p.preview.requiresSwap;
  const blocked = !p.ready || p.busy || !p.preview || p.expired || p.loading;
  return (
    <Flex vertical gap="large">
      <PageTitle
        eyebrow="STRATEGY EXECUTION"
        title="策略再平衡"
        description="目标由链上策略生成。你可以触发执行，但不能指定目标池或仓位区间。"
        action={
          <Button
            onClick={() => {
              setRevision((previous) => previous + 1);
              p.onRefresh();
            }}
            loading={p.loading}
            disabled={!d.initialized || p.busy}
          >
            刷新计划预览
          </Button>
        }
      />
      <PauseSummary pause={d.pause} />
      <TwoColumns
        left={
          <KeyValues
            title="当前执行状态"
            items={[
              { label: '当前仓位', value: venues[d.activeVenue] },
              {
                label: '已执行市场状态',
                value: !d.initialized
                  ? '尚未初始化'
                  : d.oracle.healthy
                    ? regimes[d.plan.marketRegime]
                    : '预言机不可用',
              },
              { label: '已提交计划版本', value: String(d.plan.version) },
              {
                label: '冷却时间',
                value: idleExit
                  ? '撤至 IDLE 豁免冷却；重新入场仍需冷却'
                  : p.cooldown
                    ? `${p.cooldown} 秒后可执行`
                    : '已结束',
              },
              { label: '最大协议换币滑点', value: `${Number(d.params.maxSwapSlippageBps) / 100}%` },
              {
                label: '最大迁移净值损失',
                value: `${Number(d.params.maxMigrationLossBps) / 100}%`,
              },
            ]}
          />
        }
        right={
          <Card title="候选计划">
            {p.previewError ? (
              <Alert showIcon type="warning" title="当前无法预览" description={p.previewError} />
            ) : p.preview && d.oracle.healthy ? (
              <Flex vertical gap="middle">
                <Space wrap>
                  <Tag color="cyan">{venues[p.preview.plan.targetVenue]}</Tag>
                  <Tag>{regimes[p.preview.plan.marketRegime]}</Tag>
                  <Tag color={p.preview.requiresSwap ? 'orange' : 'green'}>
                    {p.preview.requiresSwap ? '需要换币' : '无需换币'}
                  </Tag>
                </Space>
                <Typography.Text>
                  候选版本 {String(p.preview.plan.version)} · Tick {p.preview.plan.tickLower} →{' '}
                  {p.preview.plan.tickUpper}
                </Typography.Text>
                <Typography.Text code className="hash-text">
                  {p.preview.plan.planHash}
                </Typography.Text>
                <Typography.Text>
                  方向：
                  {p.preview.direction === 1
                    ? `${m.symbol0} → ${m.symbol1}`
                    : p.preview.direction === 2
                      ? `${m.symbol1} → ${m.symbol0}`
                      : '无'}
                </Typography.Text>
                {p.expired && <Alert title="预览已超过 60 秒，请刷新" type="warning" />}
              </Flex>
            ) : (
              <Alert title="点击刷新计划预览，读取实时策略目标" type="info" />
            )}
          </Card>
        }
      />
      <TwoColumns
        left={
          <ActionForm
            title="普通再平衡"
            description="任何账户都可触发无需换币的计划。极端偏离撤至 IDLE 豁免冷却，重新入场仍需冷却；其他执行检查保持有效。"
            fields={[]}
            submit="执行普通再平衡"
            busy={p.busy}
            disabled={
              blocked ||
              (p.cooldown > 0 && !idleExit) ||
              !!p.preview?.requiresSwap ||
              d.pause.plainRebalancePaused
            }
            onSubmit={p.onExecute}
          />
        }
        right={
          <SwapRebalanceForm
            p={p}
            revision={revision}
            disabled={
              blocked ||
              !d.oracle.healthy ||
              p.cooldown > 0 ||
              !p.allowedSwap ||
              !p.preview?.requiresSwap ||
              (p.preview.direction !== 1 && p.preview.direction !== 2) ||
              d.pause.swapRebalancePaused
            }
          />
        }
      />
      <Alert
        type="info"
        showIcon
        title="行情模拟与 Vault 执行彼此独立"
        description="持续交易进程仅改变池状态。市场信号不会自动更新已执行仓位，计划提交、换币与建仓都需要人工触发，并通过合约的全部风控检查。"
      />
    </Flex>
  );
}
