import { useConnection } from 'wagmi';
import type { PublicClient } from 'viem';
import { deployment } from '../../../../config/web3';
import type { Deployment } from '../../../../config/types';
import { vaultAbi } from '../../../../contracts';
import { previewExpired } from '../../../../shared/utils/format';
import {
  useVaultAccess,
  useVaultSnapshot,
  useDeploymentValidation,
} from '../../server-store/queries';
import { usePreviewQuery } from '../../server-store/preview';
import { vaultKey } from '../../server-store/keys';
import type { RebalancePreview } from '../../../types';

export async function readRebalancePreview(
  client: PublicClient,
  m: Deployment,
  atBlock?: { number: bigint; timestamp: bigint },
): Promise<RebalancePreview> {
  const block = atBlock ?? (await client.getBlock());
  const result = await client.readContract({
    address: m.vault,
    abi: vaultAbi,
    functionName: 'previewRebalance',
    blockNumber: block.number,
  });
  return { plan: result[0], ...result[1], at: Number(block.timestamp) };
}
export function useRebalanceSelector() {
  const snapshot = useVaultSnapshot();
  const access = useVaultAccess();
  const { client, valid } = useDeploymentValidation();
  const { address, chainId } = useConnection();
  const preview = usePreviewQuery(
    vaultKey(deployment, 'preview', 'rebalance', address, chainId),
    valid && !!snapshot.data?.initialized,
    () => readRebalancePreview(client!, deployment!),
  );
  const d = snapshot.data;
  const cooldown = d
    ? Math.max(0, d.lastChange + Number(d.params.minRebalanceCooldown) - d.blockTime)
    : 0;
  const expired =
    !!preview.data && !!d && (!d.oracle.healthy || previewExpired(preview.data.at, d.blockTime));
  return {
    client,
    address,
    chainId,
    snapshot,
    access,
    preview,
    cooldown,
    expired,
    allowedSwap: access.confirmed && !!(access.data?.manager || access.data?.keeper),
  };
}
