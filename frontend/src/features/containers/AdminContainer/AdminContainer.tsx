import { PermissionNotice } from '../../../shared/components/PermissionNotice';
import { QueryStatus } from '../../../shared/components/QueryStatus';
import { describeError } from '../../../shared/web3/errors';
import { Admin } from '../../components/Admin';
import { useAdminSelector } from './server-store/selector';
import { useAdminMutation } from './server-store/mutation';
export function AdminContainer() {
  const state = useAdminSelector();
  const actions = useAdminMutation();
  if (state.access.error || state.access.loading)
    return (
      <QueryStatus
        loading={!state.access.error}
        error={state.access.error && describeError(state.access.error)}
      />
    );
  if (!state.allowed || !state.access.data) return <PermissionNotice />;
  return (
    <QueryStatus
      loading={state.governance.isPending}
      error={state.governance.error && describeError(state.governance.error)}
    >
      {state.governance.data && (
        <Admin
          access={state.access.data}
          governance={state.governance.data}
          ready={actions.ready && state.access.confirmed}
          busy={actions.busy}
          members={state.members.data}
          membersLoading={state.members.isPending}
          membersError={state.members.error ? describeError(state.members.error) : undefined}
          onRefreshMembers={() => void state.members.refetch()}
          onGrant={actions.grant}
          onRevoke={actions.revoke}
          onAccept={actions.accept}
          onBeginTransfer={actions.beginTransfer}
          onCancelTransfer={actions.cancelTransfer}
          onChangeDelay={actions.changeDelay}
          onRollbackDelay={actions.rollbackDelay}
          onScheduleRenounce={actions.scheduleRenounce}
          onRenounceAdmin={actions.renounceAdmin}
          onRenounceRole={actions.renounceRole}
        />
      )}
    </QueryStatus>
  );
}
