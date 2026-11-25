import { App } from 'antd';
import { useConnect, useConnectors, useDisconnect, useSwitchChain } from 'wagmi';
import { deployment } from '../../../../config/web3';
import { describeError } from '../../../../shared/web3/errors';
export function useWalletMutation() {
  const { mutate: connect, isPending } = useConnect();
  const connectors = useConnectors();
  const { mutate: disconnect } = useDisconnect();
  const { mutate: switchChain } = useSwitchChain();
  const { message } = App.useApp();
  return {
    connecting: isPending,
    connect() {
      const connector = connectors[0];
      if (!connector) {
        message.warning('请安装支持以太坊的浏览器钱包');
        return;
      }
      connect({ connector }, { onError: (error) => message.error(describeError(error)) });
    },
    disconnect: () => disconnect(),
    switchChain: () =>
      switchChain(
        { chainId: deployment?.chainId ?? 31337 },
        { onError: (error) => message.error(describeError(error)) },
      ),
  };
}
