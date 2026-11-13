import { useNavigate } from 'react-router-dom';
import { deployment } from '../../../config/web3';
import { QueryStatus } from '../../../shared/components/QueryStatus';
import { describeError } from '../../../shared/web3/errors';
import { Overview } from '../../components/Overview';
import { useOverviewSelector } from './server-store/selector';
export function OverviewContainer() {
  const { snapshot, events } = useOverviewSelector();
  const navigate = useNavigate();
  return (
    <QueryStatus loading={snapshot.loading} error={snapshot.error && describeError(snapshot.error)}>
      {snapshot.data && deployment && (
        <Overview
          data={snapshot.data}
          deployment={deployment}
          events={events.data}
          eventsLoading={events.isPending}
          eventsError={events.error ? describeError(events.error) : undefined}
          onPortfolio={() => navigate('/portfolio')}
          onRebalance={() => navigate('/rebalance')}
        />
      )}
    </QueryStatus>
  );
}
