# Swap Rebalance 数学规范

本文档定义 `rebalanceWithSwap` 的计算口径和后置校验。`PRODUCT_SPEC.md` 负责描述业务流程和权限；`ARCHITECTURE.md` 负责描述接口与模块边界。

本文档不定义任意 Router、任意路径或任意 calldata。v1 使用部署时封存的 Router、Token 对、Pool/Fee Tier 和固定 Swap 方法。

## 1. 统一口径

所有数量均使用对应 ERC-20 的 raw units：

- `amount0`、`B0`、`used0`、`unused0` 使用 token0 raw units；
- `amount1`、`B1`、`used1`、`unused1` 使用 token1 raw units；
- 跨 Token 比较或计算比例前，必须使用 canonical TWAP 和 decimals 转换为 token1 价值；
- `BPS = 10_000`。

一次 Swap Rebalance 在退出旧 Position 前捕获健康 Oracle 快照：

- `twapTickBefore`：本次迁移使用的唯一参考 Tick；
- `NAVBefore`：迁移前按 `twapTickBefore` 计算的 token1 价值；
- `B0`、`B1`：退出旧 Position 后、执行 Swap 前的 Vault 实际余额。

退出旧 Position 后必须重新读取 Vault 余额。不能使用退出前的 Position 快照代替 `B0/B1`。

## 2. `previewDeposit` 与资产偏差

目标 Adapter 必须提供与真实 `deposit()` 使用相同数学的只读预览能力：

```solidity
function previewDeposit(
    uint256 amount0,
    uint256 amount1,
    PositionPlan calldata plan
) external view returns (uint256 used0, uint256 used1);
```

`previewDeposit(B0, B1, plan)` 的语义是：假设目标 Adapter 现在接收 `B0/B1`，在 `plan` 指定的 Venue 和 Range 下，预计能够实际部署的两种 Token 数量。

它不能转移资产、创建 Position、领取费用或改变任何状态；其数学必须与真实 `deposit()` 一致。

定义：

$$
unused_0 = B_0 - used_0
$$

$$
unused_1 = B_1 - used_1
$$

`dustTolerance0` 和 `dustTolerance1` 是唯一的舍入容忍概念，分别使用 token0 和 token1 raw units 表示。它们只用于忽略整数舍入、最小单位和 AMM 计算造成的可接受微小剩余；该范围内的余额仍然属于 Vault，不是损失，也不能作为可自由转移的余额。

方向判断：

- `unused0 > dustTolerance0` 且 `unused1 <= dustTolerance1`：token0 是明显过量资产，Swap 方向为 token0 → token1；
- `unused1 > dustTolerance1` 且 `unused0 <= dustTolerance0`：token1 是明显过量资产，Swap 方向为 token1 → token0；
- 两边都不超过对应 `dustTolerance0/1`：不需要 Swap；
- 两边都明显超过对应 `dustTolerance0/1`：目标计划、Adapter 预览或资产快照不一致，必须回滚。

V2 的 `used0/used1` 主要由 Pair 储备比例决定。V3 的 `used0/used1` 由目标 Pool、当前价格、`tickLower`、`tickUpper` 和 liquidity 数学决定。

## 3. Swap 输入数量

Keeper/Admin 可以通过链下模拟准备 `amountIn`，但 Vault 不信任其计算结果。

Vault 必须验证：

- `amountIn > 0`；
- 输入 Token 是 `previewDeposit` 识别出的过量 Token；
- `amountIn` 不超过 Vault 当前该输入 Token 的可用余额；
- Swap 后不会把资产比例从一侧过量变成另一侧明显过量；
- Swap 后的 `deployBps` 和 `idleBps` 满足部署时固定的协议参数；
- Swap 后的完整迁移满足 `maxMigrationLossBps` 和资产状态不变量。

对输入 `x`，先使用协议允许的最差 Swap 输出模拟余额，再验证目标 Position：

对于 token0 → token1：

$$
H_0(x) = B_0 - x
$$

$$
H_1(x) = B_1 + protocolMinOut(x)
$$

对于 token1 → token0：

$$
H_0(x) = B_0 + protocolMinOut(x)
$$

$$
H_1(x) = B_1 - x
$$

然后调用：

```text
(used0, used1) = targetAdapter.previewDeposit(H0(x), H1(x), currentPlan)
```

并计算：

$$
DeployableNAV_1(x) = used_1 + Q_1(used_0; twapTickBefore)
$$

$$
NAV_{after,sim}(x) = H_1(x) + Q_1(H_0(x); twapTickBefore)
$$

$$
DeployBps(x) =
\left\lfloor
\frac{DeployableNAV_1(x) \times BPS}
{NAV_{after,sim}(x)}
\right\rfloor
$$

$$
IdleValue_1(x) =
(H_1(x)-used_1) + Q_1(H_0(x)-used_0; twapTickBefore)
$$

$$
IdleBps(x) =
\left\lfloor
\frac{IdleValue_1(x) \times BPS}
{NAV_{after,sim}(x)}
\right\rfloor
$$

 `amountIn` 必须满足：

$$
DeployBps(x) \ge minDeployBps
$$

$$
IdleBps(x) \le maxHealthyIdleBps
$$

Keeper 可以在链下寻找合适的 `x`。Vault 只验证值是否安全、方向正确且最终可建仓，不负责链上优化。

## 4. `protocolMinOut` 与 Keeper 最低输出

定义方向报价：

$$
OracleQuoteOut(x) =
\begin{cases}
Q_1(x; twapTickBefore), & token0 \rightarrow token1 \\
Q_0(x; twapTickBefore), & token1 \rightarrow token0
\end{cases}
$$

其中 `Q1` 和 `Q0` 必须处理 Pool 内部 Token 顺序、Vault Token 顺序、raw units 和 decimals。

允许的最大价格偏差为 `maxSwapSlippageBps` 时，协议最低输出为：

$$
protocolMinOut(x) =
\left\lceil
\frac{
OracleQuoteOut(x) \times (BPS-maxSwapSlippageBps)
}{BPS}
\right\rceil
$$

为了避免 Swap 后才发现部署率不足，Keeper 计算 `x` 时必须使用 `protocolMinOut(x)` 作为最差输出，而不是使用理想的 `OracleQuoteOut(x)`。因此， `x` 在协议允许的最差成交结果下，也必须满足上一节的 `DeployBps` 和 `IdleBps` 条件。

Keeper/Admin 可以额外提供更严格的 `keeperMinAmountOut`。实际传给 Router 的最低输出为：

$$
minAmountOut =
\max(protocolMinOut(x), keeperMinAmountOut)
$$

`keeperMinAmountOut` 只能提高本次交易的最低输出保护，不能改变 Swap 方向、`amountIn`、目标 Venue 或目标 Range。传入过高的值只会使本次交易回滚，不会使 Vault 多交换资产。

## 5. Router 与固定 Swap 方法

v1 的 Router、Token 对、Pool/Fee Tier、固定 Swap 方法和接收地址规则在 `ControlledSwapExecutor` 部署或不可变初始化时配置，并在 Bootstrap 时校验。Bootstrap 后不能由 Keeper/Admin 通过调用参数替换。

推荐使用固定的 exact-input、single-hop 方法：

- `tokenIn` 和 `tokenOut` 只能是 Vault 固定的 token0/token1；
- Pool/Fee Tier 来自封存配置；
- `amountIn` 和 `minAmountOut` 是本次执行参数；
- 接收地址固定为 Vault 或受控 Executor；
- 不接受任意 Router、任意路径、任意 calldata、任意回调接收方或无限授权。

Keeper/Admin 提交交易级的 `expectedPlanHash`、`expectedZeroForOne`、`amountIn`、`keeperMinAmountOut` 和 `deadline`。Vault 执行时重新根据 `previewDeposit` 推导方向，必须与该确认值一致。

## 6. Executor 与 Vault 的职责

`ControlledSwapExecutor` 只负责 Swap 本地安全检查和执行：

- 只接受 Vault 调用；
- 验证固定 Router、Token 对、方向、`amountIn`、`minAmountOut` 和 `deadline`；
- 使用精确授权并在不需要时清理授权；
- 固定回调和接收地址；
- 执行 Swap 后重新读取 Token 余额，不能只信任 Router 返回值。

完整迁移校验由 Vault 负责。Vault 必须在 Swap、目标 Adapter 建仓和所有外部调用完成后，重新读取实际资产和 Position，并校验：

- `deployBps >= minDeployBps`；
- `idleBps <= maxHealthyIdleBps`；
- 目标 Position 唯一且有效；
- 无 Swap 路径的逐 Token 资产守恒，允许差异仅在 `dustTolerance0/1` 范围内；
- 带 Swap 路径的 Executor 实际余额增量满足 `minAmountOut`；
- NAV 损失不超过 `maxMigrationLossBps`。

迁移前捕获的 `twapTickBefore` 用于迁移前后 NAV 比较：

$$
NAV_{after} \ge
\left\lceil
\frac{NAV_{before} \times (BPS-maxMigrationLossBps)}{BPS}
\right\rceil
$$

任一后置条件失败，整笔交易回滚，包括旧 Position 退出、Swap 和新 Position 建仓。

## 7. V2 与 V3 例子

### 7.1 V2

目标 Pair 比例为 `1 WETH : 2,000 USDC`。退出旧 Position 后 Vault 有 `2 WETH` 和 `1,000 USDC`。

不 Swap 预览只能使用：

```text
used0 = 0.5 WETH
used1 = 1,000 USDC
unused0 = 1.5 WETH
unused1 = 0 USDC
```

因此方向为 WETH → USDC。Keeper 可以提交一个 `amountIn`，Vault 用最差 `protocolMinOut` 模拟 Swap 后的 `H0/H1`，再确认目标 Pair 的 `previewDeposit` 能达到部署率和 Idle 要求。传入过小的 `amountIn` 会因部署率不足回滚，传入过大的 `amountIn` 会因换过头或 Idle 条件不满足回滚。

### 7.2 V3

目标 V3 Range 由 `PositionPlan` 的 `tickLower/tickUpper` 定义。当前价格靠近 Range 上沿时，目标 Position 可能主要需要 token1，不是 50:50。

例如 Adapter 根据当前价格和 Range 计算目标比例约为 `0.2 WETH : 1,500 USDC`。如果退出旧 Position 后 Vault 有 `2 WETH` 和 `500 USDC`，`previewDeposit` 会报告 token0 明显过量，方向为 WETH → USDC。Vault 使用同一目标 Range 的 V3 liquidity 数学模拟 `amountIn`，并在实际建仓后重新读取 Position，不能用固定 50:50 或仅用 Swap 输出判断成功。

## 8. 失败条件

以下情况必须回滚：

- `currentPlan.requiresSwap == false`；
- `expectedPlanHash` 与重新生成的当前计划不匹配；
- `expectedZeroForOne` 与 Vault 重新计算的 Swap 方向不一致；
- `amountIn` 方向错误、超过可用余额或导致资产比例换过头；
- 实际输出低于 `minAmountOut`；
- `deadline` 已过期；
- `DeployBps`、`IdleBps` 或 NAV 损失校验失败；
- 无 Swap 路径的逐 Token 资产守恒失败；
- 带 Swap 路径的实际余额增量低于 `minAmountOut`；
- Router、Token 对、Pool、Fee Tier 或回调接收方不符合封存配置；
- Oracle 不健康或 Swap 安全边界不满足。

失败交易不得更新 `positionPlan`、`lastCommittedRegime`、`planVersion`、`lastSuccessfulRebalanceAt` 或资产位置。
