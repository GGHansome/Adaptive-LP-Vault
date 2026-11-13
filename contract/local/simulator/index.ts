import { erc20Abi, parseEventLogs, type Address, type TransactionReceipt } from 'viem';
import { mkdirSync, openSync, writeFileSync, readFileSync, unlinkSync, closeSync } from 'node:fs';
import { resolve } from 'node:path';
import { setTimeout } from 'node:timers/promises';
import {
  root,
  accounts,
  publicClient,
  manifest,
  assertDeployment,
  official,
  artifact,
  send,
  read,
  stringify,
} from '../tools/local.js';
import { options, random, targetOffset } from './scenarios.js';
const config = options(process.argv.slice(2));
const m = manifest();
await assertDeployment(m);
mkdirSync(resolve(root, 'local/.state'), { recursive: true });
const lock = resolve(root, 'local/.state/market.lock');
try {
  const previous = Number(readFileSync(lock, 'utf8'));
  try {
    process.kill(previous, 0);
    throw new Error(`已有交易进程 ${previous}，请先停止它`);
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code !== 'ESRCH') throw e;
  }
  unlinkSync(lock);
} catch (e) {
  if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e;
}
const fd = openSync(lock, 'wx');
writeFileSync(fd, String(process.pid));
closeSync(fd);
process.on('exit', () => {
  try {
    unlinkSync(lock);
  } catch {
    /* Already cleaned up. */
  }
});
const routerAbi = official(
  '@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json',
).abi;
const v2RouterAbi = official('@uniswap/v2-periphery/build/UniswapV2Router02.json').abi;
const v2Abi = official('@uniswap/v2-core/build/UniswapV2Pair.json').abi;
const poolAbi = official(
  '@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json',
).abi;
function outputFromReceipt(receipt: TransactionReceipt, token: Address): bigint {
  const transfers = parseEventLogs({ abi: erc20Abi, eventName: 'Transfer', logs: receipt.logs });
  return transfers
    .filter(
      (log) =>
        log.address.toLowerCase() === token.toLowerCase() &&
        log.args.to.toLowerCase() === accounts[6].address.toLowerCase(),
    )
    .reduce((sum, log) => sum + log.args.value, 0n);
}
const unit0 = 10n ** BigInt(m.decimals0),
  unit1 = 10n ** BigInt(m.decimals1);
for (const router of [m.router, m.v2Router])
  for (const [token, unit] of [
    [m.token0, unit0],
    [m.token1, unit1],
  ] as const) {
    const allowance = (await read(token, erc20Abi, 'allowance', [
      accounts[6].address,
      router,
    ])) as bigint;
    if (allowance < unit * 1_000_000n)
      await send(6, token, erc20Abi, 'approve', [router, unit * 100_000_000n]);
  }
let stopped = false;
const controller = new AbortController();
for (const signal of ['SIGINT', 'SIGTERM'] as const)
  process.on(signal, () => {
    stopped = true;
    controller.abort();
  });
const rng = random(config.seed);
const start = (await publicClient.getBlock()).timestamp;
const baseTick = Math.log(10 ** (m.decimals1 - m.decimals0)) / Math.log(1.0001);
let round = 0,
  failures = 0;
console.log(
  stringify({
    event: 'started',
    ...config,
    trader: accounts[6].address,
    notice:
      '仅本地测试交易，不执行 Vault 再平衡。场景按链上时间推进，达到目标后持续保持以等待手动执行。',
  }),
);
const market = [
  { name: 'v2', address: m.pair, fee: 3000 },
  { name: 'v3-low', address: m.lowPool, fee: 500 },
  { name: 'v3-high', address: m.highPool, fee: 3000 },
  { name: 'canonical', address: m.canonicalPool, fee: 10000 },
];
while (!stopped && (!config.rounds || round < config.rounds)) {
  try {
    await assertDeployment(m);
    const block = await publicClient.getBlock();
    const elapsed = Number(block.timestamp - start);
    const target = baseTick + targetOffset(config.scenario, elapsed, rng()) + config.bias;
    for (const pool of market) {
      if (stopped) break;
      let current: number, liquidity: bigint, sqrtCurrent: bigint;
      if (pool.name === 'v2') {
        const [r0, r1] = (await read(pool.address, v2Abi, 'getReserves')) as readonly [
          bigint,
          bigint,
          number,
        ];
        current = Math.log(Number(r1) / Number(r0)) / Math.log(1.0001);
        sqrtCurrent = BigInt(Math.floor(Math.sqrt(Number(r1) / Number(r0)) * 2 ** 96));
        // Virtual full-range liquidity estimate only sizes the trade; router supplies the executable quote.
        liquidity = BigInt(Math.floor(Math.sqrt(Number(r0) * Number(r1))));
      } else {
        const slot = await read(pool.address, poolAbi, 'slot0');
        sqrtCurrent = slot[0];
        current = slot[1];
        liquidity = await read(pool.address, poolAbi, 'liquidity');
      }
      const delta = Math.max(-200, Math.min(200, target - current));
      const zeroForOne = delta < 0;
      const next = current + delta;
      const sqrtTarget = BigInt(Math.floor(1.0001 ** (next / 2) * 2 ** 96));
      const Q96 = 1n << 96n;
      let input = zeroForOne
        ? (liquidity * (sqrtCurrent - sqrtTarget) * Q96) / (sqrtCurrent * sqrtTarget)
        : (liquidity * (sqrtTarget - sqrtCurrent)) / Q96;
      if (input < 0n) input = -input;
      // A minimum noise trade keeps both-direction activity even very close to the target.
      const inputUnit = zeroForOne ? unit0 : unit1;
      input = (input * BigInt(Math.round(config.scale * 1000))) / 1000n;
      input = input < inputUnit ? inputUnit : input;
      input = input > inputUnit * 20_000n ? inputUnit * 20_000n : input;
      const tokenIn = zeroForOne ? m.token0 : m.token1,
        tokenOut = zeroForOne ? m.token1 : m.token0;
      if ((await read(tokenIn, erc20Abi, 'balanceOf', [accounts[6].address])) < input)
        throw new Error('交易账户余额不足，请重建本地环境；进程不会无限增发代币');
      const deadline = (await publicClient.getBlock()).timestamp + 60n;
      let hash: string, out: bigint;
      if (pool.name === 'v2') {
        const path = [tokenIn, tokenOut];
        const quote = (await read(m.v2Router, v2RouterAbi, 'getAmountsOut', [
          input,
          path,
        ])) as bigint[];
        const minOut = (quote[1] * 9850n) / 10000n;
        if (!minOut) throw new Error('输出过小');
        const result = await send(6, m.v2Router, v2RouterAbi, 'swapExactTokensForTokens', [
          input,
          minOut,
          path,
          accounts[6].address,
          deadline,
        ]);
        hash = result.hash;
        out = outputFromReceipt(result.receipt, tokenOut);
      } else {
        const params = {
          tokenIn,
          tokenOut,
          fee: pool.fee,
          recipient: accounts[6].address,
          deadline,
          amountIn: input,
          amountOutMinimum: 1n,
          sqrtPriceLimitX96: 0n,
        };
        const quote = await publicClient.simulateContract({
          address: m.router,
          abi: routerAbi,
          functionName: 'exactInputSingle',
          args: [params],
          account: accounts[6],
        });
        const minOut = ((quote.result as bigint) * 9850n) / 10000n;
        if (!minOut) throw new Error('输出过小');
        const result = await send(6, m.router, routerAbi, 'exactInputSingle', [
          { ...params, amountOutMinimum: minOut },
        ]);
        hash = result.hash;
        out = outputFromReceipt(result.receipt, tokenOut);
      }
      console.log(
        stringify({
          event: 'swap',
          round,
          pool: pool.name,
          hash,
          direction: zeroForOne ? 'token0→token1' : 'token1→token0',
          amountIn: input,
          amountOut: out,
          targetTick: Math.round(target),
          previousTick: Math.round(current),
        }),
      );
    }
    const oracle = await read(m.oracle, artifact('CanonicalV3Oracle').abi, 'snapshot');
    console.log(
      stringify({
        event: 'market',
        round,
        elapsed,
        healthy: oracle.healthy,
        deviationBps: oracle.deviationBps,
        spotTick: oracle.spotTick,
        twapTick: oracle.twapTick,
        shortTwapTick: oracle.shortTwapTick,
        notice: '仓位不会自动调整，请在前端刷新计划并手动执行。',
      }),
    );
    failures = 0;
    round++;
  } catch (error) {
    failures++;
    console.error(
      stringify({
        event: 'error',
        failures,
        message: error instanceof Error ? error.message : String(error),
      }),
    );
    if (failures >= 3) {
      process.exitCode = 1;
      break;
    }
  }
  try {
    await setTimeout(config.interval * 2 ** Math.min(failures, 3), undefined, {
      signal: controller.signal,
    });
  } catch {
    break;
  }
}
console.log(stringify({ event: 'stopped', completedRounds: round }));
