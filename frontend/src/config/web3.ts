import { createConfig, http } from 'wagmi';
import { injected } from 'wagmi/connectors';
import { foundry } from 'wagmi/chains';
import { parseDeployment } from './deployment';
import type { Deployment } from './types';

const manifests = import.meta.glob('../generated/deployment.json', {
  eager: true,
  import: 'default',
});
let deployment: Deployment | undefined;
let deploymentError: string | undefined;
try {
  const manifest = Object.values(manifests)[0];
  if (manifest) deployment = parseDeployment(manifest);
} catch (error) {
  deploymentError = error instanceof Error ? error.message : '部署配置无效';
}
export { deployment, deploymentError };
export const rpcUrl = import.meta.env.VITE_RPC_URL || 'http://127.0.0.1:8545';
export const wagmiConfig = createConfig({
  chains: [foundry],
  connectors: [injected()],
  transports: { [foundry.id]: http(rpcUrl) },
  pollingInterval: 2000,
});
