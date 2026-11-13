import { Alert, Flex, Spin, Typography } from 'antd';
import type { QueryStatusProps } from './interface';
export function QueryStatus({ loading, error, children }: QueryStatusProps) {
  if (error) return <Alert type="error" showIcon title="链上状态不可用" description={error} />;
  if (loading)
    return (
      <Flex align="center" justify="center" vertical gap="middle">
        <Spin />
        <Typography.Text>正在验证合约并读取链上状态…</Typography.Text>
      </Flex>
    );
  return children;
}
