import { PermissionNotice } from '../../../shared/components/PermissionNotice';
import { QueryStatus } from '../../../shared/components/QueryStatus';
import { describeError } from '../../../shared/web3/errors';
import { Controls } from '../../components/Controls';
import { useControlsSelector } from './server-store/selector';
import { useControlsMutation } from './server-store/mutation';
export function ControlsContainer() {
  const { snapshot, access } = useControlsSelector();
  const mutation = useControlsMutation();
  const error = snapshot.error ?? access.error;
  if (error || snapshot.loading || access.loading)
    return <QueryStatus loading={!error} error={error && describeError(error)} />;
  if (!access.data || !(access.data.manager || access.data.guardian)) return <PermissionNotice />;
  return (
    snapshot.data && (
      <Controls
        pause={snapshot.data.pause}
        configs={snapshot.data.configs}
        initialized={snapshot.data.initialized}
        manager={access.data.manager}
        ready={mutation.ready && access.confirmed}
        busy={mutation.busy}
        onSetPause={mutation.setPause}
        onSetAdapter={mutation.setAdapter}
        onEmergencyExit={mutation.emergencyExit}
      />
    )
  );
}
