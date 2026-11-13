import { useQuery } from '@tanstack/react-query';
import { useConnection, usePublicClient } from 'wagmi';
import { deployment } from '../../../config/web3';
import { accountKey, vaultKey } from './keys';
import {
  readAccess,
  readAccount,
  readEvents,
  readGovernance,
  readMembers,
  readParameters,
  readSnapshot,
  validateDeployment,
} from './read';

// Account-independent public RPC reads always use the configured target chain.
export function useDeploymentValidation() {
  const client = usePublicClient({ chainId: deployment?.chainId ?? 31337 });
  const query = useQuery({
    queryKey: vaultKey(deployment, 'validation'),
    enabled: !!deployment && !!client,
    queryFn: () => validateDeployment(client!, deployment!),
    refetchInterval: 3000,
    staleTime: 2000,
  });
  return { client, query, valid: query.isSuccess && !query.isError };
}
export function useVaultSnapshot() {
  const validation = useDeploymentValidation();
  const params = useQuery({
    queryKey: vaultKey(deployment, 'parameters'),
    enabled: validation.valid,
    queryFn: () => readParameters(validation.client!, deployment!),
    staleTime: Infinity,
  });
  const query = useQuery({
    queryKey: vaultKey(deployment, 'snapshot'),
    enabled: validation.valid && params.isSuccess && !params.isError,
    queryFn: () => readSnapshot(validation.client!, deployment!, params.data!),
    refetchInterval: 3000,
    staleTime: 2000,
  });
  const error = validation.query.error ?? params.error ?? query.error;
  return {
    data: error ? undefined : query.data,
    error,
    loading: !error && (!validation.valid || params.isPending || query.isPending),
    refetch: query.refetch,
  };
}
export function useVaultAccess() {
  const { address, chainId } = useConnection();
  const { client, valid, query: validation } = useDeploymentValidation();
  const identityReady = !!address && chainId === deployment?.chainId;
  const query = useQuery({
    queryKey: accountKey(deployment, 'access', address),
    enabled: valid && identityReady,
    queryFn: () => readAccess(client!, deployment!, address!),
    refetchInterval: 3000,
    staleTime: 1000,
  });
  const confirmed = valid && identityReady && query.isSuccess && !query.isError;
  return {
    data: confirmed ? query.data : undefined,
    confirmed,
    error: validation.error ?? query.error,
    loading: identityReady && !confirmed && !query.isError,
    refetch: query.refetch,
  };
}
export function useAccountAssets() {
  const { address, chainId } = useConnection();
  const { client, valid } = useDeploymentValidation();
  const enabled = valid && !!address && chainId === deployment?.chainId;
  const query = useQuery({
    queryKey: accountKey(deployment, 'account', address),
    enabled,
    queryFn: () => readAccount(client!, deployment!, address!),
    refetchInterval: 3000,
    staleTime: 1000,
  });
  return { ...query, data: enabled && !query.isError ? query.data : undefined };
}
export function useVaultEvents() {
  const { client, valid } = useDeploymentValidation();
  return useQuery({
    queryKey: vaultKey(deployment, 'events'),
    enabled: valid,
    queryFn: () => readEvents(client!, deployment!),
    refetchInterval: 6000,
    staleTime: 4000,
  });
}
export function useVaultGovernance(enabled: boolean) {
  const { client, valid } = useDeploymentValidation();
  return useQuery({
    queryKey: vaultKey(deployment, 'governance'),
    enabled: valid && enabled,
    queryFn: () => readGovernance(client!, deployment!),
    refetchInterval: 3000,
    staleTime: 2000,
  });
}
export function useRoleMembers(enabled: boolean) {
  const { client, valid } = useDeploymentValidation();
  return useQuery({
    queryKey: vaultKey(deployment, 'members'),
    enabled: valid && enabled,
    queryFn: () => readMembers(client!, deployment!),
    refetchInterval: 30000,
    staleTime: 10000,
  });
}
