import type { Deployment } from '../../../config/types';
import type { EventRow, VaultSnapshot } from '../../types';
export type OverviewProps = {
  data: VaultSnapshot;
  deployment: Deployment;
  events?: EventRow[];
  eventsLoading: boolean;
  eventsError?: string;
  onPortfolio: () => void;
  onRebalance: () => void;
};
