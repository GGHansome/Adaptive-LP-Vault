export type Scenario = 'steady' | 'trend' | 'shock' | 'recovery';
export function random(seed: number) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 4294967296;
  };
}
const DEFAULT_SHOCK_TICKS = 1200;
const MAX_SHOCK_TICKS = 5000;

export function targetOffset(
  scenario: Scenario,
  elapsed: number,
  noise: number,
  shockTicks = DEFAULT_SHOCK_TICKS,
): number {
  if (scenario === 'steady') return Math.round((noise - 0.5) * 16);
  if (scenario === 'trend') return Math.round(Math.min(180, elapsed * 2) + (noise - 0.5) * 8);
  if (scenario === 'shock') return elapsed < 10 ? 0 : shockTicks;
  return elapsed < 10 ? 1200 : Math.max(0, 1200 - Math.floor((elapsed - 10) * 20));
}
export function options(args: string[]) {
  const result: Record<string, string> = {
    scenario: 'steady',
    interval: '3000',
    seed: '42',
    rounds: '0',
    scale: '1',
    bias: '0',
    'shock-ticks': String(DEFAULT_SHOCK_TICKS),
  };
  for (let i = 0; i < args.length; i += 2) {
    if (!args[i].startsWith('--') || args[i + 1] === undefined)
      throw new Error(
        '参数格式：--scenario steady --interval 3000 --seed 42 --rounds 0 --scale 1 --bias 0（shock 可加 --shock-ticks -1200）',
      );
    const key = args[i].slice(2);
    if (!(key in result)) throw new Error(`未知参数 ${key}`);
    result[key] = args[i + 1];
  }
  if (!['steady', 'trend', 'shock', 'recovery'].includes(result.scenario))
    throw new Error('不支持的场景');
  for (const key of ['interval', 'seed', 'rounds'])
    if (!/^\d+$/.test(result[key]) || !Number.isSafeInteger(Number(result[key])))
      throw new Error(`无效整数参数 ${key}`);
  if (result.scenario !== 'shock' && args.some((arg, i) => i % 2 === 0 && arg === '--shock-ticks'))
    throw new Error('--shock-ticks 仅适用于 shock 场景');
  const shockTicks = Number(result['shock-ticks']);
  if (
    !/^[+-]?\d+$/.test(result['shock-ticks']) ||
    !shockTicks ||
    Math.abs(shockTicks) > MAX_SHOCK_TICKS
  )
    throw new Error(`--shock-ticks 必须是绝对值在 1–${MAX_SHOCK_TICKS} 之间的整数`);
  const o = {
    scenario: result.scenario as Scenario,
    interval: Number(result.interval),
    seed: Number(result.seed),
    rounds: Number(result.rounds),
    scale: Number(result.scale),
    bias: Number(result.bias),
    shockTicks,
  };
  if (
    o.interval < 500 ||
    o.interval > 60000 ||
    o.rounds > 100000 ||
    !Number.isFinite(o.scale) ||
    o.scale <= 0 ||
    o.scale > 2 ||
    !Number.isFinite(o.bias) ||
    Math.abs(o.bias) > 100
  )
    throw new Error('参数超限：间隔 500–60000ms，规模 (0,2]，方向偏置 -100–100 ticks');
  return o;
}
