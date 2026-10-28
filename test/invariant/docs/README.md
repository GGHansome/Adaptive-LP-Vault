# 有状态不变量测试

连续执行随机存赎、转账、迁移和控制操作，检查份额、资产、权限和历史记录是否始终一致。测试函数、随机操作及覆盖限制见 [函数目录](INVARIANT_TEST_REVIEW.md)，协议规则见 [架构文档](../../../docs/ARCHITECTURE.md)。

## 运行与失败重放

在仓库根目录执行；首次运行先安装 [测试依赖](../../README.md#运行)。

```bash
# 默认：每个不变量 256 轮，每轮 128 次操作。
forge test --match-path 'test/invariant/*.t.sol' --summary

# 开发短测，包含固定可达性测试。
FOUNDRY_INVARIANT_RUNS=16 FOUNDRY_INVARIANT_DEPTH=64 \
  forge test --match-path 'test/invariant/*.t.sol' -vv

# 扩展：1000 轮 × 256 次操作。
FOUNDRY_PROFILE=nightly forge test --match-path 'test/invariant/*.t.sol' --summary
```

失败时保存随机种子、缩减后的操作顺序和代码版本，用相同配置及 `--fuzz-seed` 重跑；本机也可用 `forge test --rerun`。保留 `cache/invariant` 反例，修复后先重放，再运行完整测试。

## 怎样判断结果

- 只随机调用明确注册的 17 类操作。前提不满足记为跳过，满足后任何意外回滚都失败（`fail_on_revert = true`）；故意触发的拒绝会核对错误和选定状态。
- Foundry 的 Calls 是尝试次数，不是成功次数；成功、跳过和已核对失败由操作生成合约（Handler）分别记录。固定可达性测试确认关键路径确实执行过。
- 每轮结束保留故障和暂停状态，由 Guardian（紧急退出角色）退出仓位，再让用户全部赎回，以检查退出能力。

## 会计模型与舍入预算

用户份额定价只包含 Vault（资金库）直接持币和活跃仓位；累计资金流还包含未启用 V2 适配器收到的 LP 捐赠，防止启用时重复记作收入。参考模型直接读取协议状态重算本金和手续费，不以适配器快照为答案。

只有累计资产账本允许取整误差。每种 Token 分别按最小单位累加预算：初始化 `4`、每次存款 `4`、每次普通/换币迁移 `8`、实际紧急退出 `4`、每次赎回 `2`、每轮收尾另预留 `4`。这不是整枚 Token、百分比损失或生产 `dustTolerance` 的定义；份额定价、实际转账和协议快照等仍精确比较。

## 模型边界

- 共用环境见 [`LocalUniswapFixture.sol`](../../helpers/LocalUniswapFixture.sol)。项目和官方 Uniswap 合约真实执行，但预言机快照由测试控制，观察 Tick（V3 价格位置编号）为零，仓位池价格固定；独立换币池执行真实交易。
- 默认精度为 18/18，6/18 环境只重复三个会计不变量。参考模型与生产共用 `PriceMath.sqrtRatioAtTick`，无法独立排除该函数的共同错误。
- 不替代真实历史价格变化、负 Tick、价格越界、同池重建、恶意依赖、重入、管理员延迟交接或主网分叉测试。

修改随机操作、资产公式或环境时，同步更新函数目录和误差预算，并运行可达性及完整不变量测试。
