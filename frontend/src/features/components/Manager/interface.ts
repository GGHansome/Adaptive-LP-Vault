import type { ReactNode } from 'react';
import type { Deployment } from '../../../config/types';
import type { VaultSnapshot } from '../../types';
export type ManagerProps = {
  data: VaultSnapshot;
  deployment: Deployment;
  address?: string;
  ready: boolean;
  busy: boolean;
  controls: ReactNode;
  onConfigure: (venue: number, adapter: string) => Promise<void>;
  onBootstrap: (values: { amount0: string; amount1: string; receiver: string }) => Promise<void>;
  onRefresh: () => void;
};
