import { App } from 'antd';
import { useConnection, useWalletClient } from 'wagmi';
import { getConnection } from 'wagmi/actions';
import { useQueryClient } from '@tanstack/react-query';
import { deployment, wagmiConfig } from '../../../config/web3';
import { executeTransaction, type ContractCall } from '../../../shared/web3/transaction';
import { transactionIdentity, useTransactionStore } from '../../../shared/store/transactionStore';
import { affectedKeys, type Impact } from './keys';
import { useDeploymentValidation } from './queries';

export function useVaultWrite() {
  const connection = useConnection();
  const { data: wallet } = useWalletClient();
  const { client, valid } = useDeploymentValidation();
  const queryClient = useQueryClient();
  const { message } = App.useApp();
  const busy = useTransactionStore((state) => state.busy);
  const ready =
    valid && !!wallet && !!connection.address && connection.chainId === deployment?.chainId;
  async function run(
    impact: Impact,
    operation: (send: (call: ContractCall) => Promise<void>) => Promise<void>,
  ) {
    const m = deployment,
      account = connection.address;
    if (!ready || !m || !account || !wallet || !client)
      throw new Error('请先连接正确网络的钱包，并等待链上状态加载成功');
    return executeTransaction(
      {
        identity: transactionIdentity(m.chainId, m.instanceId, account),
        async assertIdentity() {
          const current = getConnection(wagmiConfig);
          const addresses = await wallet.getAddresses();
          if (
            current.address?.toLowerCase() !== account.toLowerCase() ||
            current.chainId !== m.chainId ||
            addresses[0]?.toLowerCase() !== account.toLowerCase() ||
            (await wallet.getChainId()) !== m.chainId
          )
            throw new Error('账户或网络已变化，请重试');
        },
        async simulate(call) {
          // Dynamic ABI is confined to this generic execution boundary. Business mutations use generated ABIs.
          const input = { ...call, account };
          const estimate = await client.estimateContractGas(input);
          // Round up the shared 20% buffer before simulating the exact gas limit to send.
          const gas = (estimate * 120n + 99n) / 100n;
          const { request } = await client.simulateContract({ ...input, gas });
          return () => wallet.writeContract(request);
        },
        receipt: (hash) => client.waitForTransactionReceipt({ hash }),
        async confirmed(call) {
          message.success(`${call.label}成功`);
          try {
            await Promise.all(
              affectedKeys(m, account, impact).map((queryKey) =>
                queryClient.invalidateQueries({ queryKey }),
              ),
            );
          } catch {
            message.warning('交易已确认，部分数据刷新失败，请手动刷新');
          }
        },
      },
      operation,
    );
  }
  return {
    ready,
    busy,
    address: connection.address,
    run,
    send: (impact: Impact, call: ContractCall) => run(impact, (send) => send(call)),
  };
}
