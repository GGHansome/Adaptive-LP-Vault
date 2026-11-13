import type { Address } from 'viem';

export type Plan = {
  planHash: Address;
  targetVenue: number;
  marketRegime: number;
  tickLower: number;
  tickUpper: number;
  version: bigint;
};
export type Oracle = {
  healthy: boolean;
  spotTick: number;
  twapTick: number;
  shortTwapTick: number;
  spotPriceToken1: bigint;
  twapPriceToken1: bigint;
  shortTwapPriceToken1: bigint;
  deviationBps: bigint;
  observedAt: number;
  twapWindowSeconds: number;
  shortTwapWindowSeconds: number;
};
export type Position = {
  venue: number;
  adapter: Address;
  principal0: bigint;
  principal1: bigint;
  claimableFee0: bigint;
  claimableFee1: bigint;
  amount0: bigint;
  amount1: bigint;
  liquidity: bigint;
  positionId: bigint;
  tickLower: number;
  tickUpper: number;
};
export type Assets = {
  idle0: bigint;
  idle1: bigint;
  position0: bigint;
  position1: bigint;
  total0: bigint;
  total1: bigint;
  totalShares: bigint;
};
export type Pause = {
  depositPaused: boolean;
  plainRebalancePaused: boolean;
  swapRebalancePaused: boolean;
};
export type Access = {
  admin: boolean;
  manager: boolean;
  guardian: boolean;
  keeper: boolean;
  pendingAdmin: boolean;
};
export type AdapterConfig = {
  venue: number;
  adapter: Address;
  tickSpacing: number;
  enabled: boolean;
};
export type VaultSnapshot = {
  initialized: boolean;
  activeVenue: number;
  assets: Assets;
  position?: Position;
  oracle: Oracle;
  plan: Plan;
  pause: Pause;
  nav?: bigint;
  idleBps?: bigint;
  lastChange: number;
  blockTime: number;
  blockNumber: bigint;
  configs: AdapterConfig[];
  params: Record<string, bigint | number>;
};
export type Governance = {
  pendingAdmin: { address: Address; acceptAt: number };
  adminDelay: number;
  pendingDelay: { delay: number; effectiveAt: number };
  blockTime: number;
};
export type AccountAssets = {
  balance0: bigint;
  balance1: bigint;
  shares: bigint;
  allowance0: bigint;
  allowance1: bigint;
};
export type EventRow = { key: string; name: string; block: string; hash: string };
export type RoleMember = { address: Address; roles: { role: string; has: boolean }[] };
export type RebalancePreview = { plan: Plan; requiresSwap: boolean; direction: number; at: number };
export type DepositFormValues = {
  amount0: string;
  amount1: string;
  receiver: string;
  slippage: string;
};
export type RedeemFormValues = {
  shares: string;
  owner: string;
  receiver: string;
  slippage: string;
};
export type DepositPreview = { used0: bigint; used1: bigint; shares: bigint };
export type RedeemPreview = { out0: bigint; out1: bigint };
export const venues = ['持币 · IDLE', 'Uniswap V2', 'V3 · 低费率', 'V3 · 高费率'];
export const regimes = ['低偏离', '中偏离', '高偏离', '极端偏离'];
