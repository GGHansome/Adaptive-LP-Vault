# Adaptive LP Vault 架构文档

- 文档版本：1.0
- 文档状态：实现规范
- 实现基线：Foundry + Solidity
- 对应产品文档：[PRODUCT_SPEC.md](PRODUCT_SPEC.md)
- 代码状态：本文档中的目录、接口和类型为待实现设计，不表示仓库已有合约代码

本文档定义合约边界、依赖方向、存储模型、接口、错误、事件、调用时序和测试要求。产品规则以 [PRODUCT_SPEC.md](PRODUCT_SPEC.md) 为准；两份文档中的名称必须保持一致。

## 1. 架构原则

1. `AdaptiveLPVault` 是唯一资产编排入口，负责权限、状态机、资产转移和跨模块原子性。
2. `VaultAccounting` 是无状态数学模块，不持有资产、不调用外部合约、不决定策略。
3. `CanonicalV3Oracle` 是部署时绑定的唯一价格来源；`deviationBps` 在 Oracle 内部产生，不从调用者输入。
4. `MarketRegimeStrategy` 只读链上快照并确定性生成 `PositionPlan`，不转移资产、不调用 AMM。
5. `IPositionAdapter` 隔离 Uniswap V2/V3 细节，Adapter 不能铸造或销毁 shares。
6. `ControlledSwapExecutor` 不是通用交易聚合器，只能按 Vault 验证过的 `SwapPlan` 执行 token0/token1 交换。
7. Registry 的遍历不是资产会计路径。Vault 只读取 `activeVenue` 对应 Adapter，保证 Gas 有界。
8. 所有资产迁移入口采用 Checks-Effects-Interactions、非重入保护和外部调用后的状态重读。

## 2. 系统边界

```mermaid
flowchart TB
    subgraph Actors
        LP[LP 用户]
        Caller[Permissionless Caller]
        Keeper[Keeper]
        Guardian[Guardian]
        DefaultAdmin[Default Admin]
        Manager[Manager]
    end

    subgraph Protocol[Adaptive LP Vault Protocol]
        Vault[AdaptiveLPVault]
        Accounting[VaultAccounting]
        Oracle[CanonicalV3Oracle]
        Strategy[MarketRegimeStrategy]
        Swap[ControlledSwapExecutor]
        V2Adapter[UniswapV2Adapter]
        V3Adapter[UniswapV3Adapter]
    end

    subgraph External[外部协议]
        V2Pair[Uniswap V2 Pair]
        V3Pool[Canonical Uniswap V3 Pool]
        V3Venue[Target Uniswap V3 Pool]
        PositionManager[NonfungiblePositionManager]
        Router[Approved Swap Router]
        ERC20[WETH / USDC ERC20]
    end

    LP --> Vault
    Caller --> Vault
    Keeper --> Vault
    Guardian --> Vault
    DefaultAdmin --> Vault
    Manager --> Vault
    Vault --> Accounting
    Vault --> Oracle
    Vault --> Strategy
    Vault --> Swap
    Vault --> V2Adapter
    Vault --> V3Adapter
    V2Adapter --> V2Pair
    V3Adapter --> V3Venue
    V3Adapter --> PositionManager
    Oracle --> V3Pool
    Swap --> Router
    Vault --> ERC20
```

### 2.1 依赖方向

允许的依赖方向如下：

```mermaid
flowchart LR
    Core[core] --> Interfaces[interfaces]
    Core --> Accounting[accounting]
    Core --> Oracle[oracle]
    Core --> Strategy[strategy]
    Core --> Adapters[adapters]
    Core --> Swap[swap]
    Accounting --> Libraries[libraries]
    Oracle --> Libraries
    Strategy --> Interfaces
    Adapters --> Interfaces
    Adapters --> Libraries
    Swap --> Interfaces
    Interfaces --> ExternalInterfaces[外部协议接口]
```

禁止以下依赖：

- Accounting 依赖 Vault 存储、Adapter 具体实现或外部调用；
- Strategy 依赖 msg.sender、Keeper 参数或任意 Router；
- Adapter 直接铸造/销毁 shares 或修改 Vault 的策略状态；
- Oracle 读取目标 Venue 作为价格来源；
- Swap Executor 修改 `activeVenue`、shares 供应量或策略参数。

## 3. Foundry 项目目录

以下目录是规划中的实现结构，当前仓库未实现这些 Solidity 文件。

```text
AdaptiveLPVault/
├── foundry.toml
├── remappings.txt
├── src/
│   ├── core/
│   │   ├── AdaptiveLPVault.sol
│   │   ├── VaultRoles.sol
│   │   └── VaultPause.sol
│   ├── accounting/
│   │   ├── VaultAccounting.sol
│   │   └── AccountingTypes.sol
│   ├── oracle/
│   │   ├── CanonicalV3Oracle.sol
│   │   └── OracleTypes.sol
│   ├── strategy/
│   │   ├── MarketRegimeStrategy.sol
│   │   └── StrategyTypes.sol
│   ├── adapters/
│   │   ├── AdapterRegistry.sol
│   │   ├── UniswapV2Adapter.sol
│   │   ├── UniswapV3Adapter.sol
│   │   └── AdapterTypes.sol
│   ├── swap/
│   │   ├── ControlledSwapExecutor.sol
│   │   └── SwapTypes.sol
│   ├── interfaces/
│   │   ├── IAdaptiveLPVault.sol
│   │   ├── IVaultAccounting.sol
│   │   ├── ICanonicalV3Oracle.sol
│   │   ├── IMarketRegimeStrategy.sol
│   │   ├── IPositionAdapter.sol
│   │   ├── IAdapterRegistry.sol
│   │   ├── IControlledSwapExecutor.sol
│   │   ├── IUniswapV2External.sol
│   │   └── IUniswapV3External.sol
│   └── libraries/
│       ├── PriceMath.sol
│       ├── PositionPlanHash.sol
│       ├── SafeTransferLib.sol
│       └── ValidationLib.sol
├── test/
│   ├── unit/
│   │   ├── VaultAccounting.t.sol
│   │   ├── CanonicalV3Oracle.t.sol
│   │   ├── MarketRegimeStrategy.t.sol
│   │   ├── UniswapV2Adapter.t.sol
│   │   ├── UniswapV3Adapter.t.sol
│   │   └── ControlledSwapExecutor.t.sol
│   ├── integration/
│   │   ├── DepositRedeem.t.sol
│   │   └── Rebalance.t.sol
│   ├── invariant/
│   │   ├── VaultInvariants.t.sol
│   │   └── AccountingInvariants.t.sol
│   ├── fork/
│   │   ├── MainnetOracle.t.sol
│   │   └── MainnetUniswapFlows.t.sol
│   ├── mocks/
│   └── helpers/
├── script/
│   ├── Deploy.s.sol
│   ├── Configure.s.sol
│   └── Bootstrap.s.sol
├── lib/
├── docs/
│   ├── PRODUCT_SPEC.md
│   └── ARCHITECTURE.md
└── README.md
```

目录职责：


| 目录                 | 职责                                  | 约束                                                                                            |
| ------------------ | ----------------------------------- | --------------------------------------------------------------------------------------------- |
| `src/core`         | Vault 入口、角色、暂停和状态机                  | 唯一资产编排层                                                                                       |
| `src/accounting`   | NAV、shares、比例、Idle 和损失计算            | 无状态、无外部调用                                                                                     |
| `src/oracle`       | Uniswap V3 `observe`、报价和健康检查        | 不接受外部价格输入                                                                                     |
| `src/strategy`     | Market Regime、Hysteresis、Range 和计划  | 只读、确定性                                                                                        |
| `src/adapters`     | Registry 及 V2/V3 Venue 适配           | 只能由 Vault 调用资产方法                                                                              |
| `src/swap`         | 白名单 Router 和受限 Swap                 | 不得成为通用聚合器                                                                                     |
| `src/interfaces`   | 内外部协议契约                             | 不包含实现状态                                                                                       |
| `src/libraries`    | 全精度数学、哈希和安全转账                       | 不保存协议状态                                                                                       |
| `test/unit`        | 单模块行为                               | Mock 外部依赖                                                                                     |
| `test/integration` | 跨模块完整流程                             | 覆盖原子回滚                                                                                        |
| `test/invariant`   | 不变量和模糊测试                            | 覆盖资产、shares、单活 Position                                                                       |
| `test/fork`        | Mainnet/Fork 外部协议行为                 | 验证真实 V2/V3 接口                                                                                 |
| `script`           | 分阶段部署、角色指派、Adapter 绑定和一次性 Bootstrap | 数值参数仅由 Deploy 写入；主网按 Deploy → Grant Roles → Configure → Bootstrap 执行，`bootstrap()` 内部执行最终绑定校验 |
| `docs`             | 发布后的文档副本                            | 以根目录规范为源                                                                                      |




## 4. 核心类型与枚举

以下为 Solidity 类型契约的规范形状。字段名、顺序和语义不得在实现中无记录变更。

### 4.1 枚举

```solidity
enum VenueType {
    IDLE,
    UNISWAP_V2,
    UNISWAP_V3_LOW_FEE,
    UNISWAP_V3_HIGH_FEE
}

enum MarketRegime {
    LOW_DEVIATION,
    MEDIUM_DEVIATION,
    HIGH_DEVIATION,
    EXTREME_DEVIATION
}

enum PauseFlag {
    DEPOSIT,
    PLAIN_REBALANCE,
    SWAP_REBALANCE
}

enum SwapDirection {
    NONE,
    ZERO_FOR_ONE,
    ONE_FOR_ZERO
}
```

`VenueType` 描述资产位置，`MarketRegime` 描述Strategy 市场状态，Oracle 健康性由 `OracleSnapshot.healthy` 独立表达；`PauseFlag` 描述暂停入口。`SwapDirection.NONE` 表示不需要 Swap，`ZERO_FOR_ONE` 表示 token0 → token1，`ONE_FOR_ZERO` 表示 token1 → token0。

### 4.2 部署配置类型

```solidity
struct VaultConfig {
    address token0;
    address token1;
    uint8 token0Decimals;
    uint8 token1Decimals;
    uint256 dustTolerance0;
    uint256 dustTolerance1;
    address canonicalOracle;
    address swapExecutor;
    uint256 minimumLockedShares;
    uint256 minimumInitialNav;
}

struct AccessControlConfig {
    uint48 initialDefaultAdminDelay;
    address initialDefaultAdmin;
}

struct OracleConfig {
    address token0;
    address token1;
    address canonicalPool;
    uint32 twapWindowSeconds;
    uint32 shortTwapWindowSeconds;
}

struct StrategyConfig {
    uint32 minRebalanceCooldown;
    uint24 enterMediumBps;
    uint24 exitMediumBps;
    uint24 enterHighBps;
    uint24 exitHighBps;
    uint24 enterExtremeBps;
    uint24 exitExtremeBps;
    uint24 narrowRangeHalfWidthSteps;
    uint24 wideRangeHalfWidthSteps;
    uint16 minRecenterBps;
    uint16 maxHealthyIdleBps;
    uint16 maxSwapSlippageBps;
    uint16 maxMigrationLossBps;
}
```

`VaultConfig`、`OracleConfig` 和 `StrategyConfig` 仅作为构造参数与内存传参结构，不作为整体状态变量写入普通 storage。各字段在部署时通过协议硬边界与字段关系校验后，分别写入所属合约的 Solidity `immutable` 状态变量；部署后任何角色均不得修改。

`VaultConfig.token0Decimals/token1Decimals` 必须分别等于两个固定 Token 的 `IERC20Metadata.decimals()` 返回值，且两者均不得大于 18；不一致或超限时以 `InvalidTokenDecimals(token, configured, actual)` 拒绝部署。

`OracleConfig.token0/token1` 使用 Vault 的 Token 顺序；`canonicalPool` 的内部 Token 与对应 Uniswap 顺序可以不同，但其资产对必须与这两个地址一致。

`AccessControlConfig` 仅作为 Vault 构造参数传入 OpenZeppelin Contracts v5 `AccessControlDefaultAdminRules`。`initialDefaultAdmin` 必须非零；`initialDefaultAdminDelay` 是根管理员转移的初始等待时间，应在部署前校准，Mainnet 部署应采用非零值。

### 4.3 Oracle 与资产快照

```solidity
struct OracleSnapshot {
    int24 spotTick;
    int24 twapTick;
    int24 shortTwapTick;
    uint256 spotPriceToken1;
    uint256 twapPriceToken1;
    uint256 shortTwapPriceToken1;
    uint256 deviationBps;
    uint32 twapWindowSeconds;
    uint32 shortTwapWindowSeconds;
    uint32 observedAt;
    bool healthy;
}

struct AssetSnapshot {
    uint256 idle0;
    uint256 idle1;
    uint256 position0;
    uint256 position1;
    uint256 total0;
    uint256 total1;
    uint256 nav1;
    uint256 idleValue1;
    uint256 idleBps;
    uint256 totalShares;
}

struct PositionSnapshot {
    VenueType venue;
    address adapter;
    uint256 principal0;
    uint256 principal1;
    uint256 claimableFee0;
    uint256 claimableFee1;
    uint256 amount0;
    uint256 amount1;
    uint256 liquidity;
    uint256 positionId;
    int24 tickLower;
    int24 tickUpper;
}
```

`amount0/amount1` 必须等于 `principal + claimableFee` 的唯一会计结果。费用归集后，Adapter 必须重新读取并返回新的快照。

### 4.4 Position Plan、Assess Deployment 与 Swap Plan

```solidity
struct PositionPlan {
    bytes32 planHash;
    VenueType targetVenue;
    MarketRegime marketRegime;
    int24 tickLower;
    int24 tickUpper;
    uint64 version;
}

struct DeploymentAssessment {
    bool requiresSwap;
    uint256 used0;
    uint256 used1;
    SwapDirection direction;
}

struct SwapPlan {
    bytes32 planHash;
    SwapDirection direction;
    uint256 amountIn;
    uint256 minAmountOut;
    uint32 deadline;
}

struct V3RangeContext {
    int24 lowFeeTickSpacing;
    int24 highFeeTickSpacing;
}
```

- `V3RangeContext` 由 Vault 根据 `_adapterByVenue` 的 spacing 缓存构造，只作为 Strategy 调用的运行时上下文，不属于部署策略参数。
- `planHash` 覆盖 `targetVenue`、`marketRegime`、`tickLower`、`tickUpper` 和 `version`。
- `DeploymentAssessment` 是 Vault 根据当前资产和目标 Adapter 生成的临时内存结果，不写入 `lastExecutedPlan` storage。
- `SwapPlan` 是 Vault 在执行入口内构造、仅传给 `ControlledSwapExecutor` 的交易级对象，不是调用者可自由提交的完整目标结构。
- `deadline` 由调用入口独立校验；调用者不能传入任意目标字段、Router、实际方向或 calldata。

### 4.5 运行时控制状态

```solidity
struct PauseState {
    bool depositPaused;
    bool plainRebalancePaused;
    bool swapRebalancePaused;
}
```

`PauseState` 归属于 `AdaptiveLPVault` 的运行时控制状态，由 `VaultPause` 逻辑读写并以普通 storage 保存。

### 4.6 Registry 绑定类型

```solidity
struct AdapterConfig {
    VenueType venue;
    address adapter;
    int24 tickSpacing;
    bool enabled;
}
```

`AdapterConfig` 归属于 Vault 继承的 `AdapterRegistry`，是 `_adapterByVenue` Mapping 的值类型。`venue` 必须与 Mapping Key 一致；`tickSpacing` 是配置时从 Adapter 绑定读取并验证后写入的缓存，V2 Venue 固定为零。Bootstrap 成功后 Adapter 身份字段和 spacing 缓存冻结，只有 `enabled` 可以继续修改。

## 5. 存储归属与状态转换

### 5.1 Vault 存储

`AdaptiveLPVault` 至少保存：


| 存储项                                             | 类型             | 存储方式        | 写入时机                               | 约束                                                 |
| ----------------------------------------------- | -------------- | ----------- | ---------------------------------- | -------------------------------------------------- |
| `token0/token1`                                 | `address`      | `immutable` | 构造                                 | 固定资产对和顺序；部署后不可修改                                   |
| `token0Decimals/token1Decimals`                 | `uint8`        | `immutable` | 构造                                 | 分别等于固定 Token 的 `decimals()` 且不超过 18；部署后不可修改               |
| `dustTolerance0/dustTolerance1`                 | `uint256`      | `immutable` | 构造                                 | 仅用于整数舍入和最小单位容忍；部署后不可修改                             |
| `canonicalOracle`                               | `address`      | `immutable` | 构造                                 | 固定 `CanonicalV3Oracle` 合约；部署后不可替换                  |
| `swapExecutor`                                  | `address`      | `immutable` | 构造                                 | 固定 `ControlledSwapExecutor` 合约；部署后不可替换             |
| `minimumLockedShares`                           | `uint256`      | `immutable` | 构造                                 | Bootstrap 时铸造给 Vault 自身，永久锁定                       |
| `minimumInitialNav`                             | `uint256`      | `immutable` | 构造                                 | Bootstrap 最低 NAV；调用者不能覆盖                           |
| `minRebalanceCooldown`                          | `uint32`       | `immutable` | 构造                                 | 单位为秒；部署时校验，部署后不可修改                                  |
| `enterMediumBps/exitMediumBps`                  | `uint24`       | `immutable` | 构造                                 | 满足完整 Hysteresis 阈值关系；部署后不可修改                       |
| `enterHighBps/exitHighBps`                      | `uint24`       | `immutable` | 构造                                 | 满足完整 Hysteresis 阈值关系；部署后不可修改                       |
| `enterExtremeBps/exitExtremeBps`                | `uint24`       | `immutable` | 构造                                 | 满足完整 Hysteresis 阈值关系；部署后不可修改                       |
| `narrowRangeHalfWidthSteps/wideRangeHalfWidthSteps` | `uint24`        | `immutable` | 构造                                 | spacing 步数；部署后不可修改                           |
| `minRecenterBps/maxHealthyIdleBps`                | `uint16`       | `immutable` | 构造                                 | `maxHealthyIdleBps <= BPS`；`minDeployBps` 由 `BPS - maxHealthyIdleBps` 派生储                                |
| `maxSwapSlippageBps/maxMigrationLossBps`        | `uint16`       | `immutable` | 构造                                 | 不超过协议硬上限；部署后不可修改                                   |
| `initialized`                                   | `bool`         | `storage`   | Bootstrap 成功                       | 只能从 false 到 true                                   |
| `activeVenue`                                   | `VenueType`    | `storage`   | Bootstrap/Rebalance/Emergency Exit | 与有效 Position 一致                                    |
| `activeAdapter`                                 | `address`      | `storage`   | Bootstrap/Rebalance                | 必须来自 Bootstrap 成功后已冻结的 Registry 绑定                 |
| `lastPositionChangeAt`                           | `uint32`       | `storage`   | Bootstrap、两类 Rebalance 成功 | 初始为 0；两类 Rebalance 共用其 Cooldown；Emergency Exit 跳过检查且不更新；失败交易和 IDLE 幂等分支不更新 |
| `planVersion`                                   | `uint64`       | `storage`   | 成功 Position 结构变化                   | 初始为 0；每次成功变化递增 1，失败交易不更新                           |
| `lastExecutedPlan`                              | `PositionPlan` | `storage`   | Bootstrap/成功策略计划执行                 | 保存最近一次成功执行的 Strategy 计划；其 `marketRegime` 是 Hysteresis 历史，非策略 Position 变化后可与当前资产位置不同 |
| `pauseState`                                    | `PauseState`   | `storage`   | `setPauseState` 或 Emergency Exit   | 初始为全 false；Redeem 不受影响                             |


Vault 不保存由 Registry 遍历产生的冗余资产总额。`totalAssets()` 每次读取 Idle 余额和当前 Active Adapter 快照，并调用 Accounting 计算。

### 5.2 Oracle 配置存储

`CanonicalV3Oracle` 是独立部署的 Oracle 合约：


| 存储项                      | 类型       | 存储方式        | 写入时机      | 约束                                                       |
| ------------------------ | -------- | ----------- | --------- | -------------------------------------------------------- |
| `canonicalPool`          | `address` | `immutable` | Oracle 构造 | 固定 canonical Uniswap V3 Pool；部署后不可替换                      |
| `token0/token1`          | `address` | `immutable` | Oracle 构造 | 与 Vault 的 immutable Token 地址及顺序一致；两者必须组成 canonical Pool 资产对 |
| `twapWindowSeconds`      | `uint32` | `immutable` | Oracle 构造 | 大于零且不超过协议硬上限；部署后不可修改                                     |
| `shortTwapWindowSeconds` | `uint32` | `immutable` | Oracle 构造 | `0 < shortTwapWindowSeconds < twapWindowSeconds`；部署后不可修改 |


Oracle 在构造时完成 canonical Pool、Vault Token 顺序、窗口关系和协议硬边界校验。实现可以使用独立的 `immutable` 字段承载，而不要求把整个 `OracleConfig` 结构体写入普通 storage。

### 5.3 Registry 存储

`AdapterRegistry` 是 `AdaptiveLPVault` 继承的内部存储与校验模块。


| 存储项               | 类型                                    | 存储方式                 | 写入时机                                                             | 约束                               |
| ----------------- | ------------------------------------- | -------------------- | ---------------------------------------------------------------- | -------------------------------- |
| `_adapterByVenue` | `mapping(VenueType => AdapterConfig)` | 普通 `storage` Mapping | `configureAdapter` 写入 Adapter 地址和经过验证的 `tickSpacing` 并将 `enabled` 设为 true；Bootstrap 后 `setAdapterEnabled` 仅修改 `enabled` | Key 只允许三个非 IDLE Venue；不得用于遍历资产会计 |


`adapter == address(0)` 表示该 Venue 未注册。`IDLE` 不是 Adapter，`_adapterByVenue[IDLE]` 必须保持零值，`getAdapter(IDLE)` 返回 `address(0)`，`isEnterEnabled(IDLE)` 返回 `false`。`isEnterEnabled(venue)` 仅按 `adapter != address(0) && enabled` 派生 Registry 层结果；其他入口门控由 Vault 负责。`tickSpacing` 是经过验证的 Strategy 读取缓存；

### 5.4 Adapter 合约存储

`UniswapV2Adapter` 和 `UniswapV3Adapter` 是独立部署的 Adapter 合约；每个 Adapter 至少保存以下不可变绑定字段：


| 存储项             | 类型          | 存储方式        | 写入时机       | 约束                                   |
| --------------- | ----------- | ----------- | ---------- | ------------------------------------ |
| `vault`         | `address`   | `immutable` | Adapter 构造 | 只有该 Vault 可以调用资产变更方法；部署后不可替换         |
| `venue`         | `VenueType` | `immutable` | Adapter 构造 | 必须与 Adapter 实现及 Registry 注册 Venue 一致 |
| `pool`          | `address`   | `immutable` | Adapter 构造 | 固定绑定的 V2 Pair 或 V3 Pool；部署后不可替换      |
| `token0/token1` | `address`   | `immutable` | Adapter 构造 | 必须与 Vault 固定资产及顺序一致；部署后不可替换          |
| `feeTier`       | `uint24`    | `immutable` | Adapter 构造 | V3 必须与 Pool Fee Tier 一致；V2 固定为零      |
| `tickSpacing`   | `int24`     | `immutable` | Adapter 构造 | V3 必须与 Pool `tickSpacing()` 一致；V2 固定为零 |


V3 Adapter 还保存：


| 存储项               | 类型        | 存储方式        | 写入时机              | 约束                                              |
| ----------------- | --------- | ----------- | ----------------- | ----------------------------------------------- |
| `positionManager` | `address` | `immutable` | Adapter 构造        | 固定的 NonfungiblePositionManager；部署后不可替换          |
| `positionId`      | `uint256` | `storage`   | 创建 Position 或完整退出 | 无有效 NFT Position 时为零；同一 Adapter 最多一个有效 Position |




### 5.6 ControlledSwapExecutor 合约存储

`ControlledSwapExecutor` 是独立部署的 Swap 执行合约；其固定依赖和调用权限不属于 Vault 或 Registry 的存储。Executor 至少保存以下部署时固定的绑定字段：


| 存储项             | 类型                     | 存储方式        | 写入时机        | 约束                                     |
| --------------- | ---------------------- | ----------- | ----------- | -------------------------------------- |
| `vault`         | `address`              | `immutable` | Executor 构造 | 只有该 Vault 可以调用 `executeSwap()`；部署后不可替换 |
| `router`        | `address`              | `immutable` | Executor 构造 | 固定白名单 Router；部署后不可替换                   |
| `token0/token1` | `address`              | `immutable` | Executor 构造 | 只能交换 Vault 固定的资产对；部署后不可替换              |
| `swapPool`      | `address`              | `immutable` | Executor 构造 | 固定批准使用的 Swap Pool；部署后不可替换              |
| `feeTier`       | `uint24`               | `immutable` | Executor 构造 | 必须与 `swapPool` 的 Fee Tier 一致；部署后不可替换   |
| `swapMethod`    | 固定代码逻辑或 `immutable` 枚举 | 部署时固定       | Executor 构造 | 仅允许 v1 规定的 exact-input、single-hop 方法   |


Executor 不存储独立的 Swap recipient 或持久 Router allowance；

### 5.7 状态转换约束

Vault 的生命周期、资产位置和运行时控制彼此独立。

生命周期仅由 `initialized` 表达：

```mermaid
stateDiagram-v2
    [*] --> UNINITIALIZED
    UNINITIALIZED --> OPEN: bootstrap() succeeds
```

已初始化 Vault 的资产位置仍由 `activeVenue` 表达：

```mermaid
stateDiagram-v2
    [*] --> IDLE: bootstrap() with EXTREME plan
    [*] --> ACTIVE: bootstrap() with healthy plan and no-swap assessment
    ACTIVE --> ACTIVE: recenter or migrate
    ACTIVE --> IDLE: extreme plan or emergency exit
    IDLE --> ACTIVE: valid non-IDLE plan
```

`PAUSED` 不是生命周期或资产位置。暂停开关、Adapter 进入状态、Oracle 健康状态、当前资产位置和 `lastExecutedPlan.marketRegime` 表示的 Hysteresis 历史彼此独立；单独改变这些运行时控制不得触发生命周期或资产位置转换。
## 6. 接口契约



### 6.1 Vault 接口

```solidity
interface IAdaptiveLPVault is IAccessControlDefaultAdminRules, IAdapterRegistry {
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function MANAGER_ROLE() external view returns (bytes32);
    function KEEPER_ROLE() external view returns (bytes32);
    function GUARDIAN_ROLE() external view returns (bytes32);

    function bootstrap(uint256 amount0, uint256 amount1, address receiver) external;

    function deposit(
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 minSharesOut,
        address receiver
    ) external returns (uint256 amount0Used, uint256 amount1Used, uint256 sharesMinted);

    function redeem(
        uint256 shares,
        uint256 minAmount0Out,
        uint256 minAmount1Out,
        address receiver,
        address owner
    ) external returns (uint256 amount0Out, uint256 amount1Out);

    function rebalance(bytes32 expectedPlanHash, uint32 deadline) external;

    function rebalanceWithSwap(
        bytes32 expectedPlanHash,
        SwapDirection expectedDirection,
        uint256 amountIn,
        uint256 keeperMinAmountOut,
        uint32 deadline
    ) external;

    function setPauseState(PauseState calldata newState) external;
    function emergencyExitToIdle() external;

    function previewRebalance()
        external
        view
        returns (PositionPlan memory plan, DeploymentAssessment memory assessment);

    function totalAssets() external view returns (uint256 total0, uint256 total1);
    function assetSnapshot() external view returns (AssetSnapshot memory);
    function lastExecutedPlan() external view returns (PositionPlan memory);
    function pauseState() external view returns (PauseState memory);
}
```

`_assessDeployment` 是 Vault 内部只读函数，不属于 `IAdaptiveLPVault` ABI：

```solidity
function _assessDeployment(
    PositionPlan memory plan,
    uint256 amount0,
    uint256 amount1,
    int24 twapTick
) internal view returns (DeploymentAssessment memory assessment);
```

### 6.2 Oracle 接口

```solidity
interface ICanonicalV3Oracle {
    function snapshot() external view returns (OracleSnapshot memory);
    function quoteToken0InToken1(uint256 amount0, int24 tick, bool roundUp)
        external
        view
        returns (uint256 amount1);
    function quoteToken1InToken0(uint256 amount1, int24 tick, bool roundUp)
        external
        view
        returns (uint256 amount0);
    function isHealthy() external view returns (bool);
    function canonicalPool() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
}
```

Oracle 架构边界：

- `snapshot()` 只从部署时绑定的 canonical Pool 读取数据；不得使用目标 Venue 或调用者提供的替代价格；
- `quoteToken0InToken1()` 和 `quoteToken1InToken0()` 使用固定的 Vault Token 顺序和全精度数学；`roundUp == false` 时向下取整，`roundUp == true` 时向上取整；
- Oracle 负责输出 `OracleSnapshot` 和健康状态，不负责决定策略状态或目标 Venue；

### 6.3 Strategy 接口

```solidity
interface IMarketRegimeStrategy {
    function getPlan(
        OracleSnapshot calldata oracle,
        AssetSnapshot calldata assets,
        PositionSnapshot calldata currentPosition,
        VenueType currentVenue,
        MarketRegime lastCommittedRegime,
        StrategyConfig calldata config,
        V3RangeContext calldata rangeContext,
        uint64 currentVersion
    ) external view returns (PositionPlan memory);
}
```

Strategy 架构边界：

- Strategy 是只读、确定性的计划生成模块，只接收调用者提供的快照、部署时固定的策略配置和已验证的 V3 spacing 上下文；
- `rangeContext` 由 Vault 从 `_adapterByVenue` 的 spacing 缓存构造，Strategy 不读取 Registry 或目标 Pool；
- Vault 在执行前必须重新读取 Oracle、资产和 Position 快照，并传入当前 `planVersion`；`planVersion == 0` 时传入并忽略 `lastCommittedRegime` 参数的默认值，`planVersion > 0` 时将 `lastExecutedPlan.marketRegime` 作为该参数传入；调用者不能提交完整的目标计划替代 Strategy 结果；
- Strategy 只生成 `PositionPlan`，不转移资产、不调用 Router、不修改 Vault 状态；

### 6.4 Adapter 接口

```solidity
interface IPositionAdapter {
    function vault() external view returns (address);
    function venue() external view returns (VenueType);
    function pool() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function feeTier() external view returns (uint24);
    function tickSpacing() external view returns (int24);
    function snapshot() external view returns (PositionSnapshot memory);
    function syncFees() external returns (uint256 fee0, uint256 fee1);
    function previewDeposit(uint256 amount0Max, uint256 amount1Max, PositionPlan calldata plan)
        external
        view
        returns (uint256 used0, uint256 used1);
    function deposit(uint256 amount0Max, uint256 amount1Max, PositionPlan calldata plan)
        external
        returns (uint256 used0, uint256 used1, uint256 liquidity);
    function withdraw(uint256 shares, uint256 totalShares)
        external
        returns (uint256 amount0, uint256 amount1);
    function withdrawAll() external returns (uint256 amount0, uint256 amount1);
}
```

Adapter 架构边界：

- `vault()`、`venue()`、`pool()`、`token0()`、`token1()`、`feeTier()` 和 `tickSpacing()` 返回 Adapter 部署时固定的绑定信息；V2 Adapter 的 `feeTier()` 和 `tickSpacing()` 固定返回零；
- 所有资产变更方法只接受 Vault 调用；Adapter 不铸造或销毁 shares，也不修改 Vault 的策略状态；
- `previewDeposit()` 必须只读，并与真实 `deposit()` 使用一致的底层 AMM 计算路径；Deposit 比例使用当前 Position Snapshot 的 `principal0/principal1`，`amount0Max/amount1Max` 是使用上限，返回的 `used0/used1` 是实际使用数量；
- Vault 仅可在非 IDLE 目标满足 `isEnterEnabled(targetVenue) == true` 后调用 `previewDeposit()` 或 `deposit()`；用户 Deposit 使用当前 `activeVenue` 作为目标；
- `snapshot()` 返回完整的 Position 资产快照，费用和本金不得在同一会计路径中重复计价；
- `snapshot()`、`syncFees()`、`withdraw()` 和 `withdrawAll()` 不受 Adapter `enabled` 限制，并必须继续支持已禁用 Active Adapter 的计价和退出；`withdraw()` 和 `withdrawAll()` 必须将资产返回 Vault 控制的地址；

### 6.5 Registry 接口

```solidity
interface IAdapterRegistry {
    function configureAdapter(
        VenueType venue,
        address adapter
    ) external;

    function getAdapter(VenueType venue) external view returns (address adapter);
    function getConfig(VenueType venue) external view returns (AdapterConfig memory);
    function isEnterEnabled(VenueType venue) external view returns (bool);
    function setAdapterEnabled(VenueType venue, bool enabled) external;
}
```

`IAdapterRegistry` 由 `AdaptiveLPVault` 在 Vault 同一地址上实现，不代表独立部署合约。

Registry 架构边界：

- `configureAdapter()` 只接受已独立部署的 Adapter 地址；Vault 从 Adapter 读取绑定信息并完成校验，再写入 Adapter 地址、`tickSpacing` 缓存和 `enabled = true`；
- `configureAdapter()` 仅在 Bootstrap 前开放并可重复调用；该方法不部署 Adapter、不转移资产、不创建 Position；
- Bootstrap 成功时重新验证 Adapter 的 immutable 绑定与 Registry 的 `tickSpacing` 缓存并冻结身份字段；此后 `setAdapterEnabled()` 只能修改 `enabled`；

### 6.6 Swap Executor 接口

```solidity
interface IControlledSwapExecutor {
    function executeSwap(SwapPlan calldata plan)
        external
        returns (uint256 amountOut);

    function router() external view returns (address);
    function vault() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swapPool() external view returns (address);
    function feeTier() external view returns (uint24);
}
```

ControlledSwapExecutor 架构边界：

- `vault`、Router、token0/token1、`swapPool`、Fee Tier 和固定 Swap 方法在部署或不可变初始化时固定，Bootstrap 后不能由 Keeper/Manager 替换；
- Executor 只接受 Vault 调用，只执行 `SwapPlan` 指定的交易级参数和局部 Swap 安全检查；
- Executor 不调用 Strategy，不退出或建立 Position，也不负责完整迁移损失、部署率、Idle 或单活 Position 的后置校验；这些检查由 Vault 负责；



## 7. 错误契约

错误使用 custom error，Vault 自定义错误名和触发语义固定如下；继承自 OpenZeppelin `IAccessControl`、`IAccessControlDefaultAdminRules` 和 shares ERC-20 的标准错误不在此重复声明：

```solidity
error AlreadyInitialized();
error NotInitialized();
error GuardianCannotUnpause();
error Paused(PauseFlag flag);
error OracleUnhealthy();
error ObservationInsufficient();
error InvalidAssetPair();
error InvalidTokenDecimals(address token, uint8 configured, uint8 actual);
error MinimumNavNotMet();
error ZeroAmount();
error ActivePositionSingleSided();
error SharesSlippage(uint256 actual, uint256 minimum);
error AssetSlippage(uint256 amount0, uint256 amount1);
error InvalidPlanHash();
error InvalidSwapDirection();
error InvalidTickSpacing();
error InvalidTickRange();
error DeadlineExpired();
error NoStateChangeRequired();
error CooldownActive(uint256 availableAt);
error SwapRequired();
error SwapNotAllowed();
error RouterNotAllowed();
error TokenNotAllowed();
error SwapAmountExceeded();
error SwapSlippage();
error MigrationLossExceeded();
error IdleLimitExceeded();
error DeploymentRatioTooLow();
error ActivePositionExists();
error PositionNotCleared();
error AdapterNotRegistered();
error AdapterDisabled();
error NotVaultCaller();
error UnsupportedToken();
error Reentrancy();
```

错误参数只能包含帮助调用者修正请求所需的信息，不得泄露可被用来绕过权限或安全限制的内部假设。`InvalidTokenDecimals(token, configured, actual)` 用于 Vault 构造时任一 Token 的配置 decimals 与 `IERC20Metadata.decimals()` 返回值不一致，或链上返回值大于 18。角色授权和 `renounceRole` 调用者确认失败分别采用 OpenZeppelin `IAccessControl` 的 `AccessControlUnauthorizedAccount` 与 `AccessControlBadConfirmation`。`redeem` 在 `owner` shares 余额不足或代赎 allowance 不足时，分别采用 OpenZeppelin `IERC20Errors` 的 `ERC20InsufficientBalance` 与 `ERC20InsufficientAllowance` 标准语义；持有人自赎不检查 allowance。`AccessControlInvalidDefaultAdmin`、`AccessControlEnforcedDefaultAdminRules` 和 `AccessControlEnforcedDefaultAdminDelay` 直接采用 `IAccessControlDefaultAdminRules` 的标准语义，用于非法根管理员、绕过单一根管理员/两阶段规则以及尚未满足延迟的操作；Vault 不定义额外的最后管理员错误或自定义根管理员计数错误。`GuardianCannotUnpause()` 用于 Guardian 尝试把任一暂停位从 true 改为 false。`NotInitialized()` 用于要求已初始化状态的入口，包括 `setPauseState`、`setAdapterEnabled`、Emergency Exit 和未初始化 Vault 上的 `previewRebalance()`；该检查必须早于这些入口的业务状态读取。`OracleUnhealthy()` 用于 Bootstrap、Deposit、Preview 和两类 Rebalance 的健康门控，该错误路径不生成或返回 `PositionPlan`。`ActivePositionSingleSided()` 仅用于 V3 Active Position 的 `principal0` 或 `principal1` 为零时的 Deposit 前置检查；`ZeroAmount()` 用于双边 Position 下实际 `d0` 或 `d1` 为零；`SharesSlippage(actual, minimum)` 用于执行过程中计算出的 `sharesMinted` 低于 `minSharesOut`；`IdleLimitExceeded()` 用于 Deposit 或 Rebalance 的 Idle 健康约束失败。`AdapterDisabled()` 用于当前 Active Adapter 已禁用的 Deposit，以及非 IDLE 候选目标 Adapter 已禁用的 Bootstrap、Preview 和两类 Rebalance；检查必须发生在对应 Adapter 的 `previewDeposit()`、`deposit()` 或用户 Token 转入之前，不阻止从已禁用旧 Adapter 读取、同步费用或退出。`InvalidTickSpacing()` 用于 Adapter 绑定缺少、非正值或与 Pool 不一致的 V3 spacing；`InvalidTickRange()` 用于 spacing 步数换算溢出、边界不合法或生成的 Range 超出 Uniswap V3 可用 Tick。`SwapRequired()` 是回滚返回的 custom error，不是事件；当 Bootstrap 或普通 `rebalance` 的 `DeploymentAssessment.requiresSwap` 为 true 时使用该错误终止交易。`CooldownActive(availableAt)` 用于两类 Rebalance 在 `block.timestamp < uint256(lastPositionChangeAt) + minRebalanceCooldown` 时回滚，其中 `availableAt` 是允许再次执行计划性 Rebalance 的最早时间；Emergency Exit 不触发该错误。

## 8. 事件契约

事件字段是链下索引和审计的稳定接口。以下代码块仅列出 Vault 自定义事件；继承自 `IAccessControl`、`IAccessControlDefaultAdminRules` 和 shares ERC-20 的标准事件不在此重复声明。所有事件由 Vault 或对应模块在状态成功更新后发出。

```solidity
event VaultBootstrapped(
    address indexed manager,
    uint256 amount0,
    uint256 amount1,
    uint256 grossInitialShares,
    uint256 lockedShares,
    VenueType initialVenue
);

event Deposit(
    address indexed caller,
    address indexed receiver,
    uint256 amount0,
    uint256 amount1,
    uint256 shares
);

event Redeem(
    address indexed caller,
    address indexed receiver,
    address indexed owner,
    uint256 shares,
    uint256 amount0,
    uint256 amount1
);

event PositionPlanCommitted(
    bytes32 indexed planHash,
    uint64 indexed version,
    VenueType targetVenue,
    MarketRegime regime
);

event RebalanceExecuted(
    address indexed caller,
    bytes32 indexed planHash,
    VenueType previousVenue,
    VenueType targetVenue,
    bool withSwap,
    uint256 total0,
    uint256 total1,
    uint256 nav1,
    uint256 idleBps
);

event V3RangeChanged(
    bytes32 indexed planHash,
    int24 oldTickLower,
    int24 oldTickUpper,
    int24 newTickLower,
    int24 newTickUpper
);

event FeesSynchronized(
    address indexed adapter,
    uint256 fee0,
    uint256 fee1,
    uint256 total0,
    uint256 total1
);

event SwapExecuted(
    address indexed router,
    SwapDirection direction,
    uint256 amountIn,
    uint256 amountOut,
    uint256 protocolMinOut
);

event AdapterConfigured(
    VenueType indexed venue,
    address indexed adapter,
    address indexed pool,
    uint24 feeTier,
    int24 tickSpacing
);
event AdapterStatusChanged(VenueType indexed venue, address indexed adapter, bool enabled);
event PauseStateChanged(
    address indexed caller,
    bool depositPaused,
    bool plainRebalancePaused,
    bool swapRebalancePaused
);
event EmergencyExit(address indexed caller, VenueType previousVenue, uint256 amount0, uint256 amount1);
```

事件规则：

- `Redeem` 记录实际调用者 `caller`、被销毁 shares 的持有人 `owner` 和资产接收者 `receiver`；shares 必须从 `owner` 销毁；
- `FeesSynchronized` 的金额是本次从 claimable 状态归集的增量，不是再次计入总资产的额外资产；
- `RebalanceExecuted` 只在所有 post-condition 成功后发出；
- 任何以 custom error 回滚的交易都不会保留事件日志，协议不定义失败事件；`SwapRequired()` 通过 revert data 返回；
- `activeVenue` 的链下历史由动作事件共同重建：`VaultBootstrapped.initialVenue` 初始化位置，成功的 `RebalanceExecuted.targetVenue` 更新位置，`EmergencyExit` 将位置更新为 `IDLE`；同 Venue V3 Recenter 的 `previousVenue == targetVenue`。协议不定义额外的通用资产位置或 Idle 状态变化事件；
- `RoleAdminChanged`、`RoleGranted` 和 `RoleRevoked` 采用 OpenZeppelin `IAccessControl` 标准语义；
- `DefaultAdminTransferScheduled`、`DefaultAdminTransferCanceled`、`DefaultAdminDelayChangeScheduled` 和 `DefaultAdminDelayChangeCanceled` 采用 `IAccessControlDefaultAdminRules` 标准语义；
- `PauseStateChanged` 只在 `setPauseState` 或 Emergency Exit 实际改变暂停 storage 时发出，自动门控和无状态变化调用不得发出；
- `AdapterConfigured` 与 `AdapterStatusChanged` 由 Vault 地址上的继承式 Registry 入口发出；`AdapterConfigured` 的 Pool、Fee Tier 和 `tickSpacing` 字段是配置时从 Adapter/Pool 读取并验证后的实际绑定值；
- Emergency Exit 不发 Swap 事件，因为该路径禁止 Swap；只有调用前 `activeVenue != IDLE` 且全部 Position 成功清空时发出 `EmergencyExit`，调用前已为 IDLE 时不发出该事件；

## 9. 关键调用时序

### 9.1 Bootstrap

```mermaid
sequenceDiagram
    participant Manager
    participant Vault
    participant Oracle
    participant Accounting
    participant Strategy
    participant Adapter

    Manager->>Vault: bootstrap(amount0, amount1, receiver)
    Vault->>Vault: validate complete configured Adapter bindings and cached tickSpacing
    Vault->>Oracle: snapshot()
    Oracle-->>Vault: healthy OracleSnapshot
    Vault->>Accounting: compute seed NAV and grossInitialShares
    Vault->>Strategy: getPlan(seed snapshots, default lastCommittedRegime, verified rangeContext, planVersion = 0)
    Strategy-->>Vault: deterministic initial PositionPlan with version = 1
    Vault->>Vault: require target Adapter enter enabled if targetVenue is non-IDLE
    Vault->>Adapter: previewDeposit(seed amounts, plan) if targetVenue is non-IDLE
    Adapter-->>Vault: used0/used1
    Vault->>Vault: build DeploymentAssessment; validate ratio; revert SwapRequired if assessment.requiresSwap
    Vault->>Vault: transferFrom token0/token1
    Vault->>Vault: mint and lock grossInitialShares
    Vault->>Adapter: deposit if targetVenue is non-IDLE
    Adapter-->>Vault: used amounts and liquidity
    Vault->>Vault: validate ACTIVE or EXTREME IDLE post-state; commit lastExecutedPlan and planVersion = 1; set lastPositionChangeAt = block.timestamp; set initialized = true and freeze bindings
    Vault-->>Manager: PositionPlanCommitted and VaultBootstrapped
```

### 9.2 Deposit

```mermaid
sequenceDiagram
    participant User
    participant Vault
    participant Oracle
    participant Adapter
    participant Accounting

    User->>Vault: deposit(max0, max1, minSharesOut)
    Vault->>Vault: validate initialized, deposit pause and non-IDLE activeVenue; require isEnterEnabled(activeVenue)
    Vault->>Oracle: snapshot()
    Vault->>Adapter: syncFees() and snapshot() for principal0/principal1
    Vault->>Accounting: compute amounts and shares from pre-state
    Accounting-->>Vault: used0, used1, shares
    Vault->>Vault: transferFrom only used amounts
    Vault->>Adapter: deposit(used0, used1, lastExecutedPlan)
    Adapter-->>Vault: unused amounts and liquidity
    Vault->>Vault: validate idle, position and slippage
    Vault->>Vault: mint shares
    Vault-->>User: Deposit
```

### 9.3 Redeem

```mermaid
sequenceDiagram
    participant Caller
    participant Vault
    participant Adapter
    participant Accounting

    Caller->>Vault: redeem(shares, min0, min1, receiver, owner)
    Vault->>Vault: verify owner balance and allowance(owner, Caller) when Caller != owner
    Vault->>Adapter: syncFees() and snapshot()
    Vault->>Accounting: compute fraction from pre-burn supply
    Accounting-->>Vault: proportional amounts
    Vault->>Adapter: withdraw(shares, totalShares)
    Adapter-->>Vault: token0/token1
    Vault->>Vault: add proportional Idle and validate final outputs against minAmount0Out/minAmount1Out
    Vault->>Vault: burn owner shares and transfer assets to receiver; retain the locked-share portion of the current Position or Idle assets
    Vault-->>Caller: Redeem(caller, receiver, owner, shares, amount0, amount1)
```

### 9.4 Plain Rebalance

```mermaid
sequenceDiagram
    participant Caller
    participant Vault
    participant Oracle
    participant Strategy
    participant OldAdapter
    participant NewAdapter

    Caller->>Vault: rebalance(expectedPlanHash, deadline)
    Vault->>Oracle: snapshot()
    Vault->>Strategy: getPlan(current snapshots, lastExecutedPlan.marketRegime as lastCommittedRegime, verified rangeContext, planVersion)
    Strategy-->>Vault: deterministic PositionPlan
    Vault->>Vault: require target Adapter enter enabled if targetVenue is non-IDLE
    Vault->>NewAdapter: previewDeposit(current assets, plan) if targetVenue is non-IDLE
    NewAdapter-->>Vault: used0/used1
    Vault->>Vault: build DeploymentAssessment; validate deadline, hash and cooldown; revert SwapRequired if assessment.requiresSwap
    Vault->>OldAdapter: syncFees() and withdrawAll()
    OldAdapter-->>Vault: token0/token1
    Vault->>NewAdapter: deposit() without swap
    NewAdapter-->>Vault: unused amounts and liquidity
    Vault->>Vault: validate conservation, idle and single position
    Vault->>Vault: commit lastExecutedPlan and incremented planVersion; set lastPositionChangeAt = block.timestamp
    Vault-->>Caller: PositionPlanCommitted and RebalanceExecuted
```

### 9.5 Swap Rebalance

```mermaid
sequenceDiagram
    participant Keeper
    participant Vault
    participant Oracle
    participant Strategy
    participant OldAdapter
    participant SwapExecutor
    participant NewAdapter

    Keeper->>Vault: rebalanceWithSwap(expectedPlanHash, expectedDirection, amountIn, keeperMinAmountOut, deadline)
    Vault->>Oracle: snapshot()
    Vault->>Strategy: getPlan(current snapshots, lastExecutedPlan.marketRegime as lastCommittedRegime, verified rangeContext, planVersion)
    Strategy-->>Vault: PositionPlan
    Vault->>Vault: require target Adapter enter enabled
    Vault->>NewAdapter: previewDeposit(current assets, plan)
    NewAdapter-->>Vault: used0/used1
    Vault->>Vault: build initial DeploymentAssessment (initialDeployBps) from T0/T1; validate hash, deadline, cooldown, assessment.requiresSwap and expectedDirection
    Vault->>OldAdapter: syncFees() and withdrawAll()
    OldAdapter-->>Vault: token0/token1
    Vault->>Vault: verify actual balances against assessed assets; simulate worst-case post-swap balances
    Vault->>NewAdapter: previewDeposit(simulated post-swap balances, plan)
    NewAdapter-->>Vault: simulated used0/used1
    Vault->>Vault: validate amountIn, simulatedDeployBps and idle; construct SwapPlan
    Vault->>SwapExecutor: executeSwap(validated SwapPlan)
    SwapExecutor-->>Vault: actual amountOut
    Vault->>NewAdapter: deposit() with adjusted assets
    NewAdapter-->>Vault: unused amounts and liquidity
    Vault->>Vault: validate NAV loss, deployment, idle, dust tolerance and position
    Vault->>Vault: commit lastExecutedPlan and incremented planVersion; set lastPositionChangeAt = block.timestamp
    Vault-->>Keeper: PositionPlanCommitted, RebalanceExecuted and SwapExecuted
```

### 9.6 Emergency Exit

```mermaid
sequenceDiagram
    participant Guardian
    participant Vault
    participant Adapter

    Guardian->>Vault: emergencyExitToIdle()
    Vault->>Vault: bypass minRebalanceCooldown
    alt activeVenue != IDLE
        Vault->>Adapter: syncFees()
        Vault->>Adapter: withdrawAll()
        Adapter-->>Vault: token0/token1
        Vault->>Vault: verify conservation and position liquidity == 0
        Vault->>Vault: activeVenue = IDLE; increment planVersion; preserve lastExecutedPlan and lastPositionChangeAt
        Vault->>Vault: set all pause flags true
        Vault-->>Guardian: EmergencyExit and PauseStateChanged if pause storage changed
    else activeVenue == IDLE
        Vault->>Vault: skip Adapter; preserve position, venue, version, history and lastPositionChangeAt
        Vault->>Vault: set all pause flags true
        Vault-->>Guardian: PauseStateChanged only if pause storage changed
    end
```

## 10. 关键实现细节

### 10.1 V3 Oracle 数学

- `observe([twapWindowSeconds, shortTwapWindowSeconds, 0])` 返回三个累计 Tick；分别计算 `twapTick` 和 `shortTwapTick`。
- 负的非整除结果必须向负无穷取整，而不是 Solidity 默认的向零截断。
- 用 `TickMath.getSqrtRatioAtTick` 计算 `Q1/Q0` 双向报价，使用全精度乘除防止中间乘法溢出。
- `Q1` 输入 token0 raw units 并返回 token1 raw units；`Q0` 输入 token1 raw units 并返回 token0 raw units。
- canonical Uniswap V3 Pool 按地址从小到大定义 Pool token0/token1；在资产对绑定已验证的前提下，报价函数以输入 Token 作为 `baseToken`：`baseToken < quoteToken` 时按 Pool token0 → token1 报价，否则按 Pool token1 → token0 反向报价。
- 报价使用全精度乘除；`roundUp == false` 时返回精确商的向下取整结果，`roundUp == true` 时返回精确商的向上取整结果；`protocolMinOut` 的方向报价和 BPS 滑点折算分别向上取整。
- Oracle 使用 `shortTwapTick` 和 `twapTick` 计算 `deviationBps`；NAV 仍使用 `twapTick`，`spotTick` 保留用于 Range 越界和 Swap 风控。



### 10.2 V3 费用读取顺序

推荐实现顺序：

1. 读取 Position Manager 的 `positions(tokenId)`，取得 liquidity、Tick 边界、fee growth 快照和 tokens owed。
2. 通过 Pool 的 Position 状态计算尚未写入 Manager 缓存的 fee growth 增量；只读路径不得依赖状态修改。
3. 只读估值将 principal 与 claimable fee 合并一次形成 `PositionSnapshot.amount0/amount1`。
4. 费用同步按 `PRODUCT_SPEC.md` §6.8 的统一会计路径执行；Deposit 比例只使用 `principal0/principal1`。
5. 收取后重新读取 `positions(tokenId)`、Vault ERC-20 余额和 Adapter 快照；用于后续状态变更的快照中 `claimableFee0/1` 必须为零。
6. 旧快照不得继续参与 post-state 会计。

若底层 Position Manager 的具体版本不支持某个读取路径，必须在 Adapter 内实现等价的唯一计价路径，并在测试中证明同一费用不会被两次计入。

### 10.3 V2 资产读取

V2 Adapter 读取 Pair `getReserves()`、LP Token 总供应量和 Adapter 持有的 LP Token 余额。按比例计算的储备权益同时包含交易费用形成的储备增长，不再产生独立 claimable fee 字段。

### 10.4 舍入与全精度

Bootstrap 使用 `grossInitialShares = mulDiv(NAV_seed, 10^18, 10^token1Decimals)`，向下舍入；`minimumLockedShares` 包含在该总量内并铸造给 Vault 自身（`address(this)`），其余铸造给 `receiver`。Vault 不提供锁定 shares 的转出或救援机制。


| 操作           | 舍入方向     | 原因                                        |
| ------------ | -------- | ----------------------------------------- |
| 存款实际数量       | 向下       | 不超过用户最大输入                                 |
| shares 铸造    | 向下       | 不让新用户取得超额权益                               |
| 赎回 token 输出  | 向下       | `dustTolerance0/1` 范围内的余额留在 Vault，保护剩余持有人 |
| `idleBps`    | 向下       | 不因显示舍入误判健康                                |
| 迁移损失下限       | 向下计算允许损失 | 不放宽安全阈值                                   |
| V3 mean tick | 向负无穷     | 与 Uniswap V3 OracleLibrary 语义一致           |




### 10.5 授权与回调

- Adapter 对 Position Manager、Pair、Router 的授权使用最小额度，并在不需要时清零。
- Swap Executor 不暴露调用者可指定的 receiver；相关资产流遵循 `PRODUCT_SPEC.md` 第 9.4 节。
- 每个外部调用前后按模块契约检查固定计量账户的余额变化、Position 状态和目标 Token。
- 所有入口使用 `nonReentrant`；Token 回调、V3 mint callback 和 Router callback 必须验证发送方。

## 11. 安全不变量与测试矩阵

### 11.1 必须保持的不变量


| 编号     | 不变量                                                                                 | 违反时              |
| ------ | ----------------------------------------------------------------------------------- | ---------------- |
| INV-01 | 支持资产所有权始终属于 shares 持有人                                                              | 回滚或暂停相关入口        |
| INV-02 | 非 IDLE 时最多一个有效 Active Position                                                      | Rebalance 回滚     |
| INV-03 | IDLE 时所有 Adapter 有效 liquidity 为零                                                    | Emergency/状态更新回滚 |
| INV-04 | `totalAssets` 不重复计入 principal、fees 或 Donation                                       | 会计测试失败           |
| INV-05 | Deposit shares 使用存款前 NAV/Supply                                                     | Deposit 回滚       |
| INV-06 | Redeem 使用销毁前 Supply，从显式 `owner` 销毁 shares，并按比例退出 Idle/Position；非 owner 调用者只有在 `allowance(owner, msg.sender)` 足够时才能执行 | Redeem 回滚        |
| INV-07 | Oracle 不健康时不执行价值相关操作                                                                | 入口回滚             |
| INV-08 | Permissionless Caller 不能改变计划内容                                                      | 计划哈希校验失败         |
| INV-09 | Swap 只允许固定 token0/token1、部署时封存的 Router/方法和目标过量资产修复范围                                | Swap 回滚          |
| INV-10 | 两类 Rebalance 均不得在 Cooldown 结束前执行；Emergency Exit 跳过该检查且不更新 `lastPositionChangeAt`；失败交易不更新 `lastPositionChangeAt`、版本或资产位置，IDLE 幂等分支不更新时间戳 | `CooldownActive(availableAt)` 或原子回滚 |
| INV-11 | 支持资产 Donation 不可被角色救援                                                               | 不存在对应接口          |
| INV-12 | Pause 不阻止正常双资产 Redeem                                                               | 赎回测试失败           |
| INV-13 | `lastExecutedPlan` 只在健康 Strategy 计划成功执行后更新；其 `marketRegime` 是 Hysteresis 历史，不从 `activeVenue` 或 `lastExecutedPlan.targetVenue` 推导 | 状态机测试失败          |
| INV-14 | 每次成功的 Position 结构变化使 `planVersion` 恰好递增 1，失败交易及非结构变化不更新                             | 版本与原子性测试失败       |
| INV-15 | `DEFAULT_ADMIN_ROLE` 至多由一个账户持有，转移、放弃和延迟变更只能通过 `AccessControlDefaultAdminRules` 标准流程 | 权限操作回滚           |
| INV-16 | Default Admin 不因根角色自动获得 Vault 业务权限，Guardian 只能收紧暂停和 Adapter 状态                      | 权限操作回滚           |
| INV-17 | 任一合法 `PositionPlan` 的 `targetVenue` 与 `marketRegime` 严格双射：`IDLE` ↔ `EXTREME_DEVIATION`、`UNISWAP_V2` ↔ `HIGH_DEVIATION`、`UNISWAP_V3_HIGH_FEE` ↔ `MEDIUM_DEVIATION`、`UNISWAP_V3_LOW_FEE` ↔ `LOW_DEVIATION` | 计划校验失败 |
| INV-18 | 禁用 Adapter 不移除现有 Position 的计价与退出能力，但阻止 Deposit、迁入和同 Venue Recenter 增加其 liquidity | `AdapterDisabled()` |




### 11.2 测试矩阵


| 测试层                 | 必测场景                                                                                                                                                                                                                      |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Accounting 单元测试     | raw units、Token decimals 链上值与配置一致且均不超过 18、配置不一致或超限时以 `InvalidTokenDecimals` 回滚、负 Tick、NAV、Bootstrap/Deposit shares 舍入、Idle、迁移损失、零值和溢出边界                                                                                                                                               |
| Oracle 单元测试         | 长/短窗口 `observe` 累计 Tick、负数向负无穷取整、观察不足、Pool 绑定、`Q1/Q0` 双向报价、Vault/Pool Token 顺序、向上/向下取整、Short TWAP/TWAP 偏离                                                                                                                                                     |
| Strategy 单元测试       | Oracle 不健康快照回滚且不生成计划、`planVersion == 0` 的首次完整分类、四种历史 regime 的进入/退出 Hysteresis、`lastExecutedPlan.marketRegime` 作为 `lastCommittedRegime` 参数传递、Venue/Regime 严格双射、候选版本、spacing 步数换算与低/高费率 Pool spacing 映射、Range 对齐、边界回滚与中心偏移 Recenter、稳定计划哈希                                                                                 |
| V2 Adapter 测试       | 储备权益、费用已包含、`amount0Max/amount1Max` 与实际 `used0/used1`、部分退出、实际退出数量与余额变化、Token 顺序                                                                                                                                                         |
| V3 Adapter 测试       | principal、tokens owed、fee growth 增量、领取后重读、principal 比例与手续费隔离、`amount0Max/amount1Max` 与实际 `used0/used1`、immutable binding getters、`tickSpacing`、Range、部分退出、实际退出数量与余额变化、旧 NFT 清理                                                                                                                               |
| Adapter Registry 测试 | `configureAdapter(venue, adapter)` 的绑定校验、`tickSpacing` 缓存、初始化前重复配置、Bootstrap 后绑定和缓存冻结、仅 `enabled` 可变、Pool/Fee Tier 不重复存储                                                                                  |
| Swap 测试             | 固定 Router/Token 方法、方向、过量资产修复范围、方向报价与 BPS 滑点折算的两段向上取整、派生部署阈值、minOut、deadline、Vault 向 Executor 精确交付输入、Vault 输出余额增量与返回值一致、Executor 余额恢复基线、回调验证和授权清理                                                                                                                         |
| Deposit/Redeem 集成测试 | 只转实际数量、V3 单边 Active Position 的 `ActivePositionSingleSided()`、双边 Position 零实际存款的 `ZeroAmount()`、按 principal 比例的限制侧与非整除舍入、手续费不影响 Deposit 比例、暂停赎回、Oracle 异常赎回、Redeem 最小双资产输出、持有人自赎不消费 allowance、授权 spender 从显式 `owner` 销毁 shares 并消费有限 allowance、最大 allowance 不递减、任意 `receiver` 收款、owner 余额或 allowance 不足时原子回滚、捐赠、单边/高 Idle、比例公平性、当前 Active Adapter 禁用时 Deposit 在 Adapter 调用和 Token 转入前回滚、禁用后资产仍计价且 Redeem 成功 |
| Rebalance 集成测试      | V2↔V3、V3↔V3、进入/退出 IDLE、计划与部署评估分离、相同评估输入只调用一次 `previewDeposit`、未初始化 Preview 回滚 `NotInitialized()`、Oracle 不健康 Preview 回滚 `OracleUnhealthy()`、非 IDLE 目标 Adapter 禁用时 Preview/两类 Rebalance 回滚且允许从已禁用旧 Adapter 迁出、Bootstrap 初始化 `lastPositionChangeAt`、两类 Rebalance 共用 Cooldown 与 `CooldownActive(availableAt)`、Emergency Exit 绕过检查且不重置计时、IDLE 幂等分支不更新时间戳、全部流通 shares 赎回保留锁定份额对应资产、`activeVenue`/`planVersion`/`lastExecutedPlan` 不因 Redeem 改变、`expectedPlanHash`、`expectedDirection`、模拟 Swap 后评估、deadline、无 Swap 资产守恒、带 Swap 实际输出与 NAV 损失、后置条件和原子回滚 |
| 事件契约测试            | `VaultBootstrapped.initialVenue` 初始化链下位置，`RebalanceExecuted.targetVenue` 更新位置且同 Venue Recenter 保持相同值，`EmergencyExit` 将位置更新为 `IDLE`；已在 IDLE 的幂等 Emergency Exit 不发出 `EmergencyExit`；自定义事件 ABI 不包含额外的通用资产位置或 Idle 状态变化事件 |
| Invariant/Fuzz      | 资产守恒、shares 公平性、单活 Position、费用不重复、任意调用者不能越权                                                                                                                                                                               |
| Mainnet Fork        | 真实 canonical Pool TWAP、V2 Pair、V3 Position Manager、Router 和 Tick spacing                                                                                                                                                  |
| 安全测试                | 重入、闪电贷 Spot 操纵、Sandwich、Adapter 恶意返回、Default Admin 单账户约束、两阶段延迟转移/取消/接受、延迟变更、根角色无隐式业务权限、业务角色授予/撤销、Guardian 只能收紧控制、初始化前治理入口、暂停和 Adapter 状态滥用、暂停位与 Adapter `enabled` 作为独立运行时控制的组合、禁用 Active Adapter 不修改资产位置/计划版本/历史计划/暂停 storage                                                                                |




## 12. 交付前检查

- `PRODUCT_SPEC.md` 与本文档的函数、类型、事件、角色和参数名称一致。
- 所有规划目录已明确标记为待实现结构，不能被误读为已存在代码。
- 所有 Mermaid、表格和 Solidity 代码块位于 Markdown 顶层，且围栏成对闭合。
- 所有资产变更方法定义调用者、输入、输出、失败条件和原子性。
- V3 Oracle、V3 费用同步、V2 储备计价和 Donation 语义均有可执行测试用例。
- 没有支持资产 rescue/sweep 接口，没有外部 `DEVIATION` 入参，没有将 `deviationBps` 描述为波动率。
- 所有事件在状态成功更新后发出，并包含足以重建资产位置和策略状态的字段。
