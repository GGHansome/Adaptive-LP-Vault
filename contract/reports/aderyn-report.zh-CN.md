# Aderyn 分析报告（中文译本）

本报告由 [Aderyn](https://github.com/Cyfrin/aderyn) 生成。Aderyn 是区块链安全公司 [Cyfrin](https://cyfrin.io) 开发的静态分析工具。本报告不能替代人工审计或安全评审，其用途仅限于辅助识别潜在的安全漏洞，不应将其作为其他用途的依据。

> 翻译说明：本文件译自 [英文原报告](aderyn-report.md)，保留原报告的问题编号、严重程度、实例数量、代码片段和源码位置。报告中的发现属于静态分析工具的检测结果，本译文未对其是否构成实际漏洞进行人工确认。nSLOC 指非注释源代码行数。

# 目录

- [汇总](#summary)
  - [文件汇总](#files-summary)
  - [文件明细](#files-details)
  - [问题汇总](#issue-summary)
- [高危问题](#high-issues)
  - [H-1：重入：外部调用之后修改状态](#h-1-reentrancy-state-change-after-external-call)
  - [H-2：通过 memory 参数修改 storage 数组](#h-2-storage-array-edited-with-memory)
  - [H-3：不安全的整数类型转换](#h-3-unsafe-casting-of-integers)
- [低危问题](#low-issues)
  - [L-1：仅使用一次的内部函数](#l-1-internal-function-used-only-once)
  - [L-2：较大的数字字面量](#l-2-large-numeric-literal)
  - [L-3：使用字面量而非常量](#l-3-literal-instead-of-constant)
  - [L-4：局部变量遮蔽状态变量](#l-4-local-variable-shadows-state-variable)
  - [L-5：仅调用一次的修饰器](#l-5-modifier-invoked-only-once)
  - [L-6：`nonReentrant` 不是第一个修饰器](#l-6-nonreentrant-is-not-the-first-modifier)
  - [L-7：PUSH0 操作码](#l-7-push0-opcode)
  - [L-8：循环中包含 `require`/`revert`](#l-8-loop-contains-requirerevert)
  - [L-9：状态变更未触发事件](#l-9-state-change-without-event)
  - [L-10：未检查返回值](#l-10-unchecked-return)
  - [L-11：未初始化的局部变量](#l-11-uninitialized-local-variable)
  - [L-12：未固定 Solidity 版本的 pragma 指令](#l-12-unspecific-solidity-pragma)
  - [L-13：未使用的自定义错误](#l-13-unused-error)

<a id="summary"></a>
 
# 汇总

<a id="files-summary"></a>

## 文件汇总

| 项目 | 数值 |
| --- | --- |
| .sol 文件数 | 27 |
| nSLOC 总数 | 3271 |

<a id="files-details"></a>

## 文件明细

| 文件路径 | nSLOC |
| --- | --- |
| src/adapters/AdapterTypes.sol | 23 |
| src/adapters/UniswapV2Adapter.sol | 193 |
| src/adapters/UniswapV3Adapter.sol | 494 |
| src/control/AdapterRegistry.sol | 234 |
| src/control/VaultControl.sol | 102 |
| src/control/VaultPause.sol | 50 |
| src/control/VaultRoles.sol | 30 |
| src/core/AdaptiveLPVault.sol | 987 |
| src/core/VaultComponentFactory.sol | 33 |
| src/core/VaultTypes.sol | 81 |
| src/interfaces/IAdapterRegistry.sol | 20 |
| src/interfaces/IAdaptiveLPVault.sol | 103 |
| src/interfaces/ICanonicalV3Oracle.sol | 19 |
| src/interfaces/IControlledSwapExecutor.sol | 26 |
| src/interfaces/IPositionAdapter.sol | 39 |
| src/interfaces/IUniswapV2External.sol | 15 |
| src/interfaces/IUniswapV3External.sol | 127 |
| src/interfaces/IVaultComponentFactory.sol | 18 |
| src/interfaces/IVaultControl.sol | 23 |
| src/interfaces/IVaultPause.sol | 11 |
| src/interfaces/IVaultRoles.sol | 10 |
| src/libraries/PriceMath.sol | 56 |
| src/libraries/VaultStrategyMath.sol | 194 |
| src/oracle/CanonicalV3Oracle.sol | 198 |
| src/oracle/OracleTypes.sol | 20 |
| src/swap/ControlledSwapExecutor.sol | 147 |
| src/swap/SwapTypes.sol | 18 |
| **总计** | **3271** |

<a id="issue-summary"></a>

## 问题汇总

| 类别 | 问题数量 |
| --- | --- |
| 高危 | 3 |
| 低危 | 13 |

<a id="high-issues"></a>

# 高危问题

<a id="h-1-reentrancy-state-change-after-external-call"></a>

## H-1：重入：外部调用之后修改状态

在外部调用之后修改状态可能导致重入攻击。请采用“检查—状态更新—外部交互”（checks-effects-interactions）模式来避免此问题。

<details><summary>发现 33 处实例</summary>

- 发现位置：src/adapters/UniswapV2Adapter.sol [第 52 行](../src/adapters/UniswapV2Adapter.sol#L52)

	状态变更：`_VAULT = config.vault`、`_POOL = config.pool`、`_TOKEN0 = pairToken0`、`_TOKEN1 = pairToken1`、`_PAIR = pair`
	```solidity
	        try pair.token0() returns (address value) {
	```

- 发现位置：src/adapters/UniswapV2Adapter.sol [第 57 行](../src/adapters/UniswapV2Adapter.sol#L57)

	状态变更：`_VAULT = config.vault`、`_POOL = config.pool`、`_TOKEN0 = pairToken0`、`_TOKEN1 = pairToken1`、`_PAIR = pair`
	```solidity
	        try pair.token1() returns (address value) {
	```

- 发现位置：src/adapters/UniswapV2Adapter.sol [第 70 行](../src/adapters/UniswapV2Adapter.sol#L70)

	状态变更：`_VAULT = config.vault`、`_POOL = config.pool`、`_TOKEN0 = pairToken0`、`_TOKEN1 = pairToken1`、`_PAIR = pair`
	```solidity
	        try pair.factory() returns (address value) {
	```

- 发现位置：src/adapters/UniswapV2Adapter.sol [第 78 行](../src/adapters/UniswapV2Adapter.sol#L78)

	状态变更：`_VAULT = config.vault`、`_POOL = config.pool`、`_TOKEN0 = pairToken0`、`_TOKEN1 = pairToken1`、`_PAIR = pair`
	```solidity
	        try IUniswapV2Factory(config.factory).getPair(pairToken0, pairToken1) returns (address value) {
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 89 行](../src/adapters/UniswapV3Adapter.sol#L89)

	状态变更：`_VAULT = config.vault`、`_VENUE = config.venue`、`_POOL_ADDRESS = config.pool`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_POSITION_MANAGER_ADDRESS = config.positionManager`、`_FEE_TIER = poolFee`、`_TICK_SPACING = poolTickSpacing`、`_POOL = pool_`、`_POSITION_MANAGER = positionManager_`
	```solidity
	        try pool_.token0() returns (address value) {
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 94 行](../src/adapters/UniswapV3Adapter.sol#L94)

	状态变更：`_VAULT = config.vault`、`_VENUE = config.venue`、`_POOL_ADDRESS = config.pool`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_POSITION_MANAGER_ADDRESS = config.positionManager`、`_FEE_TIER = poolFee`、`_TICK_SPACING = poolTickSpacing`、`_POOL = pool_`、`_POSITION_MANAGER = positionManager_`
	```solidity
	        try pool_.token1() returns (address value) {
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 107 行](../src/adapters/UniswapV3Adapter.sol#L107)

	状态变更：`_VAULT = config.vault`、`_VENUE = config.venue`、`_POOL_ADDRESS = config.pool`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_POSITION_MANAGER_ADDRESS = config.positionManager`、`_FEE_TIER = poolFee`、`_TICK_SPACING = poolTickSpacing`、`_POOL = pool_`、`_POSITION_MANAGER = positionManager_`
	```solidity
	        try pool_.factory() returns (address value) {
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 112 行](../src/adapters/UniswapV3Adapter.sol#L112)

	状态变更：`_VAULT = config.vault`、`_VENUE = config.venue`、`_POOL_ADDRESS = config.pool`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_POSITION_MANAGER_ADDRESS = config.positionManager`、`_FEE_TIER = poolFee`、`_TICK_SPACING = poolTickSpacing`、`_POOL = pool_`、`_POSITION_MANAGER = positionManager_`
	```solidity
	        try pool_.fee() returns (uint24 value) {
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 117 行](../src/adapters/UniswapV3Adapter.sol#L117)

	状态变更：`_VAULT = config.vault`、`_VENUE = config.venue`、`_POOL_ADDRESS = config.pool`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_POSITION_MANAGER_ADDRESS = config.positionManager`、`_FEE_TIER = poolFee`、`_TICK_SPACING = poolTickSpacing`、`_POOL = pool_`、`_POSITION_MANAGER = positionManager_`
	```solidity
	        try pool_.tickSpacing() returns (int24 value) {
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 122 行](../src/adapters/UniswapV3Adapter.sol#L122)

	状态变更：`_VAULT = config.vault`、`_VENUE = config.venue`、`_POOL_ADDRESS = config.pool`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_POSITION_MANAGER_ADDRESS = config.positionManager`、`_FEE_TIER = poolFee`、`_TICK_SPACING = poolTickSpacing`、`_POOL = pool_`、`_POSITION_MANAGER = positionManager_`
	```solidity
	        try positionManager_.factory() returns (address value) {
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 134 行](../src/adapters/UniswapV3Adapter.sol#L134)

	状态变更：`_VAULT = config.vault`、`_VENUE = config.venue`、`_POOL_ADDRESS = config.pool`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_POSITION_MANAGER_ADDRESS = config.positionManager`、`_FEE_TIER = poolFee`、`_TICK_SPACING = poolTickSpacing`、`_POOL = pool_`、`_POSITION_MANAGER = positionManager_`
	```solidity
	        try IUniswapV3Factory(config.factory).getPool(poolToken0, poolToken1, poolFee) returns (address value) {
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 252 行](../src/adapters/UniswapV3Adapter.sol#L252)

	状态变更：`_positionId = tokenId`、`_positionId = 0`
	```solidity
	                _POSITION_MANAGER.burn(tokenId);
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 258 行](../src/adapters/UniswapV3Adapter.sol#L258)

	状态变更：`_positionId = tokenId`
	```solidity
	        uint256 balance0Before = IERC20(_TOKEN0).balanceOf(address(this));
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 259 行](../src/adapters/UniswapV3Adapter.sol#L259)

	状态变更：`_positionId = tokenId`
	```solidity
	        uint256 balance1Before = IERC20(_TOKEN1).balanceOf(address(this));
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 272 行](../src/adapters/UniswapV3Adapter.sol#L272)

	状态变更：`_positionId = tokenId`
	```solidity
	            (tokenId, liquidityCreated, used0, used1) = _POSITION_MANAGER.mint(
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 348 行](../src/adapters/UniswapV3Adapter.sol#L348)

	状态变更：`_positionId = 0`
	```solidity
	        _POSITION_MANAGER.burn(tokenId);
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 151 行](../src/core/AdaptiveLPVault.sol#L151)

	状态变更：`vaultControl = control`、`swapExecutor = executor`
	```solidity
	        (IVaultControl control, IControlledSwapExecutor executor) = IVaultComponentFactory(vaultConfig.componentFactory)
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 333 行](../src/core/AdaptiveLPVault.sol#L333)

	状态变更：`activeVenue = plan.targetVenue`
	```solidity
	            _depositToAdapter(
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 390 行](../src/core/AdaptiveLPVault.sol#L390)

	状态变更：`activeVenue = plan.targetVenue`
	```solidity
	        uint256 balance0 = IERC20(token0).balanceOf(address(this));
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 391 行](../src/core/AdaptiveLPVault.sol#L391)

	状态变更：`activeVenue = plan.targetVenue`
	```solidity
	        uint256 balance1 = IERC20(token1).balanceOf(address(this));
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 407 行](../src/core/AdaptiveLPVault.sol#L407)

	状态变更：`activeVenue = plan.targetVenue`
	```solidity
	        _depositToAdapter(
	```

- 发现位置：src/oracle/CanonicalV3Oracle.sol [第 47 行](../src/oracle/CanonicalV3Oracle.sol#L47)

	状态变更：`_CANONICAL_POOL = config.canonicalPool`、`_TOKEN0 = token0_`、`_TOKEN1 = token1_`、`_TOKEN0_DECIMALS = token0Decimals_`、`_TOKEN1_DECIMALS = token1Decimals_`、`_TWAP_WINDOW_SECONDS = config.twapWindowSeconds`、`_SHORT_TWAP_WINDOW_SECONDS = config.shortTwapWindowSeconds`、`_POOL = pool_`
	```solidity
	        try pool_.token0() returns (address value) {
	```

- 发现位置：src/oracle/CanonicalV3Oracle.sol [第 52 行](../src/oracle/CanonicalV3Oracle.sol#L52)

	状态变更：`_CANONICAL_POOL = config.canonicalPool`、`_TOKEN0 = token0_`、`_TOKEN1 = token1_`、`_TOKEN0_DECIMALS = token0Decimals_`、`_TOKEN1_DECIMALS = token1Decimals_`、`_TWAP_WINDOW_SECONDS = config.twapWindowSeconds`、`_SHORT_TWAP_WINDOW_SECONDS = config.shortTwapWindowSeconds`、`_POOL = pool_`
	```solidity
	        try pool_.token1() returns (address value) {
	```

- 发现位置：src/oracle/CanonicalV3Oracle.sol [第 62 行](../src/oracle/CanonicalV3Oracle.sol#L62)

	状态变更：`_CANONICAL_POOL = config.canonicalPool`、`_TOKEN0 = token0_`、`_TOKEN1 = token1_`、`_TOKEN0_DECIMALS = token0Decimals_`、`_TOKEN1_DECIMALS = token1Decimals_`、`_TWAP_WINDOW_SECONDS = config.twapWindowSeconds`、`_SHORT_TWAP_WINDOW_SECONDS = config.shortTwapWindowSeconds`、`_POOL = pool_`
	```solidity
	        try pool_.factory() returns (address value) {
	```

- 发现位置：src/oracle/CanonicalV3Oracle.sol [第 67 行](../src/oracle/CanonicalV3Oracle.sol#L67)

	状态变更：`_CANONICAL_POOL = config.canonicalPool`、`_TOKEN0 = token0_`、`_TOKEN1 = token1_`、`_TOKEN0_DECIMALS = token0Decimals_`、`_TOKEN1_DECIMALS = token1Decimals_`、`_TWAP_WINDOW_SECONDS = config.twapWindowSeconds`、`_SHORT_TWAP_WINDOW_SECONDS = config.shortTwapWindowSeconds`、`_POOL = pool_`
	```solidity
	        try pool_.fee() returns (uint24 value) {
	```

- 发现位置：src/oracle/CanonicalV3Oracle.sol [第 72 行](../src/oracle/CanonicalV3Oracle.sol#L72)

	状态变更：`_CANONICAL_POOL = config.canonicalPool`、`_TOKEN0 = token0_`、`_TOKEN1 = token1_`、`_TOKEN0_DECIMALS = token0Decimals_`、`_TOKEN1_DECIMALS = token1Decimals_`、`_TWAP_WINDOW_SECONDS = config.twapWindowSeconds`、`_SHORT_TWAP_WINDOW_SECONDS = config.shortTwapWindowSeconds`、`_POOL = pool_`
	```solidity
	        try pool_.tickSpacing() returns (int24 value) {
	```

- 发现位置：src/oracle/CanonicalV3Oracle.sol [第 83 行](../src/oracle/CanonicalV3Oracle.sol#L83)

	状态变更：`_CANONICAL_POOL = config.canonicalPool`、`_TOKEN0 = token0_`、`_TOKEN1 = token1_`、`_TOKEN0_DECIMALS = token0Decimals_`、`_TOKEN1_DECIMALS = token1Decimals_`、`_TWAP_WINDOW_SECONDS = config.twapWindowSeconds`、`_SHORT_TWAP_WINDOW_SECONDS = config.shortTwapWindowSeconds`、`_POOL = pool_`
	```solidity
	        try IUniswapV3Factory(config.factory).getPool(token0_, token1_, fee_) returns (address value) {
	```

- 发现位置：src/swap/ControlledSwapExecutor.sol [第 52 行](../src/swap/ControlledSwapExecutor.sol#L52)

	状态变更：`_VAULT = config.vault`、`_ROUTER_ADDRESS = config.router`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_SWAP_POOL = config.swapPool`、`_FEE_TIER = poolFee`、`_ROUTER = IUniswapV3SwapRouter(config.router)`
	```solidity
	        try pool.token0() returns (address value) {
	```

- 发现位置：src/swap/ControlledSwapExecutor.sol [第 57 行](../src/swap/ControlledSwapExecutor.sol#L57)

	状态变更：`_VAULT = config.vault`、`_ROUTER_ADDRESS = config.router`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_SWAP_POOL = config.swapPool`、`_FEE_TIER = poolFee`、`_ROUTER = IUniswapV3SwapRouter(config.router)`
	```solidity
	        try pool.token1() returns (address value) {
	```

- 发现位置：src/swap/ControlledSwapExecutor.sol [第 70 行](../src/swap/ControlledSwapExecutor.sol#L70)

	状态变更：`_VAULT = config.vault`、`_ROUTER_ADDRESS = config.router`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_SWAP_POOL = config.swapPool`、`_FEE_TIER = poolFee`、`_ROUTER = IUniswapV3SwapRouter(config.router)`
	```solidity
	        try pool.factory() returns (address value) {
	```

- 发现位置：src/swap/ControlledSwapExecutor.sol [第 75 行](../src/swap/ControlledSwapExecutor.sol#L75)

	状态变更：`_VAULT = config.vault`、`_ROUTER_ADDRESS = config.router`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_SWAP_POOL = config.swapPool`、`_FEE_TIER = poolFee`、`_ROUTER = IUniswapV3SwapRouter(config.router)`
	```solidity
	        try pool.fee() returns (uint24 value) {
	```

- 发现位置：src/swap/ControlledSwapExecutor.sol [第 83 行](../src/swap/ControlledSwapExecutor.sol#L83)

	状态变更：`_VAULT = config.vault`、`_ROUTER_ADDRESS = config.router`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_SWAP_POOL = config.swapPool`、`_FEE_TIER = poolFee`、`_ROUTER = IUniswapV3SwapRouter(config.router)`
	```solidity
	        try IUniswapV3Factory(config.factory).getPool(poolToken0, poolToken1, poolFee) returns (address value) {
	```

- 发现位置：src/swap/ControlledSwapExecutor.sol [第 91 行](../src/swap/ControlledSwapExecutor.sol#L91)

	状态变更：`_VAULT = config.vault`、`_ROUTER_ADDRESS = config.router`、`_TOKEN0 = poolToken0`、`_TOKEN1 = poolToken1`、`_SWAP_POOL = config.swapPool`、`_FEE_TIER = poolFee`、`_ROUTER = IUniswapV3SwapRouter(config.router)`
	```solidity
	        try IUniswapV3SwapRouter(config.router).factory() returns (address value) {
	```

</details>

<a id="h-2-storage-array-edited-with-memory"></a>

## H-2：通过 memory 参数修改 storage 数组

将 storage（持久化存储）引用传递给参数类型为 memory（内存）的函数，不会按预期更新原 storage 变量。请考虑改用 storage 参数。

<details><summary>发现 3 处实例</summary>

- 发现位置：src/core/AdaptiveLPVault.sol [第 258 行](../src/core/AdaptiveLPVault.sol#L258)

	```solidity
	        _depositToAdapter(adapter, _lastExecutedPlan, amount0Used, amount1Used);
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 261 行](../src/core/AdaptiveLPVault.sol#L261)

	```solidity
	        _validateSingleActivePositions(activeVenue, _lastExecutedPlan, afterPosition);
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 447 行](../src/core/AdaptiveLPVault.sol#L447)

	```solidity
	            _validateSingleActivePositions(VenueType.IDLE, _lastExecutedPlan, _emptyPosition());
	```

</details>

<a id="h-3-unsafe-casting-of-integers"></a>

## H-3：不安全的整数类型转换

在 Solidity 中，对 int/uint 进行向下类型转换可能造成数据丢失和非预期行为。当较大的整数类型转换为较小的整数类型时（例如从 uint256 转换为 uint128），其数值可能超出目标类型的取值范围，导致截断和有效位丢失。请使用 OpenZeppelin 的 SafeCast 库安全地进行整数向下类型转换。

<details><summary>发现 1 处实例</summary>

- 发现位置：src/libraries/PriceMath.sol [第 80 行](../src/libraries/PriceMath.sol#L80)

	```solidity
	        sqrtPriceX96 = uint160(rounded);
	```

</details>

<a id="low-issues"></a>

# 低危问题

<a id="l-1-internal-function-used-only-once"></a>

## L-1：仅使用一次的内部函数

请考虑将逻辑直接内联到调用函数中，而不是拆分为单独的函数。这可以减少函数调用次数，并提高可读性。

<details><summary>发现 1 处实例</summary>

- 发现位置：src/libraries/VaultStrategyMath.sol [第 159 行](../src/libraries/VaultStrategyMath.sol#L159)

	```solidity
	    function unpackPlanStrategyConfig(uint256 packed) internal pure returns (PlanStrategyConfig memory config) {
	```

</details>

<a id="l-2-large-numeric-literal"></a>

## L-2：较大的数字字面量

对于数值较大且为 10000 倍数的字面量，可以改用科学计数法。请使用 `e` 记法，例如用 `1e18` 代替完整的数字值。

<details><summary>发现 3 处实例</summary>

- 发现位置：src/core/AdaptiveLPVault.sol [第 41 行](../src/core/AdaptiveLPVault.sol#L41)

	```solidity
	    uint256 private constant BPS = 10_000;
	```

- 发现位置：src/libraries/VaultStrategyMath.sol [第 18 行](../src/libraries/VaultStrategyMath.sol#L18)

	```solidity
	    uint256 private constant BPS = 10_000;
	```

- 发现位置：src/oracle/CanonicalV3Oracle.sol [第 15 行](../src/oracle/CanonicalV3Oracle.sol#L15)

	```solidity
	    uint256 private constant BPS = 10_000;
	```

</details>

<a id="l-3-literal-instead-of-constant"></a>

## L-3：使用字面量而非常量

请定义并使用 `constant` 变量来代替字面量。如果同一个常量字面值被多次使用，请创建一个常量状态变量，并在整个合约中引用它。

<details><summary>发现 28 处实例</summary>

- 发现位置：src/core/AdaptiveLPVault.sol [第 488 行](../src/core/AdaptiveLPVault.sol#L488)

	```solidity
	        return 18;
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 1067 行](../src/core/AdaptiveLPVault.sol#L1067)

	```solidity
	        if (binding.token0Decimals > 18) {
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 1070 行](../src/core/AdaptiveLPVault.sol#L1070)

	```solidity
	        if (binding.token1Decimals > 18) {
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 1129 行](../src/core/AdaptiveLPVault.sol#L1129)

	```solidity
	        if (value > 18) revert IAdaptiveLPVault.InvalidTokenDecimals(token, value);
	```

- 发现位置：src/libraries/PriceMath.sol [第 27 行](../src/libraries/PriceMath.sol#L27)

	```solidity
	        uint256 ratioX128 = Math.mulDiv(uint256(sqrtPriceX96), sqrtPriceX96, 1 << 64);
	```

- 发现位置：src/libraries/PriceMath.sol [第 41 行](../src/libraries/PriceMath.sol#L41)

	```solidity
	        uint256 ratioX128 = Math.mulDiv(uint256(sqrtPriceX96), sqrtPriceX96, 1 << 64);
	```

- 发现位置：src/libraries/PriceMath.sol [第 54 行](../src/libraries/PriceMath.sol#L54)

	```solidity
	        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 55 行](../src/libraries/PriceMath.sol#L55)

	```solidity
	        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 56 行](../src/libraries/PriceMath.sol#L56)

	```solidity
	        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 57 行](../src/libraries/PriceMath.sol#L57)

	```solidity
	        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 58 行](../src/libraries/PriceMath.sol#L58)

	```solidity
	        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 59 行](../src/libraries/PriceMath.sol#L59)

	```solidity
	        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 60 行](../src/libraries/PriceMath.sol#L60)

	```solidity
	        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 61 行](../src/libraries/PriceMath.sol#L61)

	```solidity
	        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 62 行](../src/libraries/PriceMath.sol#L62)

	```solidity
	        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 63 行](../src/libraries/PriceMath.sol#L63)

	```solidity
	        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 64 行](../src/libraries/PriceMath.sol#L64)

	```solidity
	        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 65 行](../src/libraries/PriceMath.sol#L65)

	```solidity
	        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 66 行](../src/libraries/PriceMath.sol#L66)

	```solidity
	        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 67 行](../src/libraries/PriceMath.sol#L67)

	```solidity
	        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 68 行](../src/libraries/PriceMath.sol#L68)

	```solidity
	        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 69 行](../src/libraries/PriceMath.sol#L69)

	```solidity
	        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 70 行](../src/libraries/PriceMath.sol#L70)

	```solidity
	        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 71 行](../src/libraries/PriceMath.sol#L71)

	```solidity
	        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
	```

- 发现位置：src/libraries/PriceMath.sol [第 72 行](../src/libraries/PriceMath.sol#L72)

	```solidity
	        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;
	```

- 发现位置：src/oracle/CanonicalV3Oracle.sol [第 162 行](../src/oracle/CanonicalV3Oracle.sol#L162)

	```solidity
	        uint32[] memory secondsAgos = new uint32[](3);
	```

- 发现位置：src/oracle/CanonicalV3Oracle.sol [第 175 行](../src/oracle/CanonicalV3Oracle.sol#L175)

	```solidity
	        if (tickCumulatives.length != 3 || secondsPerLiquidityCumulativeX128s.length != 3) {
	```

</details>

<a id="l-4-local-variable-shadows-state-variable"></a>

## L-4：局部变量遮蔽状态变量

请重命名与状态变量同名、从而遮蔽该状态变量的局部变量。

<details><summary>发现 4 处实例</summary>

- 发现位置：src/core/AdaptiveLPVault.sol [第 103 行](../src/core/AdaptiveLPVault.sol#L103)

	```solidity
	        address token0;
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 104 行](../src/core/AdaptiveLPVault.sol#L104)

	```solidity
	        address token1;
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 105 行](../src/core/AdaptiveLPVault.sol#L105)

	```solidity
	        uint8 token0Decimals;
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 106 行](../src/core/AdaptiveLPVault.sol#L106)

	```solidity
	        uint8 token1Decimals;
	```

</details>

<a id="l-5-modifier-invoked-only-once"></a>

## L-5：仅调用一次的修饰器

请考虑移除该修饰器，或将其逻辑内联到调用函数中。

<details><summary>发现 1 处实例</summary>

- 发现位置：src/swap/ControlledSwapExecutor.sol [第 28 行](../src/swap/ControlledSwapExecutor.sol#L28)

	```solidity
	    modifier onlyVault() {
	```

</details>

<a id="l-6-nonreentrant-is-not-the-first-modifier"></a>

## L-6：`nonReentrant` 不是第一个修饰器

为防范其他修饰器中的重入，`nonReentrant` 修饰器应放在修饰器列表的第一位。

<details><summary>发现 8 处实例</summary>

- 发现位置：src/adapters/UniswapV2Adapter.sol [第 168 行](../src/adapters/UniswapV2Adapter.sol#L168)

	```solidity
	        nonReentrant
	```

- 发现位置：src/adapters/UniswapV2Adapter.sol [第 191 行](../src/adapters/UniswapV2Adapter.sol#L191)

	```solidity
	        nonReentrant
	```

- 发现位置：src/adapters/UniswapV2Adapter.sol [第 205 行](../src/adapters/UniswapV2Adapter.sol#L205)

	```solidity
	    function withdrawAll() external override onlyVault nonReentrant returns (uint256 amount0, uint256 amount1) {
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 204 行](../src/adapters/UniswapV3Adapter.sol#L204)

	```solidity
	    function syncFees() external override onlyVault nonReentrant returns (uint256 fee0, uint256 fee1) {
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 237 行](../src/adapters/UniswapV3Adapter.sol#L237)

	```solidity
	        nonReentrant
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 322 行](../src/adapters/UniswapV3Adapter.sol#L322)

	```solidity
	        nonReentrant
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 341 行](../src/adapters/UniswapV3Adapter.sol#L341)

	```solidity
	    function withdrawAll() external override onlyVault nonReentrant returns (uint256 amount0, uint256 amount1) {
	```

- 发现位置：src/swap/ControlledSwapExecutor.sol [第 108 行](../src/swap/ControlledSwapExecutor.sol#L108)

	```solidity
	    function executeSwap(SwapPlan calldata plan) external override onlyVault nonReentrant returns (uint256 amountOut) {
	```

</details>

<a id="l-7-push0-opcode"></a>

## L-7：PUSH0 操作码

Solc 编译器自 0.8.20 版本起，将默认目标 EVM（以太坊虚拟机）版本切换为 Shanghai，这意味着生成的字节码会包含 PUSH0 操作码。如果计划部署到以太坊主网以外的链，例如可能不支持 PUSH0 的 L2（二层网络），请务必选择适当的 EVM 版本，否则合约部署将会失败。

<details><summary>发现 27 处实例</summary>

- 发现位置：src/adapters/AdapterTypes.sol [第 2 行](../src/adapters/AdapterTypes.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/adapters/UniswapV2Adapter.sol [第 2 行](../src/adapters/UniswapV2Adapter.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 2 行](../src/adapters/UniswapV3Adapter.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/control/AdapterRegistry.sol [第 2 行](../src/control/AdapterRegistry.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/control/VaultControl.sol [第 2 行](../src/control/VaultControl.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/control/VaultPause.sol [第 2 行](../src/control/VaultPause.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/control/VaultRoles.sol [第 2 行](../src/control/VaultRoles.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 2 行](../src/core/AdaptiveLPVault.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/core/VaultComponentFactory.sol [第 2 行](../src/core/VaultComponentFactory.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/core/VaultTypes.sol [第 2 行](../src/core/VaultTypes.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IAdapterRegistry.sol [第 2 行](../src/interfaces/IAdapterRegistry.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IAdaptiveLPVault.sol [第 2 行](../src/interfaces/IAdaptiveLPVault.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/ICanonicalV3Oracle.sol [第 2 行](../src/interfaces/ICanonicalV3Oracle.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IControlledSwapExecutor.sol [第 2 行](../src/interfaces/IControlledSwapExecutor.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IPositionAdapter.sol [第 2 行](../src/interfaces/IPositionAdapter.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IUniswapV2External.sol [第 2 行](../src/interfaces/IUniswapV2External.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IUniswapV3External.sol [第 2 行](../src/interfaces/IUniswapV3External.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IVaultComponentFactory.sol [第 2 行](../src/interfaces/IVaultComponentFactory.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IVaultControl.sol [第 2 行](../src/interfaces/IVaultControl.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IVaultPause.sol [第 2 行](../src/interfaces/IVaultPause.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IVaultRoles.sol [第 2 行](../src/interfaces/IVaultRoles.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/libraries/PriceMath.sol [第 2 行](../src/libraries/PriceMath.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/libraries/VaultStrategyMath.sol [第 2 行](../src/libraries/VaultStrategyMath.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/oracle/CanonicalV3Oracle.sol [第 2 行](../src/oracle/CanonicalV3Oracle.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/oracle/OracleTypes.sol [第 2 行](../src/oracle/OracleTypes.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/swap/ControlledSwapExecutor.sol [第 2 行](../src/swap/ControlledSwapExecutor.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/swap/SwapTypes.sol [第 2 行](../src/swap/SwapTypes.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

</details>

<a id="l-8-loop-contains-requirerevert"></a>

## L-8：循环中包含 `require`/`revert`

请避免在循环中使用 `require` / `revert` 语句，因为单个异常元素就可能导致整笔交易失败。更好的做法是在处理失败时容许继续执行，并在循环处理结束后返回失败的元素。

<details><summary>发现 2 处实例</summary>

- 发现位置：src/core/AdaptiveLPVault.sol [第 895 行](../src/core/AdaptiveLPVault.sol#L895)

	```solidity
	        for (uint256 i; i < 2; ++i) {
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 927 行](../src/core/AdaptiveLPVault.sol#L927)

	```solidity
	        for (uint256 i; i < 2; ++i) {
	```

</details>

<a id="l-9-state-change-without-event"></a>

## L-9：状态变更未触发事件

该函数修改了状态变量，但未触发任何事件。请考虑触发事件，以便链下索引器跟踪这些变更。

<details><summary>发现 2 处实例</summary>

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 233 行](../src/adapters/UniswapV3Adapter.sol#L233)

	```solidity
	    function deposit(uint256 amount0Max, uint256 amount1Max, PositionPlan calldata plan)
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 341 行](../src/adapters/UniswapV3Adapter.sol#L341)

	```solidity
	    function withdrawAll() external override onlyVault nonReentrant returns (uint256 amount0, uint256 amount1) {
	```

</details>

<a id="l-10-unchecked-return"></a>

## L-10：未检查返回值

函数返回了一个值，但该值被忽略。请考虑检查返回值。

<details><summary>发现 12 处实例</summary>

- 发现位置：src/adapters/UniswapV2Adapter.sol [第 255 行](../src/adapters/UniswapV2Adapter.sol#L255)

	```solidity
	        _PAIR.burn(_VAULT);
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 423 行](../src/adapters/UniswapV3Adapter.sol#L423)

	```solidity
	        _POSITION_MANAGER.decreaseLiquidity(
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 433 行](../src/adapters/UniswapV3Adapter.sol#L433)

	```solidity
	        _POSITION_MANAGER.collect(
	```

- 发现位置：src/control/AdapterRegistry.sol [第 59 行](../src/control/AdapterRegistry.sol#L59)

	```solidity
	            _checkManagerOrGuardian();
	```

- 发现位置：src/control/VaultPause.sol [第 36 行](../src/control/VaultPause.sol#L36)

	```solidity
	        _setPauseState(newState, _msgSender());
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 204 行](../src/core/AdaptiveLPVault.sol#L204)

	```solidity
	            _validateHealthyDeployment(afterAssets, oracle.twapTick);
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 262 行](../src/core/AdaptiveLPVault.sol#L262)

	```solidity
	        _validateHealthyDeployment(afterAssets, oracle.twapTick);
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 496 行](../src/core/AdaptiveLPVault.sol#L496)

	```solidity
	        vaultControl.checkManagerOrGuardian(_msgSender());
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 500 行](../src/core/AdaptiveLPVault.sol#L500)

	```solidity
	        vaultControl.checkManagerOrKeeper(_msgSender());
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 520 行](../src/core/AdaptiveLPVault.sol#L520)

	```solidity
	        vaultControl.pauseAll(caller);
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 732 行](../src/core/AdaptiveLPVault.sol#L732)

	```solidity
	        IPositionAdapter(adapter).withdrawAll();
	```

- 发现位置：src/swap/ControlledSwapExecutor.sol [第 128 行](../src/swap/ControlledSwapExecutor.sol#L128)

	```solidity
	        _ROUTER.exactInputSingle(
	```

</details>

<a id="l-11-uninitialized-local-variable"></a>

## L-11：未初始化的局部变量

请初始化所有变量。如果变量预期初始化为零，请显式将其设为零，以提高代码可读性。

<details><summary>发现 2 处实例</summary>

- 发现位置：src/core/AdaptiveLPVault.sol [第 895 行](../src/core/AdaptiveLPVault.sol#L895)

	```solidity
	        for (uint256 i; i < 2; ++i) {
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 927 行](../src/core/AdaptiveLPVault.sol#L927)

	```solidity
	        for (uint256 i; i < 2; ++i) {
	```

</details>

<a id="l-12-unspecific-solidity-pragma"></a>

## L-12：未固定 Solidity 版本的 pragma 指令

请考虑在合约中使用明确固定的 Solidity 版本，而不是较宽的版本范围。例如，用 `pragma solidity 0.8.0;` 代替 `pragma solidity ^0.8.0;`。

<details><summary>发现 25 处实例</summary>

- 发现位置：src/adapters/AdapterTypes.sol [第 2 行](../src/adapters/AdapterTypes.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/adapters/UniswapV2Adapter.sol [第 2 行](../src/adapters/UniswapV2Adapter.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/adapters/UniswapV3Adapter.sol [第 2 行](../src/adapters/UniswapV3Adapter.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/control/AdapterRegistry.sol [第 2 行](../src/control/AdapterRegistry.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/control/VaultControl.sol [第 2 行](../src/control/VaultControl.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/control/VaultPause.sol [第 2 行](../src/control/VaultPause.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/control/VaultRoles.sol [第 2 行](../src/control/VaultRoles.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/core/AdaptiveLPVault.sol [第 2 行](../src/core/AdaptiveLPVault.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/core/VaultComponentFactory.sol [第 2 行](../src/core/VaultComponentFactory.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/core/VaultTypes.sol [第 2 行](../src/core/VaultTypes.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IAdapterRegistry.sol [第 2 行](../src/interfaces/IAdapterRegistry.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IAdaptiveLPVault.sol [第 2 行](../src/interfaces/IAdaptiveLPVault.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/ICanonicalV3Oracle.sol [第 2 行](../src/interfaces/ICanonicalV3Oracle.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IControlledSwapExecutor.sol [第 2 行](../src/interfaces/IControlledSwapExecutor.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IPositionAdapter.sol [第 2 行](../src/interfaces/IPositionAdapter.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IUniswapV2External.sol [第 2 行](../src/interfaces/IUniswapV2External.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IUniswapV3External.sol [第 2 行](../src/interfaces/IUniswapV3External.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IVaultComponentFactory.sol [第 2 行](../src/interfaces/IVaultComponentFactory.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IVaultControl.sol [第 2 行](../src/interfaces/IVaultControl.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IVaultPause.sol [第 2 行](../src/interfaces/IVaultPause.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/interfaces/IVaultRoles.sol [第 2 行](../src/interfaces/IVaultRoles.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/oracle/CanonicalV3Oracle.sol [第 2 行](../src/oracle/CanonicalV3Oracle.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/oracle/OracleTypes.sol [第 2 行](../src/oracle/OracleTypes.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/swap/ControlledSwapExecutor.sol [第 2 行](../src/swap/ControlledSwapExecutor.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

- 发现位置：src/swap/SwapTypes.sol [第 2 行](../src/swap/SwapTypes.sol#L2)

	```solidity
	pragma solidity ^0.8.24;
	```

</details>

<a id="l-13-unused-error"></a>

## L-13：未使用的自定义错误

请考虑使用或移除未使用的自定义错误。

<details><summary>发现 1 处实例</summary>

- 发现位置：src/interfaces/ICanonicalV3Oracle.sol [第 28 行](../src/interfaces/ICanonicalV3Oracle.sol#L28)

	```solidity
	    error InvalidTick(int24 tick);
	```

</details>
