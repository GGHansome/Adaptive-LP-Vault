type Estimate = { excess: bigint; idle: bigint; total: bigint };

type Search = {
  balance: bigint;
  estimate: (amountIn: bigint) => Promise<Estimate>;
  simulate: (amountIn: bigint) => Promise<boolean>;
};

export async function searchSwapAmount({ balance, estimate, simulate }: Search) {
  const candidates = new Map<bigint, Estimate>();
  async function evaluate(amountIn: bigint) {
    const cached = candidates.get(amountIn);
    if (cached) return cached;
    const result = await estimate(amountIn);
    candidates.set(amountIn, result);
    return result;
  }

  // Search estimated asset balance, not the (potentially non-monotone) transaction result.
  let lo = 0n;
  let hi = balance;
  for (let i = 0; i < 12 && hi - lo > 1n; i++) {
    const middle = (lo + hi) / 2n;
    if ((await evaluate(middle)).excess > 0n) lo = middle;
    else hi = middle;
  }
  const nearby = [lo, hi];
  for (const bps of [10n, 25n, 50n, 100n, 200n]) {
    const step = (balance * bps + 9_999n) / 10_000n;
    nearby.push(lo - step, hi + step);
  }
  await Promise.all([...new Set(nearby)].filter((n) => n > 0n && n <= balance).map(evaluate));

  const ranked = [...candidates].filter(([, estimate]) => estimate.total > 0n);
  ranked.sort(([a, x], [b, y]) => {
    const difference = x.idle * y.total - y.idle * x.total;
    return difference < 0n ? -1 : difference > 0n ? 1 : a < b ? -1 : 1;
  });
  for (const [amountIn] of ranked.slice(0, 8)) {
    if (await simulate(amountIn)) return amountIn;
  }
}
