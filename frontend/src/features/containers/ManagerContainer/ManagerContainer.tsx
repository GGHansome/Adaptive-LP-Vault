import { useConnection } from 'wagmi';
import { deployment } from '../../../config/web3';
import { PermissionNotice } from '../../../shared/components/PermissionNotice';
import { QueryStatus } from '../../../shared/components/QueryStatus';
import { describeError } from '../../../shared/web3/errors';
import { Manager } from '../../components/Manager';
import { ControlsContainer } from '../ControlsContainer';
import { useManagerSelector } from './server-store/selector';
import { useManagerMutation } from './server-store/mutation';
export function ManagerContainer() {
  const { address } = useConnection();
  const { snapshot, access } = useManagerSelector();
  const mutation = useManagerMutation();
  const error = snapshot.error ?? access.error;
  if (error || snapshot.loading || access.loading)
    return <QueryStatus loading={!error} error={error && describeError(error)} />;
  if (!access.data?.manager) return <PermissionNotice />;
  return (
    deployment &&
    snapshot.data && (
      <Manager
        data={snapshot.data}
        deployment={deployment}
        address={address}
        ready={mutation.ready && access.confirmed}
        busy={mutation.busy}
        controls={<ControlsContainer />}
        onConfigure={mutation.configure}
        onBootstrap={mutation.bootstrap}
        onRefresh={() => void snapshot.refetch()}
      />
    )
  );
}
