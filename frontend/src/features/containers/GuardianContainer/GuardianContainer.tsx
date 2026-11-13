import { Alert, Flex } from 'antd';
import { PageTitle } from '../../../shared/components/PageTitle';
import { ControlsContainer } from '../ControlsContainer';
export function GuardianContainer() {
  return (
    <Flex vertical gap="large">
      <PageTitle
        eyebrow="SAFETY CONTROLS"
        title="安全控制"
        description="Guardian 可收紧控制和紧急退出；解除限制需要 Manager 权限。"
      />
      <Alert
        type="info"
        showIcon
        title="业务暂停不影响正常赎回，也不赋予任何角色提取用户本金的权限。"
      />
      <ControlsContainer />
    </Flex>
  );
}
