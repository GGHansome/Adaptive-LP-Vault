import type { Deployment } from '../../../config/types';
import type {
  AccountAssets,
  DepositFormValues,
  RedeemFormValues,
  DepositPreview,
  RedeemPreview,
} from '../../types';
export type PortfolioProps = {
  deployment: Deployment;
  address?: string;
  connected: boolean;
  ready: boolean;
  busy: boolean;
  initialized: boolean;
  account?: AccountAssets;
  accountError?: string;
  reason?: string;
  ratio?: readonly [bigint, bigint];
  depositPreview?: DepositPreview;
  redeemPreview?: RedeemPreview;
  previewError?: string;
  depositPreviewLoading: boolean;
  redeemPreviewLoading: boolean;
  onDepositChange: (values: DepositFormValues) => void;
  onRedeemChange: (values: RedeemFormValues) => void;
  onDepositPreview: () => void;
  onRedeemPreview: () => void;
  onApprove: (token: 0 | 1) => Promise<void>;
  onDeposit: () => Promise<void>;
  onRedeem: () => Promise<void>;
  onTransfer: (values: { to: string; shares: string }) => Promise<void>;
  onApproveShares: (values: { spender: string; shares: string }) => Promise<void>;
  onRenounce: (role: string) => Promise<void>;
};
