import { useConnection, useBlockNumber } from 'wagmi';
import { deployment } from '../../../../config/web3';
import { useVaultAccess } from '../../server-store/queries';
export function useShellSelector() {
  return { connection: useConnection(), access: useVaultAccess() };
}
export function useBlockStatusSelector() {
  return useBlockNumber({ chainId: deployment?.chainId ?? 31337, watch: true });
}
