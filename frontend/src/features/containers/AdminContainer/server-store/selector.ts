import { useVaultAccess, useVaultGovernance, useRoleMembers } from '../../server-store/queries';
export function useAdminSelector() {
  const access = useVaultAccess();
  const allowed = access.confirmed && !!(access.data?.admin || access.data?.pendingAdmin);
  const governance = useVaultGovernance(allowed);
  const members = useRoleMembers(access.confirmed && !!access.data?.admin);
  return { access, governance, members, allowed };
}
