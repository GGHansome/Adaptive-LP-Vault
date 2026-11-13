import { Flex, Typography } from 'antd';
import type { PageTitleProps } from './interface';
export function PageTitle({ eyebrow, title, description, action }: PageTitleProps) {
  return (
    <Flex justify="space-between" align="center" wrap gap="middle">
      <div>
        <Typography.Text type="secondary">{eyebrow}</Typography.Text>
        <Typography.Title level={1}>{title}</Typography.Title>
        <Typography.Paragraph type="secondary">{description}</Typography.Paragraph>
      </div>
      {action}
    </Flex>
  );
}
