import { isAddress } from 'viem';
import type { Deployment } from './types';

export function parseDeployment(value: unknown): Deployment {
  if (!value || typeof value !== 'object') throw new Error('部署清单格式无效');
  const v = value as Record<string, unknown>;
  const addresses = [
    'vault',
    'control',
    'oracle',
    'executor',
    'token0',
    'token1',
    'v2Factory',
    'v3Factory',
    'v2Router',
    'router',
    'positionManager',
    'pair',
    'lowPool',
    'highPool',
    'canonicalPool',
  ];
  if (addresses.some((key) => typeof v[key] !== 'string' || !isAddress(v[key], { strict: false })))
    throw new Error('部署清单包含无效合约地址');
  if (
    typeof v.instanceId !== 'string' ||
    !v.instanceId ||
    v.chainId !== 31337 ||
    typeof v.deploymentBlock !== 'string' ||
    !/^\d+$/.test(v.deploymentBlock) ||
    typeof v.deploymentBlockHash !== 'string' ||
    !/^0x[\da-fA-F]{64}$/.test(v.deploymentBlockHash) ||
    ![v.decimals0, v.decimals1].every(
      (n) => typeof n === 'number' && Number.isInteger(n) && n >= 0 && n <= 255,
    ) ||
    ![v.symbol0, v.symbol1].every((s) => typeof s === 'string' && s.length > 0) ||
    !Array.isArray(v.adapters) ||
    v.adapters.length !== 3 ||
    !v.adapters.every((a) => typeof a === 'string' && isAddress(a, { strict: false })) ||
    !Array.isArray(v.bootstrapAmounts) ||
    v.bootstrapAmounts.length !== 2 ||
    !v.bootstrapAmounts.every((a) => typeof a === 'string' && /^\d+$/.test(a)) ||
    !v.accounts ||
    typeof v.accounts !== 'object' ||
    !Object.values(v.accounts).every(
      (a) => typeof a === 'string' && isAddress(a, { strict: false }),
    )
  )
    throw new Error('部署清单的网络、身份、精度或初始化字段无效');
  // All Deployment fields are validated above; this assertion is confined to the JSON boundary.
  return v as Deployment;
}
