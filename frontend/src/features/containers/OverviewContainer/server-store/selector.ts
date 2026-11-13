import { useVaultEvents, useVaultSnapshot } from '../../server-store/queries';
export function useOverviewSelector() {
  const snapshot = useVaultSnapshot();
  const events = useVaultEvents();
  return { snapshot, events };
}
