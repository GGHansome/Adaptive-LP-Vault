import { Card, Descriptions } from 'antd';
import type { KeyValuesProps } from './interface';
export function KeyValues({ title, items }: KeyValuesProps) {
  return (
    <Card title={title}>
      <Descriptions
        column={1}
        items={items.map((item, key) => ({ key, label: item.label, children: item.value }))}
      />
    </Card>
  );
}
