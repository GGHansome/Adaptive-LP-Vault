import { BaseError, ContractFunctionRevertedError, formatUnits, maxUint256 } from 'viem';
import type { Address, PublicClient } from 'viem';
import type { Deployment } from '../../../../config/types';
import { adapterAbi, controlAbi, oracleAbi, vaultAbi } from '../../../../contracts';
import { previewExpired, units } from '../../../../shared/utils/format';
import type { RebalancePreview } from '../../../types';
import { readRebalancePreview } from './selector';
import { searchSwapAmount } from './swap-search';

function requireCurrentSwap(expected: RebalancePreview, current: RebalancePreview) {
  if (
    previewExpired(expected.at, current.at) ||
    expected.plan.planHash !== current.plan.planHash ||
    expected.direction !== current.direction ||
    !current.requiresSwap ||
    (current.direction !== 1 && current.direction !== 2)
  )
    throw new Error('计划已变化或过期，请刷新计划后重试');
}

export async function readSuggestedSwapAmount(
  client: PublicClient,
  m: Deployment,
  account: Address,
  expected: RebalancePreview,
  minOut: string,
) {
  const block = await client.getBlock();
  const blockNumber = block.number;
  const current = await readRebalancePreview(client, m, block);
  requireCurrentSwap(expected, current);
  const { plan, direction } = current;
  const inputIsToken1 = direction === 2;
  const keeperMinOut = units(minOut, inputIsToken1 ? m.decimals0 : m.decimals1);
  if (keeperMinOut > maxUint256) throw new Error('调用者最低输出超过允许范围');
  const [assets, oracle, slippage, config] = await Promise.all([
    client.readContract({
      address: m.vault,
      abi: vaultAbi,
      functionName: 'assetSnapshot',
      blockNumber,
    }),
    client.readContract({
      address: m.oracle,
      abi: oracleAbi,
      functionName: 'snapshot',
      blockNumber,
    }),
    client.readContract({
      address: m.vault,
      abi: vaultAbi,
      functionName: 'maxSwapSlippageBps',
      blockNumber,
    }),
    client.readContract({
      address: m.control,
      abi: controlAbi,
      functionName: 'getConfig',
      args: [plan.targetVenue],
      blockNumber,
    }),
  ]);
  const { total0, total1 } = assets;
  const { twapTick, twapPriceToken1 } = oracle;
  const unit0 = 10n ** BigInt(m.decimals0);
  const remainingBps = 10_000n - BigInt(slippage);
  // A common integer scale values both tokens in token1 units without intermediate rounding.
  const value0 = (amount0: bigint) => amount0 * twapPriceToken1;
  const value1 = (amount1: bigint) => amount1 * unit0;
  const candidate = await searchSwapAmount({
    balance: inputIsToken1 ? total1 : total0,
    estimate: async (amountIn) => {
      const quote = await client.readContract({
        address: m.oracle,
        abi: oracleAbi,
        functionName: inputIsToken1 ? 'quoteToken1InToken0' : 'quoteToken0InToken1',
        args: [amountIn, twapTick, true],
        blockNumber,
      });
      // Match the on-chain conservative pre-check; caller minOut is enforced in the final simulation.
      const out = (quote * remainingBps + 9_999n) / 10_000n;
      const balance0 = inputIsToken1 ? total0 + out : total0 - amountIn;
      const balance1 = inputIsToken1 ? total1 - amountIn : total1 + out;
      const [used0, used1] = await client.readContract({
        address: config.adapter,
        abi: adapterAbi,
        functionName: 'previewDeposit',
        args: [balance0, balance1, plan],
        blockNumber,
      });
      const unused0 = value0(balance0 - used0);
      const unused1 = value1(balance1 - used1);
      return {
        excess: inputIsToken1 ? unused1 - unused0 : unused0 - unused1,
        idle: unused0 + unused1,
        total: value0(balance0) + value1(balance1),
      };
    },
    simulate: async (amountIn) => {
      try {
        await client.simulateContract({
          address: m.vault,
          abi: vaultAbi,
          functionName: 'rebalanceWithSwap',
          args: [plan.planHash, direction, amountIn, keeperMinOut, current.at + 120],
          account,
          blockNumber,
        });
        return true;
      } catch (error) {
        if (
          error instanceof BaseError &&
          error.walk((cause) => cause instanceof ContractFunctionRevertedError) instanceof
            ContractFunctionRevertedError
        )
          return false;
        throw error;
      }
    },
  });
  requireCurrentSwap(expected, await readRebalancePreview(client, m));
  if (candidate === undefined) throw new Error('未找到通过模拟的金额，请刷新计划重试或手动填写');
  return formatUnits(candidate, inputIsToken1 ? m.decimals1 : m.decimals0);
}
