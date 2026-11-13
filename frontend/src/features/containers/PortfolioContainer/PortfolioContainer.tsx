import { useState } from 'react';
import { useConnection } from 'wagmi';
import { deployment } from '../../../config/web3';
import { QueryStatus } from '../../../shared/components/QueryStatus';
import { describeError } from '../../../shared/web3/errors';
import { Portfolio } from '../../components/Portfolio';
import type { DepositFormValues, RedeemFormValues } from '../../types';
import { usePortfolioSelector } from './server-store/selector';
import { usePortfolioMutation } from './server-store/mutation';

export function PortfolioContainer() {
  const { address, isConnected } = useConnection();
  const [deposit, setDeposit] = useState<DepositFormValues>({
    amount0: '100',
    amount1: '100',
    receiver: address ?? '',
    slippage: '50',
  });
  const [redeem, setRedeem] = useState<RedeemFormValues>({
    shares: '1',
    owner: address ?? '',
    receiver: address ?? '',
    slippage: '50',
  });
  const state = usePortfolioSelector(deposit, redeem);
  const actions = usePortfolioMutation();
  const error = state.depositPreview.error ?? state.redeemPreview.error;
  return (
    <QueryStatus
      loading={state.snapshot.loading}
      error={state.snapshot.error && describeError(state.snapshot.error)}
    >
      {deployment && state.snapshot.data && (
        <Portfolio
          deployment={deployment}
          address={address}
          connected={isConnected}
          ready={state.ready && actions.ready}
          busy={actions.busy}
          initialized={state.snapshot.data.initialized}
          account={state.account.data}
          accountError={state.account.error ? describeError(state.account.error) : undefined}
          reason={state.reason}
          ratio={state.ratio}
          depositPreview={state.depositPreview.data}
          redeemPreview={state.redeemPreview.data}
          previewError={error ? describeError(error) : undefined}
          depositPreviewLoading={state.depositPreview.loading}
          redeemPreviewLoading={state.redeemPreview.loading}
          onDepositChange={(v) => {
            setDeposit(v);
            state.depositPreview.clear();
          }}
          onRedeemChange={(v) => {
            setRedeem(v);
            state.redeemPreview.clear();
          }}
          onDepositPreview={state.depositPreview.request}
          onRedeemPreview={state.redeemPreview.request}
          onApprove={(token) => actions.approve(token, token ? deposit.amount1 : deposit.amount0)}
          onDeposit={async () => {
            await actions.deposit(deposit, state.depositPreview.data);
            state.depositPreview.clear();
          }}
          onRedeem={async () => {
            await actions.redeem(redeem, state.redeemPreview.data);
            state.redeemPreview.clear();
          }}
          onTransfer={actions.transfer}
          onApproveShares={actions.approveShares}
          onRenounce={actions.renounce}
        />
      )}
    </QueryStatus>
  );
}
