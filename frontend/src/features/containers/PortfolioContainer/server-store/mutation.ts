import { erc20Abi } from 'viem';
import { vaultAbi, controlAbi } from '../../../../contracts';
import { deployment } from '../../../../config/web3';
import { positive, units, minimum, addressInput } from '../../../../shared/utils/format';
import { useVaultWrite } from '../../server-store/write';
import { useVaultAccess } from '../../server-store/queries';
import { parseRole } from '../../server-store/constants';
import type {
  DepositFormValues,
  RedeemFormValues,
  DepositPreview,
  RedeemPreview,
} from '../../../types';

export function usePortfolioMutation() {
  const write = useVaultWrite();
  const access = useVaultAccess();
  const m = deployment;
  return {
    ready: write.ready,
    busy: write.busy,
    async approve(token: 0 | 1, value: string) {
      if (!m) throw new Error('缺少部署配置');
      return write.send('approval', {
        label: `授权 ${token ? m.symbol1 : m.symbol0}`,
        address: token ? m.token1 : m.token0,
        abi: erc20Abi,
        functionName: 'approve',
        args: [m.vault, positive(value, token ? m.decimals1 : m.decimals0)],
      });
    },
    async deposit(values: DepositFormValues, preview?: DepositPreview) {
      if (!m || !preview) throw new Error('请先更新存款预览');
      const min = minimum(preview.shares, Number(values.slippage));
      if (!min) throw new Error('最低份额为零，请增加金额');
      return write.send('assets', {
        label: '存款',
        address: m.vault,
        abi: vaultAbi,
        functionName: 'deposit',
        args: [
          positive(values.amount0, m.decimals0),
          positive(values.amount1, m.decimals1),
          min,
          addressInput(values.receiver),
        ],
      });
    },
    async redeem(values: RedeemFormValues, preview?: RedeemPreview) {
      if (!m || !preview) throw new Error('请先更新赎回预览');
      return write.send('assets', {
        label: '赎回',
        address: m.vault,
        abi: vaultAbi,
        functionName: 'redeem',
        args: [
          positive(values.shares, 18),
          minimum(preview.out0, Number(values.slippage)),
          minimum(preview.out1, Number(values.slippage)),
          addressInput(values.receiver),
          addressInput(values.owner),
        ],
      });
    },
    async transfer(values: { to: string; shares: string }) {
      if (!m) throw new Error('缺少部署配置');
      return write.send('assets', {
        label: '转让份额',
        address: m.vault,
        abi: vaultAbi,
        functionName: 'transfer',
        args: [addressInput(values.to), positive(values.shares, 18)],
      });
    },
    async approveShares(values: { spender: string; shares: string }) {
      if (!m) throw new Error('缺少部署配置');
      return write.send('sharesApproval', {
        label: '份额授权',
        address: m.vault,
        abi: vaultAbi,
        functionName: 'approve',
        args: [addressInput(values.spender), units(values.shares, 18)],
      });
    },
    async renounce(role: string) {
      if (!m || !write.address) throw new Error('请先连接钱包');
      const name = role.trim().toLowerCase();
      const hash = parseRole(name);
      if (
        (name !== 'manager' && name !== 'guardian' && name !== 'keeper') ||
        !access.confirmed ||
        !access.data?.[name]
      )
        throw new Error('当前账户未持有该业务角色');
      return write.send('roles', {
        label: '放弃业务角色',
        address: m.control,
        abi: controlAbi,
        functionName: 'renounceRole',
        args: [hash, write.address],
      });
    },
  };
}
