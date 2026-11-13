import { zeroAddress } from 'viem';
import { deployment } from '../../../../config/web3';
import { controlAbi } from '../../../../contracts';
import { addressInput } from '../../../../shared/utils/format';
import { useVaultWrite } from '../../server-store/write';
import { roleHashes, parseRole } from '../../server-store/constants';
import type { Impact } from '../../server-store/keys';

export function delaySeconds(value: string) {
  if (!/^\d+$/.test(value) || BigInt(value) >= 2n ** 48n)
    throw new Error('延迟须为有效的 uint48 整数秒');
  return Number(value);
}
export function useAdminMutation() {
  const write = useVaultWrite();
  async function send(
    label: string,
    functionName: string,
    args: readonly unknown[] = [],
    impact: Impact = 'governance',
  ) {
    if (!deployment) throw new Error('缺少部署配置');
    return write.send(impact, {
      label,
      address: deployment.control,
      abi: controlAbi,
      functionName,
      args,
    });
  }
  return {
    ready: write.ready,
    busy: write.busy,
    grant: (account: string, role: string) =>
      send('授予业务角色', 'grantRole', [parseRole(role), addressInput(account)], 'roles'),
    revoke: (account: string, role: string) =>
      send('撤销业务角色', 'revokeRole', [parseRole(role), addressInput(account)], 'roles'),
    accept: () => send('接受管理员交接', 'acceptDefaultAdminTransfer'),
    beginTransfer: (account: string) =>
      send('预约管理员交接', 'beginDefaultAdminTransfer', [addressInput(account)]),
    cancelTransfer: () => send('取消管理员交接', 'cancelDefaultAdminTransfer'),
    changeDelay: (seconds: string) =>
      send('变更管理员延迟', 'changeDefaultAdminDelay', [delaySeconds(seconds)]),
    rollbackDelay: () => send('回滚管理员延迟', 'rollbackDefaultAdminDelay'),
    scheduleRenounce: () => send('预约注销根管理员', 'beginDefaultAdminTransfer', [zeroAddress]),
    renounceAdmin: () => send('注销根管理员', 'renounceRole', [roleHashes.admin, write.address]),
    renounceRole: (role: string) =>
      send('放弃业务角色', 'renounceRole', [parseRole(role), write.address], 'roles'),
  };
}
