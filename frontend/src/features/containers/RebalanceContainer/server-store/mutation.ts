import { usePublicClient } from 'wagmi';
import { deployment } from '../../../../config/web3';
import { vaultAbi } from '../../../../contracts';
import { units, previewExpired } from '../../../../shared/utils/format';
import { useVaultWrite } from '../../server-store/write';
import type { RebalancePreview } from '../../../types';
import { readRebalancePreview } from './selector';

export function useRebalanceMutation() {
  const write = useVaultWrite();
  const client = usePublicClient({ chainId: deployment?.chainId ?? 31337 });
  return {
    ready: write.ready,
    busy: write.busy,
    async execute(
      preview: RebalancePreview | undefined,
      swap?: { amountIn: string; minOut: string },
    ) {
      const m = deployment;
      if (!preview || !m || !client) throw new Error('请先获取计划预览');
      return write.run('strategy', async (send) => {
        const current = await readRebalancePreview(client, m);
        if (previewExpired(preview.at, current.at)) throw new Error('预览已过期，请重新获取计划');
        if (
          current.plan.planHash !== preview.plan.planHash ||
          current.requiresSwap !== preview.requiresSwap ||
          current.direction !== preview.direction
        )
          throw new Error('计划或换币方向已改变，请重新预览');
        const deadline = current.at + 120;
        if (swap) {
          const amount = units(swap.amountIn, preview.direction === 2 ? m.decimals1 : m.decimals0);
          if (!amount) throw new Error('换币输入必须大于零');
          await send({
            label: '换币再平衡',
            address: m.vault,
            abi: vaultAbi,
            functionName: 'rebalanceWithSwap',
            args: [
              preview.plan.planHash,
              preview.direction,
              amount,
              units(swap.minOut, preview.direction === 2 ? m.decimals0 : m.decimals1),
              deadline,
            ],
          });
        } else
          await send({
            label: '普通再平衡',
            address: m.vault,
            abi: vaultAbi,
            functionName: 'rebalance',
            args: [preview.plan.planHash, deadline],
          });
      });
    },
  };
}
