// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {
    AccessControlConfig,
    AssetSnapshot,
    DeploymentAssessment,
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
import {IUniswapV2Factory} from "../interfaces/IUniswapV2External.sol";
import {IUniswapV3Factory, IUniswapV3Pool} from "../interfaces/IUniswapV3External.sol";
import {IVaultComponentFactory} from "../interfaces/IVaultComponentFactory.sol";
import {IVaultControl} from "../interfaces/IVaultControl.sol";
import {VaultStrategyMath} from "../libraries/VaultStrategyMath.sol";
import {OracleSnapshot} from "../oracle/OracleTypes.sol";
import {SwapDirection, SwapPlan} from "../swap/SwapTypes.sol";

/// @title Adaptive LP Vault
/// @notice Dual-asset ERC-20 share vault that atomically coordinates one active Uniswap position.
/// @dev The vault orchestrates strategy inputs and accounting; the linked planner computes plans and adapters handle AMMs.
contract AdaptiveLPVault is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
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
    ICanonicalV3Oracle public immutable canonicalOracle;
    IUniswapV2Factory public immutable uniswapV2Factory;
    IUniswapV3Factory public immutable uniswapV3Factory;
    IVaultControl public immutable vaultControl;
    IControlledSwapExecutor public immutable swapExecutor;
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
    /// @notice Minimum healthy deployment ratio, derived once as BPS - maxHealthyIdleBps.
    uint256 public immutable minDeployBps;
    uint16 public immutable maxSwapSlippageBps;
    uint16 public immutable maxMigrationLossBps;

    bool public initialized;
    VenueType public activeVenue;
    uint32 public lastPositionChangeAt;
    uint64 public planVersion;

    PositionPlan private _lastExecutedPlan;

    struct PreMigrationSnapshot {
        VenueType previousVenue;
        int24 oldTickLower;
        int24 oldTickUpper;
        AssetSnapshot beforeAssets;
        uint256 navBefore;
    }

    struct AssessmentInputs {
        address adapter;
        address oracle;
        PositionPlan plan;
        uint256 amount0;
        uint256 amount1;
        uint256 dust0;
        uint256 dust1;
        uint256 minDeployBps;
        int24 twapTick;
    }

    struct OracleBinding {
        address pool;
        address token0;
        address token1;
        uint8 token0Decimals;
        uint8 token1Decimals;
    }

    /// @notice Creates a vault, derives its assets from the canonical oracle, and requests its dedicated components.
    constructor(
        string memory name_,
        string memory symbol_,
        VaultConfig memory vaultConfig,
        AccessControlConfig memory accessConfig,
        StrategyConfig memory strategyConfig
    ) ERC20(name_, symbol_) {
        _validateConstructorConfig(vaultConfig, strategyConfig);

        OracleBinding memory binding =
            _readAndValidateOracleBinding(vaultConfig.canonicalOracle, vaultConfig.uniswapV3Factory);

        token0 = binding.token0;
        token1 = binding.token1;
        token0Decimals = binding.token0Decimals;
        token1Decimals = binding.token1Decimals;

        dustTolerance0 = vaultConfig.dustTolerance0;
        dustTolerance1 = vaultConfig.dustTolerance1;
        canonicalOracle = ICanonicalV3Oracle(vaultConfig.canonicalOracle);
        uniswapV2Factory = IUniswapV2Factory(vaultConfig.uniswapV2Factory);
        uniswapV3Factory = IUniswapV3Factory(vaultConfig.uniswapV3Factory);
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
        minDeployBps = BPS - maxHealthyIdleBps;
        maxSwapSlippageBps = strategyConfig.maxSwapSlippageBps;
        maxMigrationLossBps = strategyConfig.maxMigrationLossBps;

        (IVaultControl control, IControlledSwapExecutor executor) = IVaultComponentFactory(vaultConfig.componentFactory)
            .deployComponents(
                accessConfig,
                binding.token0,
                binding.token1,
                vaultConfig.uniswapV2Factory,
                vaultConfig.uniswapV3Factory,
                binding.pool,
                vaultConfig.router
            );
        _validateComponentBindings(control, executor, binding, vaultConfig);
        vaultControl = control;
        swapExecutor = executor;
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function bootstrap(uint256 amount0, uint256 amount1, address receiver) external nonReentrant {
        _checkManager();
        if (initialized) revert IAdapterRegistry.AlreadyInitialized();
        if (amount0 == 0 || amount1 == 0) revert IAdaptiveLPVault.ZeroAmount();
        if (receiver == address(0)) revert ERC20InvalidReceiver(address(0));

        _validateConfiguredAdapters();
        _validateRangeWidths();
        _validateManagedV3PositionsEmpty();

        OracleSnapshot memory oracle = _healthyOracleSnapshot();
        PositionPlan memory plan = VaultStrategyMath.getPlan(_planInputs(oracle, _emptyPosition()));
        DeploymentAssessment memory assessment =
            _assessDeployment(_assessmentInputs(plan, amount0, amount1, oracle.twapTick));
        if (assessment.requiresSwap) revert IAdaptiveLPVault.SwapRequired();

        uint256 seedNav = _nav(amount0, amount1, oracle.twapTick);
        if (seedNav < minimumInitialNav) revert IAdaptiveLPVault.MinimumNavNotMet();
        uint256 grossInitialShares = Math.mulDiv(seedNav, 1e18, 10 ** uint256(token1Decimals));
        if (grossInitialShares <= minimumLockedShares) {
            revert IAdaptiveLPVault.InitialSharesTooLow(grossInitialShares, minimumLockedShares);
        }

        _pullExact(token0, _msgSender(), amount0);
        _pullExact(token1, _msgSender(), amount1);
        _mint(address(this), minimumLockedShares);
        _mint(receiver, grossInitialShares - minimumLockedShares);

        if (plan.targetVenue != VenueType.IDLE) {
            address adapter = _requireEnterEnabled(plan.targetVenue);
            _depositToAdapter(adapter, plan, amount0, amount1);
        }
        activeVenue = plan.targetVenue;

        (AssetSnapshot memory afterAssets, PositionSnapshot memory afterPosition) = _assetAndPositionSnapshot();
        _validateSingleActivePositions(plan.targetVenue, plan, afterPosition);
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
            emit IAdaptiveLPVault.V3RangeChanged(plan.planHash, 0, 0, plan.tickLower, plan.tickUpper);
        }
        emit IAdaptiveLPVault.VaultBootstrapped(
            _msgSender(), amount0, amount1, grossInitialShares, minimumLockedShares, plan.targetVenue
        );
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function deposit(uint256 amount0Max, uint256 amount1Max, uint256 minSharesOut, address receiver)
        external
        nonReentrant
        returns (uint256 amount0Used, uint256 amount1Used, uint256 sharesMinted)
    {
        _requireInitialized();
        if (amount0Max == 0 || amount1Max == 0) revert IAdaptiveLPVault.ZeroAmount();
        if (receiver == address(0)) revert ERC20InvalidReceiver(address(0));
        address adapter = vaultControl.requireDepositEnabled(activeVenue);

        OracleSnapshot memory oracle = _healthyOracleSnapshot();
        PositionSnapshot memory position = _synchronizeFees(adapter);
        AssetSnapshot memory beforeAssets = _assetSnapshotFromPosition(position);
        if (_isV3Venue(activeVenue) && ((position.principal0 == 0) != (position.principal1 == 0))) {
            revert IAdaptiveLPVault.ActivePositionSingleSided();
        }
        if (position.principal0 == 0 || position.principal1 == 0) {
            revert IAdaptiveLPVault.InvalidPositionPrincipal();
        }
        uint256 navBefore = _nav(beforeAssets.total0, beforeAssets.total1, oracle.twapTick);
        if (_idleBps(beforeAssets, oracle.twapTick, navBefore) > maxHealthyIdleBps) {
            revert IAdaptiveLPVault.IdleLimitExceeded();
        }

        (amount0Used, amount1Used) =
            _proportionalAmounts(amount0Max, amount1Max, position.principal0, position.principal1);
        if (amount0Used == 0 || amount1Used == 0) revert IAdaptiveLPVault.ZeroAmount();

        uint256 depositValue = _nav(amount0Used, amount1Used, oracle.twapTick);
        sharesMinted = Math.mulDiv(depositValue, beforeAssets.totalShares, navBefore);
        if (sharesMinted == 0) revert IAdaptiveLPVault.ZeroShares();
        if (sharesMinted < minSharesOut) revert IAdaptiveLPVault.SharesSlippage(sharesMinted, minSharesOut);

        _pullExact(token0, _msgSender(), amount0Used);
        _pullExact(token1, _msgSender(), amount1Used);
        _depositToAdapter(adapter, _lastExecutedPlan, amount0Used, amount1Used);

        (AssetSnapshot memory afterAssets, PositionSnapshot memory afterPosition) = _assetAndPositionSnapshot();
        _validateSingleActivePositions(activeVenue, _lastExecutedPlan, afterPosition);
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
        nonReentrant
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        _requireInitialized();
        if (shares == 0) revert IAdaptiveLPVault.ZeroAmount();
        if (receiver == address(0)) revert ERC20InvalidReceiver(address(0));
        if (owner == address(0)) revert ERC20InvalidSender(address(0));

        uint256 ownerBalance = balanceOf(owner);
        if (ownerBalance < shares) revert ERC20InsufficientBalance(owner, ownerBalance, shares);
        if (_msgSender() != owner) _spendAllowance(owner, _msgSender(), shares);

        address adapter = activeVenue == VenueType.IDLE ? address(0) : _getAdapterOrRevert(activeVenue);
        if (adapter != address(0)) _synchronizeFees(adapter);

        uint256 supply = totalSupply();
        uint256 idle0Before = IERC20(token0).balanceOf(address(this));
        uint256 idle1Before = IERC20(token1).balanceOf(address(this));
        amount0Out = Math.mulDiv(shares, idle0Before, supply);
        amount1Out = Math.mulDiv(shares, idle1Before, supply);
        if (activeVenue != VenueType.IDLE) {
            // Trusted adapters return the actual token balance increases received by the vault.
            (uint256 positionOut0, uint256 positionOut1) = IPositionAdapter(adapter).withdraw(shares, supply);
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
    function rebalance(bytes32 expectedPlanHash, uint32 deadline) external nonReentrant {
        _requireInitialized();
        _requireNotPaused(PauseFlag.PLAIN_REBALANCE);
        _requireDeadline(deadline);
        _requireCooldown();

        OracleSnapshot memory oracle = _healthyOracleSnapshot();
        (PositionPlan memory plan, DeploymentAssessment memory assessment, PositionSnapshot memory current) =
            _previewFromSnapshot(oracle);
        if (plan.planHash != expectedPlanHash || expectedPlanHash == bytes32(0)) {
            revert IAdaptiveLPVault.InvalidPlanHash();
        }
        if (!_hasStateChange(plan, current)) revert IAdaptiveLPVault.NoStateChangeRequired();
        if (assessment.requiresSwap) revert IAdaptiveLPVault.SwapRequired();

        PreMigrationSnapshot memory beforeMigration = _preMigrationSnapshot(oracle.twapTick, current);
        _exitActivePosition(current.adapter);

        if (plan.targetVenue != VenueType.IDLE) {
            address adapter = _requireEnterEnabled(plan.targetVenue);
            _depositToAdapter(
                adapter, plan, IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this))
            );
        }
        activeVenue = plan.targetVenue;

        (AssetSnapshot memory afterAssets, PositionSnapshot memory afterPosition) = _assetAndPositionSnapshot();
        _validateSingleActivePositions(plan.targetVenue, plan, afterPosition);
        uint256 finalNav;
        uint256 finalIdleBps;
        if (plan.targetVenue != VenueType.IDLE) {
            (finalNav, finalIdleBps) = _validateHealthyDeployment(afterAssets, oracle.twapTick);
        } else {
            finalNav = _nav(afterAssets.total0, afterAssets.total1, oracle.twapTick);
            finalIdleBps = _idleBps(afterAssets, oracle.twapTick, finalNav);
        }
        _requireConservation(
            beforeMigration.beforeAssets.total0,
            beforeMigration.beforeAssets.total1,
            afterAssets.total0,
            afterAssets.total1
        );

        _commitPlan(plan);
        _emitRebalanceEvents(plan, beforeMigration, afterAssets, finalNav, finalIdleBps, false);
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function rebalanceWithSwap(
        bytes32 expectedPlanHash,
        SwapDirection expectedDirection,
        uint256 amountIn,
        uint256 keeperMinAmountOut,
        uint32 deadline
    ) external nonReentrant {
        _checkManagerOrKeeper();
        _requireInitialized();
        _requireNotPaused(PauseFlag.SWAP_REBALANCE);
        _requireDeadline(deadline);
        _requireCooldown();
        if (amountIn == 0) revert IAdaptiveLPVault.ZeroAmount();

        OracleSnapshot memory oracle = _healthyOracleSnapshot();
        (PositionPlan memory plan, DeploymentAssessment memory assessment, PositionSnapshot memory current) =
            _previewFromSnapshot(oracle);
        if (plan.planHash != expectedPlanHash || expectedPlanHash == bytes32(0)) {
            revert IAdaptiveLPVault.InvalidPlanHash();
        }
        if (!_hasStateChange(plan, current)) revert IAdaptiveLPVault.NoStateChangeRequired();
        if (!assessment.requiresSwap) revert IAdaptiveLPVault.SwapNotAllowed();
        if (expectedDirection == SwapDirection.NONE || expectedDirection != assessment.direction) {
            revert IAdaptiveLPVault.InvalidSwapDirection();
        }
        if (plan.targetVenue == VenueType.IDLE) revert IAdaptiveLPVault.SwapNotAllowed();

        PreMigrationSnapshot memory beforeMigration = _preMigrationSnapshot(oracle.twapTick, current);
        _exitActivePosition(current.adapter);
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        _requireConservation(
            beforeMigration.beforeAssets.total0, beforeMigration.beforeAssets.total1, balance0, balance1
        );

        uint256 protocolMinOut = _protocolMinOut(expectedDirection, amountIn, oracle.twapTick);
        (uint256 simulated0, uint256 simulated1) =
            _simulatedSwapBalances(expectedDirection, amountIn, protocolMinOut, balance0, balance1);
        _validateSimulatedDeployment(
            _assessmentInputs(plan, simulated0, simulated1, oracle.twapTick), expectedDirection
        );

        uint256 minAmountOut = Math.max(protocolMinOut, keeperMinAmountOut);
        uint256 actualAmountOut = _executeControlledSwap(expectedDirection, amountIn, minAmountOut, deadline);

        address adapter = _requireEnterEnabled(plan.targetVenue);
        _depositToAdapter(
            adapter, plan, IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this))
        );
        activeVenue = plan.targetVenue;

        (AssetSnapshot memory afterAssets, PositionSnapshot memory afterPosition) = _assetAndPositionSnapshot();
        _validateSingleActivePositions(plan.targetVenue, plan, afterPosition);
        (uint256 finalNav, uint256 finalIdleBps) = _validateHealthyDeployment(afterAssets, oracle.twapTick);

        uint256 minimumNavAfter =
            Math.mulDiv(beforeMigration.navBefore, BPS - maxMigrationLossBps, BPS, Math.Rounding.Ceil);
        if (finalNav < minimumNavAfter) revert IAdaptiveLPVault.MigrationLossExceeded();
        _requireSwapConservation(
            expectedDirection,
            amountIn,
            actualAmountOut,
            beforeMigration.beforeAssets.total0,
            beforeMigration.beforeAssets.total1,
            afterAssets.total0,
            afterAssets.total1
        );

        _commitPlan(plan);
        _emitRebalanceEvents(plan, beforeMigration, afterAssets, finalNav, finalIdleBps, true);
    }

    /// @notice Implements the corresponding `IAdaptiveLPVault` operation.
    function emergencyExitToIdle() external nonReentrant {
        _checkManagerOrGuardian();
        _requireInitialized();

        VenueType previousVenue = activeVenue;
        if (previousVenue != VenueType.IDLE) {
            address adapter = _getAdapterOrRevert(previousVenue);
            PositionSnapshot memory position = _synchronizeFees(adapter);
            AssetSnapshot memory beforeAssets = _assetSnapshotFromPosition(position);
            _exitActivePosition(adapter);
            activeVenue = VenueType.IDLE;

            AssetSnapshot memory afterAssets = _assetSnapshot();
            _validateSingleActivePositions(VenueType.IDLE, _lastExecutedPlan, _emptyPosition());
            _requireConservation(beforeAssets.total0, beforeAssets.total1, afterAssets.total0, afterAssets.total1);
            if (planVersion == type(uint64).max) revert IAdaptiveLPVault.PlanVersionOverflow();
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
        (plan, assessment,) = _previewFromSnapshot(oracle);
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

    function _checkManager() private view {
        vaultControl.checkManager(_msgSender());
    }

    function _checkManagerOrGuardian() private view {
        vaultControl.checkManagerOrGuardian(_msgSender());
    }

    function _checkManagerOrKeeper() private view {
        vaultControl.checkManagerOrKeeper(_msgSender());
    }

    function _requireNotPaused(PauseFlag flag) private view {
        vaultControl.requireNotPaused(flag);
    }

    function _validateConfiguredAdapters() private view {
        vaultControl.validateConfiguredAdapters();
    }

    function _getAdapterOrRevert(VenueType venue) private view returns (address adapter) {
        return vaultControl.getAdapterOrRevert(venue);
    }

    function _requireEnterEnabled(VenueType venue) private view returns (address adapter) {
        return vaultControl.requireEnterEnabled(venue);
    }

    function _pauseAll(address caller) private {
        vaultControl.pauseAll(caller);
    }

    function _validateConstructorConfig(VaultConfig memory vaultConfig, StrategyConfig memory strategyConfig)
        private
        view
    {
        if (
            vaultConfig.canonicalOracle == address(0) || vaultConfig.canonicalOracle.code.length == 0
                || vaultConfig.componentFactory == address(0) || vaultConfig.componentFactory.code.length == 0
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

    function _validateComponentBindings(
        IVaultControl control,
        IControlledSwapExecutor executor,
        OracleBinding memory binding,
        VaultConfig memory vaultConfig
    ) private view {
        if (
            address(control) == address(0) || address(control).code.length == 0 || control.vault() != address(this)
                || control.token0() != binding.token0 || control.token1() != binding.token1
                || control.uniswapV2Factory() != vaultConfig.uniswapV2Factory
                || control.uniswapV3Factory() != vaultConfig.uniswapV3Factory
        ) revert IAdaptiveLPVault.InvalidControlBinding();

        if (
            address(executor) == address(0) || address(executor).code.length == 0 || executor.vault() != address(this)
                || executor.router() != vaultConfig.router || executor.swapPool() != binding.pool
                || executor.token0() != binding.token0 || executor.token1() != binding.token1
        ) revert IAdaptiveLPVault.InvalidSwapExecutorBinding();
    }

    function _validateRangeWidths() private view {
        (int24 lowSpacing, int24 highSpacing) = vaultControl.adapterTickSpacings();
        uint256 lowHalfWidth = uint256(narrowRangeHalfWidthSteps) * uint256(uint24(lowSpacing));
        uint256 highHalfWidth = uint256(wideRangeHalfWidthSteps) * uint256(uint24(highSpacing));
        if (lowHalfWidth >= highHalfWidth || highHalfWidth > uint256(uint24(MAX_TICK))) {
            revert IAdaptiveLPVault.InvalidTickRange();
        }
    }

    function _requireInitialized() private view {
        if (!initialized) revert IAdapterRegistry.NotInitialized();
    }

    function _healthyOracleSnapshot() private view returns (OracleSnapshot memory oracle) {
        oracle = canonicalOracle.snapshot();
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
        position = _activePositionSnapshot();
        assets = _assetSnapshotFromPosition(position);
    }

    /// @dev Uses a same-phase snapshot from the trusted adapter; reads current vault balances locally.
    function _assetSnapshotFromPosition(PositionSnapshot memory position)
        private
        view
        returns (AssetSnapshot memory assets)
    {
        assets.idle0 = IERC20(token0).balanceOf(address(this));
        assets.idle1 = IERC20(token1).balanceOf(address(this));
        assets.totalShares = totalSupply();
        assets.position0 = position.amount0;
        assets.position1 = position.amount1;
        assets.total0 = assets.idle0 + position.amount0;
        assets.total1 = assets.idle1 + position.amount1;
    }

    function _activePositionSnapshot() private view returns (PositionSnapshot memory position) {
        if (activeVenue == VenueType.IDLE) return _emptyPosition();
        address adapter = _getAdapterOrRevert(activeVenue);
        position = IPositionAdapter(adapter).snapshot();
    }

    function _emptyPosition() private pure returns (PositionSnapshot memory position) {
        position.venue = VenueType.IDLE;
    }

    /// @dev Returns the trusted adapter's post-collection position and requires claimable fees to be cleared.
    function _synchronizeFees(address adapter) private returns (PositionSnapshot memory position) {
        (uint256 fee0, uint256 fee1) = IPositionAdapter(adapter).syncFees();
        position = IPositionAdapter(adapter).snapshot();
        if (position.claimableFee0 != 0 || position.claimableFee1 != 0) {
            revert IAdaptiveLPVault.FeesNotCleared();
        }
        if (fee0 != 0 || fee1 != 0) {
            AssetSnapshot memory assets = _assetSnapshotFromPosition(position);
            emit IAdaptiveLPVault.FeesSynchronized(adapter, fee0, fee1, assets.total0, assets.total1);
        }
    }

    function _previewFromSnapshot(OracleSnapshot memory oracle)
        private
        view
        returns (PositionPlan memory plan, DeploymentAssessment memory assessment, PositionSnapshot memory current)
    {
        AssetSnapshot memory assets;
        (assets, current) = _assetAndPositionSnapshot();
        plan = VaultStrategyMath.getPlan(_planInputs(oracle, current));
        assessment = _assessDeployment(_assessmentInputs(plan, assets.total0, assets.total1, oracle.twapTick));
    }

    /// @notice Collects trusted chain state for the linked pure position planner.
    function _planInputs(OracleSnapshot memory oracle, PositionSnapshot memory currentPosition)
        private
        view
        returns (VaultStrategyMath.PlanInputs memory input)
    {
        (int24 lowSpacing, int24 highSpacing) = vaultControl.adapterTickSpacings();
        input = VaultStrategyMath.PlanInputs({
            oracle: oracle,
            currentPosition: currentPosition,
            strategy: _strategyConfig(),
            lastExecutedRegime: _lastExecutedPlan.marketRegime,
            activeVenue: activeVenue,
            lowSpacing: lowSpacing,
            highSpacing: highSpacing,
            planVersion: planVersion
        });
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
            oracle: address(canonicalOracle),
            plan: plan,
            amount0: amount0,
            amount1: amount1,
            dust0: dustTolerance0,
            dust1: dustTolerance1,
            minDeployBps: minDeployBps,
            twapTick: twapTick
        });
    }

    function _hasStateChange(PositionPlan memory plan, PositionSnapshot memory current) private view returns (bool) {
        if (plan.targetVenue != activeVenue) return true;
        if (!_isV3Venue(activeVenue)) return false;
        return current.tickLower != plan.tickLower || current.tickUpper != plan.tickUpper;
    }

    function _preMigrationSnapshot(int24 twapTick, PositionSnapshot memory current)
        private
        returns (PreMigrationSnapshot memory beforeMigration)
    {
        beforeMigration.previousVenue = activeVenue;
        if (_isV3Venue(activeVenue)) {
            beforeMigration.oldTickLower = current.tickLower;
            beforeMigration.oldTickUpper = current.tickUpper;
        }
        if (activeVenue == VenueType.IDLE) {
            beforeMigration.beforeAssets = _assetSnapshot();
        } else {
            PositionSnapshot memory synchronizedPosition = _synchronizeFees(current.adapter);
            beforeMigration.beforeAssets = _assetSnapshotFromPosition(synchronizedPosition);
        }
        beforeMigration.navBefore =
            _nav(beforeMigration.beforeAssets.total0, beforeMigration.beforeAssets.total1, twapTick);
    }

    /// @dev Ignores withdrawal return values; callers enforce conservation using fresh asset snapshots.
    function _exitActivePosition(address adapter) private {
        if (activeVenue == VenueType.IDLE) return;
        IPositionAdapter(adapter).withdrawAll();
        PositionSnapshot memory cleared = IPositionAdapter(adapter).snapshot();
        if (
            cleared.liquidity != 0 || cleared.amount0 != 0 || cleared.amount1 != 0 || cleared.claimableFee0 != 0
                || cleared.claimableFee1 != 0
        ) {
            revert IAdaptiveLPVault.PositionNotCleared();
        }
    }

    /// @dev The caller must resolve an enter-enabled adapter before depositing.
    function _depositToAdapter(address adapter, PositionPlan memory plan, uint256 amount0Max, uint256 amount1Max)
        private
    {
        uint256 before0 = IERC20(token0).balanceOf(address(this));
        uint256 before1 = IERC20(token1).balanceOf(address(this));
        if (amount0Max > before0 || amount1Max > before1) revert IAdaptiveLPVault.AdapterBalanceMismatch();
        if (amount0Max != 0) IERC20(token0).forceApprove(adapter, amount0Max);
        if (amount1Max != 0) IERC20(token1).forceApprove(adapter, amount1Max);
        (uint256 used0, uint256 used1,) = IPositionAdapter(adapter).deposit(amount0Max, amount1Max, plan);
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
        if (amountIn > inputBefore) revert SwapAmountExceeded();
        address executorAddress = address(swapExecutor);
        uint256 executorInput = IERC20(input).balanceOf(executorAddress);
        uint256 executorOutput = IERC20(output).balanceOf(executorAddress);
        IERC20(input).safeTransfer(executorAddress, amountIn);
        // The trusted executor measures the vault's actual output balance increase.
        actualAmountOut = swapExecutor.executeSwap(
            SwapPlan({direction: direction, amountIn: amountIn, minAmountOut: minAmountOut, deadline: deadline})
        );
        uint256 inputAfter = IERC20(input).balanceOf(address(this));
        if (inputAfter > inputBefore || inputBefore - inputAfter != amountIn) {
            revert IAdaptiveLPVault.SwapBalanceMismatch();
        }
        if (actualAmountOut < minAmountOut) {
            revert IControlledSwapExecutor.SwapSlippage(minAmountOut, actualAmountOut);
        }
        if (
            IERC20(input).balanceOf(executorAddress) != executorInput
                || IERC20(output).balanceOf(executorAddress) != executorOutput
        ) {
            revert IAdaptiveLPVault.SwapBalanceMismatch();
        }
        if (IERC20(input).allowance(executorAddress, swapExecutor.router()) != 0) {
            revert IAdaptiveLPVault.SwapAllowanceNotCleared();
        }
    }

    function _protocolMinOut(SwapDirection direction, uint256 amountIn, int24 twapTick)
        private
        view
        returns (uint256 protocolMinOut)
    {
        uint256 oracleQuote = direction == SwapDirection.ZERO_FOR_ONE
            ? canonicalOracle.quoteToken0InToken1(amountIn, twapTick, true)
            : canonicalOracle.quoteToken1InToken0(amountIn, twapTick, true);
        protocolMinOut = Math.mulDiv(oracleQuote, BPS - maxSwapSlippageBps, BPS, Math.Rounding.Ceil);
        if (protocolMinOut == 0) revert IAdaptiveLPVault.ZeroSwapOutput();
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
        PreMigrationSnapshot memory beforeMigration,
        AssetSnapshot memory afterAssets,
        uint256 finalNav,
        uint256 finalIdleBps,
        bool withSwap
    ) private {
        if (_isV3Venue(plan.targetVenue)) {
            emit IAdaptiveLPVault.V3RangeChanged(
                plan.planHash,
                beforeMigration.oldTickLower,
                beforeMigration.oldTickUpper,
                plan.tickLower,
                plan.tickUpper
            );
        }
        emit IAdaptiveLPVault.RebalanceExecuted(
            _msgSender(),
            plan.planHash,
            beforeMigration.previousVenue,
            plan.targetVenue,
            withSwap,
            afterAssets.total0,
            afterAssets.total1,
            finalNav,
            finalIdleBps
        );
    }

    /// @dev Final NAV values correspond to FinalNAV_1 and FinalDeployedNAV_1 in SWAP_REBALANE_MATH.md.
    function _validateHealthyDeployment(AssetSnapshot memory assets, int24 twapTick)
        private
        view
        returns (uint256 finalNav, uint256 finalIdleBps)
    {
        finalNav = _nav(assets.total0, assets.total1, twapTick);
        uint256 finalDeployedNav = _nav(assets.position0, assets.position1, twapTick);
        uint256 finalDeployBps = finalNav == 0 ? 0 : Math.mulDiv(finalDeployedNav, BPS, finalNav);
        if (finalNav == 0 || finalDeployBps < minDeployBps) {
            revert IAdaptiveLPVault.DeploymentRatioTooLow();
        }
        // With the same TWAP and rounding rules, finalDeployBps >= minDeployBps implies the final idle limit.
        finalIdleBps = _idleBps(assets, twapTick, finalNav);
    }

    /// @dev Validates the target position against the plan and requires non-active V3 positions to be empty.
    ///      Non-active V2 LP donations are excluded from the single-active-position constraint.
    function _validateSingleActivePositions(
        VenueType expectedVenue,
        PositionPlan memory plan,
        PositionSnapshot memory activePosition
    ) private view {
        if (expectedVenue == VenueType.UNISWAP_V2) {
            _validateActivePosition(expectedVenue, plan, activePosition);
        }
        // Keep the low/high validation order. Non-active V2 LP is an unrecognized donation.
        VenueType[2] memory venues = [VenueType.UNISWAP_V3_LOW_FEE, VenueType.UNISWAP_V3_HIGH_FEE];
        for (uint256 i; i < 2; ++i) {
            if (venues[i] == expectedVenue) {
                _validateActivePosition(expectedVenue, plan, activePosition);
            } else {
                PositionSnapshot memory position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot();
                if (position.liquidity != 0 || position.amount0 != 0 || position.amount1 != 0) {
                    revert IAdaptiveLPVault.ActivePositionExists();
                }
            }
        }
    }

    /// @dev Verifies position effectiveness and the requested V3 identifier/range.
    function _validateActivePosition(
        VenueType expectedVenue,
        PositionPlan memory plan,
        PositionSnapshot memory position
    ) private pure {
        if (position.liquidity == 0 && position.amount0 == 0 && position.amount1 == 0) {
            revert IAdaptiveLPVault.ActivePositionMissing();
        }
        if (_isV3Venue(expectedVenue)) {
            if (position.positionId == 0) revert IAdaptiveLPVault.InvalidPositionId();
            if (position.tickLower != plan.tickLower || position.tickUpper != plan.tickUpper) {
                revert IAdaptiveLPVault.PositionRangeMismatch();
            }
        }
    }

    function _validateManagedV3PositionsEmpty() private view {
        VenueType[2] memory venues = [VenueType.UNISWAP_V3_LOW_FEE, VenueType.UNISWAP_V3_HIGH_FEE];
        // V2 can receive LP before bootstrap; only V3 managed positions must start empty.
        for (uint256 i; i < 2; ++i) {
            PositionSnapshot memory position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot();
            if (position.liquidity != 0 || position.amount0 != 0 || position.amount1 != 0) {
                revert IAdaptiveLPVault.ActivePositionExists();
            }
        }
    }

    function _validateActivePositionAfterPartialExit() private view {
        PositionSnapshot memory position = _activePositionSnapshot();
        if (position.liquidity == 0) revert IAdaptiveLPVault.ActivePositionMissing();
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
        return amount1 + canonicalOracle.quoteToken0InToken1(amount0, twapTick, false);
    }

    function _idleBps(AssetSnapshot memory assets, int24 twapTick, uint256 totalNav) private view returns (uint256) {
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
        uint256 afterBalance = IERC20(token).balanceOf(address(this));
        if (afterBalance < beforeBalance || afterBalance - beforeBalance != amount) {
            revert IAdaptiveLPVault.TokenTransferMismatch(token, amount, beforeBalance, afterBalance);
        }
    }

    function _validateSimulatedDeployment(AssessmentInputs memory input, SwapDirection expectedDirection) private view {
        DeploymentAssessment memory simulatedAssessment = _assessDeployment(input);
        // A healthy simulatedDeployBps also guarantees simulatedIdleBps <= maxHealthyIdleBps.
        if (simulatedAssessment.requiresSwap) revert IAdaptiveLPVault.DeploymentRatioTooLow();
        if (simulatedAssessment.direction != SwapDirection.NONE && simulatedAssessment.direction != expectedDirection) {
            revert SwapAmountExceeded();
        }
    }

    /// @notice Assesses the target deployment using one adapter preview and the supplied TWAP tick.
    function _assessDeployment(AssessmentInputs memory input)
        private
        view
        returns (DeploymentAssessment memory assessment)
    {
        if (input.plan.targetVenue == VenueType.IDLE) {
            return DeploymentAssessment(false, SwapDirection.NONE);
        }
        (uint256 used0, uint256 used1) =
            IPositionAdapter(input.adapter).previewDeposit(input.amount0, input.amount1, input.plan);
        if (used0 > input.amount0 || used1 > input.amount1) revert IAdaptiveLPVault.AdapterBalanceMismatch();
        uint256 unused0 = input.amount0 - used0;
        uint256 unused1 = input.amount1 - used1;
        bool excess0 = unused0 > input.dust0;
        bool excess1 = unused1 > input.dust1;
        if (excess0 && excess1) revert IAdaptiveLPVault.InvalidDeploymentPreview();
        uint256 assessmentNav = _nav(input.amount0, input.amount1, input.twapTick);
        uint256 deployableNav = _nav(used0, used1, input.twapTick);
        // deployableBps is initialDeployBps for the initial assessment and simulatedDeployBps for swap simulation.
        uint256 deployableBps = assessmentNav == 0 ? 0 : Math.mulDiv(deployableNav, BPS, assessmentNav);
        assessment.requiresSwap = assessmentNav == 0 || deployableBps < input.minDeployBps;
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
        if (actual0 != binding.token0Decimals) {
            revert IAdaptiveLPVault.TokenDecimalsMismatch(binding.token0, binding.token0Decimals, actual0);
        }
        if (actual1 != binding.token1Decimals) {
            revert IAdaptiveLPVault.TokenDecimalsMismatch(binding.token1, binding.token1Decimals, actual1);
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
        if (block.timestamp > type(uint32).max) revert IAdaptiveLPVault.TimestampOverflow();
        timestamp = uint32(block.timestamp);
    }

    function _isV3Venue(VenueType venue) private pure returns (bool) {
        return venue == VenueType.UNISWAP_V3_LOW_FEE || venue == VenueType.UNISWAP_V3_HIGH_FEE;
    }
}
