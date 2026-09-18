# Swap Rebalance 数学规范

本文档定义 `rebalanceWithSwap` 的计算口径和后置校验。`PRODUCT_SPEC.md` 负责描述业务流程和权限；`ARCHITECTURE.md` 负责描述接口与模块边界。

本文档不定义任意 Router、任意路径或任意 calldata。v1 使用部署时封存的 Router、Token 对、Pool/Fee Tier 和固定 Swap 方法。

`lastExecutedPlan` 保存最近一次成功执行的策略计划，其 `marketRegime` 作为 Hysteresis 历史；Swap 数学和失败路径不得另行维护或覆盖该历史状态。

## 1. 统一口径

所有数量均使用对应 ERC-20 的 raw units：

- `amount0`、`T0`、`B0`、`H0`、`used0`、`unused0` 使用 token0 raw units；
- `amount1`、`T1`、`B1`、`H1`、`used1`、`unused1` 使用 token1 raw units；
- 跨 Token 比较或计算比例前，必须使用 canonical TWAP 和 decimals 转换为 token1 价值；
- `BPS = 10_000`。

一次 Swap Rebalance 使用同一个健康 Oracle 快照：

- `twapTick`：本次迁移使用的唯一参考 Tick；
- `NAVBefore`：迁移前按 `twapTick` 计算的 token1 价值；
- `T0`、`T1`：生成当前计划后首次部署评估使用的 Vault 总资产数量；
- `B0`、`B1`：退出旧 Position 后、执行 Swap 前的 Vault 实际余额。

首次部署评估的结果用于判断 `requiresSwap` 和 `direction`，不得为相同的 `T0/T1` 重复调用 `previewDeposit`。退出旧 Position 后必须重新读取 Vault 余额，并验证 `B0/B1` 与 `T0/T1` 的差异不超过对应 `dustTolerance0/1`；不能使用退出前的 Position 快照代替 `B0/B1`。

## 2. 部署评估与资产偏差

`_assessDeployment(plan, amount0, amount1, twapTick)` 是 Vault 内部只读的编排函数。它调用目标 Adapter 的 `previewDeposit()`，再使用返回的局部 `used0/used1` 计算仅包含 `requiresSwap` 与 `direction` 的部署评估。

对于非 IDLE 计划，Vault 必须先验证 `isEnterEnabled(plan.targetVenue) == true`，再调用目标 Adapter 的 `previewDeposit()`；禁用时以 `AdapterDisabled()` 回滚。该运行时门控不改变以下部署率、Swap 方向或舍入公式；IDLE 计划不检查 Adapter 状态，也不调用 Adapter。

目标 Adapter 必须提供与真实 `deposit()` 使用相同数学的只读预览能力：

```solidity
function previewDeposit(
    uint256 amount0Max,
    uint256 amount1Max,
    PositionPlan calldata plan
) external view returns (uint256 used0, uint256 used1);
```

`previewDeposit(amount0Max, amount1Max, plan)` 返回目标 Adapter 在 `plan` 指定的 Venue 和 Range 下预计实际使用的两种 Token 数量，并满足：

$$
used_0 \le amount0Max, \qquad used_1 \le amount1Max
$$

`amount0Max/amount1Max` 是使用上限；未使用数量留在或退回 Vault。`previewDeposit()` 不能转移资产、创建 Position、领取费用或改变任何状态，其数学必须与真实 `deposit()` 一致。

对任意评估输入 `A0/A1`，定义：

$$
unused_0 = A_0 - used_0
$$

$$
unused_1 = A_1 - used_1
$$

$$
DeployableNAV_1 = used_1 + Q_1(used_0; twapTick)
$$

$$
initialDeployBps =
\left\lfloor
\frac{DeployableNAV_1 \times BPS}
{A_1 + Q_1(A_0; twapTick)}
\right\rfloor
$$

按以下规则生成 `DeploymentAssessment`：

- `minDeployBps` 是派生值，定义为 `BPS - maxHealthyIdleBps`，不作为独立配置或独立事实来源；
- `initialDeployBps < minDeployBps` 时，`requiresSwap = true`；否则为 `false`；
- `unused0 > dustTolerance0` 且 `unused1 <= dustTolerance1` 时，`direction = ZERO_FOR_ONE`；
- `unused1 > dustTolerance1` 且 `unused0 <= dustTolerance0` 时，`direction = ONE_FOR_ZERO`；
- 两边都不超过对应 Dust 时，`direction = NONE`；
- 两边都明显超过对应 Dust 时，目标计划、Adapter 预览或资产快照不一致，必须回滚；
- IDLE 计划由 Vault 在调用 Adapter 前短路处理，固定返回 `requiresSwap = false` 和 `direction = NONE`。

`dustTolerance0` 和 `dustTolerance1` 分别使用 token0 和 token1 raw units，仅用于整数舍入、最小单位和 AMM 计算造成的可接受微小剩余；该范围内的余额仍属于 Vault。

V2 的 `used0/used1` 主要由 Pair 储备比例决定。V3 的 `used0/used1` 由目标 Pool、当前价格、`tickLower`、`tickUpper` 和 liquidity 数学决定。

## 3. Swap 输入数量

Keeper/Manager 可以通过链下模拟准备 `amountIn`，但 Vault 不信任其计算结果。

Vault 必须验证：

- `amountIn > 0`；
- 输入 Token 与首次 `DeploymentAssessment.direction` 一致；
- `amountIn` 不超过 Vault 当前该输入 Token 的可用余额；
- Swap 后不会把资产比例从一侧过量变成另一侧明显过量；
- Swap 后的 `simulatedDeployBps(x)` 和 `simulatedIdleBps(x)` 满足部署时固定的协议参数；
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

然后对模拟余额执行部署评估：

```text
(used0, used1) = targetAdapter.previewDeposit(H0(x), H1(x), currentPlan)
```


$$
DeployableNAV_1(x) = used_1 + Q_1(used_0; twapTick)
$$

$$
NAV_{after,sim}(x) = H_1(x) + Q_1(H_0(x); twapTick)
$$

$$
simulatedDeployBps(x) =
\left\lfloor
\frac{DeployableNAV_1(x) \times BPS}
{NAV_{after,sim}(x)}
\right\rfloor
$$

$$
simulatedIdleValue_1(x) =
(H_1(x)-used_1) + Q_1(H_0(x)-used_0; twapTick)
$$

$$
simulatedIdleBps(x) =
\left\lfloor
\frac{simulatedIdleValue_1(x) \times BPS}
{NAV_{after,sim}(x)}
\right\rfloor
$$

`amountIn` 必须满足：

$$
simulatedDeployBps(x) \ge minDeployBps
$$

$$
simulatedIdleBps(x) \le maxHealthyIdleBps
$$

带 Swap Rebalance 的首次评估使用 `initialDeployBps < minDeployBps` 识别 Swap 必要性；对 `amountIn` 的模拟校验使用同一派生阈值 `simulatedDeployBps(x) \ge minDeployBps` 判断最差输出下能否建立目标 Position。

同时，`simulatedAssessment.requiresSwap` 必须为 `false`，其 `direction` 不得与首次部署评估方向相反。

Keeper 可以在链下寻找合适的 `x`。Vault 只验证值是否安全、方向正确且最终可建仓，不负责链上优化。

## 4. `protocolMinOut` 与 Keeper 最低输出

定义向上取整的方向报价：

$$
OracleQuoteOutUp(x) =
\begin{cases}
Q_1(x; twapTick), & token0 \rightarrow token1 \\
Q_0(x; twapTick), & token1 \rightarrow token0
\end{cases}
$$

两个报价函数均使用统一的 Vault/canonical Pool 有序 Token 对；Token decimals 和具体取整规则遵循 [PRODUCT_SPEC.md](PRODUCT_SPEC.md) §6.1、§8.2，不执行 Pool 与 Vault 顺序之间的运行时转换。

允许的最大价格偏差为 `maxSwapSlippageBps` 时，协议最低输出为：

$$
protocolMinOut(x) =
\left\lceil
\frac{
OracleQuoteOutUp(x) \times (BPS-maxSwapSlippageBps)
}{BPS}
\right\rceil
$$

该计算先对方向报价向上取整，再对 BPS 滑点折算向上取整。与仅在最终结果处取整的精确有理数公式相比，结果相同或最多高一个输出 Token raw unit。

为了避免 Swap 后才发现部署率不足，Keeper 计算 `x` 时必须使用 `protocolMinOut(x)` 作为最差输出，而不是使用未折算滑点的方向报价。因此， `x` 在协议允许的最差成交结果下，也必须满足上一节的 `simulatedDeployBps(x)` 和 `simulatedIdleBps(x)` 条件。

Keeper/Manager 可以额外提供更严格的 `keeperMinAmountOut`。实际传给 Router 的最低输出为：

$$
minAmountOut =
\max(protocolMinOut(x), keeperMinAmountOut)
$$

`keeperMinAmountOut` 只能提高本次交易的最低输出保护，不能改变 Swap 方向、`amountIn`、目标 Venue 或目标 Range。传入过高的值只会使本次交易回滚，不会使 Vault 多交换资产。

## 5. Router 与固定 Swap 方法

v1 的 Router、Token 对、Pool/Fee Tier 和固定 Swap 方法在 `ControlledSwapExecutor` 部署或不可变初始化时配置，并在 Bootstrap 时校验。Bootstrap 后不能由 Keeper/Manager 通过调用参数替换；

推荐使用固定的 exact-input、single-hop 方法：

- `tokenIn` 和 `tokenOut` 只能是 Vault 固定的 token0/token1；
- Pool/Fee Tier 来自封存配置；
- `amountIn` 和 `minAmountOut` 是本次执行参数；
- 输出接收地址固定为 Vault；
- 不接受任意 Router、任意路径、任意 calldata、外部 receiver 或未验证的回调发送方。

Keeper/Manager 提交交易级的 `expectedPlanHash`、`expectedDirection`、`amountIn`、`keeperMinAmountOut` 和 `deadline`。`expectedDirection` 必须非 `NONE`，并与 Vault 首次 `DeploymentAssessment.direction` 一致；该参数只确认预期方向，不替代 Vault 的计算。

## 6. Executor 与 Vault 的职责

`ControlledSwapExecutor` 只负责 Swap 本地安全检查和执行：

- 只接受 Vault 调用，并仅使用 Vault 已转入的精确 `amountIn`；
- 验证方向、`amountIn`、`minAmountOut` 和 `deadline`；
- 对 Router 使用精确授权并在调用后清零；
- 将输出接收方固定为 Vault；
- 以 Vault 的输出 Token 实际余额增量计算并返回 `actualAmountOut`，不能只信任 Router 返回值。

设 `VInBefore/VOutBefore` 为 Vault 向 Executor 转入 `amountIn` 前的输入和输出 Token 余额，`VInAfterSwap/VOutAfterSwap` 为 `executeSwap()` 返回后、目标 Adapter 建仓前的余额。Vault 必须立即验证：

$$
VInBefore - VInAfterSwap = amountIn
$$

$$
actualAmountOut = VOutAfterSwap - VOutBefore \ge minAmountOut
$$

Executor 返回值等于 `actualAmountOut`；Executor 的 token0/token1 余额恢复到 Vault 转入前的基线，且其 Router allowance 为零。

目标 Adapter 建仓后，Vault 必须重新读取最终 Vault 余额与 `PositionSnapshot`。设 `I0Final/I1Final` 为 Vault 最终实际余额，`P0Final/P1Final` 为最终 `PositionSnapshot.amount0/amount1`，并定义：

$$
F_0 = I0Final + P0Final, \qquad F_1 = I1Final + P1Final
$$

$$
FinalDeployedNAV_1 = P1Final + Q_1(P0Final; twapTick)
$$

$$
FinalNAV_1 = F_1 + Q_1(F_0; twapTick)
$$

$$
finalDeployBps =
\left\lfloor
\frac{FinalDeployedNAV_1 \times BPS}
{FinalNAV_1}
\right\rfloor
$$

$$
FinalIdleValue_1 = I1Final + Q_1(I0Final; twapTick)
$$

$$
finalIdleBps =
\left\lfloor
\frac{FinalIdleValue_1 \times BPS}
{FinalNAV_1}
\right\rfloor
$$

`P0Final/P1Final` 必须来自建仓后重新读取的实际 Position 快照，不能使用 `previewDeposit()` 的预估值或仅使用 `deposit()` 返回的 `used0/used1`。以上最终公式与本次迁移的其他价值校验复用迁移开始时捕获的同一个 `twapTick`，不得重新读取 Oracle。

完整迁移校验由 Vault 在目标 Adapter 建仓后负责，包括：

- `finalDeployBps >= minDeployBps`；
- `finalIdleBps <= maxHealthyIdleBps`；
- 目标 Position 唯一且有效；
- 无 Swap 路径的逐 Token 资产守恒，允许差异仅在 `dustTolerance0/1` 范围内；
- 带 Swap 路径按 `amountIn` 和 `actualAmountOut` 调整后的资产位置与余额守恒；
- NAV 损失不超过 `maxMigrationLossBps`。

迁移前捕获的 `twapTick` 用于迁移前后 NAV 比较：

$$
NAV_{after} \ge
\left\lceil
\frac{NAV_{before} \times (BPS-maxMigrationLossBps)}{BPS}
\right\rceil
$$

任一后置条件失败，整笔交易回滚，包括旧 Position 退出、Swap 和新 Position 建仓。

## 7. V2 与 V3 例子

### 7.1 V2

目标 Pair 比例为 `1 WETH : 2,000 USDC`，且统一顺序为 `token0 = USDC`、`token1 = WETH`。退出旧 Position 后 Vault 有 `1,000 USDC` 和 `2 WETH`。

不 Swap 预览只能使用：

```text
used0 = 1,000 USDC
used1 = 0.5 WETH
unused0 = 0 USDC
unused1 = 1.5 WETH
```

因此首次部署评估方向为 token1 → token0，即 WETH → USDC。Keeper 可以提交一个 `amountIn`，Vault 用最差 `protocolMinOut` 模拟 Swap 后的 `H0/H1`，再执行部署评估并确认达到部署率和 Idle 要求。传入过小的 `amountIn` 会因部署率不足回滚，传入过大的 `amountIn` 会因换过头或 Idle 条件不满足回滚。

### 7.2 V3

目标 V3 Range 由 `PositionPlan` 的 `tickLower/tickUpper` 定义。当前价格靠近 Range 上沿时，目标 Position 可能主要需要 token1，不是 50:50。

例如 Adapter 根据当前价格和 Range 计算目标比例约为 `1,500 USDC : 0.2 WETH`。如果退出旧 Position 后 Vault 有 `500 USDC` 和 `2 WETH`，部署评估会报告 token1 明显过量，方向为 token1 → token0，即 WETH → USDC。Vault 使用同一目标 Range 的 V3 liquidity 数学模拟 `amountIn`，并在实际建仓后重新读取 Position，不能用固定 50:50 或仅用 Swap 输出判断成功。

## 8. 失败条件

以下情况必须回滚：

- 非 IDLE 目标 Adapter 的 `isEnterEnabled(targetVenue) == false`；
- 首次 `DeploymentAssessment.requiresSwap == false`；
- `expectedPlanHash` 与重新生成的当前计划不匹配；
- `expectedDirection == NONE`，或与首次 `DeploymentAssessment.direction` 不一致；
- `amountIn` 方向错误、超过可用余额或导致资产比例换过头；
- Vault 的实际输入 Token 减少量不等于 `amountIn`；
- `deadline` 已过期；
- `simulatedDeployBps(x)`、`simulatedIdleBps(x)`、`finalDeployBps`、`finalIdleBps` 或 NAV 损失校验失败；
- 无 Swap 路径的逐 Token 资产守恒失败；
- Vault 的实际输出 Token 余额增量低于 `minAmountOut`，或与 Executor 返回值不一致；
- Executor 的 token0/token1 余额未恢复调用前基线，或 Router allowance 未清零；
- Router、Token 对、Pool、Fee Tier 或输出接收方不符合封存配置；`swapPool != canonicalPool`；任一 Executor、Vault、Adapter 或绑定 Pool 的有序 `token0/token1` 不一致；或 Router/Pool 回调发送方校验失败；
- Oracle 不健康或 Swap 安全边界不满足。

失败交易不得更新 `lastExecutedPlan`、`planVersion`、`lastPositionChangeAt` 或资产位置。
