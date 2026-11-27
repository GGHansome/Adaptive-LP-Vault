import { createPublicClient, http, parseUnits } from 'viem';
import { expect, it } from 'vitest';
import { deployment } from '../../../../config/web3';
import { vaultAbi } from '../../../../contracts';
import { readRebalancePreview } from './selector';
import { readSuggestedSwapAmount } from './swap-suggestion';

it.runIf(import.meta.env.VITE_TEST_LOCAL_SWAP === '1')(
  '冲击后计算的建议金额可通过链上模拟，且不改变现有仓位',
  async () => {
    const client = createPublicClient({ transport: http('http://127.0.0.1:8545') });
    const m = deployment!;
    const account = m.accounts.keeper;
    const readPlan = () =>
      client.readContract({ address: m.vault, abi: vaultAbi, functionName: 'lastExecutedPlan' });
    const readAssets = () =>
      client.readContract({ address: m.vault, abi: vaultAbi, functionName: 'assetSnapshot' });
    const [initial, assets, preview] = await Promise.all([
      readPlan(),
      readAssets(),
      readRebalancePreview(client, m),
    ]);
    expect(preview.requiresSwap).toBe(true);
    expect(preview.direction).toBe(2);
    expect(preview.plan.targetVenue).toBe(initial.targetVenue);
    expect(preview.plan.tickLower).not.toBe(initial.tickLower);
    const suggested = await readSuggestedSwapAmount(client, m, account, preview, '0');
    const amountIn = parseUnits(suggested, m.decimals1);
    const now = await readRebalancePreview(client, m);
    await client.simulateContract({
      address: m.vault,
      abi: vaultAbi,
      functionName: 'rebalanceWithSwap',
      account,
      args: [now.plan.planHash, now.direction, amountIn, 0n, now.at + 120],
    });
    expect(await readPlan()).toEqual(initial);
    expect(await readAssets()).toEqual(assets);
    console.info('Local shock suggestion:', suggested, 'tETH');
  },
  30_000,
);
