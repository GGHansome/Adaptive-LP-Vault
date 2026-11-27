import assert from 'node:assert/strict';
import test from 'node:test';
import { random, targetOffset, options } from './scenarios.js';
test('随机种子可重复且取值合法', () => {
  const a = random(42),
    b = random(42);
  for (let i = 0; i < 1000; i++) {
    const x = a();
    assert.equal(x, b());
    assert(x >= 0 && x < 1);
  }
});
test('行情场景按链上时间生成目标，而非进程轮数', () => {
  assert.equal(targetOffset('shock', 9, 0.5), 0);
  assert.equal(targetOffset('shock', 10, 0.5), 1200);
  assert.equal(targetOffset('recovery', 70, 0.5), 0);
  assert.equal(targetOffset('trend', 200, 0.5), 180);
});
test('冲击场景支持负向 Tick，并在十秒后保持目标', () => {
  const config = options(['--scenario', 'shock', '--shock-ticks', '-1200']);
  assert.equal(config.scenario, 'shock');
  assert.equal(config.shockTicks, -1200);
  assert.equal(targetOffset(config.scenario, 9, 0.5, config.shockTicks), 0);
  assert.equal(targetOffset(config.scenario, 10, 0.5, config.shockTicks), -1200);
  assert.equal(targetOffset(config.scenario, 180, 0.5, config.shockTicks), -1200);
  assert.equal(options(['--scenario', 'shock']).shockTicks, 1200);
});
test('命令参数有严格边界', () => {
  assert.equal(options(['--rounds', '3']).rounds, 3);
  for (const a of [
    ['--interval', '0'],
    ['--scenario', 'fake'],
    ['--rounds', '-1'],
    ['--scale', 'NaN'],
    ['--bias', '101'],
    ['--scenario', 'shock', '--shock-ticks', '-5001'],
    ['--scenario', 'shock', '--shock-ticks', '1200.5'],
    ['--scenario', 'shock', '--shock-ticks', '0'],
    ['--scenario', 'steady', '--shock-ticks', '-1200'],
    ['--rpc', 'https://mainnet.example'],
  ])
    assert.throws(() => options(a));
});
