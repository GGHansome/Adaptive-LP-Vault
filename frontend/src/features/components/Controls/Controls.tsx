import { Button, Card, Checkbox, Space, Table, Tag, Alert, Flex, Typography } from 'antd';
import { useState } from 'react';
import { ActionForm } from '../../../shared/components/ActionForm';
import { short } from '../../../shared/utils/format';
import { venues, type Pause } from '../../types';
import { PauseSummary } from '../PauseSummary';
import type { ControlsProps } from './interface';

export function Controls(p: ControlsProps) {
  const [desired, setDesired] = useState<Pause>();
  const [error, setError] = useState<string>();
  const state = desired ?? p.pause;
  async function apply(action: () => Promise<void>) {
    setError(undefined);
    try {
      await action();
    } catch (e) {
      setError(e instanceof Error ? e.message : '操作失败');
    }
  }
  return (
    <Flex vertical gap="large">
      {error && <Alert type="error" title="操作未完成" description={error} />}
      <Card title={p.manager ? '暂停与恢复' : '收紧安全控制'}>
        <Flex vertical gap="middle">
          <PauseSummary pause={p.pause} />
          <Flex vertical gap="small">
            {(['depositPaused', 'plainRebalancePaused', 'swapRebalancePaused'] as const).map(
              (field, i) => (
                <Checkbox
                  key={field}
                  checked={state[field] || (!p.manager && p.pause[field])}
                  disabled={!p.ready || p.busy || (!p.manager && p.pause[field])}
                  onChange={(e) => setDesired({ ...state, [field]: e.target.checked })}
                >
                  {['暂停存款', '暂停普通再平衡', '暂停换币再平衡'][i]}
                </Checkbox>
              ),
            )}
          </Flex>
          <Button
            type="primary"
            disabled={!p.ready || p.busy || !p.initialized}
            loading={p.busy}
            onClick={() =>
              void apply(async () => {
                const latest = { ...state };
                if (!p.manager)
                  for (const field of [
                    'depositPaused',
                    'plainRebalancePaused',
                    'swapRebalancePaused',
                  ] as const)
                    latest[field] ||= p.pause[field];
                await p.onSetPause(latest);
                setDesired(undefined);
              })
            }
          >
            提交暂停状态
          </Button>
        </Flex>
      </Card>
      <Card title="适配器运行状态">
        <Flex vertical gap="middle">
          <Table
            rowKey="venue"
            pagination={false}
            dataSource={p.configs}
            scroll={{ x: 540 }}
            columns={[
              { title: '策略位置', dataIndex: 'venue', render: (v: number) => venues[v] },
              {
                title: '适配器',
                dataIndex: 'adapter',
                render: (a: string) => <code title={a}>{short(a)}</code>,
              },
              {
                title: '状态',
                dataIndex: 'enabled',
                render: (v: boolean) => (
                  <Tag color={v ? 'green' : 'orange'}>{v ? '允许进入' : '已禁用'}</Tag>
                ),
              },
              {
                title: '操作',
                key: 'action',
                render: (_, row) => (
                  <Space>
                    <Button
                      danger
                      size="small"
                      disabled={!p.ready || p.busy || !p.initialized || !row.enabled}
                      onClick={() => void apply(() => p.onSetAdapter(row.venue, false))}
                    >
                      禁用
                    </Button>
                    {p.manager && (
                      <Button
                        size="small"
                        disabled={!p.ready || p.busy || !p.initialized || row.enabled}
                        onClick={() => void apply(() => p.onSetAdapter(row.venue, true))}
                      >
                        启用
                      </Button>
                    )}
                  </Space>
                ),
              },
            ]}
          />
          <Typography.Text type="secondary">
            禁用只阻止进入或增加流动性，不阻止现有仓位计价、费用同步和退出。
          </Typography.Text>
        </Flex>
      </Card>
      <ActionForm
        title="紧急退出至 IDLE"
        description="无换币撤出当前仓位，并暂停存款和两种再平衡。正常赎回继续开放；只有 Manager 可以恢复运行控制。"
        fields={[]}
        submit="紧急退出并暂停"
        danger
        busy={p.busy}
        disabled={!p.ready || p.busy || !p.initialized}
        confirm="将撤出当前活跃 LP 仓位并暂停风险操作。此操作不会把资产转给管理员，也不会冻结赎回。"
        onSubmit={p.onEmergencyExit}
      />
    </Flex>
  );
}
