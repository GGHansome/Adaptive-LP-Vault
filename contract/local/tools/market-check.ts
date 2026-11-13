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
  const oracle = await read(m.oracle, artifact('CanonicalV3Oracle').abi, 'snapshot');
  assert.equal(oracle.healthy, true);
  assert(oracle.deviationBps >= 30n, '真实交易必须形成足以触发策略的偏离');
  const preview = await read(m.vault, artifact('AdaptiveLPVault').abi, 'previewRebalance');
  assert.equal(preview[0].marketRegime, 1);
  assert.equal(preview[0].targetVenue, 3);
  console.log(
    'PASS 冲击场景形成真实预言机偏离和中偏离候选计划',
    stringify({ oracle, plan: preview[0], assessment: preview[1] }),
  );
} finally {
  await publicClient.request({ method: 'evm_revert' as never, params: [snapshot] as never });
  console.log('已恢复行情场景验证前的本地链快照。');
}
