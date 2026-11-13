import { Space, Tag } from 'antd';
import type { Pause } from '../types';
export function PauseSummary({ pause }: { pause: Pause }) {
  return (
    <Space wrap>
      {[
        ['存款', pause.depositPaused],
        ['普通再平衡', pause.plainRebalancePaused],
        ['换币再平衡', pause.swapRebalancePaused],
      ].map(([label, value]) => (
        <Tag key={String(label)} color={value ? 'orange' : 'green'}>
          {label}：{value ? '已暂停' : '开放'}
        </Tag>
      ))}
    </Space>
  );
}
