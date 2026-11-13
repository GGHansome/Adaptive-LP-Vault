import type { Deployment } from '../../../config/types';
import type { RebalancePreview, VaultSnapshot } from '../../types';
export type RebalanceProps = {
  data: VaultSnapshot;
  deployment: Deployment;
  preview?: RebalancePreview;
  previewError?: string;
  loading: boolean;
  ready: boolean;
  busy: boolean;
  cooldown: number;
  expired: boolean;
  allowedSwap: boolean;
  onRefresh: () => void;
  onExecute: () => Promise<void>;
  onSwap: (values: { amountIn: string; minOut: string }) => Promise<void>;
};
