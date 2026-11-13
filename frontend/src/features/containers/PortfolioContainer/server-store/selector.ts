import { useConnection } from 'wagmi';
import { vaultAbi } from '../../../../contracts';
import { deployment } from '../../../../config/web3';
import { addressInput, positive } from '../../../../shared/utils/format';
import {
  useAccountAssets,
  useDeploymentValidation,
  useVaultSnapshot,
} from '../../server-store/queries';
import { usePreviewQuery } from '../../server-store/preview';
import { vaultKey } from '../../server-store/keys';
import { depositReason, proportional } from '../../../utils/rules';
import type { DepositFormValues, RedeemFormValues } from '../../../types';

export function usePortfolioSelector(deposit: DepositFormValues, redeem: RedeemFormValues) {
  const snapshot = useVaultSnapshot();
  const account = useAccountAssets();
  const { client, valid } = useDeploymentValidation();
  const { address, chainId } = useConnection();
  const m = deployment;
  const d = snapshot.data;
  const ready =
    valid && !!address && chainId === m?.chainId && !!d && !!account.data && !account.isError;
  const reason = d
    ? depositReason(
        d.initialized,
        d.activeVenue,
        d.oracle.healthy,
        d.pause.depositPaused,
        !!d.configs.find((c) => c.venue === d.activeVenue)?.enabled,
        !d.position?.principal0 || !d.position?.principal1,
        d.idleBps !== undefined && d.idleBps <= BigInt(d.params.maxHealthyIdleBps),
      )
    : undefined;
  const depositPreview = usePreviewQuery(
    vaultKey(m, 'preview', 'deposit', address, chainId, deposit),
    ready && !reason,
    async () => {
      const { result } = await client!.simulateContract({
        address: m!.vault,
        abi: vaultAbi,
        functionName: 'deposit',
        args: [
          positive(deposit.amount0, m!.decimals0),
          positive(deposit.amount1, m!.decimals1),
          0n,
          addressInput(deposit.receiver),
        ],
        account: address,
      });
      return { used0: result[0], used1: result[1], shares: result[2] };
    },
  );
  const redeemPreview = usePreviewQuery(
    vaultKey(m, 'preview', 'redeem', address, chainId, redeem),
    ready && !!d?.initialized,
    async () => {
      const { result } = await client!.simulateContract({
        address: m!.vault,
        abi: vaultAbi,
        functionName: 'redeem',
        args: [
          positive(redeem.shares, 18),
          0n,
          0n,
          addressInput(redeem.receiver),
          addressInput(redeem.owner),
        ],
        account: address,
      });
      return { out0: result[0], out1: result[1] };
    },
  );
  let ratio: readonly [bigint, bigint] | undefined;
  try {
    if (m && d?.position)
      ratio = proportional(
        positive(deposit.amount0, m.decimals0),
        positive(deposit.amount1, m.decimals1),
        d.position.principal0,
        d.position.principal1,
      );
  } catch {
    /* Invalid drafts are reported by explicit preview, never sent automatically. */
  }
  return { snapshot, account, ready, reason, depositPreview, redeemPreview, ratio };
}
