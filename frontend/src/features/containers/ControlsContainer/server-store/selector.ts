import { useVaultAccess, useVaultSnapshot } from '../../server-store/queries';
export function useControlsSelector() {
  return { snapshot: useVaultSnapshot(), access: useVaultAccess() };
}
