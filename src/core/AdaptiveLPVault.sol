// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AdapterRegistry} from "./AdapterRegistry.sol";
import {VaultPause} from "./VaultPause.sol";
import {VaultRoles} from "./VaultRoles.sol";
import {
    AccessControlConfig,
    AssetSnapshot,
    DeploymentAssessment,
    MarketRegime,
    PauseFlag,
    PositionPlan,
    StrategyConfig,
    VaultConfig,
    VenueType
} from "./VaultTypes.sol";
import {PositionSnapshot} from "../adapters/AdapterTypes.sol";
import {IAdaptiveLPVault} from "../interfaces/IAdaptiveLPVault.sol";
import {IAdapterRegistry} from "../interfaces/IAdapterRegistry.sol";
import {ICanonicalV3Oracle} from "../interfaces/ICanonicalV3Oracle.sol";
import {IControlledSwapExecutor} from "../interfaces/IControlledSwapExecutor.sol";
import {IPositionAdapter} from "../interfaces/IPositionAdapter.sol";
import {IUniswapV3Factory, IUniswapV3Pool} from "../interfaces/IUniswapV3External.sol";
import {PositionPlanHash} from "../libraries/PositionPlanHash.sol";
import {OracleSnapshot} from "../oracle/OracleTypes.sol";
import {ControlledSwapExecutor} from "../swap/ControlledSwapExecutor.sol";
import {SwapDirection, SwapExecutorConfig, SwapPlan} from "../swap/SwapTypes.sol";

/// @title Adaptive LP Vault
/// @notice Dual-asset ERC-20 share vault that atomically coordinates one active Uniswap position.
/// @dev The vault deliberately keeps strategy and accounting decisions here while adapters encapsulate AMM mechanics.
contract AdaptiveLPVault is ERC20, AdapterRegistry, VaultPause {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = 887272;

    /// @notice Indicates that immutable deployment or strategy configuration is invalid.
    error InvalidConfiguration();

    /// @notice Indicates that an operation lost more of either underlying token than its permitted dust tolerance.
    error AssetConservationViolation();

    /// @notice Indicates that a proposed exact swap input is unavailable or over-corrects the inventory imbalance.
    error SwapAmountExceeded();

    address public immutable token0;
    address public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;

    uint256 public immutable dustTolerance0;
    uint256 public immutable dustTolerance1;
    address public immutable canonicalOracle;
    address public immutable uniswapV2Factory;
    address public immutable uniswapV3Factory;
    address public immutable swapExecutor;
    uint256 public immutable minimumLockedShares;
    uint256 public immutable minimumInitialNav;

    uint32 public immutable minRebalanceCooldown;
    uint24 public immutable enterMediumBps;
    uint24 public immutable exitMediumBps;
    uint24 public immutable enterHighBps;
    uint24 public immutable exitHighBps;
    uint24 public immutable enterExtremeBps;
    uint24 public immutable exitExtremeBps;
    uint24 public immutable narrowRangeHalfWidthSteps;
    uint24 public immutable wideRangeHalfWidthSteps;
    uint16 public immutable minRecenterBps;
    uint16 public immutable maxHealthyIdleBps;
    uint16 public immutable maxSwapSlippageBps;
    uint16 public immutable maxMigrationLossBps;

    bool public initialized;
    VenueType public activeVenue;
    uint32 public lastPositionChangeAt;
    uint64 public planVersion;

    PositionPlan private _lastExecutedPlan;
    uint256 private _reentrancyStatus = 1;

    struct MigrationState {
        VenueType previousVenue;
        int24 oldTickLower;
        int24 oldTickUpper;
        AssetSnapshot beforeAssets;
        uint256 navBefore;
    }

    struct PlanInputs {
        OracleSnapshot oracle;
        PositionSnapshot currentPosition;
        StrategyConfig strategy;
        PositionPlan lastPlan;
        VenueType activeVenue;
        int24 lowSpacing;
        int24 highSpacing;
        uint64 planVersion;
    }

    struct AssessmentInputs {
        address adapter;
        address oracle;
        PositionPlan plan;
        uint256 amount0;
        uint256 amount1;
        uint256 dust0;
        uint256 dust1;
        uint16 maxIdleBps;
        int24 twapTick;
    }

    struct OracleBinding {
        address pool;
        address token0;
        address token1;
        uint8 token0Decimals;
        uint8 token1Decimals;
    }

    modifier nonReentrantVault() {
        if (_reentrancyStatus != 1) revert IAdaptiveLPVault.Reentrancy();
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    /// @notice Creates a vault, derives its asset identity from the canonical oracle, and creates its private swap executor.
    constructor(
        string memory name_,
        string memory symbol_,
        VaultConfig memory vaultConfig,
        AccessControlConfig memory accessConfig,
        StrategyConfig memory strategyConfig
    ) ERC20(name_, symbol_) VaultRoles(accessConfig) {
        _validateConstructorConfig(vaultConfig, strategyConfig);

        OracleBinding memory binding =
            _readAndValidateOracleBinding(vaultConfig.canonicalOracle, vaultConfig.uniswapV3Factory);

        token0 = binding.token0;
        token1 = binding.token1;
        token0Decimals = binding.token0Decimals;
        token1Decimals = binding.token1Decimals;

        dustTolerance0 = vaultConfig.dustTolerance0;
        dustTolerance1 = vaultConfig.dustTolerance1;
        canonicalOracle = vaultConfig.canonicalOracle;
        uniswapV2Factory = vaultConfig.uniswapV2Factory;
        uniswapV3Factory = vaultConfig.uniswapV3Factory;
        minimumLockedShares = vaultConfig.minimumLockedShares;
        minimumInitialNav = vaultConfig.minimumInitialNav;

        minRebalanceCooldown = strategyConfig.minRebalanceCooldown;
        enterMediumBps = strategyConfig.enterMediumBps;
        exitMediumBps = strategyConfig.exitMediumBps;
        enterHighBps = strategyConfig.enterHighBps;
        exitHighBps = strategyConfig.exitHighBps;
        enterExtremeBps = strategyConfig.enterExtremeBps;
        exitExtremeBps = strategyConfig.exitExtremeBps;
        narrowRangeHalfWidthSteps = strategyConfig.narrowRangeHalfWidthSteps;
        wideRangeHalfWidthSteps = strategyConfig.wideRangeHalfWidthSteps;
        minRecenterBps = strategyConfig.minRecenterBps;
        maxHealthyIdleBps = strategyConfig.maxHealthyIdleBps;
        maxSwapSlippageBps = strategyConfig.maxSwapSlippageBps;
        maxMigrationLossBps = strategyConfig.maxMigrationLossBps;

        ControlledSwapExecutor executor = new ControlledSwapExecutor(
            SwapExecutorConfig({
                vault: address(this),
                router: vaultConfig.router,
                swapPool: binding.pool,
                factory: vaultConfig.uniswapV3Factory
            })
        );
        if (
            executor.vault() != address(this) || executor.swapPool() != binding.pool
                || executor.token0() != binding.token0 || executor.token1() != binding.token1
        ) revert IAdapterRegistry.InvalidSwapPool();
        swapExecutor = address(executor);
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function bootstrap(uint256 amount0, uint256 amount1, address receiver) external nonReentrantVault {
        _checkManager();
        if (initialized) revert AlreadyInitialized();
        if (amount0 == 0 || amount1 == 0) revert IAdaptiveLPVault.ZeroAmount();

        _validateConfiguredAdapters();
        _validateRangeWidths();
        _validateExecutorBinding();
        _validateAllPositionsEmpty();

        OracleSnapshot memory oracle = _healthyOracleSnapshot();
        AssetSnapshot memory seedAssets = AssetSnapshot({
            idle0: amount0, idle1: amount1, position0: 0, position1: 0, total0: amount0, total1: amount1, totalShares: 0
        });
        PositionPlan memory plan = _getPlan(oracle, seedAssets, _emptyPosition());
        DeploymentAssessment memory assessment = _assessDeployment(plan, amount0, amount1, oracle.twapTick);
        if (assessment.requiresSwap) revert IAdaptiveLPVault.SwapRequired();

        uint256 seedNav = _nav(amount0, amount1, oracle.twapTick);
        if (seedNav < minimumInitialNav) revert IAdaptiveLPVault.MinimumNavNotMet();
        uint256 grossInitialShares = Math.mulDiv(seedNav, 1e18, 10 ** uint256(token1Decimals));
        if (grossInitialShares <= minimumLockedShares) revert IAdaptiveLPVault.MinimumNavNotMet();

        _pullExact(token0, _msgSender(), amount0);
        _pullExact(token1, _msgSender(), amount1);
        _mint(address(this), minimumLockedShares);
        _mint(receiver, grossInitialShares - minimumLockedShares);

        if (plan.targetVenue != VenueType.IDLE) {
            _deployToAdapter(plan, amount0, amount1);
        }
        activeVenue = plan.targetVenue;

        AssetSnapshot memory afterAssets = _assetSnapshot();
        _validatePositionTopology(plan.targetVenue, plan);
        if (plan.targetVenue != VenueType.IDLE) {
            _validateHealthyDeployment(afterAssets, oracle.twapTick);
        }
        _requireConservation(amount0, amount1, afterAssets.total0, afterAssets.total1);

        planVersion = plan.version;
        _lastExecutedPlan = plan;
        lastPositionChangeAt = _timestamp32();
        initialized = true;

        emit IAdaptiveLPVault.PositionPlanCommitted(plan.planHash, plan.version, plan.targetVenue, plan.marketRegime);
        if (_isV3Venue(plan.targetVenue)) {
            PositionSnapshot memory established = _activePositionSnapshot();
            emit IAdaptiveLPVault.V3RangeChanged(plan.planHash, 0, 0, established.tickLower, established.tickUpper);
        }
        emit IAdaptiveLPVault.VaultBootstrapped(
            _msgSender(), amount0, amount1, grossInitialShares, minimumLockedShares, plan.targetVenue
        );
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function deposit(uint256 amount0Max, uint256 amount1Max, uint256 minSharesOut, address receiver)
        external
        nonReentrantVault
        returns (uint256 amount0Used, uint256 amount1Used, uint256 sharesMinted)
    {
        _requireInitialized();
        _requireNotPaused(PauseFlag.DEPOSIT);
        if (activeVenue == VenueType.IDLE) revert AdapterDisabled();
        address adapter = _requireEnterEnabled(activeVenue);

        OracleSnapshot memory oracle = _healthyOracleSnapshot();
        _synchronizeFees();

        (AssetSnapshot memory beforeAssets, PositionSnapshot memory position) = _assetAndPositionSnapshot();
        if (beforeAssets.total0 == 0 || beforeAssets.total1 == 0) revert IAdaptiveLPVault.ZeroAmount();
        if (_isV3Venue(activeVenue) && (position.principal0 == 0 || position.principal1 == 0)) {
            revert IAdaptiveLPVault.ActivePositionSingleSided();
        }
        if (position.principal0 == 0 || position.principal1 == 0) revert IAdaptiveLPVault.ZeroAmount();
        if (_idleBps(beforeAssets, oracle.twapTick) > maxHealthyIdleBps) revert IAdaptiveLPVault.IdleLimitExceeded();

        (amount0Used, amount1Used) =
            _proportionalAmounts(amount0Max, amount1Max, position.principal0, position.principal1);
        if (amount0Used == 0 || amount1Used == 0) revert IAdaptiveLPVault.ZeroAmount();

        uint256 navBefore = _nav(beforeAssets.total0, beforeAssets.total1, oracle.twapTick);
        uint256 depositValue = _nav(amount0Used, amount1Used, oracle.twapTick);
        sharesMinted = Math.mulDiv(depositValue, beforeAssets.totalShares, navBefore);
        if (sharesMinted == 0) revert IAdaptiveLPVault.ZeroAmount();
        if (sharesMinted < minSharesOut) revert IAdaptiveLPVault.SharesSlippage(sharesMinted, minSharesOut);

        _pullExact(token0, _msgSender(), amount0Used);
        _pullExact(token1, _msgSender(), amount1Used);
        _approveAdapterAndDeposit(adapter, _lastExecutedPlan, amount0Used, amount1Used);

        AssetSnapshot memory afterAssets = _assetSnapshot();
        _validatePositionTopology(activeVenue, _lastExecutedPlan);
        _validateHealthyDeployment(afterAssets, oracle.twapTick);
        _requireConservation(
            beforeAssets.total0 + amount0Used, beforeAssets.total1 + amount1Used, afterAssets.total0, afterAssets.total1
        );

        _mint(receiver, sharesMinted);
        emit IAdaptiveLPVault.Deposit(_msgSender(), receiver, amount0Used, amount1Used, sharesMinted);
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function redeem(uint256 shares, uint256 minAmount0Out, uint256 minAmount1Out, address receiver, address owner)
        external
        nonReentrantVault
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        _requireInitialized();
        if (shares == 0) revert IAdaptiveLPVault.ZeroAmount();

        uint256 ownerBalance = balanceOf(owner);
        if (ownerBalance < shares) revert ERC20InsufficientBalance(owner, ownerBalance, shares);
        if (_msgSender() != owner) _spendAllowance(owner, _msgSender(), shares);

        if (activeVenue != VenueType.IDLE) _synchronizeFees();

        uint256 supply = totalSupply();
        address adapter = activeVenue == VenueType.IDLE ? address(0) : _getAdapterOrRevert(activeVenue);
        uint256 idle0Before = IERC20(token0).balanceOf(address(this));
        uint256 idle1Before = IERC20(token1).balanceOf(address(this));
        amount0Out = Math.mulDiv(shares, idle0Before, supply);
        amount1Out = Math.mulDiv(shares, idle1Before, supply);
        if (activeVenue != VenueType.IDLE) {
            (uint256 reported0, uint256 reported1) = IPositionAdapter(adapter).withdraw(shares, supply);
            uint256 positionOut0 = IERC20(token0).balanceOf(address(this)) - idle0Before;
            uint256 positionOut1 = IERC20(token1).balanceOf(address(this)) - idle1Before;
            if (reported0 != positionOut0 || reported1 != positionOut1) {
                revert IAdaptiveLPVault.AdapterBalanceMismatch();
            }
            amount0Out += positionOut0;
            amount1Out += positionOut1;
        }
        if (amount0Out < minAmount0Out || amount1Out < minAmount1Out) {
            revert IAdaptiveLPVault.AssetSlippage(amount0Out, amount1Out);
        }

        _burn(owner, shares);
        IERC20(token0).safeTransfer(receiver, amount0Out);
        IERC20(token1).safeTransfer(receiver, amount1Out);

        if (activeVenue != VenueType.IDLE) _validateActivePositionAfterPartialExit();
        emit IAdaptiveLPVault.Redeem(_msgSender(), receiver, owner, shares, amount0Out, amount1Out);
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function rebalance(bytes32 expectedPlanHash, uint32 deadline) external nonReentrantVault {
        _requireInitialized();
        _requireNotPaused(PauseFlag.PLAIN_REBALANCE);
        _requireDeadline(deadline);
        _requireCooldown();

        OracleSnapshot memory oracle = _healthyOracleSnapshot();
        (PositionPlan memory plan, DeploymentAssessment memory assessment) = _previewFromSnapshot(oracle);
        if (plan.planHash != expectedPlanHash || expectedPlanHash == bytes32(0)) {
            revert IAdaptiveLPVault.InvalidPlanHash();
        }
        if (!_hasStateChange(plan)) revert IAdaptiveLPVault.NoStateChangeRequired();
        if (assessment.requiresSwap) revert IAdaptiveLPVault.SwapRequired();

        MigrationState memory migration = _prepareMigration(oracle.twapTick);
        _exitActivePosition();

        if (plan.targetVenue != VenueType.IDLE) {
            _deployToAdapter(plan, IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
        }
        activeVenue = plan.targetVenue;

        AssetSnapshot memory afterAssets = _assetSnapshot();
        _validatePositionTopology(plan.targetVenue, plan);
        if (plan.targetVenue != VenueType.IDLE) _validateHealthyDeployment(afterAssets, oracle.twapTick);
        _requireConservation(
            migration.beforeAssets.total0, migration.beforeAssets.total1, afterAssets.total0, afterAssets.total1
        );

        _commitPlan(plan);
        _emitRebalanceEvents(plan, migration, afterAssets, oracle.twapTick, false);
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function rebalanceWithSwap(
        bytes32 expectedPlanHash,
        SwapDirection expectedDirection,
        uint256 amountIn,
        uint256 keeperMinAmountOut,
        uint32 deadline
    ) external nonReentrantVault {
        _checkManagerOrKeeper();
        _requireInitialized();
        _requireNotPaused(PauseFlag.SWAP_REBALANCE);
        _requireDeadline(deadline);
        _requireCooldown();

        OracleSnapshot memory oracle = _healthyOracleSnapshot();
        (PositionPlan memory plan, DeploymentAssessment memory assessment) = _previewFromSnapshot(oracle);
        if (plan.planHash != expectedPlanHash || expectedPlanHash == bytes32(0)) {
            revert IAdaptiveLPVault.InvalidPlanHash();
        }
        if (!_hasStateChange(plan)) revert IAdaptiveLPVault.NoStateChangeRequired();
        if (!assessment.requiresSwap) revert IAdaptiveLPVault.SwapNotAllowed();
        if (expectedDirection == SwapDirection.NONE || expectedDirection != assessment.direction) {
            revert IAdaptiveLPVault.InvalidSwapDirection();
        }
        if (amountIn == 0 || plan.targetVenue == VenueType.IDLE) revert IAdaptiveLPVault.SwapNotAllowed();

        MigrationState memory migration = _prepareMigration(oracle.twapTick);
        _exitActivePosition();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        _requireConservation(migration.beforeAssets.total0, migration.beforeAssets.total1, balance0, balance1);

        uint256 protocolMinOut = _protocolMinOut(expectedDirection, amountIn, oracle.twapTick);
        (uint256 simulated0, uint256 simulated1) =
            _simulatedSwapBalances(expectedDirection, amountIn, protocolMinOut, balance0, balance1);
        _validateSimulatedDeployment(
            _assessmentInputs(plan, simulated0, simulated1, oracle.twapTick), expectedDirection
        );

        uint256 minAmountOut = Math.max(protocolMinOut, keeperMinAmountOut);
        uint256 actualAmountOut = _executeControlledSwap(expectedDirection, amountIn, minAmountOut, deadline);

        _deployToAdapter(plan, IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
        activeVenue = plan.targetVenue;

        AssetSnapshot memory afterAssets = _assetSnapshot();
        _validatePositionTopology(plan.targetVenue, plan);
        _validateHealthyDeployment(afterAssets, oracle.twapTick);

        uint256 navAfter = _nav(afterAssets.total0, afterAssets.total1, oracle.twapTick);
        uint256 minimumNavAfter = Math.mulDiv(migration.navBefore, BPS - maxMigrationLossBps, BPS, Math.Rounding.Ceil);
        if (navAfter < minimumNavAfter) revert IAdaptiveLPVault.MigrationLossExceeded();
        _requireSwapConservation(
            expectedDirection,
            amountIn,
            actualAmountOut,
            migration.beforeAssets.total0,
            migration.beforeAssets.total1,
            afterAssets.total0,
            afterAssets.total1
        );

        _commitPlan(plan);
        _emitRebalanceEvents(plan, migration, afterAssets, oracle.twapTick, true);
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function emergencyExitToIdle() external nonReentrantVault {
        _checkManagerOrGuardian();
        _requireInitialized();

        VenueType previousVenue = activeVenue;
        if (previousVenue != VenueType.IDLE) {
            _synchronizeFees();
            AssetSnapshot memory beforeAssets = _assetSnapshot();
            _exitActivePosition();
            activeVenue = VenueType.IDLE;

            AssetSnapshot memory afterAssets = _assetSnapshot();
            _validatePositionTopology(VenueType.IDLE, _lastExecutedPlan);
            _requireConservation(beforeAssets.total0, beforeAssets.total1, afterAssets.total0, afterAssets.total1);
            if (planVersion == type(uint64).max) revert InvalidConfiguration();
            unchecked {
                ++planVersion;
            }
            emit IAdaptiveLPVault.EmergencyExit(_msgSender(), previousVenue, afterAssets.idle0, afterAssets.idle1);
        }

        _pauseAll(_msgSender());
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function previewRebalance()
        external
        view
        returns (PositionPlan memory plan, DeploymentAssessment memory assessment)
    {
        _requireInitialized();
        OracleSnapshot memory oracle = _healthyOracleSnapshot();
        return _previewFromSnapshot(oracle);
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function totalAssets() external view returns (uint256 total0, uint256 total1) {
        AssetSnapshot memory assets = _assetSnapshot();
        return (assets.total0, assets.total1);
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function assetSnapshot() external view returns (AssetSnapshot memory assets) {
        return _assetSnapshot();
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function lastExecutedPlan() external view returns (PositionPlan memory plan) {
        return _lastExecutedPlan;
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /// @inheritdoc VaultRoles
    function supportsInterface(bytes4 interfaceId) public view override(VaultRoles) returns (bool) {
        return interfaceId == type(IAdaptiveLPVault).interfaceId || super.supportsInterface(interfaceId);
    }

    function _vaultInitialized() internal view override(AdapterRegistry, VaultPause) returns (bool) {
        return initialized;
    }

    function _registryToken0() internal view override returns (address) {
        return token0;
    }

    function _registryToken1() internal view override returns (address) {
        return token1;
    }

    function _registryV2Factory() internal view override returns (address) {
        return uniswapV2Factory;
    }

    function _registryV3Factory() internal view override returns (address) {
        return uniswapV3Factory;
    }

    function _validateConstructorConfig(VaultConfig memory vaultConfig, StrategyConfig memory strategyConfig)
        private
        view
    {
        if (
            vaultConfig.canonicalOracle == address(0) || vaultConfig.canonicalOracle.code.length == 0
                || vaultConfig.router == address(0) || vaultConfig.router.code.length == 0
                || vaultConfig.uniswapV2Factory == address(0) || vaultConfig.uniswapV2Factory.code.length == 0
                || vaultConfig.uniswapV3Factory == address(0) || vaultConfig.uniswapV3Factory.code.length == 0
                || vaultConfig.minimumLockedShares == 0 || vaultConfig.minimumInitialNav == 0
        ) revert InvalidConfiguration();

        if (
            strategyConfig.narrowRangeHalfWidthSteps == 0 || strategyConfig.wideRangeHalfWidthSteps == 0
                || strategyConfig.exitMediumBps >= strategyConfig.enterMediumBps
                || strategyConfig.enterMediumBps > strategyConfig.exitHighBps
                || strategyConfig.exitHighBps >= strategyConfig.enterHighBps
                || strategyConfig.enterHighBps > strategyConfig.exitExtremeBps
                || strategyConfig.exitExtremeBps >= strategyConfig.enterExtremeBps
                || strategyConfig.enterExtremeBps > BPS || strategyConfig.minRecenterBps > BPS
                || strategyConfig.maxHealthyIdleBps >= BPS || strategyConfig.maxSwapSlippageBps >= BPS
                || strategyConfig.maxMigrationLossBps >= BPS
        ) revert InvalidConfiguration();
    }

    function _validateRangeWidths() private view {
        uint256 lowHalfWidth =
            uint256(narrowRangeHalfWidthSteps) * uint256(uint24(_adapterTickSpacing(VenueType.UNISWAP_V3_LOW_FEE)));
        uint256 highHalfWidth =
            uint256(wideRangeHalfWidthSteps) * uint256(uint24(_adapterTickSpacing(VenueType.UNISWAP_V3_HIGH_FEE)));
        if (lowHalfWidth >= highHalfWidth || highHalfWidth > uint256(uint24(MAX_TICK))) {
            revert IAdaptiveLPVault.InvalidTickRange();
        }
    }

    function _validateExecutorBinding() private view {
        IControlledSwapExecutor executor = IControlledSwapExecutor(swapExecutor);
        if (
            executor.vault() != address(this) || executor.router() == address(0)
                || executor.swapPool() != ICanonicalV3Oracle(canonicalOracle).canonicalPool()
                || executor.token0() != token0 || executor.token1() != token1
        ) revert IAdapterRegistry.InvalidSwapPool();
    }

    function _requireInitialized() private view {
        if (!initialized) revert NotInitialized();
    }

    function _healthyOracleSnapshot() private view returns (OracleSnapshot memory oracle) {
        oracle = ICanonicalV3Oracle(canonicalOracle).snapshot();
        if (!oracle.healthy) revert IAdaptiveLPVault.OracleUnhealthy();
    }

    function _assetSnapshot() private view returns (AssetSnapshot memory assets) {
        (assets,) = _assetAndPositionSnapshot();
    }

    function _assetAndPositionSnapshot()
        private
        view
        returns (AssetSnapshot memory assets, PositionSnapshot memory position)
    {
        assets.idle0 = IERC20(token0).balanceOf(address(this));
        assets.idle1 = IERC20(token1).balanceOf(address(this));
        assets.totalShares = totalSupply();
        position = _activePositionSnapshot();
        assets.position0 = position.amount0;
        assets.position1 = position.amount1;
        assets.total0 = assets.idle0 + assets.position0;
        assets.total1 = assets.idle1 + assets.position1;
    }

    function _activePositionSnapshot() private view returns (PositionSnapshot memory position) {
        if (activeVenue == VenueType.IDLE) {
            position.venue = VenueType.IDLE;
            return position;
        }
        address adapter = _getAdapterOrRevert(activeVenue);
        position = IPositionAdapter(adapter).snapshot();
        if (position.venue != activeVenue || position.adapter != adapter) {
            revert IAdaptiveLPVault.PositionNotCleared();
        }
        if (
            position.amount0 != position.principal0 + position.claimableFee0
                || position.amount1 != position.principal1 + position.claimableFee1
        ) revert IAdaptiveLPVault.AdapterBalanceMismatch();
    }

    function _emptyPosition() private pure returns (PositionSnapshot memory position) {
        position.venue = VenueType.IDLE;
    }

    function _synchronizeFees() private {
        if (activeVenue == VenueType.IDLE) return;
        address adapter = _getAdapterOrRevert(activeVenue);
        (uint256 fee0, uint256 fee1) = IPositionAdapter(adapter).syncFees();
        PositionSnapshot memory position = IPositionAdapter(adapter).snapshot();
        if (position.claimableFee0 != 0 || position.claimableFee1 != 0) {
            revert IAdaptiveLPVault.PositionNotCleared();
        }
        if (fee0 != 0 || fee1 != 0) {
            AssetSnapshot memory assets = _assetSnapshot();
            emit IAdaptiveLPVault.FeesSynchronized(adapter, fee0, fee1, assets.total0, assets.total1);
        }
    }

    function _previewFromSnapshot(OracleSnapshot memory oracle)
        private
        view
        returns (PositionPlan memory plan, DeploymentAssessment memory assessment)
    {
        (AssetSnapshot memory assets, PositionSnapshot memory current) = _assetAndPositionSnapshot();
        plan = _getPlan(oracle, assets, current);
        assessment = _assessDeployment(plan, assets.total0, assets.total1, oracle.twapTick);
    }

    function _getPlan(OracleSnapshot memory oracle, AssetSnapshot memory, PositionSnapshot memory currentPosition)
        private
        view
        returns (PositionPlan memory plan)
    {
        PlanInputs memory input = PlanInputs({
            oracle: oracle,
            currentPosition: currentPosition,
            strategy: _strategyConfig(),
            lastPlan: _lastExecutedPlan,
            activeVenue: activeVenue,
            lowSpacing: _adapterTickSpacing(VenueType.UNISWAP_V3_LOW_FEE),
            highSpacing: _adapterTickSpacing(VenueType.UNISWAP_V3_HIGH_FEE),
            planVersion: planVersion
        });
        MarketRegime regime =
            _nextRegime(input.oracle.deviationBps, input.planVersion, input.lastPlan.marketRegime, input.strategy);
        VenueType targetVenue = _venueForRegime(regime);
        int24 tickLower;
        int24 tickUpper;
        if (_isV3Venue(targetVenue)) {
            int24 spacing = targetVenue == VenueType.UNISWAP_V3_LOW_FEE ? input.lowSpacing : input.highSpacing;
            uint24 steps = regime == MarketRegime.LOW_DEVIATION
                ? input.strategy.narrowRangeHalfWidthSteps
                : input.strategy.wideRangeHalfWidthSteps;
            (tickLower, tickUpper) = _targetRange(input.oracle.twapTick, spacing, steps);
            if (input.activeVenue == targetVenue && input.currentPosition.liquidity != 0) {
                int256 currentWidth = int256(input.currentPosition.tickUpper) - int256(input.currentPosition.tickLower);
                int256 targetWidth = int256(tickUpper) - int256(tickLower);
                bool widthChanged = currentWidth != targetWidth;
                bool spotOutside = input.oracle.spotTick < input.currentPosition.tickLower
                    || input.oracle.spotTick >= input.currentPosition.tickUpper;
                int256 oldCenter = int256(input.currentPosition.tickLower) + currentWidth / 2;
                int256 newCenter = int256(tickLower) + targetWidth / 2;
                uint256 delta = uint256(oldCenter >= newCenter ? oldCenter - newCenter : newCenter - oldCenter);
                uint256 threshold = Math.mulDiv(uint256(currentWidth / 2), input.strategy.minRecenterBps, BPS);
                if (!widthChanged && !(spotOutside && delta >= threshold)) {
                    tickLower = input.currentPosition.tickLower;
                    tickUpper = input.currentPosition.tickUpper;
                }
            }
        }
        if (input.planVersion == type(uint64).max) revert IAdaptiveLPVault.InvalidTickRange();
        plan = PositionPlan({
            planHash: bytes32(0),
            targetVenue: targetVenue,
            marketRegime: regime,
            tickLower: tickLower,
            tickUpper: tickUpper,
            version: input.planVersion + 1
        });
        plan.planHash = PositionPlanHash.compute(plan);
    }

    function _strategyConfig() private view returns (StrategyConfig memory config) {
        config = StrategyConfig({
            minRebalanceCooldown: minRebalanceCooldown,
            enterMediumBps: enterMediumBps,
            exitMediumBps: exitMediumBps,
            enterHighBps: enterHighBps,
            exitHighBps: exitHighBps,
            enterExtremeBps: enterExtremeBps,
            exitExtremeBps: exitExtremeBps,
            narrowRangeHalfWidthSteps: narrowRangeHalfWidthSteps,
            wideRangeHalfWidthSteps: wideRangeHalfWidthSteps,
            minRecenterBps: minRecenterBps,
            maxHealthyIdleBps: maxHealthyIdleBps,
            maxSwapSlippageBps: maxSwapSlippageBps,
            maxMigrationLossBps: maxMigrationLossBps
        });
    }

    function _assessmentInputs(PositionPlan memory plan, uint256 amount0, uint256 amount1, int24 twapTick)
        private
        view
        returns (AssessmentInputs memory input)
    {
        address adapter = plan.targetVenue == VenueType.IDLE ? address(0) : _requireEnterEnabled(plan.targetVenue);
        input = AssessmentInputs({
            adapter: adapter,
            oracle: canonicalOracle,
            plan: plan,
            amount0: amount0,
            amount1: amount1,
            dust0: dustTolerance0,
            dust1: dustTolerance1,
            maxIdleBps: maxHealthyIdleBps,
            twapTick: twapTick
        });
    }

    function _assessDeployment(PositionPlan memory plan, uint256 amount0, uint256 amount1, int24 twapTick)
        private
        view
        returns (DeploymentAssessment memory assessment)
    {
        (assessment,,,) = _assessDeploymentWithUnused(_assessmentInputs(plan, amount0, amount1, twapTick));
    }

    function _hasStateChange(PositionPlan memory plan) private view returns (bool) {
        if (plan.targetVenue != activeVenue) return true;
        if (!_isV3Venue(activeVenue)) return false;
        PositionSnapshot memory current = _activePositionSnapshot();
        return current.tickLower != plan.tickLower || current.tickUpper != plan.tickUpper;
    }

    function _prepareMigration(int24 twapTick) private returns (MigrationState memory migration) {
        migration.previousVenue = activeVenue;
        if (_isV3Venue(activeVenue)) {
            PositionSnapshot memory oldPosition = _activePositionSnapshot();
            migration.oldTickLower = oldPosition.tickLower;
            migration.oldTickUpper = oldPosition.tickUpper;
        }
        _synchronizeFees();
        migration.beforeAssets = _assetSnapshot();
        migration.navBefore = _nav(migration.beforeAssets.total0, migration.beforeAssets.total1, twapTick);
    }

    function _exitActivePosition() private {
        if (activeVenue == VenueType.IDLE) return;
        address adapter = _getAdapterOrRevert(activeVenue);
        uint256 before0 = IERC20(token0).balanceOf(address(this));
        uint256 before1 = IERC20(token1).balanceOf(address(this));
        (uint256 reported0, uint256 reported1) = IPositionAdapter(adapter).withdrawAll();
        if (
            reported0 != IERC20(token0).balanceOf(address(this)) - before0
                || reported1 != IERC20(token1).balanceOf(address(this)) - before1
        ) {
            revert IAdaptiveLPVault.AdapterBalanceMismatch();
        }
        PositionSnapshot memory cleared = IPositionAdapter(adapter).snapshot();
        if (
            cleared.liquidity != 0 || cleared.amount0 != 0 || cleared.amount1 != 0 || cleared.claimableFee0 != 0
                || cleared.claimableFee1 != 0
        ) {
            revert IAdaptiveLPVault.PositionNotCleared();
        }
    }

    function _deployToAdapter(PositionPlan memory plan, uint256 amount0Max, uint256 amount1Max) private {
        _approveAdapterAndDeposit(_requireEnterEnabled(plan.targetVenue), plan, amount0Max, amount1Max);
    }

    function _approveAdapterAndDeposit(
        address adapter,
        PositionPlan memory plan,
        uint256 amount0Max,
        uint256 amount1Max
    ) private returns (uint256 used0, uint256 used1) {
        uint256 before0 = IERC20(token0).balanceOf(address(this));
        uint256 before1 = IERC20(token1).balanceOf(address(this));
        if (amount0Max > before0 || amount1Max > before1) revert IAdaptiveLPVault.AdapterBalanceMismatch();
        if (amount0Max != 0) IERC20(token0).forceApprove(adapter, amount0Max);
        if (amount1Max != 0) IERC20(token1).forceApprove(adapter, amount1Max);
        (used0, used1,) = IPositionAdapter(adapter).deposit(amount0Max, amount1Max, plan);
        if (amount0Max != 0) IERC20(token0).forceApprove(adapter, 0);
        if (amount1Max != 0) IERC20(token1).forceApprove(adapter, 0);
        uint256 after0 = IERC20(token0).balanceOf(address(this));
        uint256 after1 = IERC20(token1).balanceOf(address(this));
        if (
            used0 > amount0Max || used1 > amount1Max || after0 > before0 || after1 > before1
                || before0 - after0 != used0 || before1 - after1 != used1
        ) {
            revert IAdaptiveLPVault.AdapterBalanceMismatch();
        }
    }

    function _executeControlledSwap(SwapDirection direction, uint256 amountIn, uint256 minAmountOut, uint32 deadline)
        private
        returns (uint256 actualAmountOut)
    {
        address input = direction == SwapDirection.ZERO_FOR_ONE ? token0 : token1;
        address output = direction == SwapDirection.ZERO_FOR_ONE ? token1 : token0;
        uint256 inputBefore = IERC20(input).balanceOf(address(this));
        uint256 outputBefore = IERC20(output).balanceOf(address(this));
        if (amountIn > inputBefore) revert IAdaptiveLPVault.SwapNotAllowed();
        uint256 executorInput = IERC20(input).balanceOf(swapExecutor);
        uint256 executorOutput = IERC20(output).balanceOf(swapExecutor);
        IERC20(input).safeTransfer(swapExecutor, amountIn);
        uint256 reported = IControlledSwapExecutor(swapExecutor)
            .executeSwap(
                SwapPlan({direction: direction, amountIn: amountIn, minAmountOut: minAmountOut, deadline: deadline})
            );
        uint256 inputAfter = IERC20(input).balanceOf(address(this));
        uint256 outputAfter = IERC20(output).balanceOf(address(this));
        actualAmountOut = outputAfter - outputBefore;
        if (inputBefore - inputAfter != amountIn || reported != actualAmountOut || actualAmountOut < minAmountOut) {
            revert IAdaptiveLPVault.AdapterBalanceMismatch();
        }
        if (
            IERC20(input).balanceOf(swapExecutor) != executorInput
                || IERC20(output).balanceOf(swapExecutor) != executorOutput
                || IERC20(input).allowance(swapExecutor, IControlledSwapExecutor(swapExecutor).router()) != 0
        ) {
            revert IAdaptiveLPVault.AdapterBalanceMismatch();
        }
    }

    function _protocolMinOut(SwapDirection direction, uint256 amountIn, int24 twapTick)
        private
        view
        returns (uint256 protocolMinOut)
    {
        uint256 oracleQuote = direction == SwapDirection.ZERO_FOR_ONE
            ? ICanonicalV3Oracle(canonicalOracle).quoteToken0InToken1(amountIn, twapTick, true)
            : ICanonicalV3Oracle(canonicalOracle).quoteToken1InToken0(amountIn, twapTick, true);
        protocolMinOut = Math.mulDiv(oracleQuote, BPS - maxSwapSlippageBps, BPS, Math.Rounding.Ceil);
        if (protocolMinOut == 0) revert IAdaptiveLPVault.SwapNotAllowed();
    }

    function _simulatedSwapBalances(
        SwapDirection direction,
        uint256 amountIn,
        uint256 amountOut,
        uint256 balance0,
        uint256 balance1
    ) private pure returns (uint256 simulated0, uint256 simulated1) {
        if (direction == SwapDirection.ZERO_FOR_ONE) {
            if (amountIn > balance0) {
                revert SwapAmountExceeded();
            }
            return (balance0 - amountIn, balance1 + amountOut);
        }
        if (direction == SwapDirection.ONE_FOR_ZERO) {
            if (amountIn > balance1) revert SwapAmountExceeded();
            return (balance0 + amountOut, balance1 - amountIn);
        }
        revert IAdaptiveLPVault.InvalidSwapDirection();
    }

    function _commitPlan(PositionPlan memory plan) private {
        planVersion = plan.version;
        _lastExecutedPlan = plan;
        lastPositionChangeAt = _timestamp32();
        emit IAdaptiveLPVault.PositionPlanCommitted(plan.planHash, plan.version, plan.targetVenue, plan.marketRegime);
    }

    function _emitRebalanceEvents(
        PositionPlan memory plan,
        MigrationState memory migration,
        AssetSnapshot memory afterAssets,
        int24 twapTick,
        bool withSwap
    ) private {
        if (_isV3Venue(plan.targetVenue)) {
            PositionSnapshot memory established = _activePositionSnapshot();
            emit IAdaptiveLPVault.V3RangeChanged(
                plan.planHash,
                migration.oldTickLower,
                migration.oldTickUpper,
                established.tickLower,
                established.tickUpper
            );
        }
        emit IAdaptiveLPVault.RebalanceExecuted(
            _msgSender(),
            plan.planHash,
            migration.previousVenue,
            plan.targetVenue,
            withSwap,
            afterAssets.total0,
            afterAssets.total1,
            _nav(afterAssets.total0, afterAssets.total1, twapTick),
            _idleBps(afterAssets, twapTick)
        );
    }

    function _validateHealthyDeployment(AssetSnapshot memory assets, int24 twapTick) private view {
        uint256 totalNav = _nav(assets.total0, assets.total1, twapTick);
        uint256 deployedNav = _nav(assets.position0, assets.position1, twapTick);
        if (totalNav == 0 || Math.mulDiv(deployedNav, BPS, totalNav) < BPS - maxHealthyIdleBps) {
            revert IAdaptiveLPVault.DeploymentRatioTooLow();
        }
        if (_idleBps(assets, twapTick) > maxHealthyIdleBps) revert IAdaptiveLPVault.IdleLimitExceeded();
    }

    function _adapterAddresses() private view returns (address[3] memory adapters) {
        adapters[0] = _getAdapterOrRevert(VenueType.UNISWAP_V2);
        adapters[1] = _getAdapterOrRevert(VenueType.UNISWAP_V3_LOW_FEE);
        adapters[2] = _getAdapterOrRevert(VenueType.UNISWAP_V3_HIGH_FEE);
    }

    function _validatePositionTopology(VenueType expectedVenue, PositionPlan memory plan) private view {
        address[3] memory adapters = _adapterAddresses();
        VenueType[3] memory venues = [VenueType.UNISWAP_V2, VenueType.UNISWAP_V3_LOW_FEE, VenueType.UNISWAP_V3_HIGH_FEE];
        for (uint256 i; i < 3; ++i) {
            PositionSnapshot memory position = IPositionAdapter(adapters[i]).snapshot();
            bool effective = position.liquidity != 0 || position.amount0 != 0 || position.amount1 != 0;
            if (venues[i] == expectedVenue) {
                if (!effective || position.venue != expectedVenue || position.adapter != adapters[i]) {
                    revert IAdaptiveLPVault.PositionNotCleared();
                }
                if (
                    _isV3Venue(expectedVenue)
                        && (position.positionId == 0
                            || position.tickLower != plan.tickLower
                            || position.tickUpper != plan.tickUpper)
                ) {
                    revert IAdaptiveLPVault.InvalidTickRange();
                }
            } else if (effective) {
                revert IAdaptiveLPVault.ActivePositionExists();
            }
        }
    }

    function _validateAllPositionsEmpty() private view {
        address[3] memory adapters = _adapterAddresses();
        for (uint256 i; i < 3; ++i) {
            PositionSnapshot memory position = IPositionAdapter(adapters[i]).snapshot();
            if (position.liquidity != 0 || position.amount0 != 0 || position.amount1 != 0) {
                revert IAdaptiveLPVault.ActivePositionExists();
            }
        }
    }

    function _validateActivePositionAfterPartialExit() private view {
        PositionSnapshot memory position = _activePositionSnapshot();
        if (position.liquidity == 0) revert IAdaptiveLPVault.PositionNotCleared();
    }

    function _requireConservation(uint256 before0, uint256 before1, uint256 after0, uint256 after1) private view {
        if (
            (before0 > after0 && before0 - after0 > dustTolerance0)
                || (before1 > after1 && before1 - after1 > dustTolerance1)
        ) {
            revert AssetConservationViolation();
        }
    }

    function _requireSwapConservation(
        SwapDirection direction,
        uint256 amountIn,
        uint256 amountOut,
        uint256 before0,
        uint256 before1,
        uint256 after0,
        uint256 after1
    ) private view {
        uint256 expected0;
        uint256 expected1;
        if (direction == SwapDirection.ZERO_FOR_ONE) {
            if (amountIn > before0) revert SwapAmountExceeded();
            expected0 = before0 - amountIn;
            expected1 = before1 + amountOut;
        } else {
            if (amountIn > before1) revert SwapAmountExceeded();
            expected0 = before0 + amountOut;
            expected1 = before1 - amountIn;
        }
        _requireConservation(expected0, expected1, after0, after1);
    }

    function _nav(uint256 amount0, uint256 amount1, int24 twapTick) private view returns (uint256) {
        return amount1 + ICanonicalV3Oracle(canonicalOracle).quoteToken0InToken1(amount0, twapTick, false);
    }

    function _idleBps(AssetSnapshot memory assets, int24 twapTick) private view returns (uint256) {
        uint256 totalNav = _nav(assets.total0, assets.total1, twapTick);
        return totalNav == 0 ? BPS : Math.mulDiv(_nav(assets.idle0, assets.idle1, twapTick), BPS, totalNav);
    }

    function _proportionalAmounts(uint256 amount0Max, uint256 amount1Max, uint256 principal0, uint256 principal1)
        private
        pure
        returns (uint256 amount0Used, uint256 amount1Used)
    {
        (uint256 high0, uint256 low0) = Math.mul512(amount0Max, principal1);
        (uint256 high1, uint256 low1) = Math.mul512(amount1Max, principal0);
        if (high0 < high1 || (high0 == high1 && low0 <= low1)) {
            return (amount0Max, Math.mulDiv(amount0Max, principal1, principal0));
        }
        return (Math.mulDiv(amount1Max, principal0, principal1), amount1Max);
    }

    function _pullExact(address token, address from, uint256 amount) private {
        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(from, address(this), amount);
        if (IERC20(token).balanceOf(address(this)) - beforeBalance != amount) {
            revert IAdaptiveLPVault.AdapterBalanceMismatch();
        }
    }

    function _nextRegime(uint256 deviation, uint64 version, MarketRegime previous, StrategyConfig memory config)
        private
        pure
        returns (MarketRegime)
    {
        if (version == 0) {
            if (deviation >= config.enterExtremeBps) return MarketRegime.EXTREME_DEVIATION;
            if (deviation >= config.enterHighBps) return MarketRegime.HIGH_DEVIATION;
            if (deviation >= config.enterMediumBps) return MarketRegime.MEDIUM_DEVIATION;
            return MarketRegime.LOW_DEVIATION;
        }
        if (previous == MarketRegime.LOW_DEVIATION) {
            return deviation >= config.enterMediumBps ? MarketRegime.MEDIUM_DEVIATION : previous;
        }
        if (previous == MarketRegime.MEDIUM_DEVIATION) {
            if (deviation <= config.exitMediumBps) return MarketRegime.LOW_DEVIATION;
            if (deviation >= config.enterHighBps) return MarketRegime.HIGH_DEVIATION;
            return previous;
        }
        if (previous == MarketRegime.HIGH_DEVIATION) {
            if (deviation <= config.exitHighBps) return MarketRegime.MEDIUM_DEVIATION;
            if (deviation >= config.enterExtremeBps) return MarketRegime.EXTREME_DEVIATION;
            return previous;
        }
        return deviation <= config.exitExtremeBps ? MarketRegime.HIGH_DEVIATION : previous;
    }

    function _venueForRegime(MarketRegime regime) private pure returns (VenueType) {
        if (regime == MarketRegime.LOW_DEVIATION) return VenueType.UNISWAP_V3_LOW_FEE;
        if (regime == MarketRegime.MEDIUM_DEVIATION) return VenueType.UNISWAP_V3_HIGH_FEE;
        if (regime == MarketRegime.HIGH_DEVIATION) return VenueType.UNISWAP_V2;
        return VenueType.IDLE;
    }

    function _targetRange(int24 twapTick, int24 spacing, uint24 steps)
        private
        pure
        returns (int24 lowerTick, int24 upperTick)
    {
        if (spacing <= 0 || steps == 0) revert IAdaptiveLPVault.InvalidTickRange();
        int256 s = int256(spacing);
        int256 tick = int256(twapTick);
        int256 quotient = tick / s;
        int256 remainder = tick % s;
        if (remainder < 0) --quotient;
        int256 lowerCenter = quotient * s;
        int256 center = (tick - lowerCenter) * 2 <= s ? lowerCenter : lowerCenter + s;
        int256 halfWidth = int256(uint256(steps)) * s;
        int256 lower = center - halfWidth;
        int256 upper = center + halfWidth;
        if (lower < MIN_TICK || upper > MAX_TICK || lower >= upper || lower > tick || upper < tick) {
            revert IAdaptiveLPVault.InvalidTickRange();
        }
        lowerTick = int24(lower);
        upperTick = int24(upper);
    }

    function _validateSimulatedDeployment(AssessmentInputs memory input, SwapDirection expectedDirection) private view {
        (DeploymentAssessment memory assessment, uint256 unused0, uint256 unused1, uint256 totalNav) =
            _assessDeploymentWithUnused(input);
        if (assessment.requiresSwap) revert IAdaptiveLPVault.DeploymentRatioTooLow();
        if (assessment.direction != SwapDirection.NONE && assessment.direction != expectedDirection) {
            revert SwapAmountExceeded();
        }
        if (Math.mulDiv(_nav(unused0, unused1, input.twapTick), BPS, totalNav) > input.maxIdleBps) {
            revert IAdaptiveLPVault.IdleLimitExceeded();
        }
    }

    function _assessDeploymentWithUnused(AssessmentInputs memory input)
        private
        view
        returns (DeploymentAssessment memory assessment, uint256 unused0, uint256 unused1, uint256 totalNav)
    {
        if (input.plan.targetVenue == VenueType.IDLE) {
            return (DeploymentAssessment(false, SwapDirection.NONE), 0, 0, 0);
        }
        (uint256 used0, uint256 used1) =
            IPositionAdapter(input.adapter).previewDeposit(input.amount0, input.amount1, input.plan);
        if (used0 > input.amount0 || used1 > input.amount1) revert IAdaptiveLPVault.AdapterBalanceMismatch();
        unused0 = input.amount0 - used0;
        unused1 = input.amount1 - used1;
        bool excess0 = unused0 > input.dust0;
        bool excess1 = unused1 > input.dust1;
        if (excess0 && excess1) revert IAdaptiveLPVault.DeploymentRatioTooLow();
        totalNav = _nav(input.amount0, input.amount1, input.twapTick);
        uint256 deployedNav = _nav(used0, used1, input.twapTick);
        assessment.requiresSwap = totalNav == 0 || Math.mulDiv(deployedNav, BPS, totalNav) < BPS - input.maxIdleBps;
        assessment.direction =
            excess0 ? SwapDirection.ZERO_FOR_ONE : excess1 ? SwapDirection.ONE_FOR_ZERO : SwapDirection.NONE;
    }

    function _readAndValidateOracleBinding(address oracleAddress, address expectedFactory)
        private
        view
        returns (OracleBinding memory binding)
    {
        ICanonicalV3Oracle oracle = ICanonicalV3Oracle(oracleAddress);
        try oracle.canonicalPool() returns (address value) {
            binding.pool = value;
        } catch {
            revert IAdapterRegistry.InvalidSwapPool();
        }
        try oracle.token0() returns (address value) {
            binding.token0 = value;
        } catch {
            revert IAdapterRegistry.InvalidAssetPair();
        }
        try oracle.token1() returns (address value) {
            binding.token1 = value;
        } catch {
            revert IAdapterRegistry.InvalidAssetPair();
        }
        try oracle.token0Decimals() returns (uint8 value) {
            binding.token0Decimals = value;
        } catch {
            revert IAdaptiveLPVault.InvalidTokenMetadata(binding.token0);
        }
        try oracle.token1Decimals() returns (uint8 value) {
            binding.token1Decimals = value;
        } catch {
            revert IAdaptiveLPVault.InvalidTokenMetadata(binding.token1);
        }

        if (binding.pool == address(0) || binding.pool.code.length == 0) {
            revert IAdapterRegistry.InvalidSwapPool();
        }
        if (
            binding.token0 == address(0) || binding.token1 == address(0) || binding.token0 == binding.token1
                || binding.token0 >= binding.token1
        ) {
            revert IAdaptiveLPVault.InvalidTokenOrder();
        }
        if (binding.token0.code.length == 0 || binding.token1.code.length == 0) {
            revert IAdapterRegistry.InvalidAssetPair();
        }
        if (binding.token0Decimals > 18) {
            revert IAdaptiveLPVault.InvalidTokenDecimals(binding.token0, binding.token0Decimals);
        }
        if (binding.token1Decimals > 18) {
            revert IAdaptiveLPVault.InvalidTokenDecimals(binding.token1, binding.token1Decimals);
        }

        IUniswapV3Pool pool = IUniswapV3Pool(binding.pool);
        address poolFactory;
        address poolToken0;
        address poolToken1;
        uint24 poolFee;
        try pool.factory() returns (address value) {
            poolFactory = value;
        } catch {
            revert IAdapterRegistry.InvalidSwapPool();
        }
        try pool.token0() returns (address value) {
            poolToken0 = value;
        } catch {
            revert IAdapterRegistry.InvalidSwapPool();
        }
        try pool.token1() returns (address value) {
            poolToken1 = value;
        } catch {
            revert IAdapterRegistry.InvalidSwapPool();
        }
        try pool.fee() returns (uint24 value) {
            poolFee = value;
        } catch {
            revert IAdapterRegistry.InvalidSwapPool();
        }
        if (
            poolFactory != expectedFactory || poolToken0 != binding.token0 || poolToken1 != binding.token1
                || poolFee == 0
        ) {
            revert IAdapterRegistry.InvalidSwapPool();
        }
        try IUniswapV3Factory(expectedFactory).getPool(binding.token0, binding.token1, poolFee) returns (
            address registered
        ) {
            if (registered != binding.pool) revert IAdapterRegistry.InvalidSwapPool();
        } catch {
            revert IAdapterRegistry.InvalidSwapPool();
        }

        uint8 actual0 = _readTokenDecimals(binding.token0);
        uint8 actual1 = _readTokenDecimals(binding.token1);
        if (actual0 != binding.token0Decimals || actual1 != binding.token1Decimals) {
            revert IAdapterRegistry.InvalidAssetPair();
        }
    }

    function _readTokenDecimals(address token) private view returns (uint8 value) {
        try IERC20Metadata(token).decimals() returns (uint8 actual) {
            value = actual;
        } catch {
            revert IAdaptiveLPVault.InvalidTokenMetadata(token);
        }
        if (value > 18) revert IAdaptiveLPVault.InvalidTokenDecimals(token, value);
    }

    function _requireDeadline(uint32 deadline) private view {
        if (deadline == 0 || block.timestamp > deadline) revert IAdaptiveLPVault.DeadlineExpired();
    }

    function _requireCooldown() private view {
        uint256 availableAt = uint256(lastPositionChangeAt) + minRebalanceCooldown;
        if (block.timestamp < availableAt) revert IAdaptiveLPVault.CooldownActive(availableAt);
    }

    function _timestamp32() private view returns (uint32 timestamp) {
        if (block.timestamp > type(uint32).max) revert InvalidConfiguration();
        timestamp = uint32(block.timestamp);
    }

    function _isV3Venue(VenueType venue) private pure returns (bool) {
        return venue == VenueType.UNISWAP_V3_LOW_FEE || venue == VenueType.UNISWAP_V3_HIGH_FEE;
    }
}
