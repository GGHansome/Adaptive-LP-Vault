import { deployment } from '../../../config/web3';
import { QueryStatus } from '../../../shared/components/QueryStatus';
import { describeError } from '../../../shared/web3/errors';
import { Rebalance } from '../../components/Rebalance';
import { useRebalanceSelector } from './server-store/selector';
import { useRebalanceMutation } from './server-store/mutation';
export function RebalanceContainer() {
  const state = useRebalanceSelector();
  const mutation = useRebalanceMutation();
  return (
    <QueryStatus
      loading={state.snapshot.loading}
      error={state.snapshot.error && describeError(state.snapshot.error)}
    >
      {deployment && state.snapshot.data && (
        <Rebalance
          data={state.snapshot.data}
          deployment={deployment}
          preview={state.preview.data}
          previewError={state.preview.error ? describeError(state.preview.error) : undefined}
          loading={state.preview.loading}
          ready={mutation.ready}
          busy={mutation.busy}
          cooldown={state.cooldown}
          expired={state.expired}
          allowedSwap={state.allowedSwap}
          onRefresh={state.preview.request}
          onExecute={async () => {
            await mutation.execute(state.preview.data);
            state.preview.clear();
          }}
          onSwap={async (v) => {
            await mutation.execute(state.preview.data, v);
            state.preview.clear();
          }}
        />
      )}
    </QueryStatus>
  );
}
