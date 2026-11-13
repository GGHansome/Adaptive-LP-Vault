import { keccak256, stringToHex } from 'viem';
export const parameterNames = [
  'minRebalanceCooldown',
  'enterMediumBps',
  'exitMediumBps',
  'enterHighBps',
  'exitHighBps',
  'enterExtremeBps',
  'exitExtremeBps',
  'narrowRangeHalfWidthSteps',
  'wideRangeHalfWidthSteps',
  'maxHealthyIdleBps',
  'maxSwapSlippageBps',
  'maxMigrationLossBps',
  'minimumLockedShares',
  'minimumInitialNav',
] as const;
export const roleHashes = {
  admin: `0x${'0'.repeat(64)}` as `0x${string}`,
  manager: keccak256(stringToHex('MANAGER_ROLE')),
  guardian: keccak256(stringToHex('GUARDIAN_ROLE')),
  keeper: keccak256(stringToHex('KEEPER_ROLE')),
};
export function parseRole(value: string) {
  const name = value.trim().toLowerCase();
  if (name !== 'manager' && name !== 'guardian' && name !== 'keeper')
    throw new Error('业务角色仅支持 manager、guardian、keeper');
  return roleHashes[name];
}
