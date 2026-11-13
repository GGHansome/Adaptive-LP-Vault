import { Alert } from 'antd';
export function PermissionNotice() {
  return (
    <Alert
      type="warning"
      showIcon
      title="当前账户没有此页面的访问权限"
      description="请切换具有对应链上角色的钱包。根管理员不自动拥有业务角色。"
    />
  );
}
