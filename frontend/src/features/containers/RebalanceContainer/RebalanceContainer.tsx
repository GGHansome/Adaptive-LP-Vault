import { deployment } from '../../../config/web3';
import { QueryStatus } from '../../../shared/components/QueryStatus';
import { describeError } from '../../../shared/web3/errors';
import { Rebalance } from '../../components/Rebalance';
import { useRebalanceSelector } from './server-store/selector';
import { useRebalanceMutation } from './server-store/mutation';
import { readSuggestedSwapAmount } from './server-store/swap-suggestion';
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
          suggestionScope={`${state.chainId}:${state.address}`}
          onSuggestSwap={async (minOut) => {
            if (
              !deployment ||
              !state.client ||
              !state.address ||
              !state.preview.data ||
              !state.allowedSwap ||
              !mutation.ready
            )
              throw new Error('请连接 Keeper 或 Manager 钱包并刷新计划');
            try {
              return await readSuggestedSwapAmount(
                state.client,
                deployment,
                state.address,
                state.preview.data,
                minOut,
              );
            } catch (error) {
              throw new Error(describeError(error), { cause: error });
            }
          }}
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
