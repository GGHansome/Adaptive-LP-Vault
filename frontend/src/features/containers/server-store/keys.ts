import type { Address } from 'viem';
import type { Deployment } from '../../../config/types';

export type Resource =
  | 'validation'
  | 'parameters'
  | 'snapshot'
  | 'account'
  | 'access'
  | 'events'
  | 'governance'
  | 'members'
  | 'preview';
export const vaultKey = (
  m: Deployment | undefined,
  resource: Resource,
  ...params: readonly unknown[]
) => ['vault', m?.chainId, m?.instanceId, m?.vault.toLowerCase(), resource, ...params] as const;
export const accountKey = (
  m: Deployment | undefined,
  resource: 'account' | 'access',
  address?: Address,
) => vaultKey(m, resource, address?.toLowerCase());
export type Impact =
  | 'assets'
  | 'approval'
  | 'sharesApproval'
  | 'strategy'
  | 'controls'
  | 'roles'
  | 'governance';
export function affectedKeys(m: Deployment, account: Address, impact: Impact) {
  const events = vaultKey(m, 'events');
  switch (impact) {
    case 'approval':
    case 'sharesApproval':
      return [accountKey(m, 'account', account), events];
    case 'assets':
      return [vaultKey(m, 'snapshot'), vaultKey(m, 'account'), vaultKey(m, 'preview'), events];
    case 'strategy':
      return [vaultKey(m, 'snapshot'), vaultKey(m, 'account'), vaultKey(m, 'preview'), events];
    case 'controls':
      return [vaultKey(m, 'snapshot'), vaultKey(m, 'preview'), events];
    case 'roles':
      return [vaultKey(m, 'access'), vaultKey(m, 'members'), events];
    case 'governance':
      return [vaultKey(m, 'governance'), vaultKey(m, 'access'), vaultKey(m, 'members'), events];
  }
}
