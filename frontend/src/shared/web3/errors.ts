import { BaseError, ContractFunctionRevertedError } from 'viem';

export function describeError(error: unknown): string {
  if (error instanceof BaseError) {
    const revert = error.walk((e) => e instanceof ContractFunctionRevertedError);
    if (revert instanceof ContractFunctionRevertedError) {
      const name = revert.data?.errorName;
      const messages: Record<string, string> = {
        OracleUnhealthy: '预言机历史不足或读取失败，当前操作不可执行',
        CooldownActive: '再平衡冷却时间尚未结束',
        SwapRequired: '当前资产比例需要 Keeper／Manager 执行带换币再平衡',
        NoStateChangeRequired: '当前无需调整仓位',
        InvalidPlanHash: '链上计划已变化，请刷新预览后重试',
        ActivePositionSingleSided: 'V3 仓位已变为单边资产，暂停接受存款',
        IdleLimitExceeded: '闲置比例超过限制',
        GuardianCannotUnpause: 'Guardian 只能新增暂停',
        AccessControlUnauthorizedAccount: '当前账户没有执行权限',
        SharesSlippage: '份额输出低于最低要求，请更新预览',
        AssetSlippage: '资产输出低于最低要求',
        AdapterDisabled: '目标适配器已禁用',
        DeploymentRatioTooLow: '资产部署比例不足，请调整换币输入',
        MigrationLossExceeded: '迁移损失超过协议限制',
        DeadlineExpired: '交易已过期，请重新预览',
      };
      return (name && messages[name]) || `合约拒绝执行：${name ?? revert.shortMessage}`;
    }
    return error.shortMessage;
  }
  return error instanceof Error ? error.message : String(error);
}
