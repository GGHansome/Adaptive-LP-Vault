import { expect, it } from 'vitest';
import { parseDeployment } from './deployment';
import { deployment } from '../features/test/fixtures';
it('部署 JSON 在配置边界被完整校验', () => {
  expect(parseDeployment(deployment)).toEqual(deployment);
  expect(() => parseDeployment({ ...deployment, chainId: 1 })).toThrow();
  expect(() => parseDeployment({ ...deployment, decimals0: -1 })).toThrow();
  expect(() => parseDeployment({ ...deployment, adapters: [] })).toThrow();
  expect(() => parseDeployment({ ...deployment, deploymentBlockHash: deployment.vault })).toThrow();
  expect(() => parseDeployment({ ...deployment, control: 'invalid' })).toThrow();
});
