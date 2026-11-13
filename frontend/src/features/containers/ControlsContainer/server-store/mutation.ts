import { deployment } from '../../../../config/web3';
import { vaultAbi, controlAbi } from '../../../../contracts';
import { useVaultWrite } from '../../server-store/write';
import type { Pause } from '../../../types';
export function useControlsMutation() {
  const write = useVaultWrite();
  const m = deployment;
  return {
    ready: write.ready,
    busy: write.busy,
    async setPause(pause: Pause) {
      if (!m) throw new Error('缺少部署配置');
      return write.send('controls', {
        label: '更新暂停状态',
        address: m.control,
        abi: controlAbi,
        functionName: 'setPauseState',
        args: [pause],
      });
    },
    async setAdapter(venue: number, enabled: boolean) {
      if (!m) throw new Error('缺少部署配置');
      return write.send('controls', {
        label: enabled ? '启用适配器' : '禁用适配器',
        address: m.control,
        abi: controlAbi,
        functionName: 'setAdapterEnabled',
        args: [venue, enabled],
      });
    },
    async emergencyExit() {
      if (!m) throw new Error('缺少部署配置');
      return write.send('strategy', {
        label: '紧急退出',
        address: m.vault,
        abi: vaultAbi,
        functionName: 'emergencyExitToIdle',
      });
    },
  };
}
