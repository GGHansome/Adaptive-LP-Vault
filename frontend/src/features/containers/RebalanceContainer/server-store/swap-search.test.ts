import { expect, it, vi } from 'vitest';
import { searchSwapAmount } from './swap-search';

it('优先模拟最平衡金额，失败后选择通过模拟的候选', async () => {
  const simulate = vi.fn(async (input: bigint) => input === 49n);
  const result = await searchSwapAmount({
    balance: 100n,
    estimate: async (input) => ({
      excess: 100n - 2n * input,
      idle: input > 50n ? 2n * input - 100n : 100n - 2n * input,
      total: 100n,
    }),
    simulate,
  });
  expect(simulate.mock.calls[0]).toEqual([50n]);
  expect(result).toBe(49n);
});

it('候选去重，不超过余额或只读请求预算，无解时不猜测', async () => {
  const balance = 100_000n;
  const estimate = vi.fn(async (input: bigint) => ({
    excess: balance - 2n * input,
    idle: balance,
    total: balance,
  }));
  const simulate = vi.fn<(input: bigint) => Promise<boolean>>(async () => false);
  expect(await searchSwapAmount({ balance, estimate, simulate })).toBeUndefined();
  const evaluated = estimate.mock.calls.map(([n]) => n);
  expect(evaluated.length).toBeLessThanOrEqual(24);
  expect(new Set(evaluated).size).toBe(evaluated.length);
  expect(evaluated.every((n) => n > 0n && n <= balance)).toBe(true);
  expect(simulate.mock.calls.length).toBe(8);
});

it('完整模拟的连接错误向上报告，不按金额失败继续试', async () => {
  const simulate = vi.fn(async () => {
    throw new Error('RPC disconnected');
  });
  await expect(
    searchSwapAmount({
      balance: 100n,
      estimate: async (input) => ({
        excess: 100n - 2n * input,
        idle: input > 50n ? 2n * input - 100n : 100n - 2n * input,
        total: 100n,
      }),
      simulate,
    }),
  ).rejects.toThrow('RPC disconnected');
  expect(simulate).toHaveBeenCalledTimes(1);
});
