import { erc20Abi } from 'viem';
import { deployment } from '../../../../config/web3';
import { vaultAbi, controlAbi } from '../../../../contracts';
import { addressInput, positive } from '../../../../shared/utils/format';
import { useVaultWrite } from '../../server-store/write';
export function useManagerMutation() {
  const write = useVaultWrite();
  const m = deployment;
  return {
    ready: write.ready,
    busy: write.busy,
    async configure(venue: number, adapter: string) {
      if (!m) throw new Error('缺少部署配置');
      return write.send('controls', {
        label: '配置适配器',
        address: m.control,
        abi: controlAbi,
        functionName: 'configureAdapter',
        args: [venue, addressInput(adapter)],
      });
    },
    async bootstrap(values: { amount0: string; amount1: string; receiver: string }) {
      if (!m) throw new Error('缺少部署配置');
      const a = positive(values.amount0, m.decimals0),
        b = positive(values.amount1, m.decimals1),
        receiver = addressInput(values.receiver);
      return write.run('assets', async (send) => {
        await send({
          label: `初始化授权 ${m.symbol0}`,
          address: m.token0,
          abi: erc20Abi,
          functionName: 'approve',
          args: [m.vault, a],
        });
        await send({
          label: `初始化授权 ${m.symbol1}`,
          address: m.token1,
          abi: erc20Abi,
          functionName: 'approve',
          args: [m.vault, b],
        });
        await send({
          label: '初始化 Vault',
          address: m.vault,
          abi: vaultAbi,
          functionName: 'bootstrap',
          args: [a, b, receiver],
        });
      });
    },
  };
}
