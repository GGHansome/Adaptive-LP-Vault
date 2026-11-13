import { useVaultAccess, useVaultSnapshot } from '../../server-store/queries';
export function useManagerSelector() {
  return { snapshot: useVaultSnapshot(), access: useVaultAccess() };
}
