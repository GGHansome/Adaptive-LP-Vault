# Adaptive LP Vault 部署规范

- 文档版本：1.0
- 文档状态：实现规范
- 适用范围：v1 Ethereum Mainnet 部署、配置、Bootstrap 与部署证据
- 对应产品文档：[PRODUCT_SPEC.md](PRODUCT_SPEC.md)
- 对应架构文档：[ARCHITECTURE.md](ARCHITECTURE.md)
- Swap 数学规范：[SWAP_REBALANE_MATH.md](SWAP_REBALANE_MATH.md)

本文中的“部署负责人”是负责确认配置、执行或审批部署并保存证据的链下责任主体，不是合约角色，也不自动拥有 Default Admin、Manager、Guardian 或 Keeper 权限。具体责任主体必须写入每次部署记录。

## 1. 文档职责与发布边界

本文中的“检查”默认指部署脚本或部署负责人在交易外读取链上状态、执行模拟并比较预期结果；它不代替合约入口自身的检查。`bootstrap()` 的链上前置条件和状态变化由 `PRODUCT_SPEC.md` §5.2 定义，接口与内部调用时序由 `ARCHITECTURE.md` 定义。

部署流程必须使用上游文档已经确定的合约地址、参数和绑定关系。部署文档只记录这些输入、验证其实际部署结果，并保存可复核证据；发现上游配置不成立时停止发布，不在本文档中另行解释或改写协议语义。

## 2. 部署输入

部署前必须固定并记录以下输入，部署脚本不得从未版本化的本地默认值静默补齐：

- 目标网络和 `chainId`；
- 源码提交、Solidity 编译器版本、EVM 目标、优化器配置和依赖版本；
- `VaultStrategyMath` 和 `VaultComponentFactory` 的发布版本及部署或复用选择；
- canonical Pool、Uniswap Factory、Router、Position Manager 和三个目标 Venue Pool；
- `initialDefaultAdmin`、`initialDefaultAdminDelay` 以及 Manager、Guardian、Keeper 的初始成员；
- Vault 名称、符号、`VaultConfig`、`AccessControlConfig`、`StrategyConfig` 和 Oracle 窗口；
- Bootstrap 的 `amount0`、`amount1` 和 `receiver`；
- 流动性预检的 `liquidityTestAmount0`、`liquidityTestAmount1` 和 `deploymentMaxPriceImpactBps`。

`liquidityTestAmount0/1` 使用对应 Token raw units，必须大于零，并按预期上线资产规模和最大单次 Swap 场景选取。它们只定义部署验收场景，不写入合约，也不构成运行时 `amountIn` 上限。

`deploymentMaxPriceImpactBps` 是部署验收阈值，不写入合约，且必须满足：

```text
0 <= deploymentMaxPriceImpactBps < maxSwapSlippageBps
```

严格小于运行时滑点上限是为了给报价变化、区块状态变化和实际执行保留余量。具体数值必须在部署记录中显式给出，本文档不为具体资产对预设数值。

## 3. 部署输入静态检查

发送第一笔部署交易前，部署脚本必须检查配置文件和既有外部协议依赖：

1. 目标 `chainId` 正确，配置中的既有 Factory、Pool、Router、Position Manager 和 Token 地址存在合约代码。
2. canonical Pool 的 Factory、Fee Tier 和代码绑定符合协议允许的 Uniswap V3 实现。
3. canonical Pool 的 `token0/token1` 非零、互不相同且按地址升序。
4. 两个 Token 的 metadata 可读取，`decimals()` 均不超过 18。
5. Router 支持协议固定的 exact-input、single-hop 方法，并能路由 canonical Pool 的 Fee Tier。
6. `swapPool` 配置与 canonical Pool 地址完全相同；不得通过仅校验 Token 对相同来替代地址相等。
7. 每个 Adapter 除 `vault` 外的计划构造参数与 `ARCHITECTURE.md` 定义的 Venue、Pool、Token 顺序、Fee Tier、Tick Spacing 和 Position Manager 关系一致；`vault` 参数在第 5.2 节使用实际已部署 Vault 地址填入。
8. `initialDefaultAdmin` 非零，Mainnet 的 `initialDefaultAdminDelay` 使用经部署负责人确认的非零值。
9. 策略阈值、Range 宽度、Dust、Idle、Swap 滑点和迁移损失参数满足全部链上硬边界与字段关系。
10. 发布配置下，所有合约的 runtime 不超过 24,576 字节，initcode（含构造参数）不超过 49,152 字节；任一超限时阻断发布。
11. 复用的 `VaultStrategyMath` 和 `VaultComponentFactory` 必须有代码，且与指定源码和发布编译配置对应的部署产物一致；使用不可升级的固定实现。

任一检查失败时不得继续部署。

## 4. Oracle 与流动性预检

### 4.1 Oracle 可用性预检

在计划发送 Bootstrap 交易的目标状态上调用 Oracle `snapshot()`，要求 `healthy == true`，并记录网络、区块和返回结果。

### 4.2 双向指定金额报价

不得使用 V3 Pool 当前裸 `liquidity()` 数值作为唯一流动性质量标准。部署预检必须通过最终固定的 Router、canonical Pool、Fee Tier 和 exact-input single-hop 方法，对两个方向分别报价：

```text
liquidityTestAmount0: token0 -> token1
liquidityTestAmount1: token1 -> token0
```

对每个方向，使用当前健康 canonical TWAP 计算 `oracleQuoteOut`，并通过配置后的真实执行路径获得 `quotedAmountOut`。部署价格影响按以下规则计算：

```text
quotedAmountOut >= oracleQuoteOut:
    priceImpactBps = 0

quotedAmountOut < oracleQuoteOut:
    priceImpactBps = ceil(
        (oracleQuoteOut - quotedAmountOut) * BPS / oracleQuoteOut
    )
```

两个方向必须同时满足：

```text
priceImpactBps <= deploymentMaxPriceImpactBps
quotedAmountOut >= protocolMinOut(liquidityTestAmount)
```

`protocolMinOut` 必须使用 `SWAP_REBALANE_MATH.md` 定义的方向报价和两段向上取整规则计算。任一方向报价失败、跨错 Pool、低于 `protocolMinOut` 或超过部署价格影响阈值时，不得继续部署。

预检必须记录目标网络、区块号、Pool、Fee Tier、测试方向、输入数量、TWAP Tick、`oracleQuoteOut`、`quotedAmountOut` 和 `priceImpactBps`。这些结果只证明记录区块及测试金额下的流动性状态，不保证未来外部 LP 不会撤走流动性。

### 4.3 Mainnet Fork 完整模拟

进入真实部署前，必须在固定 Mainnet Fork 区块执行：

- Oracle 长短窗口与双向报价；
- canonical Pool 与 Swap Pool 地址相等校验；
- 两个方向的固定 Router Swap；
- Vault、VaultControl、Executor 和 Adapter 的 Token 顺序与绑定校验；
- Bootstrap 成功路径和所有失败回滚路径；
- 至少一个完整 `rebalanceWithSwap` 场景，覆盖旧 Position 退出、Swap、新 Position 建立、部署率、Idle、资产守恒和 NAV 损失校验；
- Router allowance 清零、Executor 余额恢复基线和 Vault 实际输出余额增量校验。

Fork 测试必须使用与真实部署相同的发布产物、链接配置、外部地址、构造参数和固定 Swap 方法，并通过 `VaultComponentFactory` 创建 Vault 专属组件。

## 5. 分阶段部署流程

主网部署按以下阶段执行；每一阶段的交易和校验结果必须在进入下一阶段前确认。

### 5.1 准备 Vault 构造输入

准备 Vault 名称、符号、`VaultConfig`、`AccessControlConfig` 和 `StrategyConfig`。`VaultConfig.canonicalOracle` 与 `VaultConfig.componentFactory` 在第 5.2 节填入实际部署或验证后的地址。

使用 `--libraries src/libraries/VaultStrategyMath.sol:VaultStrategyMath:<已验证库地址>` 链接 Vault；编译、部署和源码验证使用同一映射。发送部署交易前确认所有链接引用均已解析且地址正确。

### 5.2 Deploy

1. 部署或验证并复用 `VaultStrategyMath` 和 `VaultComponentFactory`，确认与发布产物一致。
2. 部署 `CanonicalV3Oracle`，固定 canonical Pool 和 Oracle 窗口。
3. 使用已验证的库地址链接并部署 `AdaptiveLPVault`，传入第 5.1 节的构造输入；构造函数调用组件工厂创建专属 `VaultControl` 和 `ControlledSwapExecutor`。
4. 读取 Vault 的 `vaultControl`、`swapExecutor`；验证两个组件的 `vault()` 均等于 Vault 地址，Token 顺序一致，Control 的 V2/V3 Factory 绑定正确，Executor 的 Router 与输入一致且 `swapPool()` 等于 canonical Pool。
5. 结合构造期 immutable 填充值核对链上 Vault runtime 与最终链接产物，并确认库地址正确。
6. 使用实际 Vault 地址部署三个非 IDLE Venue Adapter，固定各自的 Venue、Pool 和所需 Position Manager，验证所有 Adapter 的 `vault()` 等于 Vault 地址。

任一步骤出现构造参数、子合约创建或链上读取不一致时，停止流程并重新部署受影响的未初始化实例；不得继续进入角色配置或 Bootstrap。

### 5.3 Grant Roles

由当前 Default Admin 在 `Vault.vaultControl()` 对应的 `VaultControl` 上授予 Manager、Guardian 和 Keeper 角色，并通过 `hasRole()` 逐项确认。发送 Bootstrap 交易的账户必须具有 Manager 角色。

### 5.4 Configure

Manager 在同一 `VaultControl` 上调用 `configureAdapter()`，绑定三个非 IDLE Venue。每次配置后在该 Control 上查询并验证：

- `getAdapter(venue)` 返回预期地址；
- `isEnterEnabled(venue) == true`；
- `getConfig(venue).tickSpacing` 与 Adapter 及 Pool 一致；
- Adapter 的 immutable Vault、Venue、Pool、Token、Fee Tier 和 Position Manager 绑定正确。

初始化前允许重复配置以修正绑定；Bootstrap 后身份字段和 Tick Spacing 缓存冻结。

### 5.5 发送 Bootstrap 交易前的链下发布门禁

发送交易前必须：

1. 在计划发送交易的最新确认区块重新执行第 3 节静态检查，并核对实际已部署地址和 Registry 读取结果；
2. 重新执行第 4 节 Oracle 与双向流动性预检；
3. 核对 Bootstrap 调用者、`amount0`、`amount1`、`receiver`、Token 余额和 allowance 与部署记录一致；
4. 使用完全相同的调用者、参数和当前链上状态对 `bootstrap(amount0, amount1, receiver)` 执行 `eth_call` 模拟，要求模拟成功；无法可靠复现计划交易上下文时，必须在对应区块的 Mainnet Fork 上模拟；
5. 将检查区块、读取结果和模拟结果写入部署记录。

任一门禁失败时不得发送 Bootstrap 交易。

### 5.6 Bootstrap 交易与链上强制校验

Manager 在 Vault 上调用 `bootstrap(amount0, amount1, receiver)`，链上校验和状态变化遵循 `PRODUCT_SPEC.md` §5.2。

交易成功并达到要求的确认数后，执行第 6 节部署后验证；失败时记录回滚原因并按第 7 节处理。

## 6. 部署后验证与证据

Bootstrap 成功后必须生成可复核的部署记录，至少包括：

- 网络、`chainId`、部署区块和全部交易哈希；
- 源码提交、编译器、EVM、优化器和依赖版本；
- `VaultStrategyMath` 地址、部署来源和 runtime 代码哈希，Vault 链接映射、最终 creation/runtime 产物与尺寸检查结果；
- deployer、Vault、组件工厂、专属 VaultControl 和 Executor 地址，组件工厂的部署来源与代码哈希、组件绑定验证结果；
- Oracle、Executor、Router、canonical/Swap Pool、三个 Adapter、三个 Venue Pool和 Position Manager 地址；
- 全部 immutable 配置和策略参数；
- VaultControl 的角色成员、Adapter Registry 绑定、`enabled` 和 `PauseState`；
- Vault 的 `initialized`、`activeVenue`、`planVersion`、`lastExecutedPlan` 和 `lastPositionChangeAt`；
- Bootstrap 输入、接收人、初始 shares、锁定 shares 和初始 Position；
- Oracle 与流动性预检记录；
- Mainnet Fork 测试区块和测试结果；
- 浏览器源码验证结果及最终 ABI。

部署记录中的 canonical Pool 地址必须与 Swap Pool 地址完全相同。任何读取结果与部署输入不一致时，不得宣布部署完成或开放 Deposit。

## 7. 部署失败与重新部署

- 发送 Bootstrap 前发现错误：停止操作，根据错误发生阶段修正未冻结配置，或废弃错误实例并重新部署。
- Bootstrap 交易失败：记录回滚原因，修正调用输入或仍允许修改的部署配置，再从第 5.5 节重新执行链下发布门禁。
- Bootstrap 后发现 immutable 配置错误：不得宣布部署完成；后续处置适用 `PRODUCT_SPEC.md` 的不可变绑定和用户退出规则，部署侧必须准备新的 Vault 实例及单独批准的迁移方案。

第 4 节预检只证明记录区块和测试金额下的外部依赖状态，不提供永久流动性保证；运行期的暂停、紧急退出和用户赎回行为由 `PRODUCT_SPEC.md` 定义，不在本文重复。

## 8. 文档同步要求

以下变化必须同步更新本文档并重新执行对应预检：

- 目标网络、外部 Uniswap 地址、Router 或 Position Manager 改变；
- Vault 构造参数、组件工厂、Control/Executor 创建参数、immutable 字段或部署顺序改变；
- `VaultStrategyMath` 源码、编译配置、链接地址、链接方式或库代码哈希改变；
- Oracle 窗口、策略硬边界、Swap 方法或滑点公式改变；
- Adapter 数量、Venue、Pool、Fee Tier 或 Tick Spacing 改变；
- Bootstrap 参数或角色初始化流程改变；
- 部署证据格式、Fork 测试入口或发布阻断条件改变。
