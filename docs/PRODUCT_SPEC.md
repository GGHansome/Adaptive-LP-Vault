# Adaptive LP Vault 产品技术文档

- 文档版本：1.0
- 文档状态：实现规范
- 适用范围：v1 双资产、单活 Venue、纯链上策略的智能合约系统
- 示例资产：WETH / USDC
- 目标网络：Ethereum Mainnet
- 实现基线：Foundry + Solidity
- 实现状态：本文档定义待实现协议，不表示合约已部署、审计或通过测试

本文档只定义产品行为、业务规则和计算口径。合约模块、数据结构、接口、事件、测试目录和调用时序见 [ARCHITECTURE.md](ARCHITECTURE.md)；部署顺序、链下发布门禁、流动性预检和部署证据见 [DEPLOYMENT.md](DEPLOYMENT.md)。

## 1. 产品定义与边界

### 1.1 产品定义

Adaptive LP Vault 是一个针对固定 `token0/token1` 资产对的双资产流动性管理 Vault，其用户会计语义如下：

- 后续 Deposit 按当前 Active Position 的本金比例提供两种资产；
- 用户获得可转让的 ERC-20 shares；
- Shares 代表对 Vault 当前已纳入会计的底层资产的按比例所有权，包括 Idle 余额、Active Position 的本金和已归属手续费；非活跃 V2 LP 按 §5.5 在激活时确认。

Vault 根据 canonical Uniswap V3 Pool 产生的链上价格信号，在以下 Venue 中选择一个目标状态：

- Uniswap V2 全价格区间流动性；
- Uniswap V3 低费率池的窄区间；
- Uniswap V3 高费率池的宽区间；
- IDLE，即没有活跃策略 LP Position，允许非活跃 V2 保留未确认捐赠 LP。

v1 不承诺最大化 APY，也不使用链下报价、链下策略签名或外部数据服务。策略只提供可重复验证的风险状态和目标 Position Plan。

### 1.2 v1 固定边界


| 边界              | v1 规则                                             | 不属于 v1                                |
| --------------- | ------------------------------------------------- | ------------------------------------- |
| 资产              | 每个 Vault 永久绑定一对 `token0/token1`；示例为 WETH/USDC     | 动态更换资产对、Fee-on-Transfer、Rebasing 资产   |
| Shares          | Vault 自己发行 ERC-20 shares；存取款均为双资产                 | 标准单资产 ERC-4626 接口、自动换币存款              |
| Active Position | 任意时刻最多一个纳入会计的策略主动 LP Position                 | 多 Venue 并行权重、连续组合优化                   |
| 价格来源            | 部署时固定且不可替换的 canonical Uniswap V3 Pool             | Chainlink、后端价格、调用者传入价格、目标池自报价         |
| 策略输入            | Oracle 内部计算 `deviationBps`；Vault 策略逻辑只读取 Oracle 快照 | 调用者传入 `DEVIATION`、历史标准差、实现波动率、手续费 APR |
| 普通 Rebalance    | 允许撤出旧仓并使用现有双边资产建仓，不执行 Swap                        | 任意 Router、任意 calldata、调用者指定目标         |
| Swap Rebalance  | 仅 Keeper/Manager 使用受限的 token0/token1 Swap；成交 Pool 与 canonical Pool 为同一地址 | 通用聚合器、独立成交池、用户自定义路径、无上限 Swap                |
| 支持 Venue        | Uniswap V2、两个指定 Fee Tier 的 Uniswap V3、IDLE        | 动态新增 DEX 或初始化后替换 Adapter              |
| 外部 AMM 身份       | 每次部署固定官方 Uniswap V2 Factory 与 V3 Factory；canonical Pool、Swap Pool 和全部 Venue Pool 必须由对应固定 Factory 登记 | 信任 Pool 自报的 Factory、运行时更换 Factory、Uniswap Fork 或其他 DEX |
| 底层资产处理          | 直接转入的 token0/token1 永久计入 Vault，视为捐赠               | 对支持资产执行 rescue、sweep 或返还              |




### 1.3 明确的非目标

以下内容不会作为 v1 的产品承诺或策略输入：

- 根据历史手续费推断未来收益；
- 以 APY、手续费率或无常损失的估计值执行收益最大化；
- 通过 Swap 把用户的单边存款转换为双资产；
- 在 Oracle 不健康时继续进行价值相关的存款或 Rebalance；
- 通过管理员提款、救援或任意转账解决会计问题；
- 通过一个“波动率”字段代替明确的价格偏离定义。



## 2. 参与者与权限

权限由 Vault 固定绑定的专属 `VaultControl` 管理。角色权限不等于资产所有权；任何角色都不能直接取得 Vault 支持资产本金。


| 角色                    | 可调用操作                                      | 业务权限                           | 明确禁止                                                             | 暂停影响                                                                           |
| --------------------- | ------------------------------------------ | ------------------------------ | ---------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| LP 用户                 | `deposit`、`redeem`、shares 转账、只读查询          | 按规则提供双资产、获得和转让 shares、按比例赎回    | 单边存款、指定策略目标、调用 Swap Rebalance、取得额外 shares                        | `depositPaused` 不影响赎回；其他暂停不应阻止正常双资产赎回                                          |
| Permissionless Caller | `rebalance`、只读查询                           | 在部署评估无需 Swap 时触发 Vault 策略逻辑生成当前计划 | 指定 Venue、Fee Tier、Tick Range、Swap、Router 或接收地址                   | 受 `plainRebalancePaused`、Cooldown、Oracle 健康、`expectedPlanHash` 和 `deadline` 限制 |
| Keeper                | `rebalanceWithSwap`、普通 Rebalance、只读查询      | 按受控 Swap 参数修复资产比例并执行有效目标计划     | 任意 Token、任意 Router、超限数量、降低协议 `minOut`、绕过 NAV 检查                  | 受 `swapRebalancePaused` 和全部 Oracle/风控门控限制                                      |
| Guardian              | 暂停入口、禁用 Adapter、`emergencyExitToIdle`、只读查询 | 在异常情况下停止风险操作并无 Swap 撤出 LP      | 更换核心依赖、提取支持资产、执行任意 Swap                                          | 可暂停存款和 Rebalance；不应冻结赎回或紧急退出                                                   |
| Default Admin         | 业务角色授予/撤销、根管理员两阶段转移与延迟管理、只读查询 | 仅管理权限归属和根角色生命周期              | 在未另持业务角色时调用 Bootstrap、暂停、Adapter 或资产操作                           | 业务暂停不影响角色管理；不因根角色自动取得任何业务权限                                                 |
| Manager               | Bootstrap、Adapter 状态管理、全部受控操作              | 初始化 Vault、配置既有依赖、管理运行时控制状态     | 修改部署固定数值、Bootstrap 后替换 Oracle/Router/Adapter、sweep 支持资产、绕过用户输出保护 | 可管理暂停状态，但不能以暂停为由提取用户资产                                                         |



## 3. 领域术语


| 术语                         | 规范定义                                                                      | 数据来源或计算方式                               | 可变性与禁止混用                                  |
| -------------------------- | ------------------------------------------------------------------------- | --------------------------------------- | ----------------------------------------- |
| Vault                      | 持有 Idle 资产、发行 shares 并编排所有模块的核心合约                                         | 合约存储和 Adapter 快照                        | Vault 不实现 V2/V3 内部数学                      |
| VaultControl               | 专属的角色、暂停和 Adapter Registry 管理合约 | Vault 的固定绑定 | 不执行资产操作，不修改 shares 或策略状态 |
| token0 / token1            | canonical Uniswap V3 Pool 按地址升序确定的两种底层资产及其唯一协议顺序                              | Oracle 从 canonical Pool 读取并由 Vault 缓存为 immutable 地址和 decimals | `token0 < token1`；Vault、Oracle、Swap Executor、所有 Adapter 及其 Pool 必须使用相同顺序；前端可独立选择展示顺序 |
| Venue                      | 一个具体的流动性池实例或 IDLE 状态                                                      | `VenueType` 加 Adapter 配置                | Venue 不是抽象的 DEX 名称                        |
| Adapter                    | 封装某个 Venue 的存取流动性、费用和 Position 数据的受信模块                                    | Registry 中的固定地址                         | 不能决定 shares；`enabled` 只控制建立或增加 liquidity，禁用后现有 Position 仍可计价和退出 |
| Active Adapter             | `activeVenue != IDLE` 时与当前资产位置对应的唯一 Adapter；IDLE 时不存在 Active Adapter                    | 由 `getAdapter(activeVenue)` 从 Bootstrap 后冻结的 Registry 绑定派生 | 不单独存储；`getAdapter(IDLE) == address(0)`          |
| Active Position            | 当前唯一结构有效的外部 LP Position                                                   | Active Adapter 的 Position 快照            | 有效性不包含 Adapter `enabled`；非 IDLE 时最多一个，IDLE 时必须为零 |
| Idle Assets                | 直接保存在 Vault、未部署到 LP 的 token0/token1                                       | Vault ERC-20 余额                         | 不是固定比例缓冲；由部署结果、费用、舍入或 IDLE 产生             |
| Principal                  | 当前 LP liquidity 对应的底层 token0/token1 数量，不含未领取手续费                           | V2 储备权益或 V3 liquidity 数学                | 不得与 claimable fee 重复相加                    |
| Claimable Fees             | 已归属于 Position 但尚未转入 Vault 的 token0/token1 手续费                             | V2 已包含在储备权益；V3 fee growth / tokens owed | 只可在一个计价路径中出现                              |
| Total Assets               | Idle 加 Active Adapter 对 Vault 的完整资产报告                                     | `T0 = I0 + A0`、`T1 = I1 + A1`           | 不得额外扫描未知 Adapter 或重复添加费用                  |
| NAV                        | 按 canonical TWAP 将全部资产折算为 token1 的价值                                      | `NAV1 = T1 + Q1(T0; twapTick)`          | 仅用于定价和风控，不代表可立即换成 token1                  |
| TWAP                       | canonical V3 Pool 在 `twapWindowSeconds` 内的 arithmetic mean tick 对应的几何平均价格 | 一次 `observe([twapWindowSeconds, shortTwapWindowSeconds, 0])`，取 `tickCumulatives[2] - tickCumulatives[0]` | 用于 NAV、目标 Range 和偏离基准，不是现价或统计波动率          |
| Short TWAP Tick            | canonical V3 Pool 在 `shortTwapWindowSeconds` 内的 arithmetic mean tick      | 同一次 `observe([twapWindowSeconds, shortTwapWindowSeconds, 0])`，取 `tickCumulatives[2] - tickCumulatives[1]` | 只用于偏离信号，不单独作为 NAV                         |
| Spot Tick                  | canonical Pool 当前 `slot0().tick`                                          | 同一 Oracle 读取                            | 用于 V3 Range 越界与 Recenter 判定，不参与 `deviationBps`、NAV、`protocolMinOut` 或 Swap 风控 |
| DEVIATION / `deviationBps` | 短周期 TWAP 价格相对 TWAP 价格的绝对偏离，单位为基点                                          | Oracle 内部计算                             | 不接受外部输入；不得命名为 volatility                  |
| Oracle Healthy             | 运行时观察历史、Pool 动态数据、Tick 和报价均足以生成完整可用的价格快照                              | Oracle 每次生成快照时检查                         | 与部署期固定绑定校验、`EXTREME_DEVIATION` 独立；极端偏离可以仍然健康 |
| Market Regime              | Vault 策略逻辑根据健康 Oracle 快照和滞后规则输出的策略状态                                       | LOW/MEDIUM/HIGH/EXTREME                 | 不是收益评级或风险免责                               |
| Last Executed Regime / `lastExecutedPlan.marketRegime` | 最近一次成功执行的健康策略计划所提交的 Regime，作为 Hysteresis 历史 | Vault 持久化的 `lastExecutedPlan` | 不从 `activeVenue` 或 `lastExecutedPlan.targetVenue` 推导；Emergency Exit、Redeem 和 Oracle 不健康不覆盖 |
| Plan Version / `planVersion` | Position 结构状态的单调版本；候选计划使用下一版本 | Vault 持久化状态 | `0` 仅表示首次计划尚未成功；成功结构变化后递增 |
| Position Plan              | 目标 Venue、Market Regime、V3 Range 和计划版本的结构目标                                  | Vault 策略逻辑确定性生成                          | Rebalance 调用者只能提交期望哈希和 deadline，不能改写内容    |
| Last Executed Plan / `lastExecutedPlan` | 最近一次成功执行的完整策略计划 | Vault 持久化状态 | 非策略 Position 变化后可与当前资产位置不同；其 `marketRegime` 是 Hysteresis 历史 |
| Hysteresis                 | 状态进入和退出使用不同阈值形成的滞后区间                                                      | 部署固定的策略参数                             | 不能用 Cooldown 替代                           |
| Cooldown                   | 两类计划性 Rebalance 距最近一次成功 Bootstrap 或计划性 Rebalance 的最小时间间隔                                        | Vault 存储的 `lastPositionChangeAt`              | Emergency Exit 跳过前置检查且不更新计时；失败交易和 IDLE 幂等调用不更新 |
| Donation                   | 未铸造 shares 而无请求转入的资产，包含 Vault 支持 Token 和 Adapter LP 捐赠                                              | ERC-20 实际余额增加                           | 永久归确认时的 shares 持有人；确认时点见 §5.5，v1 不提供救援                 |




## 4. 系统行为总览

Vault 负责资产会计和原子执行；VaultControl 管理角色、暂停与 Adapter 绑定；策略逻辑生成目标；Oracle 产生价格快照；Adapter 与具体 AMM 交互；Swap Executor 执行受限换币。

```mermaid
flowchart LR
    User[LP 用户] -->|双资产 Deposit/Redeem| Vault[AdaptiveLPVault]
    Caller[Permissionless Caller] -->|无 Swap Rebalance| Vault
    DefaultAdmin[Default Admin] -->|角色指派与根角色管理| Control[VaultControl]
    Manager[Manager] -->|Bootstrap 与受控资产操作| Vault
    Manager -->|暂停与 Adapter 配置| Control
    Keeper[Keeper] -->|受控 Swap Rebalance| Vault
    Guardian[Guardian] -->|暂停与禁用 Adapter| Control
    Guardian -->|紧急退出| Vault
    Vault -->|权限与运行时控制检查| Control
    Vault --> Oracle[CanonicalV3Oracle]
    Vault --> Swap[ControlledSwapExecutor]
    Vault --> V2[UniswapV2Adapter]
    Vault --> V3[UniswapV3Adapter]
    V2 --> V2Pool[Uniswap V2 Pair]
    V3 --> V3Pool[Uniswap V3 Pool and PositionManager]
    Oracle --> Canonical[Canonical Uniswap V3 Pool]
```





### 4.1 单活 Position 规则

- `activeVenue == IDLE` 时，不存在纳入会计的 Active Position；非活跃 V2 Adapter 可保留 §5.5 定义的未确认捐赠 LP。
- `activeVenue != IDLE` 时，只有对应 Adapter 的 Position 纳入会计；非活跃 V3 Adapter 的受管理仓位必须为空，非活跃 V2 捐赠 LP 不构成第二个策略主动仓位，也不阻止 Bootstrap、Deposit、Rebalance 或 Emergency Exit。
- Rebalance 必须先完成旧 Position 退出，再建立新 Position；整个过程在一笔交易内原子完成。



## 5. Vault 生命周期与存取款



### 5.1 生命周期与资产位置

Vault 的状态由生命周期、资产位置和运行时控制三个独立维度表达。

**生命周期阶段**仅由 `initialized` 派生：

| 阶段 | 唯一判定 | 进入条件 | 退出条件 |
| --- | --- | --- | --- |
| `UNINITIALIZED` | `initialized == false` | 合约部署后 | Bootstrap 成功后进入 `OPEN` |
| `OPEN` | `initialized == true` | Bootstrap 成功后 | 无；`initialized` 只能从 false 变为 true |

**资产位置**由 `activeVenue` 和 Position 不变量表达：

- `activeVenue == IDLE` 表示没有纳入会计的 Active Position，允许非活跃 V2 保留未确认捐赠 LP；
- `activeVenue != IDLE` 表示只有当前 Venue 对应 Adapter 的 Position 纳入会计；
- `IDLE` 和 `ACTIVE` 均可与 `OPEN` 组合。

### 5.2 Bootstrap

Bootstrap 只能由 Manager 调用且只能成功一次。`minimumLockedShares` 在部署时固定，不能由 Manager 在 Bootstrap 调用中临时指定。

前置条件：

- Vault 尚未初始化；
- 两个 V3 Adapter 的受管理仓位必须为空；已有 V2 LP 按 §5.5 处理，不要求其实际余额为零；
- `bootstrap()` 必须在任何初始资产转入、shares 铸造或 Adapter 建仓前，重新校验由 canonical Pool 派生并由 canonical Oracle 固化的 token0/token1、Token decimals、canonical Oracle、Swap Executor 和所有 v1 Adapter 的完整 immutable 绑定及 `tickSpacing` 缓存；
- 验证 `swapExecutor.swapPool() == canonicalOracle.canonicalPool()`；
- Oracle Healthy；
- 初始 token0 和 token1 均大于零；
- 初始 `NAV1` 不低于 `minimumInitialNav`。

执行规则：

1. 读取 TWAP，并根据 `amount0/amount1` 构造零 Position 的初始资产快照。
2. 以 `planVersion == 0` 表示无历史计划，由 Vault 策略逻辑生成初始计划。
3. 初始计划按 LOW → MEDIUM → HIGH → EXTREME 的完整进入阈值分类，并返回 `version == 1` 的计划。
4. 校验初始计划的目标 Venue 和 Range，并对初始资产执行部署评估。
5. 按第 6.4 节公式计算 `grossInitialShares`。
6. 转入 `amount0/amount1` 并完成铸造：`minimumLockedShares` 铸造给 Vault 自身（`address(this)`），其余发送到 `receiver`。
7. 计划为 `EXTREME_DEVIATION` 时，资产保留在 Vault 并直接进入 IDLE。
8. 计划为 LOW、MEDIUM 或 HIGH 时，部署评估必须满足 `requiresSwap == false` 和最低部署率，并在同一交易内建立目标 Position 后进入 ACTIVE。
9. 部署评估的 `requiresSwap == true` 时，以 `SwapRequired()` 回滚；具体策略见第 9 节。
10. 验证部署率、资产守恒和 Position 唯一性；首次激活 V2 时将已确认的捐赠纳入完整资产快照，初始 shares 仍仅由本次 `amount0/amount1` 计算。
11. 将初始计划写入 `lastExecutedPlan`，将 `planVersion` 写为 `1`，并将 `lastPositionChangeAt` 写为当前 `block.timestamp`。
12. 将 `initialized` 置为 `true`，并发出 `PositionPlanCommitted` 和 `VaultBootstrapped` 事件，按条件发出 `V3RangeChanged`。

Bootstrap 完成后的遵从规则如下：

- Bootstrap 已包含首次策略执行，无需再手动调用 Rebalance；
- Bootstrap 失败时，全部资产转移、shares 铸造和 Adapter 状态必须回滚，且不得发出 `VaultBootstrapped`；
- Bootstrap 成功后不得重新初始化，也不得通过销毁 shares 重新开启 Bootstrap。

### 5.3 Deposit

用户提交 `amount0Max`、`amount1Max`、`minSharesOut` 和 `receiver`。Vault 只转入按当前唯一 Active Position 本金比例计算的实际数量，不先转入全部最大值。

前置条件：

- `initialized == true`；
- `depositPaused == false`；
- Oracle Healthy；
- `activeVenue != IDLE` 且 Active Position 结构有效；
- `isEnterEnabled(activeVenue) == true`；Adapter 已禁用时以 `AdapterDisabled()` 回滚；
- 存款前 `T0 > 0`、`T1 > 0`；
- V3 Active Position 的 `principal0 > 0` 且 `principal1 > 0`；任一侧为零时以 `ActivePositionSingleSided()` 回滚；
- 存款前 `idleBps <= maxHealthyIdleBps`；

设当前 Active Position Snapshot 的本金为 `p0 = principal0`、`p1 = principal1`。`d0` 和 `d1` 是实际从用户转入的数量，按以下最大共同存款公式计算：

$$
amount0Max \times p_1 \le amount1Max \times p_0
\quad\Longrightarrow\quad
 d_0 = amount0Max,\qquad
 d_1 = \left\lfloor\frac{amount0Max \times p_1}{p_0}\right\rfloor
$$

$$
amount0Max \times p_1 > amount1Max \times p_0
\quad\Longrightarrow\quad
 d_1 = amount1Max,\qquad
 d_0 = \left\lfloor\frac{amount1Max \times p_0}{p_1}\right\rfloor
$$

所有乘除使用全精度 `mulDiv` 语义。公式必须满足 `d0 <= amount0Max`、`d1 <= amount1Max`；不得使用 `amount0/amount1` 或整个 Vault 的 `T0/T1` 作为 Deposit 比例来源。手续费不参与该比例计算。

执行规则：

1. 读取存款前 Oracle、资产和 Active Position Snapshot；费用同步按 §6.8 的统一会计路径执行并按条件发出 `FeesSynchronized`，且不改变 Deposit 比例来源。
2. 按上述公式计算实际 `d0`、`d1`；若 `d0 == 0` 或 `d1 == 0`，以 `ZeroAmount()` 回滚。
3. 使用存款前 `NAV1`、`S` 和实际 `d0`、`d1` 计算 `sharesMinted`。
4. 验证 `sharesMinted >= minSharesOut`；否则以 `SharesSlippage(sharesMinted, minSharesOut)` 回滚。
5. 从用户转入实际 `d0`、`d1`。
6. 按当前 Position Plan 尝试增加流动性；不能部署的数量保留为 Idle。
7. 验证 post-state 的 `idleBps`、单活 Position 和资产守恒。
8. 铸造 shares 给 `receiver` 并发出 `Deposit` 事件。

任一检查失败，整笔交易回滚，用户未使用的最大输入不会离开钱包。

### 5.4 Redeem

调用者提交 `shares`、`minAmount0Out`、`minAmount1Out`、`receiver` 和 `owner`。`owner` 是被销毁 shares 的持有人，`receiver` 是接收最终 token0/token1 的地址，`msg.sender` 是实际调用者；`owner != msg.sender` 检查并消费 `owner` 授予 `msg.sender` 的 shares allowance。赎回不执行 Swap，不以 Oracle 价值判断是否允许，并且不因三个业务暂停开关而关闭。

设销毁前总供应量为 `S`，`owner` 销毁 `x` shares。非 IDLE 时完成费用同步后、调用 Active Adapter 退出前，记 Vault 实际持有的 Idle 余额为 `I0/I1`；IDLE 时直接使用当前 Vault 余额。Idle 部分分别向下取整：

$$
 idleOut_0 = \left\lfloor\frac{x \times I_0}{S}\right\rfloor, \qquad
 idleOut_1 = \left\lfloor\frac{x \times I_1}{S}\right\rfloor
$$

非 IDLE 时，`positionOut0/positionOut1` 是 Active Adapter 按 `x/S` 退出其原生 Position 单位后实际返回 Vault 的 token0/token1 余额增量；IDLE 时二者均为零。最终实际输出为：

$$
 amount0Out = idleOut_0 + positionOut_0, \qquad
 amount1Out = idleOut_1 + positionOut_1
$$

执行规则：

- 首先检查 `initialized == true`；未初始化时以 `NotInitialized()` 回滚
- 校验 `owner` 的 shares 余额；`msg.sender != owner` 时按 ERC-20 规则消费 `allowance(owner, msg.sender)`；
- 非 IDLE 时调取 `syncFees()` 同步 Active Adapter 的费用并按条件发出 `FeesSynchronized`；IDLE 时不得调用 Adapter。随后读取销毁前总供应量和资产快照；
- 在 Adapter 退出前固定 `I0/I1`，按上述公式计算 `idleOut0/idleOut1`；不得把 Adapter 退出后转入 Vault 的资产再次计入 Idle 分配；
- 非 IDLE 时调用 Active Adapter `withdraw(x, S)` 按规则向下取整，并将底层 AMM 实际退出资产返回 Vault。Vault 必须验证 Adapter 返回值分别等于本次调用造成的 token0/token1 实际余额增量，不一致时以 `AdapterBalanceMismatch()` 回滚；IDLE 时不得调用 Adapter，`positionOut0/positionOut1` 固定为零；
- 将 `positionOut0/positionOut1` 与 `idleOut0/idleOut1` 合并为最终实际 `amount0Out/amount1Out`；
- 在 Vault 层验证最终实际 `amount0Out >= minAmount0Out` 且 `amount1Out >= minAmount1Out`；
- 从 `owner` 销毁 shares 后，将最终 token0/token1 转账给 `receiver`。

如果除 `minimumLockedShares` 外的流通 shares 全部赎回，Vault 不发生生命周期或资产位置转换：

- 仍按上述分段输出规则从当前 Active Adapter 部分退出并分配 Idle，保留 `minimumLockedShares` 对应的剩余 Position 或 Idle 资产；如果当前资产位置为 IDLE，则保持 IDLE；
- `activeVenue`、`planVersion` 和 `lastExecutedPlan` 保持不变；
- 按既定 Position 一致性和资产守恒规则校验剩余 Position；
- 后续 Deposit、Redeem 和 Rebalance 继续按照已初始化 Vault 的既定规则执行。

### 5.5 Donation

直接转入 Vault 的 token0/token1 不会触发 shares 铸造，也不会被识别为用户 Deposit。实际余额增加自动进入 `I0/I1`，因此提高总资产和现有 shares 的 share price。

v1 规则如下：

- 支持资产 Donation 永久归属于现有 shares 持有人；
- Donation 不改变按 Active Position 本金比例计算的 Deposit 数量，但可能提高 `idleBps` 并关闭后续存款；
- Vault 不提供支持资产 `rescue`、`sweep`、退款或管理员提取接口；
- 非支持资产不属于 v1 核心流程，不得通过通用转账接口引入资产转移权限。

V2 LP 捐赠采用激活时确认规则：

- V2 非活跃时，其实际 LP 余额暂不纳入 `totalAssets`、NAV、Deposit 定价或 Redeem；这些 LP 不构成第二个策略主动仓位，也不要求主动清理。
- Bootstrap 或 Rebalance 激活 V2 后，已有 LP 与本次铸造 LP 一并纳入会计，不增发 shares、不提供捐赠者退款或提取权；收益由激活时全部 shares 持有人（包括锁定份额）按比例分享。协议接受激活前新存款者分享收益，激活前已赎回者不分享。
- V2 活跃时收到 LP 捐赠立即纳入会计；迁出或紧急退出 V2 时，退出全部实际 LP。Active 为 V3 或 IDLE 时，Emergency Exit 不处理非活跃 V2 的未确认 LP。
- 激活 V2 的建仓路径必须验证实际 LP 余额增量等于 Adapter 返回的本次铸造量。最终部署率、Idle、逐 Token 守恒和（带 Swap 时）迁移净值损失统一使用包含新确认捐赠的完整会计快照；因此捐赠可以抵补最终资产净值减少，但可能被迁移成本消耗。成功事件、查询、后续定价和赎回使用同一完整会计快照。
- V3 仅管理内部记录的 `_positionId`；外来 NFT 不自动接管、不计价，也没有取回入口。对活跃受管理 NFT 追加 liquidity 的捐赠随该 Position 纳入会计。

该规则保留单活会计与赎回路径，避免因第三方强制转入 LP 阻断操作；非活跃 V2 捐赠的收益归属取决于激活时点，而非捐赠时点。



## 6. Shares 与资产会计



### 6.1 单位和快照

- 所有 ERC-20 数量在合约内部使用各自 token 的 raw units。
- v1 要求两个支持 Token 的 `IERC20Metadata.decimals()` 均不超过 18；`CanonicalV3Oracle` 从 canonical Pool 读取有序 `token0/token1` 后读取两个 Token 的 decimals，Vault 再从 canonical Oracle 取得并缓存这些 immutable 值。Token 地址必须非零、互不相同且满足 `token0 < token1`；Pool 或 Token metadata 读取失败、Token 顺序不合法或 decimals 超限时，相关合约部署或绑定校验回滚。
- Shares 固定使用 18 decimals；一份完整 share 的初始名义价值为一份完整 token1。
- `NAV1`、`minimumInitialNav` 和迁移损失均以 token1 raw units 表示。
- `Q1(amount0; tick)` 返回 token1 raw units，`Q0(amount1; tick)` 返回 token0 raw units；canonical Pool、Vault、Oracle、Swap Executor、所有 Adapter 及其绑定 Pool 使用相同的有序 Token 顺序，因此 `Q1` 固定表示 token0 → token1，`Q0` 固定表示 token1 → token0。价格函数必须处理 Token decimals，具体取整规则由使用它的公式定义。
- 百分比使用 `BPS = 10_000`。
- 所有乘除使用全精度 `mulDiv` 语义；不足一单位时按照每个公式规定的方向舍入。
- Shares 铸造向下舍入；Redeem 的 Idle 分配和 Adapter 原生 Position 单位按各自公式向下舍入，最终 token 输出使用底层 AMM 实际退出量；零 shares 或零实际存款必须回滚。



### 6.2 Total Assets

令：

- `I0/I1`：Vault 当前实际持有的 Idle token0/token1；
- `A0/A1`：唯一 Active Adapter 对 Vault 报告的完整 Position token0/token1；
- `P0/P1`：Position principal；
- `F0/F1`：尚未归集的 claimable fees。

统一资产定义为：

$$
T_0 = I_0 + A_0, \qquad T_1 = I_1 + A_1
$$

在费用尚未归集的读取阶段：

$$
A_0 = P_0 + F_0, \qquad A_1 = P_1 + F_1
$$

费用归集后的资产快照必须满足：

- `F0/F1` 归零；
- 已归集数量进入 `I0/I1`；
- Adapter 快照已重新读取；
- 旧 `F0/F1` 不得再次计入 `A0/A1`。

资产汇总只读取唯一 Active Adapter：

- 只有 `activeVenue` 对应 Adapter 可以贡献 `A0/A1`；
- Registry 不得通过遍历所有 Adapter 汇总资产，以保证查询 Gas 有界并避免重复计价已禁用 Adapter。

### 6.3 TWAP NAV 与 Share Price

canonical Oracle 给出 `twapTick`，其报价函数定义为 `Q1`。Vault 的 token1 计价净资产为：

$$
NAV_1 = T_1 + Q_1(T_0; twapTick)
$$

当 `S > 0` 时，单份 share 的 token1 价值为：

$$
sharePrice_1 = \frac{NAV_1}{S}
$$

`NAV1` 用于 Deposit 定价、share price 展示、迁移损失和 Idle 健康检查；Redeem 默认返回原始双资产，不将资产强制换成 token1。

### 6.4 Shares 铸造

**Bootstrap**

设初始资产按 Bootstrap TWAP 计算的 token1 价值为：

$$
NAV_{seed} = amount_1 + Q_1(amount_0; twapTick_{bootstrap})
$$

创世总铸造量为：

$$
grossInitialShares = \left\lfloor \frac{NAV_{seed} \times 10^{shareDecimals}}{10^{token1Decimals}} \right\rfloor
$$

其中 `shareDecimals = 18`。接收者获得：

$$
receiverShares = grossInitialShares - minimumLockedShares
$$

`minimumLockedShares` 遵循以下铸造规则：

- 它包含在 `grossInitialShares` 中，不得额外增发；
- 必须满足 `grossInitialShares > minimumLockedShares`；
- 必须满足 `receiverShares > 0`；
- 该公式在首次建仓前计算，无论初始计划进入 ACTIVE 还是 IDLE 都保持不变。

`minimumLockedShares` 在 Bootstrap 时铸造给 Vault 自身，作为永久锚定资本；`totalSupply()` 始终不得低于该数量。

**后续 Deposit**

存款前读取 `NAV_before` 和 `S_before`。用户实际存入价值为：

$$
D_1 = d_1 + Q_1(d_0; twapTick_{before})
$$

后续存款铸造量为：

$$
sharesMinted = \left\lfloor \frac{D_1 \times S_{before}}{NAV_{before}} \right\rfloor
$$

该公式必须在用户资产转入和新 Position 建立前计算。任何中间状态的资产增加都不能用于抬高用户获得的 shares。

### 6.5 Idle 比例

Idle 的 token1 价值和比例为：

$$
IdleValue_1 = I_1 + Q_1(I_0; twapTick)
$$

$$
idleBps = \left\lfloor \frac{IdleValue_1 \times BPS}{NAV_1} \right\rfloor
$$

`idleBps` 的健康约束取决于资产位置：

- `activeVenue == IDLE` 时，`idleBps` 应接近 `BPS`，不受 `maxHealthyIdleBps` 约束，但必须关闭公众 Deposit；
- `activeVenue != IDLE` 时，Deposit 和普通 Rebalance 必须满足各自的 Idle 上限。

### 6.6 资产守恒

无 Swap Rebalance 必须保持 token0/token1 的经济构成：

- 旧 Position 退出后，token0/token1 必须进入 Vault Idle 或新 Active Position；
- 只允许 `dustTolerance0/1` 范围内由整数舍入、最小单位和 AMM 数学造成的差异。

对应约束为：

$$
T_{0,after} \ge T_{0,before} - dustTolerance_0
$$

$$
T_{1,after} \ge T_{1,before} - dustTolerance_1
$$

`dustTolerance0/1` 是本文唯一的舍入容忍概念，具体口径如下：

- `dustTolerance0` 和 `dustTolerance1` 分别使用 token0/token1 raw units 表示；
- 只覆盖整数舍入、最小单位和 AMM 数学造成的可接受微小差异；
- 容忍范围内的余额仍属于 Vault，不是可忽略的资产损失；
- 公式中的 `dustTolerance_0/1` 分别对应上述两个配置值。

### 6.7 迁移损失

带 Swap Rebalance 路径在经过 swap 后允许配置的最大价值损失：

$$
NAV_{after} \ge NAV_{before} \times \left(1 - \frac{maxMigrationLossBps}{BPS}\right)
$$

`maxMigrationLossBps` 只限制 Vault 资产价值损失，不从用户本金支付调用者 Gas。所有后置条件失败时交易回滚。

### 6.8 手续费同步与正确计价口径

手续费同步的作用，是在改变 shares 总供应量或 Position 结构前，把尚未领取的 V3 手续费从 Position 会计转移到 Vault 实际余额，并让后续资产快照只使用一个来源。

**V2 口径**

V2 Adapter 按 Vault 持有的 LP Token 在 Pair 总供应量中的比例，计算其对应的 Pair 储备 `P0/P1`。交易手续费已经通过储备增长反映在 LP Token 权益中，因此：

- V2 Position 的资产金额直接由 LP Token 比例和当前储备计算；
- 不额外设置或添加独立的 `F0/F1` 手续费金额；
- V2 Adapter 的 `syncFees()` 不领取资产，返回零费用即可。

**V3 口径**

V3 Adapter 通过 `PositionSnapshot` 返回 Position 的本金、未领取手续费和汇总金额：

- `principal0/principal1`：当前 Pool 价格、Position Tick Range 和 liquidity 对应的 token0/token1 本金，不包含手续费；
- `claimableFee0/claimableFee1`：Position 已归属、可以领取但尚未转入 Vault 的 token0/token1，必须包含 Position Manager 已记录的 `tokensOwed` 和当前 fee growth 增量；
- `amount0/amount1`：Position 的唯一汇总金额，必须满足：

$$
amount_0 = principal_0 + claimableFee_0, \qquad amount_1 = principal_1 + claimableFee_1
$$

Vault 使用 `amount0/amount1` 计入 Position 资产后，不得再次加入 `claimableFee0/claimableFee1`。费用领取后，`claimableFee0/claimableFee1` 应从 Position 快照中移除，领取数量只能通过 Vault 实际余额进入 Idle 资产。

调用时机：`Deposit`、`Redeem`、`Plain Rebalance`、`Swap Rebalance`、`Emergency Exit` 在形成用于定价或迁移的最终资产快照前，必须按统一会计路径调用当前 Active Adapter 的 `syncFees()`；普通 shares 转账和只读接口无需同步。


V3 Adapter 的 `syncFees()` 执行前必须满足：

- `activeVenue != IDLE`；`activeVenue == IDLE` 时跳过费用同步，并将本次同步费用视为零；
- Active Position 存在：V2 Adapter 持有的 LP Token 余额必须大于零；V3 Adapter 的 `positionId` 必须大于零。

V3 Adapter 的 `syncFees()` 必须按以下顺序执行：

1. 记录 Vault 同步前的 token0/token1 实际余额；
2. 通过零 liquidity poke 结晶截至当前 Pool 状态的全部 fee growth；
3. 调用固定 Position Manager，将该 Position 的全部可领取 token0/token1 领取到 Vault；
4. 重新读取 Vault 的 token0/token1 实际余额和 PositionSnapshot；
5. 以 Vault 余额增量作为 `fee0/fee1` 返回值。
6. 校验同步后 PositionSnapshot 的 `claimableFee0 == 0` 且 `claimableFee1 == 0`；

任一同步后校验失败时，当前调用必须回滚。



### 6.9 捐赠对会计的影响

以下影响针对直接转入 Vault 的 token0/token1；V2 LP 的确认时点和最终检查口径遵循 §5.5。Donation 直接增加 `I0/I1`，没有对应 `sharesMinted`。因此 Donation 发生后：

- `NAV1` 和 `sharePrice1` 可能上升；
- Donation 不改变按 Active Position 本金比例计算的 Deposit 数量；
- `idleBps` 可能超过健康上限；
- 新 Deposit 应被关闭，直到恢复健康结构。

这不是首存或手续费结算漏洞，而是协议明确接受的无请求资产捐赠语义。

## 7. Venue、Adapter 与 Registry 行为

### 7.1 AdapterRegistry 配置

Adapter 绑定由专属 `VaultControl` 管理；初始化前，将三个非 IDLE Venue 分别绑定到唯一的 Adapter。Adapter 自身在部署时固定保存其 Vault、Venue、Pool 和（V3）Position Manager，并从绑定 Pool 读取 token0/token1、Fee Tier、Tick Spacing`。

在 `VaultControl` 上调用 `configureAdapter(venue, adapter)` 的规则如下：

- 仅 Manager 可在 `initialized == false` 时调用；
- 调用时必须验证 Adapter 合约代码、Vault、Venue、Pool、Adapter 与 Pool 的 `token0/token1`、Fee Tier 和 `tickSpacing` 的绑定关系，并验证 Pool 固定 Factory 的登记关系 ；V3 Adapter 的 `tickSpacing` 必须为正且与其 Pool 的实际 `tickSpacing()` 一致，V2 Adapter 的 Fee Tier 和 `tickSpacing` 固定为零；验证失败时以 `InvalidTokenOrder()`、`InvalidTickSpacing()` 或对应绑定错误回滚；
- 成功后将 Adapter 地址、经过验证的 `tickSpacing` 缓存和 `enabled = true` 写入 `_adapterByVenue`，并发出 `AdapterConfigured`；
- 该方法不转移资产、不创建 Position，也不改变 shares 或策略状态；
- 初始化前可重复调用，以修正绑定。

Bootstrap 对 Registry 执行最终封存：

- 重新验证全部 Adapter immutable 绑定与 Registry 的 `tickSpacing` 缓存，并冻结 Adapter 身份和 spacing 缓存；
- 此后只能通过 `setAdapterEnabled(venue, enabled)` 改变运行状态；
- `enabled` 表示是否允许在该 Adapter 建立或增加 liquidity，包括用户 Deposit、迁入该 Venue 和同 Venue V3 Recenter；
- 任一非 IDLE 目标在调用 `previewDeposit()` 或 `deposit()` 前必须满足 `isEnterEnabled(targetVenue) == true`，否则以 `AdapterDisabled()` 回滚；
- 禁用当前 Active Adapter 不使现有 Position 结构失效，不改变 `activeVenue`、`planVersion`、`lastExecutedPlan` 或暂停 storage；该 Position 继续参与资产计价，并允许读取、费用同步、Redeem、完整退出和 Emergency Exit。

### 7.2 Uniswap V2 Adapter

V2 Adapter 必须固定绑定一个 Pair、Vault 以及从该 Pair 读取的 token0/token1，并提供：

- `snapshot()` 固定返回 `venue = UNISWAP_V2` 和 `adapter = address(this)`；
- 按 Pair 当前储备计算的 LP Token 权益作为 `PositionSnapshot` 的 `principal0/principal1` 和 `amount0/amount1`；`claimableFee0/1` 为零；
- `PositionSnapshot.liquidity` 等于 Adapter 实际持有的 LP Token 余额，使用 LP Token raw units；`positionId`、`tickLower` 和 `tickUpper` 固定为零；
- 按 Pair 当前储备比例增加流动性；
- 读取 LP Token 余额和 Pair 总供应量；
- 完整退出和按比例部分退出；
- 只从 Vault 拉取实际部署所需的 `used0/used1`；相对 `amount0Max/amount1Max` 未使用的数量继续保留在 Vault 作为 Idle。

V2 的 `liquidity` 是 Adapter 原生 Position 单位，只用于 V2 内部计算和通用的零/非零有效性判断，不得与 V3 liquidity 比较或换算。Adapter 的 LP Token 余额为零时，`venue` 和 `adapter` 仍返回固定绑定值，其余 Position 数量字段均为零。

V2 Position 覆盖全价格区间，不存在 Tick Range，但仍承担 AMM 价格风险、无常损失、流动性风险和 MEV 风险。

### 7.3 Uniswap V3 Adapter

V3 Adapter 必须固定绑定一个 Pool、Fee Tier、Tick Spacing、Position Manager 和 Vault，并从该 Pool 读取 token0/token1，同时管理一个 NFT Position。Position 包含：

- `tokenId`；
- `tickLower`、`tickUpper`；
- `liquidity`；
- principal 和 claimable fee 的读取状态。

V3 Adapter 的 Position 管理规则如下：

- 支持创建、增加、减少 liquidity、收取费用、按比例退出和旧 Position 清理；
- 必须满足 `tickLower < tickUpper`；
- `tickLower` 和 `tickUpper` 必须对齐 Pool 的 `tickSpacing`；
- 旧 NFT 可以保留为零 liquidity 且零 owed fee 的清理状态，但不得计为有效 Position。

### 7.4 IDLE

IDLE 不是 Adapter，而是 `activeVenue == IDLE` 的资产位置状态。IDLE 状态下：

- 全部已纳入会计的支持资产直接保存在 Vault；非活跃 V2 可保留 §5.5 定义的未确认捐赠 LP；
- 不产生纳入 Vault 会计的 LP 手续费；
- 不执行外部 LP Position；
- 仍承担 token 本身、ERC-20、Vault 和角色权限风险；
- 新 Deposit 关闭，双资产 Redeem 保持开放；
- 需要向策略逻辑传入 `currentPosition` 时，由 Vault 在内存中构造规范空快照：`venue = IDLE`、`adapter = address(0)`，`principal0/principal1`、`claimableFee0/1`、`amount0/amount1`、`liquidity`、`positionId` 和 `tickLower/tickUpper` 全部为零；
- Bootstrap 在尚无 Active Position 时使用同一个规范空快照。



## 8. Oracle 与价格口径



### 8.1 Canonical Uniswap V3 Oracle

canonical Oracle 在部署时绑定一个 Uniswap V3 Pool。canonical Pool 是 Vault Token 顺序和价格来源的最终事实来源；该 Pool 必须满足：

- `canonicalPool.token0()` 和 `canonicalPool.token1()` 均非零、互不相同且满足 `canonicalPool.token0() < canonicalPool.token1()`；
- `CanonicalV3Oracle` 从 canonical Pool 读取该 `token0/token1`，并从对应 Token 合约读取 decimals；
- Vault 从 canonical Oracle 取得并缓存相同的 `token0/token1` 和 decimals；
- canonical Pool、Vault、Oracle、ControlledSwapExecutor、所有 Adapter 及其绑定 Pool 的 `token0/token1` 必须完全一致；
- `ControlledSwapExecutor.swapPool()` 必须与 `canonicalPool` 为同一地址；v1 不允许使用独立成交池；
- canonical Pool 必须满足 §1.2 的外部 AMM 身份边界；Pool 地址、对应固定 V3 Factory 的登记关系、Fee Tier 和代码哈希通过初始化检查；
- `0 < shortTwapWindowSeconds < twapWindowSeconds`；
- 对 WETH/USDC，标准 Pool 顺序为 `token0 = USDC`、`token1 = WETH`；前端展示可以使用 WETH/USDC 等用户顺序，但不改变协议内部 Token 顺序。

Oracle 不读取目标 Venue 作为自己的价格来源。V2、两个 V3 Venue 的 NAV 和 Vault 策略输入都使用同一 canonical Pool。

### 8.2 TWAP 计算

Oracle 调用：

```solidity
uint32[] memory secondsAgos = new uint32[](3);
secondsAgos[0] = twapWindowSeconds;
secondsAgos[1] = shortTwapWindowSeconds;
secondsAgos[2] = 0;
(int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
int56 twapDelta = tickCumulatives[2] - tickCumulatives[0];
int24 twapTick = arithmeticMeanTickRoundedDown(twapDelta, twapWindowSeconds);
int56 shortTwapDelta = tickCumulatives[2] - tickCumulatives[1];
int24 shortTwapTick = arithmeticMeanTickRoundedDown(shortTwapDelta, shortTwapWindowSeconds);
```

TWAP Tick 的计算口径如下：

- `arithmeticMeanTickRoundedDown` 对负数向负无穷取整，与 Uniswap V3 `OracleLibrary.consult` 语义一致；
- `twapTick` 和 `shortTwapTick` 都表示 arithmetic mean tick 对应的几何平均价格，不是价格的简单算术平均。

Spot Tick 和价格报价遵循以下规则：

- Oracle 同时读取 `pool.slot0().tick` 作为 `spotTick`；
- `spotTick` 不参与 `deviationBps`；
- `Q1/Q0` 报价通过 `TickMath` 和全精度乘除完成；
- canonical Pool、Vault、Oracle、Swap Executor、所有 Adapter 及其绑定 Pool 使用相同的有序 Token 顺序，`Q1` 固定为 token0 → token1，`Q0` 固定为 token1 → token0；
- `spotPriceToken1`、`twapPriceToken1` 和 `shortTwapPriceToken1` 分别是以 `10^token0Decimals` 个 token0 raw units（1 个完整 token0）为参考量，使用对应 Tick 通过 `Q1` 向下取整得到的 token1 raw units；
- `observedAt` 等于生成本次快照时的 `block.timestamp`，只用于前端、索引器和调试元数据，不参与任何协议计算或状态门控。

### 8.3 DEVIATION 定义

对固定的 `referenceAmount0 = 10^{token0Decimals}`（1 个完整 token0）分别使用 `shortTwapTick` 和 `twapTick` 报价：

$$
P_{short} = Q_1(referenceAmount_0; shortTwapTick)
$$

$$
P_{twap} = Q_1(referenceAmount_0; twapTick)
$$

`P_short` 和 `P_twap` 同时分别作为 `shortTwapPriceToken1` 和 `twapPriceToken1` 写入 OracleSnapshot；`spotPriceToken1` 使用相同参考量和 `spotTick` 计算。三个字段均为 token1 raw units，并按 `Q1` 向下取整。

$$
 deviationBps = \left\lfloor \frac{|P_{short} - P_{twap}| \times BPS}{P_{twap}} \right\rfloor
$$

`deviationBps` 完全由 Oracle 从链上 Pool 状态计算。任何外部函数都不能传入、覆盖或替换该值。该指标只表示短周期 TWAP 相对 TWAP 的价格偏离，不表示：

- 历史标准差；
- 实现波动率；
- 未来波动预测；
- 任何 Venue 的手续费 APR；
- 扣除无常损失后的最优收益。



### 8.4 Oracle Healthy 与失败门控

**部署期固定约束与绑定失败**

`CanonicalV3Oracle` 构造时必须校验 canonical Pool 地址和合约代码、Factory、Fee Tier、代码哈希、有序 `token0/token1`、Token metadata、窗口关系和协议硬边界。配置不合法时构造交易直接以对应错误回滚，不得部署一个以 `healthy == false` 表示错误配置的 Oracle。

**运行时快照可用性**

Oracle 每次生成快照时检查动态 Pool 数据。以下任一情况发生时，`snapshot()` 必须返回 `OracleSnapshot.healthy == false`：

- Observation 历史不足以覆盖 `twapWindowSeconds` 或 `shortTwapWindowSeconds`；
- `observe()`、`slot0()` 或其他必要的 Pool 数据读取失败；
- `P_twap == 0`，或任一必需报价为零。

`OracleSnapshot.healthy` 是快照有效性的判别字段。不健康时，`snapshot()` 不回滚，并返回以下规范快照：

- `spotTick`、`twapTick`、`shortTwapTick`、三个价格字段和 `deviationBps` 全部为零；
- `twapWindowSeconds`、`shortTwapWindowSeconds` 返回 Oracle 的 immutable 配置；
- `observedAt` 等于本次调用的 `block.timestamp`；
- `healthy = false`。

上述零值仅为无效占位值，不表示实际 Tick、价格或偏离为零。链上及链下消费者必须先检查 `healthy`；不健康时不得生成或展示 Market Regime。

无论失败发生在读取还是计算阶段，Oracle 都不得返回部分结果或上一次健康结果。实现必须捕获可处理的外部读取失败，避免动态失败穿透为 revert。Observation 历史是否充足不影响 Oracle 构造；Bootstrap 仍须通过本节的健康门控，链下发布预检见 [DEPLOYMENT.md](DEPLOYMENT.md)。

**Vault 运行时门控**

Bootstrap、Deposit、Preview、普通 Rebalance 和 `rebalanceWithSwap` 读取到 `healthy == false` 时，必须统一以 `OracleUnhealthy()` 回滚，不得生成或返回 `PositionPlan`，也不得修改资产位置、计划版本或 Hysteresis 历史。正常双资产 Redeem 继续开放；Guardian/Manager 仍可执行不依赖价格估值的无 Swap Emergency Exit。

极端 `deviationBps` 是健康 Oracle 下的策略状态，不自动等同于 Oracle 不健康。

## 9. 策略与 Rebalance

### 9.1 Vault 策略输入和输出

Vault 的策略逻辑是只读且确定性的计划生成器。输入仅来自：

- 当前 Oracle Snapshot；
- 当前 `activeVenue` 和 Position Snapshot；
- `lastExecutedPlan.marketRegime` 作为持久化的 Hysteresis 历史；
- 当前 `planVersion`；
- 已配置并验证的低费率 Pool 和高费率 Pool `tickSpacing`；
- 部署时固定且受硬边界约束的策略参数。

计划生成器根据 Position、Oracle 快照、历史 Regime、当前 Venue、固定策略参数和已验证的目标 Pool 配置，确定性生成完整的 `PositionPlan`；其内容包含 `targetVenue`、`marketRegime`、规范化的 `tickLower/tickUpper`、`version` 和 `planHash`。Tick 字段在 V3 计划中表示目标 Range，在非 V3 计划中使用 §9.1.3 定义的固定占位值。

- `planHash` 是对所有影响仓位结构且可稳定复算的计划字段计算的哈希；
- `version` 和 `planHash` 用于执行时的计划身份校验；
- 计划生成只产生候选计划，不直接提交 Vault 的 `planVersion` 或 `lastExecutedPlan` 更新；

**Vault 提供 `previewRebalance()` 策略只读接口**。规则如下：

1. 检查 `initialized == true`；未初始化时以 `NotInitialized()` 回滚。
2. 检查 Oracle 不健康时以 `OracleUnhealthy()` 回滚。
3. 生成最新 `PositionPlan`；目标为非 IDLE 时检查 `isEnterEnabled(targetVenue) == true`，禁用时以 `AdapterDisabled()` 回滚。
4. 使用与执行入口相同的部署评估路径返回 `PositionPlan` 与仅包含 `requiresSwap`、`direction` 的 `DeploymentAssessment`。

`previewRebalance()` 的使用边界如下：

- 前端通过回滚原因判断计划不可执行的原因；
- 前端和 Keeper 可在发送交易前据此选择 `rebalance` 或 `rebalanceWithSwap`；
- 预览结果只用于执行前判断；
- 真正执行时，Vault 仍须重新读取最新状态、重新生成计划、重新评估部署并校验哈希。

### 9.1.1 Position 结构版本与提交规则

`planVersion` 是 Vault 对 Position 结构状态的单调提交版本；策略逻辑只生成候选计划，成功的 Position 结构变化才提交新版本。

- `planVersion` 初始为 `0`；
- 策略逻辑生成的候选 `PositionPlan.version` 固定为当前 `planVersion + 1`；
- `version` 和 `planHash` 共同用于确认候选计划的身份；
- 候选计划生成、预览或哈希校验成功，不代表 `planVersion` 已经更新。

以下操作成功时，`planVersion` 必须恰好递增 1：

- Bootstrap；
- Venue 迁移；
- V3 Recenter；
- 策略进入或退出 IDLE；
- 调用前 `activeVenue != IDLE` 的 Emergency Exit；

以下操作不得更新 `planVersion`：

- 沿既有 Position 按当前计划增加流动性的 Deposit；
- 部分 Redeem；
- 费用同步；
- Donation；
- 暂停状态变化；
- Adapter `enabled` 变化；
- 任何失败交易。


### 9.1.2 Position 市场状态与目标 Venue


| Market Regime       | 进入条件                                                          | 目标 Venue | 目标行为                    |
| ------------------- | ------------------------------------------------------------- | -------- | ----------------------- |
| `LOW_DEVIATION`     | 健康 Oracle 且偏离低于进入 MEDIUM 的阈值                                  | V3 低费率池  | 以 TWAP Tick 为中心的窄 Range |
| `MEDIUM_DEVIATION`  | 从 LOW 上升跨过 `enterMediumBps`，或从 HIGH 下降跨过 `exitHighBps`        | V3 高费率池  | 以 TWAP Tick 为中心的宽 Range |
| `HIGH_DEVIATION`    | 从 MEDIUM 上升跨过 `enterHighBps`，或从 EXTREME 下降跨过 `exitExtremeBps` | V2 全价池      | 全价格区间，避免主动窄 Range 管理    |
| `EXTREME_DEVIATION` | 从 HIGH 上升跨过 `enterExtremeBps`                                 | IDLE     | 无 Swap 撤出或保持全部资产在 Vault |

其中 `Market Regime` 状态进入和退出使用不同阈值形成的 Hysteresis 滞后状态机

定义策略参数包括：`enterMediumBps`、`exitMediumBps`、`enterHighBps`、`exitHighBps`、`enterExtremeBps`、`exitExtremeBps`。参数必须满足：

$$
0 \le exitMediumBps < enterMediumBps \le exitHighBps < enterHighBps \le exitExtremeBps < enterExtremeBps
$$

状态转换规则：

- LOW 只有在 `deviationBps >= enterMediumBps` 时进入 MEDIUM；
- MEDIUM 只有在 `deviationBps <= exitMediumBps` 时回到 LOW，在 `deviationBps >= enterHighBps` 时进入 HIGH；
- HIGH 只有在 `deviationBps <= exitHighBps` 时回到 MEDIUM，在 `deviationBps >= enterExtremeBps` 时进入 EXTREME；
- EXTREME 只有在 `deviationBps <= exitExtremeBps` 时回到 HIGH；
- 未跨越当前状态对应边界时保持当前状态。

Vault 策略逻辑根据 `planVersion` 选择 Hysteresis 的分类方式：

- `planVersion == 0`：没有已提交的历史计划，按 LOW → MEDIUM → HIGH → EXTREME 的完整进入阈值直接分类；
- `planVersion > 0`：使用 `lastExecutedPlan.marketRegime` 作为 Hysteresis 历史执行上述状态转换；
- Hysteresis 只控制幅度，Cooldown 只控制时间频率，两者不可互相替代。

### 9.1.3 Position Tick 字段、V3 Range 计算与 Recenter

`PositionPlan.tickLower/tickUpper` 按目标 Venue 规范化生成：

- `LOW_DEVIATION` 和 `MEDIUM_DEVIATION` 的 V3 计划按本节后续规则生成有效 Range；`0/0` 不是合法 V3 Range；
- `HIGH_DEVIATION` 的 `UNISWAP_V2` 计划固定使用 `tickLower = 0`、`tickUpper = 0`；
- `EXTREME_DEVIATION` 的 `IDLE` 计划固定使用 `tickLower = 0`、`tickUpper = 0`；

对于 V3 计划，Vault 策略逻辑使用由已验证 Adapter 配置提供的目标 Pool spacing：

- `LOW_DEVIATION` 的目标 Venue 是 `UNISWAP_V3_LOW_FEE`，使用低费率 Pool 的 `tickSpacing`；
- `MEDIUM_DEVIATION` 的目标 Venue 是 `UNISWAP_V3_HIGH_FEE`，使用高费率 Pool 的 `tickSpacing`；
- `narrowRangeHalfWidthSteps` 和 `wideRangeHalfWidthSteps` 表示目标 Pool 的 spacing 间隔数量，不是 raw Tick 数量；两个值都必须大于零；
- 有效半宽按以下公式计算：

$$
lowHalfWidthTicks = narrowRangeHalfWidthSteps \times lowFeeTickSpacing
$$

$$
highHalfWidthTicks = wideRangeHalfWidthSteps \times highFeeTickSpacing
$$

Vault 策略逻辑按以下规则确定 `targetCenterTick`：

- 以 `twapTick` 为价格中心参考；
- 不使用调用者传入的 Tick，也不直接跟随 Spot Tick；
- 将 `twapTick` 对齐到距离最近的目标 Pool `tickSpacing` 整数倍；
- 距离相等时固定向下选择，以得到确定性的 `targetCenterTick`。

根据当前 Market Regime 生成目标 Range：

- `LOW_DEVIATION` 使用 `tickLower = targetCenterTick - lowHalfWidthTicks` 和 `tickUpper = targetCenterTick + lowHalfWidthTicks`；
- `MEDIUM_DEVIATION` 使用 `tickLower = targetCenterTick - highHalfWidthTicks` 和 `tickUpper = targetCenterTick + highHalfWidthTicks`；
- `tickLower < tickUpper`，且 `tickLower`、`tickUpper` 均为目标 Pool `tickSpacing` 的整数倍；由于 `targetCenterTick` 和有效半宽均由目标 spacing 的整数倍构成，边界不再执行二次取整；
- 生成的 `tickLower` 小于 Uniswap V3 `MIN_TICK` 或 `tickUpper` 大于 `MAX_TICK` 时以 `InvalidTickRange()` 回滚，不夹紧或移动 `targetCenterTick`；
- Range 必须覆盖 `twapTick`；
- Bootstrap 的最终校验必须满足 `lowHalfWidthTicks < highHalfWidthTicks`，确保窄 Range 的实际 Tick 宽度严格小于宽 Range。

对于已存在的同 Venue V3 Position，先计算以下 Recenter 参数：

- `currentRangeWidth = currentTickUpper - currentTickLower`；
- `currentRangeHalfWidth = currentRangeWidth / 2`；
- `currentCenterTick = currentTickLower + currentRangeHalfWidth`；
- `centerDelta = abs(targetCenterTick - currentCenterTick)`；
- 当前 Market Regime 要求的目标 Range 宽度为对应有效半宽的两倍。

只有满足以下任一条件时才允许 Recenter：

- 当前 Range 宽度与当前 Market Regime 要求的目标宽度不一致；
- 当前 Spot Tick 已离开现有 Range，并且 `centerDelta >= currentRangeHalfWidth * minRecenterBps / BPS`。

Spot 越界但 TWAP 目标中心尚未移动足够远时，不立即跟随 Spot 重建仓位。Tick 对齐后的新 Range 必须与旧 Range 不同，否则以 `NoStateChangeRequired` 回滚。

#### 9.2 部署评估 与 `requiresSwap`

Vault 策略逻辑生成候选 `PositionPlan` 后，调用内部只读的 `_assessDeployment(AssessmentInputs memory input)` 对指定资产执行部署评估。该函数调用目标 Adapter 的 `previewDeposit()` 获取局部 `used0/used1`，再根据统一部署评估公式计算仅包含 `requiresSwap` 与 `direction` 的 `DeploymentAssessment`。

生成部署评估规则如下:

- `minDeployBps` 由唯一配置的 `maxHealthyIdleBps` 派生：`minDeployBps = BPS - maxHealthyIdleBps`；
- 对 MarketRegime 为 LOW、MEDIUM 或 HIGH 的非 IDLE 计划，如果 `initialDeployBps < minDeployBps`，标记 `requiresSwap = true`；
- `initialDeployBps >= minDeployBps` 时，标记 `requiresSwap = false`；
- `EXTREME_DEVIATION` 以 IDLE 为目标，返回 `requiresSwap = false` 和 `direction = NONE`，不受部署率边界约束；
- 非 IDLE 计划的 `direction` 由 `used0/used1` 与未使用余额确定，完整规则见 [SWAP_REBALANE_MATH.md](SWAP_REBALANE_MATH.md)。

按以上规则返回包含 `requiresSwap`、`direction` 的 `DeploymentAssessment`。

`requiresSwap = true` 表示当前资产比例无法通过无 Swap 路径达到最低部署率，还需做对应处理如下：

- 未初始化时 Bootstrap 以 `SwapRequired()` 回滚，由 Manager 调整初始 token 比例后重试；
- 已初始化 Vault 的普通 `rebalance` 同样以 `SwapRequired()` 回滚；
- 只有 Keeper/Manager 可以改用 `rebalanceWithSwap` 执行该计划；
- EVM 回滚不保留状态更新或事件日志，因此不得发出 `VaultBootstrapped`、`RebalanceExecuted` 或 `SwapExecuted`；
- 调用方通过回滚返回的 `SwapRequired()` 识别失败原因。

### 9.3 普通 Rebalance

任何地址都可以调用 `rebalance(expectedPlanHash, deadline)`，其中 `expectedPlanHash` 表示调用者预期执行的计划身份，用于乐观并发控制；

前置条件：

- `initialized == true`；未初始化时以 `NotInitialized()` 回滚
- `expectedPlanHash` 和 `deadline` 不为空；
- `plainRebalancePaused == false`；
- Oracle Healthy；
- `deadline` 尚未到期；
- `minRebalanceCooldown` 已结束；
- 重新生成的 Position Plan 内的 `planHash` 与 `expectedPlanHash` 匹配；
- Position Plan 的目标为非 IDLE 时，`isEnterEnabled(targetVenue) == true`；
- 部署评估的 `requiresSwap == false`；
- Position Plan 满足 Venue 迁移、V3 Recenter 或进入 IDLE其中之一；

普通 Rebalance 必须按以下顺序原子执行：

1. 生成当前候选 `PositionPlan`；
2. 目标为非 IDLE 时检查目标 Adapter 已启用
3. 对当前资产执行部署评估并要求 `requiresSwap == false`；
4. 同步费用并按条件发出 `FeesSynchronized`；
5. 退出旧 Position；
6. 建立目标 Position 或进入 IDLE；
7. 归还未使用资产；
8. 验证资产守恒、Idle 和单活 Position；激活 V2 时使用包含新确认捐赠的完整会计快照，成功事件使用同一完整会计快照；
9. 将 `planVersion` 更新为执行计划的 `version`；
10. 将 `lastExecutedPlan` 更新为执行计划，并更新 `lastPositionChangeAt`；
11. 发出 `PositionPlanCommitted` 和 `RebalanceExecuted` 事件并按条件发出 `V3RangeChanged`。

任一步骤失败时，交易必须回滚，且不得更新上述状态。

### 9.4 带 Swap Rebalance

仅 Keeper/Manager 可以调用：`rebalanceWithSwap(expectedPlanHash, expectedDirection, amountIn, keeperMinAmountOut, deadline)`。

固定的 Swap 基础设施：每个 `AdaptiveLPVault` 在构造时通过组件工厂创建并永久绑定自己的 `ControlledSwapExecutor`。Executor 固定绑定该 Vault、Router 和 canonical Pool，从 `swapPool` 读取并保存 `token0/token1`，且必须与 Vault 和 canonical Pool 完全一致。Vault 在调用 `executeSwap()` 前向该 Executor 转入精确的 `amountIn`；Executor 只在本次调用期间持有输入资产，Router 的输出接收方固定为 Vault，调用者不能覆盖。

`maxSwapSlippageBps` 是部署时固定的协议滑点上限，任何调用者都不能覆盖。Vault 使用本次迁移开始时捕获的 canonical TWAP 计算协议最低输出 `protocolMinOut`；方向报价和滑点折算均向上取整。Vault 将 `minAmountOut = max(protocolMinOut, keeperMinAmountOut)` 写入本次 `SwapPlan`。

Vault 在退出旧 Position 和执行 Swap 前，必须完成以下检查：

- 调用者具有 Keeper 或 Manager 角色；
- `initialized == true`；
- `swapRebalancePaused == false`；
- Oracle Healthy；
- `expectedPlanHash` 非零，且 `block.timestamp <= deadline`；
- `minRebalanceCooldown` 已结束；
- 重新生成的当前计划的 `planHash` 等于 `expectedPlanHash`；
- 当前计划的目标 Adapter 满足 `isEnterEnabled(targetVenue) == true`；
- 当前部署评估的 `requiresSwap == true`；
- `expectedDirection` 非 `NONE`，并与当前部署评估的 `direction` 一致；
- `amountIn > 0`

带 Swap Rebalance 必须在一笔交易内原子完成：

1. 生成当前候选 `PositionPlan`；
2. 检查目标 Adapter 已启用，再对当前 `T0/T1` 执行首次部署评估，使用派生值 `minDeployBps = BPS - maxHealthyIdleBps` 校验 `initialDeployBps < minDeployBps`、`requiresSwap == true` 以及 `direction == expectedDirection`；
3. 同步费用并按条件发出 `FeesSynchronized`，捕获迁移前 TWAP 和 NAV；退出旧 Position 后重新读取实际余额；
4. 检查 `amountIn`，根据最差 `protocolMinOut` 模拟 Swap 后余额并计算 `simulatedDeployBps(x)` 与 `simulatedIdleBps(x)`，验证不会换过头且满足部署率和 Idle 限制，再构造临时 `SwapPlan`；
5. 记录 Vault 的输入/输出 Token 余额和 Executor 的 token0/token1 余额，将精确的 `amountIn` 从 Vault 转入 Executor，再调用 `ControlledSwapExecutor.executeSwap()` 执行固定 exact-input Swap；
6. 在调用目标 Adapter 前重新读取余额，以 Vault 的输出 Token 实际余额增量作为 `actualAmountOut`，并验证 Vault 的输入 Token 减少量等于 `amountIn`、`actualAmountOut` 等于 Executor 返回值且不低于 `minAmountOut`、Executor 的 token0/token1 余额恢复到转入前基线、Executor 对 Router 的 allowance 为零；该局部校验不使用 `dustTolerance0/1` 放宽；
7. 使用 Swap 后的实际余额，在目标 Adapter 建立当前计划指定的 Position；
8. 重新读取最终 Vault 余额和实际 `PositionSnapshot`，复用迁移开始时捕获的同一个 `twapTick` 计算 `finalDeployBps`、`finalIdleBps` 和迁移后 NAV，完成最终迁移校验；激活 V2 时使用包含新确认捐赠的完整会计快照。全部校验通过后，将 `lastExecutedPlan` 更新为执行计划，并提交 `planVersion` 和 `lastPositionChangeAt`；
9. 发出 `PositionPlanCommitted`、`RebalanceExecuted`、`SwapExecuted`和按条件发出 `V3RangeChanged`事件，其中 `SwapExecuted.amountOut = actualAmountOut`。

目标 Adapter 建仓完成后，Vault 必须重新读取实际状态并验证（激活 V2 时使用包含新确认捐赠的完整会计快照）：

- `finalDeployBps >= minDeployBps`，其中 `minDeployBps = BPS - maxHealthyIdleBps`；
- `finalIdleBps <= maxHealthyIdleBps`；
- 完整迁移后的 NAV 损失不超过 `maxMigrationLossBps`；
- 资产位置和余额守恒成立，允许的舍入差异仅限 `dustTolerance0/1`；

Swap 方向、`previewDeposit`、 `amountIn`、`protocolMinOut`、`keeperMinAmountOut`、V2/V3 比例以及舍入公式的完整定义见 [SWAP_REBALANE_MATH.md](SWAP_REBALANE_MATH.md)。

### 9.5 Emergency Exit to IDLE

Guardian/Manager 可在不依赖价格估值的情况下触发幂等紧急退出 `emergencyExitToIdle()`。该入口先检查 Guardian/Manager 角色，再检查 `initialized == true`；已授权调用者在未初始化时以 `NotInitialized()` 回滚。该入口不检查 `minRebalanceCooldown`，紧急撤仓不会被计划性 Rebalance 的时间限制阻塞。

当调用前 `activeVenue != IDLE` 时：

1. 调用当前 Active Adapter 的 `syncFees()`，领取全部可领取手续费并按条件发出 `FeesSynchronized`；
2. 移除当前 Active Adapter 的全部 LP liquidity，并验证资产守恒和旧 Position liquidity 为零；不处理非活跃 V2 的未确认捐赠 LP；
3. 设置 `activeVenue = IDLE`；
4. 将 `planVersion` 递增 1，并保持 `lastExecutedPlan` 和 `lastPositionChangeAt` 不变；该时间戳继续约束后续计划性 Rebalance，历史计划的 `marketRegime` 继续作为 Hysteresis 历史。

当调用前 `activeVenue == IDLE` 时：

- 不调用任何 Adapter；
- 不修改 `activeVenue`、`planVersion`、`lastExecutedPlan` 或 `lastPositionChangeAt`；
- 不发出 `EmergencyExit`。

两个分支最后都必须把 `depositPaused`、`plainRebalancePaused` 和 `swapRebalancePaused` 设为 true。只有暂停 storage 实际变化时才发出 `PauseStateChanged`；只有调用前 `activeVenue != IDLE` 且 Active Position 成功清空时才发出 `EmergencyExit`。如果调用前已经 IDLE 且三个暂停位均为 true，调用成功但不修改状态，也不发出事件。

## 10. 暂停与权限控制

### 10.1 根管理员与业务角色

VaultControl 使用 OpenZeppelin Contracts v5 `AccessControlDefaultAdminRules` 提供根管理员标准流程：

| 角色 | 固定标识 | 角色管理员 | 权限范围 | 初始授权 |
| --- | --- | --- | --- | --- |
| Default Admin | `DEFAULT_ADMIN_ROLE`，即 `bytes32(0)` | 只能由 `AccessControlDefaultAdminRules` 标准流程管理 | 授予/撤销业务角色，管理根管理员继任与转移延迟 | 构造时授予非零 `initialDefaultAdmin` |
| Manager | `keccak256("MANAGER_ROLE")` | `DEFAULT_ADMIN_ROLE` | Bootstrap、Adapter 配置、暂停恢复、受控 Swap、Emergency Exit 等全部业务管理操作 | 不自动授予，由 Default Admin 指派 |
| Keeper | `keccak256("KEEPER_ROLE")` | `DEFAULT_ADMIN_ROLE` | 带 Swap Rebalance 和普通 Rebalance | 不自动授予，由 Default Admin 指派 |
| Guardian | `keccak256("GUARDIAN_ROLE")` | `DEFAULT_ADMIN_ROLE` | 收紧暂停、禁用 Adapter、Emergency Exit | 不自动授予，由 Default Admin 指派 |

### 10.2 独立暂停开关

| 开关 | 关闭的入口 | 不关闭的入口 |
| --- | --- | --- |
| `depositPaused` | Bootstrap 后公众 Deposit | Redeem、只读查询 |
| `plainRebalancePaused` | 无 Swap Rebalance | Redeem、Emergency Exit |
| `swapRebalancePaused` | 带 Swap Rebalance | Redeem、无 Swap Emergency Exit |

暂停状态在部署时默认为全 false。未初始化 Vault 不允许调用 `setPauseState`，因此 `bootstrap()` 不读取暂停位，也不会因运行时暂停状态被阻止。

自动门控和 Emergency Exit 的暂停状态遵循以下区分：

- Oracle 不健康、IDLE、完全单边、Idle 超限、Adapter 禁用或异常、Position 不一致时，只在对应入口实时回滚；
- 自动门控不写入暂停 storage，也不发出 `PauseStateChanged`；
- Emergency Exit 成功后，必须显式把三个暂停位全部设为 true；ACTIVE 与 IDLE 分支的 Adapter 调用和事件行为遵循第 9.5 节；
- 只有暂停 storage 实际变化时，才额外发出 `PauseStateChanged`；
- 后续恢复必须由 Manager 显式执行。

### 10.3 运行时控制权限

角色管理、`configureAdapter`、`setPauseState` 和 `setAdapterEnabled` 在 VaultControl 上调用；资产、计划和 Bootstrap 入口在 Vault 上调用。

| 入口 | 调用者 | 可调用阶段 | 资产流向与结果 |
| --- | --- | --- | --- |
| `grantRole` / `revokeRole`（业务角色） | 当前 Default Admin | 初始化前后均可 | 更新业务角色成员并发出标准角色事件；不改变 Default Admin |
| `renounceRole`（业务角色） | 角色持有人本人 | 初始化前后均可 | 放弃调用者自己的业务角色并发出 `RoleRevoked` |
| `beginDefaultAdminTransfer(newAdmin)` | 当前 Default Admin | 初始化前后均可 | 计划根管理员转移；`newAdmin == address(0)` 表示计划放弃根管理员，必须等待 `pendingDefaultAdminSchedule` 生效 |
| `cancelDefaultAdminTransfer` | 当前 Default Admin | 初始化前后均可 | 取消尚未完成的根管理员转移或放弃计划 |
| `acceptDefaultAdminTransfer` | 待接任账户 | 初始化前后均可 | 在计划生效后完成转移；不自动授予任何业务角色 |
| `renounceRole(DEFAULT_ADMIN_ROLE, msg.sender)` | 当前 Default Admin | 初始化前后均可，但必须先安排 `beginDefaultAdminTransfer(address(0))` 并等待计划生效 | 完成根管理员放弃；否则以 `AccessControlEnforcedDefaultAdminDelay` 回滚；成功后 `defaultAdmin()` 为零地址 |
| `changeDefaultAdminDelay` / `rollbackDefaultAdminDelay` | 当前 Default Admin | 初始化前后均可 | 计划或回滚根管理员转移延迟变更 |
| `configureAdapter` | Manager | 仅初始化前 | 注册已独立部署的 Adapter，验证其绑定并缓存 `tickSpacing`，将 `enabled` 初始化为 true，并发出 `AdapterConfigured` |
| `bootstrap` | Manager | 仅初始化前；只能成功一次 | 健康且部署评估无需 Swap 时进入 ACTIVE，EXTREME 进入 IDLE，铸造并锁定 shares，冻结 Adapter 身份绑定；部署评估的 `requiresSwap` 为 true 时以 `SwapRequired()` 回滚 |
| `deposit` | 任意 LP 用户 | 仅初始化后 | 仅在当前 Active Adapter 已启用时转入实际数量并铸造公平 shares |
| `redeem` | Shares 持有人或获授权 spender | 仅初始化后 | 按比例退出 Position 和 Idle，从显式 `owner` 销毁 shares，并向 `receiver` 返回双资产；非 owner 调用者必须消费足额 shares allowance；不要求 Oracle 健康，不受暂停或 Adapter 禁用影响 |
| `rebalance` | 任意地址 | 仅初始化后 | 原子退出旧 Position，建立已启用的新 Position 或进入 IDLE；部署评估的 `requiresSwap` 为 true 时以 `SwapRequired()` 回滚 |
| `rebalanceWithSwap` | Keeper/Manager | 仅初始化后 | Vault 内部构造受控 SwapPlan，执行换币后在已启用的目标 Adapter 建立 Position |
| `setPauseState` | Guardian/Manager | 仅初始化后 | 原子写入三个暂停位并发出 `PauseStateChanged`；只有 Manager 可以解除暂停 |
| `setAdapterEnabled(venue, false)` | Guardian/Manager | 仅初始化后 | 禁止在该 Adapter 建立或增加 liquidity，并发出 `AdapterStatusChanged`；现有 Position 仍计价且可读取、Redeem 和退出，不改变 Position、计划版本或暂停状态 |
| `setAdapterEnabled(venue, true)` | Manager | 仅初始化后 | 恢复在该 Adapter 建立或增加 liquidity，并发出 `AdapterStatusChanged` |
| `emergencyExitToIdle` | Guardian/Manager | 仅初始化后 | 不依赖 Oracle 健康且不执行 Swap；非 IDLE 时清空 Position、进入 IDLE 并递增版本，已在 IDLE 时不调用 Adapter；两个分支均将三个暂停位设为 true |
| `previewRebalance` | 任意地址 | 仅初始化后 | 返回基于当前状态的只读候选计划和部署评估；非 IDLE 目标 Adapter 禁用时以 `AdapterDisabled()` 回滚，不修改任何状态 |

表中所有“仅初始化后”入口在 `initialized == false` 时统一以 `NotInitialized()` 回滚。`deposit`、`redeem`、`rebalance` 和 `previewRebalance` 必须首先执行生命周期检查；`rebalanceWithSwap`、`setPauseState`、`setAdapterEnabled` 和 `emergencyExitToIdle` 必须先执行角色授权，再立即执行生命周期检查。

### 10.4 依赖封存

Bootstrap 成功后不可替换：

- canonical Oracle Pool 和 Oracle 合约；
- Vault 固定绑定的 VaultControl 及其权限、暂停和 Registry 管理职责；
- Vault 构造时通过组件工厂创建并永久绑定的 Swap Executor、固定 Router、与 canonical Pool 相同的 Swap Pool、Token 对、Pool/Fee Tier 和固定 Swap 方法；
- Adapter 地址、immutable 绑定；
- shares 的会计语义和赎回规则。

未来新增 Venue 或改变会计语义必须部署新 Vault 并执行显式迁移，不得静默升级现有 shares。

## 11. 安全边界与关键不变量



### 11.1 资产所有权

- Vault 和 Active Adapter 中的支持资产全部归 shares 持有人共同所有。
- Default Admin、Manager、Guardian、Keeper 和 Rebalance Caller 无任意本金转出权限。
- v1 净 LP 手续费全部归 shares 持有人。
- 资产 Donation 不可救援或退款。



### 11.2 Shares 公平性

- Bootstrap 使用初始 TWAP NAV 按一份完整 token1 对应一份完整 share 的名义价格铸造 `grossInitialShares`，锁定份额包含在总铸造量内。
- Deposit 使用存款前 NAV 和总供应量。
- Shares 铸造向下舍入，零 shares 回滚。
- 已有持有人在 Deposit 前已纳入会计的收益不被新用户分享；非活跃 V2 LP 的延迟确认及收益归属遵循 §5.5。
- Redeem 使用销毁前供应量，分别按同一 `x/S` 比例分配退出前 Idle 和退出 Adapter 原生 Position 单位，并以 Adapter 实际返回 Vault 的资产增量形成最终输出；shares 必须从显式 `owner` 销毁，非 owner 调用者必须消费 `allowance(owner, msg.sender)`。



### 11.3 外部调用安全

- Deposit、Redeem、Rebalance 和 Emergency Exit 使用非重入保护。
- `minAmount0Out` 和 `minAmount1Out` 仅用于 `redeem` 的最终双资产交付；`protocolMinOut` 和 `keeperMinAmountOut` 仅用于 `rebalanceWithSwap` 的 Swap；Bootstrap、Deposit、Adapter 资产变更方法和 Emergency Exit 不接受业务层 `minOut` 参数；
- `deadline` 仅用于 `rebalance` 的计划有效期，以及 `rebalanceWithSwap` 和 `ControlledSwapExecutor` 的 Swap 有效期；Bootstrap、Deposit、Redeem、Adapter 资产变更方法和 Emergency Exit 不要求调用者提供 `deadline`；
- 外部调用后重新读取余额、费用和 Position 状态。
- 不支持任意回调、任意 Router 或 Adapter/Executor 对外部合约的无限授权残留；shares 的用户 allowance 按本节 `owner` 规则处理。
- 失败交易不得留下部分 shares、旧 Position 与新 Position 并存或状态/资产不一致。



### 11.4 Oracle 与策略安全

- 单区块 Spot 操纵不直接进入 `deviationBps`，因为该指标由 Oracle 根据 `shortTwapTick` 和 `twapTick` 计算，调用者不能传入或覆盖；
- canonical Pool 同时是唯一 Swap Pool，避免独立成交池与定价池分离；同池约束不消除公开 AMM Swap 的 Sandwich 风险，剩余损失由 Swap 最低输出和迁移 NAV 损失上限约束；
- Observation 不足、报价为零或资产绑定错误时关闭价值相关操作。
- TWAP 只提高操纵成本，不构成绝对安全保证。
- `deviationBps` 不是波动率，也不用于宣称收益最优。
- `lastExecutedPlan` 只在健康策略计划成功执行后更新；其 `marketRegime` 是 Hysteresis 历史，不从 `activeVenue` 或 `lastExecutedPlan.targetVenue` 推导；
- 每次成功的 Position 结构变化必须使 `planVersion` 恰好递增 1，失败交易和非结构变化不得更新。



### 11.5 单活和迁移安全

- 非 IDLE 时最多一个纳入会计的策略主动 Position；非活跃 V2 未确认 LP 遵循 §5.5。
- 普通 Rebalance 不执行 Swap。
- 带 Swap Rebalance 必须受角色、Token、Router、数量、`keeperMinAmountOut` 和 NAV 后置条件共同限制。
- 禁用 Adapter 的现有 Position 仍参与资产计价并可完整或按比例退出，但不得继续增加 liquidity。



## 12. 实现验收清单

实现进入 [DEPLOYMENT.md](DEPLOYMENT.md) 定义的部署流程前，必须通过以下协议行为验收项；部署顺序、外部地址核验、流动性预检、Fork 发布门槛和部署证据不在本节重复定义。

身份与初始化：

- `token0/token1`、canonical Pool、canonical Oracle、Vault 构造时创建的 Swap Executor、所有 Adapter 和绑定 Pool 的有序 Token 一致性已在部署或绑定时验证；`swapExecutor.vault() == address(vault)` 且 `swapExecutor.swapPool() == canonicalOracle.canonicalPool()`；标准 Uniswap 顺序要求 `token0 < token1`；
- 两个支持 Token 的链上 decimals 均不超过 18，且由 Token metadata 派生并缓存，Token metadata 读取失败或超限时相关部署回滚；
- Bootstrap 只能成功一次；
- `deposit`、`redeem`、`rebalance`、`rebalanceWithSwap`、`setPauseState`、`setAdapterEnabled`、`emergencyExitToIdle` 和 `previewRebalance` 在未初始化时均按 §10.3 的检查优先级以 `NotInitialized()` 回滚；
- Bootstrap 的最低 NAV、最低部署率、锁定 shares 和回滚语义完整。

治理与权限：

- `initialDefaultAdmin`、`initialDefaultAdminDelay` 和三个业务角色标识经过测试；
- Default Admin 单账户约束经过测试；
- Default Admin 两阶段延迟转移、取消和接受流程，以及先 `beginDefaultAdminTransfer(address(0))`、等待 `pendingDefaultAdminSchedule < block.timestamp`、再由当前管理员调用 `renounceRole(DEFAULT_ADMIN_ROLE, msg.sender)` 的根管理员放弃流程，均经过测试；直接放弃或延迟未生效时必须以 `AccessControlEnforcedDefaultAdminDelay` 回滚；
- Default Admin 延迟变更流程经过测试；
- 根角色无隐式业务权限的限制经过测试；
- 初始化前治理边界，以及 Guardian 只能收紧暂停和 Adapter 状态的限制，均经过测试。

会计与用户操作：

- Deposit 只提取实际数量，按存款前 NAV 铸造 shares；当前 Active Adapter 禁用时在任何 Adapter 外部调用和 Token 转入前以 `AdapterDisabled()` 回滚，其他健康门控同样有效；
- Redeem 在暂停和 Oracle 异常时仍能按 §5.4 分别计算退出前 Idle 份额与 Adapter 原生 Position 单位份额，以 Adapter 实际返回 Vault 的资产增量形成最终双资产输出，并仅以该最终实际输出校验 `minAmount0Out/minAmount1Out`；持有人自赎不消费 allowance，授权 spender 代赎从显式 `owner` 销毁 shares、消费足额 allowance，并可将双资产发送给指定 `receiver`；余额或 allowance 不足及任一最终最小输出不满足时整笔回滚；
- V2 费用只通过 LP Token 储备权益计价；V2 `PositionSnapshot` 和 IDLE/Bootstrap 的策略 `currentPosition` 分别按 §7.2、§7.4 规范化，并覆盖有效与空 Position 测试；
- V3 principal 与 claimable fees 不重复计价；
- Donation 按 §5.5 的确认时点进入总资产，且不存在支持资产 rescue/sweep 权限；覆盖非活跃 V2 不阻断操作、激活时收益分配及新确认捐赠参与最终部署率、资产守恒和迁移净值检查。

Oracle 与策略：

- `observe([twapWindowSeconds, shortTwapWindowSeconds, 0])` 的调用经过测试；
- 负 Tick 向负无穷取整经过测试；
- `spotPriceToken1`、`twapPriceToken1` 和 `shortTwapPriceToken1` 均以 `10^token0Decimals` 个 token0 raw units 为参考量，返回 token1 raw units，并与对应 Tick 的 `Q1` 向下取整结果一致；`observedAt` 等于快照生成时的 `block.timestamp`；
- `Q1/Q0` 双向报价、统一有序 Token、decimals 和向上/向下取整经过测试；
- `deviationBps` 由 Oracle 内部根据 `shortTwapTick` 和 `twapTick` 生成；
- 未初始化 Preview 以 `NotInitialized()` 回滚；
- Oracle 不健康时，`snapshot()` 不回滚并按 §8.4 返回规范不健康快照；不同失败阶段均不得泄露部分结果或复用上一次健康结果，链上及链下消费者不得从不健康快照生成 Market Regime；Preview 和执行入口均以 `OracleUnhealthy()` 回滚，且不生成占位计划；
- Vault 策略逻辑使用 `planVersion == 0` 识别首次分类；之后使用 `lastExecutedPlan.marketRegime` 作为 Hysteresis 历史；
- `narrowRangeHalfWidthSteps` 和 `wideRangeHalfWidthSteps` 按对应 Pool 的 `tickSpacing` 换算，低费率与高费率 Pool 的 spacing 来源及缓存一致，非法或越界 Range 以 `InvalidTickRange()` 回滚；HIGH/V2 与 EXTREME/IDLE 计划按 §9.1.3 生成规范化 Tick 占位值；
- `planHash` 的字段规范化与架构文档定义的精确 ABI 编码经过链上、链下复算一致性测试；
- Position 结构变化的版本递增和 Range 规则均经过测试。

Rebalance、退出与接口：

- Bootstrap 初始化 `lastPositionChangeAt`，两类 Rebalance 受同一 Cooldown 限制，Emergency Exit 可绕过检查且不重置计时，IDLE 幂等分支和失败交易不更新时间戳；
- 普通 Rebalance 不含 Swap；
- Preview、普通 Rebalance 和 Swap Rebalance 在非 IDLE 目标 Adapter 禁用时均以 `AdapterDisabled()` 回滚，但允许从已禁用的旧 Adapter 迁出；
- Swap Rebalance 仅限 Keeper/Manager，且全部后置条件原子校验；
- 紧急退出不执行 Swap，并能在 Oracle 不健康时清空 Active Position、进入 IDLE；已在 IDLE 时调用不访问 Adapter、不改变 Position 版本或历史计划，重复调用只在需要时收紧暂停位；
- 关键事件、错误和状态查询满足 [ARCHITECTURE.md](ARCHITECTURE.md) 的接口契约。



## 13. 版本边界

本文档只描述 v1。多 Venue 权重、单资产 Wrapper、其他 DEX Adapter、历史费率 Checkpoint、Keeper 激励、Timelock 和可升级迁移属于后续版本，不能在 v1 实现中隐式加入。