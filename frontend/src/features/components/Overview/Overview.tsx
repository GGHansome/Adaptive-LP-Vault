import {
  Card,
  Tag,
  Table,
  Progress,
  Alert,
  Button,
  Descriptions,
  Empty,
  Flex,
  Row,
  Col,
  Statistic,
  Typography,
} from 'antd';
import { ArrowRightOutlined } from '@ant-design/icons';
import { PageTitle } from '../../../shared/components/PageTitle';
import { TwoColumns } from '../../../shared/components/TwoColumns';
import { venues, regimes } from '../../types';
import { amount, short } from '../../../shared/utils/format';
import type { OverviewProps } from './interface';

export function Overview({
  data: d,
  deployment: m,
  events,
  eventsLoading,
  eventsError,
  onPortfolio,
  onRebalance,
}: OverviewProps) {
  const idle = d.idleBps === undefined ? undefined : Number(d.idleBps) / 100;
  const sharePrice =
    d.nav !== undefined && d.assets.totalShares
      ? (d.nav * 10n ** 18n) / d.assets.totalShares
      : undefined;
  return (
    <Flex vertical gap="large">
      <PageTitle
        eyebrow="VAULT OVERVIEW"
        title="流动性总览"
        description="了解资产分布、策略仓位与协议运行状态。"
        action={
          <Button type="primary" onClick={onPortfolio}>
            管理我的资产 <ArrowRightOutlined />
          </Button>
        }
      />
      <Card>
        <Flex justify="space-between" align="center" wrap gap="large">
          <div>
            <Tag color="green">链上运行状态</Tag>
            <Typography.Title level={2}>让每一次仓位调整，都有可验证的依据。</Typography.Title>
            <Typography.Paragraph type="secondary">
              单活仓位 · 链上价格信号 · 双资产权益
            </Typography.Paragraph>
            <Tag>UNISWAP V2 / V3</Tag>
            <Tag>NON-CUSTODIAL</Tag>
          </div>
          <Statistic title="ACTIVE VENUE" value={venues[d.activeVenue]} />
        </Flex>
      </Card>
      <Row gutter={[16, 16]}>
        <Col xs={24} sm={12} xl={6}>
          <Card>
            <Statistic title={`资产净值 · ${m.symbol1}`} value={amount(d.nav, m.decimals1)} />
            <Typography.Text type="secondary">
              {d.oracle.healthy ? '按长周期 TWAP 计价' : '预言机不可用，暂不展示估值'}
            </Typography.Text>
          </Card>
        </Col>
        <Col xs={24} sm={12} xl={6}>
          <Card>
            <Statistic
              title="每份额净值"
              value={amount(sharePrice, m.decimals1, 6)}
              suffix={m.symbol1}
            />
            <Typography.Text type="secondary">
              总供应量 {amount(d.assets.totalShares, 18)} ALPV
            </Typography.Text>
          </Card>
        </Col>
        <Col xs={24} sm={12} xl={6}>
          <Card>
            <Statistic title="当前策略仓位" value={venues[d.activeVenue]} />
            <Typography.Text type="secondary">
              已执行状态：
              {!d.initialized
                ? '尚未初始化'
                : d.oracle.healthy
                  ? regimes[d.plan.marketRegime]
                  : '预言机不可用'}
            </Typography.Text>
          </Card>
        </Col>
        <Col xs={24} sm={12} xl={6}>
          <Card>
            <Statistic title="预言机健康" value={d.oracle.healthy ? '运行正常' : '暂不可用'} />
            <Typography.Text type="secondary">
              {d.oracle.shortTwapWindowSeconds}s / {d.oracle.twapWindowSeconds}s 价格窗口
            </Typography.Text>
          </Card>
        </Col>
      </Row>
      <TwoColumns
        left={
          <Card title="资产分布" extra={<Tag>双资产会计</Tag>}>
            <Flex vertical gap="middle">
              <Descriptions
                column={1}
                items={[
                  {
                    key: 'token0',
                    label: m.symbol0,
                    children: amount(d.assets.total0, m.decimals0),
                  },
                  {
                    key: 'token1',
                    label: m.symbol1,
                    children: amount(d.assets.total1, m.decimals1),
                  },
                  {
                    key: 'idle',
                    label: '活跃仓位 / 闲置资产',
                    children:
                      idle === undefined
                        ? '—'
                        : `${(100 - idle).toFixed(2)}% / ${idle.toFixed(2)}%`,
                  },
                ]}
              />
              <Progress percent={idle === undefined ? 0 : 100 - idle} showInfo={false} />
              <Typography.Text type="secondary">
                闲置资产依然属于份额持有人。这里展示资产位置，不代表收益表现。
              </Typography.Text>
            </Flex>
          </Card>
        }
        right={
          <Card
            title="策略与价格信号"
            extra={
              <Button type="link" onClick={onRebalance}>
                查看计划 <ArrowRightOutlined />
              </Button>
            }
          >
            <Descriptions
              column={1}
              size="small"
              items={[
                {
                  key: 'spot',
                  label: `现价（${m.symbol1} / ${m.symbol0}）`,
                  children: d.oracle.healthy
                    ? amount(d.oracle.spotPriceToken1, m.decimals1, 8)
                    : '不可用',
                },
                {
                  key: 'twap',
                  label: '长周期 TWAP',
                  children: d.oracle.healthy
                    ? amount(d.oracle.twapPriceToken1, m.decimals1, 8)
                    : '不可用',
                },
                {
                  key: 'short',
                  label: '短周期 TWAP',
                  children: d.oracle.healthy
                    ? amount(d.oracle.shortTwapPriceToken1, m.decimals1, 8)
                    : '不可用',
                },
                {
                  key: 'deviation',
                  label: '短／长周期价格偏离',
                  children: d.oracle.healthy ? (
                    <Tag color="cyan">{(Number(d.oracle.deviationBps) / 100).toFixed(2)}%</Tag>
                  ) : (
                    '不可用'
                  ),
                },
                {
                  key: 'range',
                  label: '活跃 Tick 区间',
                  children:
                    d.position && d.activeVenue > 1
                      ? `${d.position.tickLower} → ${d.position.tickUpper}`
                      : '全区间 / 无活跃 V3 仓位',
                },
                {
                  key: 'fee',
                  label: 'V3 待领取手续费',
                  children: d.position
                    ? `${amount(d.position.claimableFee0, m.decimals0)} ${m.symbol0} / ${amount(d.position.claimableFee1, m.decimals1)} ${m.symbol1}`
                    : '—',
                },
              ]}
            />
          </Card>
        }
      />
      <Card
        title="最近链上活动"
        extra={<Typography.Text type="secondary">最近 500 个区块 · 最多 12 条</Typography.Text>}
      >
        {eventsError ? (
          <Alert type="warning" title="最近活动读取失败" description={eventsError} />
        ) : eventsLoading || events?.length ? (
          <Table
            loading={eventsLoading}
            pagination={false}
            size="middle"
            dataSource={events}
            scroll={{ x: 540 }}
            columns={[
              { title: '事件', dataIndex: 'name' },
              { title: '区块', dataIndex: 'block' },
              {
                title: '交易哈希',
                dataIndex: 'hash',
                render: (hash: string) => <code title={hash}>{short(hash)}</code>,
              },
              { title: '状态', key: 'status', render: () => <Tag color="green">已确认</Tag> },
            ]}
          />
        ) : (
          <Empty description="暂无链上事件" />
        )}
      </Card>
      <Alert
        type="info"
        showIcon
        title="本地测试环境"
        description="测试资产没有真实价值。V2 手续费包含在储备权益中；V3 手续费单独展示。价格偏离不是波动率、年化收益率或收益承诺。"
      />
    </Flex>
  );
}
