import { Alert, Button, Flex, Typography } from 'antd';
import { short } from '../utils/format';
export function TransactionNotice({
  label,
  stage,
  hash,
  error,
  account,
  onRetry,
}: {
  label: string;
  stage: string;
  hash?: string;
  error?: string;
  account?: string;
  onRetry?: () => void;
}) {
  return (
    <div className="transaction-notice" role="status">
      <Alert
        type={onRetry ? 'warning' : error ? 'error' : 'info'}
        showIcon
        title={label}
        description={
          <Flex vertical gap="small">
            <Typography.Text>{stage}</Typography.Text>
            {account && (
              <Typography.Text type="secondary">提交账户：{short(account)}</Typography.Text>
            )}
            {hash && <code>{short(hash)}</code>}
            {error && <Typography.Text>{error}</Typography.Text>}
            {onRetry && <Button onClick={onRetry}>重新查询确认</Button>}
          </Flex>
        }
      />
    </div>
  );
}
