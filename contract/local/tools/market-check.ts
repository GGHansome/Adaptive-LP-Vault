import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import {
  publicClient,
  manifest,
  assertDeployment,
  artifact,
  read,
  root,
  stringify,
} from './local.js';
const m = manifest();
await assertDeployment(m);
const previousPlan = await read(m.vault, artifact('AdaptiveLPVault').abi, 'lastExecutedPlan');
assert.equal(previousPlan.marketRegime, 0, '场景验证需要最近执行状态为低偏离的 Vault');
const snapshot = await publicClient.request({ method: 'evm_snapshot' as never });
try {
  const child = spawn(
    process.execPath,
    [
      '--import',
      'tsx',
      resolve(root, 'local/simulator/index.ts'),
      '--scenario',
      'shock',
      '--rounds',
      '10',
      '--interval',
      '500',
    ],
    { cwd: root, stdio: 'inherit' },
  );
  const code = await new Promise<number | null>((resolve, reject) => {
    child.on('error', reject);
    child.on('exit', resolve);
  });
  assert.equal(code, 0);
  const blockNumber = await publicClient.getBlockNumber({ cacheTime: 0 });
  const oracle = await read(
    m.oracle,
    artifact('CanonicalV3Oracle').abi,
    'snapshot',
    [],
    blockNumber,
  );
  assert.equal(oracle.healthy, true);
  const abi = artifact('AdaptiveLPVault').abi;
  const [enterMedium, enterHigh, enterExtreme] = await Promise.all(
    ['enterMediumBps', 'enterHighBps', 'enterExtremeBps'].map((name) => read(m.vault, abi, name)),
  );
  assert(oracle.deviationBps >= BigInt(enterMedium), '真实交易必须形成足以触发策略的偏离');
  const preview = await read(m.vault, abi, 'previewRebalance', [], blockNumber);
  const expectedRegime =
    oracle.deviationBps >= BigInt(enterExtreme)
      ? 3
      : oracle.deviationBps >= BigInt(enterHigh)
        ? 2
        : 1;
  assert.equal(preview[0].marketRegime, expectedRegime);
  assert.equal(preview[0].targetVenue, [2, 3, 1, 0][expectedRegime]);
  console.log(
    'PASS 冲击场景按完整进入阈值生成最终候选计划',
    stringify({ oracle, plan: preview[0], assessment: preview[1] }),
  );
} finally {
  await publicClient.request({ method: 'evm_revert' as never, params: [snapshot] as never });
  console.log('已恢复行情场景验证前的本地链快照。');
}
