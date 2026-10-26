// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VaultStrategyMath} from "../../src/libraries/VaultStrategyMath.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";

import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {AdaptiveLPVault} from "../../src/core/AdaptiveLPVault.sol";
import {VaultComponentFactory} from "../../src/core/VaultComponentFactory.sol";
import {VaultControl} from "../../src/control/VaultControl.sol";
import {
    AccessControlConfig,
    DeploymentAssessment,
    PositionPlan,
    StrategyConfig,
    VaultConfig,
    VenueType
} from "../../src/core/VaultTypes.sol";
import {IAdapterRegistry} from "../../src/interfaces/IAdapterRegistry.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";
import {IControlledSwapExecutor} from "../../src/interfaces/IControlledSwapExecutor.sol";
import {IVaultComponentFactory} from "../../src/interfaces/IVaultComponentFactory.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {OracleSnapshot} from "../../src/oracle/OracleTypes.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";

contract AssessmentToken is ERC20 {
    constructor() ERC20("Assessment Token", "AT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Provides a deterministic rounded valuation while keeping the real vault orchestration under test.
contract AssessmentOracle {
    address public immutable canonicalPool;
    address public immutable token0;
    address public immutable token1;
    uint8 public constant token0Decimals = 18;
    uint8 public constant token1Decimals = 18;
    uint256 public quoteDivisor = 1;
    OracleSnapshot private _snapshot;

    constructor(address pool, address token0_, address token1_) {
        canonicalPool = pool;
        token0 = token0_;
        token1 = token1_;
        setDeviation(1000);
    }

    function setDeviation(uint256 deviation) public {
        _snapshot.healthy = true;
        _snapshot.deviationBps = deviation;
        _snapshot.twapTick = 17;
    }

    function setQuoteDivisor(uint256 divisor) external {
        quoteDivisor = divisor;
    }

    function snapshot() external view returns (OracleSnapshot memory) {
        return _snapshot;
    }

    function quoteToken0InToken1(uint256 amount, int24, bool roundUp) external view returns (uint256) {
        return amount / quoteDivisor + (roundUp && amount % quoteDivisor != 0 ? 1 : 0);
    }
}

contract AdaptiveLPVaultAssessmentTest is Test {
    AdaptiveLPVault private vault;
    AssessmentOracle private oracle;
    AssessmentToken private token0;
    AssessmentToken private token1;
    address private v2Adapter;
    address private lowAdapter;
    address private highAdapter;
    VaultConfig private vaultConfig;
    StrategyConfig private strategyConfig;

    function setUp() public {
        AssessmentToken a = new AssessmentToken();
        AssessmentToken b = new AssessmentToken();
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);
        address v2Factory = _endpoint("assessment v2 factory");
        address v3Factory = _endpoint("assessment v3 factory");
        address router = _endpoint("assessment router");
        address lowPool = _pool("assessment low pool", v3Factory, 500);
        _mockAddress(router, "factory()", v3Factory);
        vm.mockCall(
            v3Factory,
            abi.encodeWithSignature("getPool(address,address,uint24)", address(token0), address(token1), uint24(500)),
            abi.encode(lowPool)
        );
        oracle = new AssessmentOracle(lowPool, address(token0), address(token1));
        VaultConfig memory config = VaultConfig({
            dustTolerance0: 1,
            dustTolerance1: 1,
            canonicalOracle: address(oracle),
            componentFactory: address(new VaultComponentFactory()),
            router: router,
            uniswapV2Factory: v2Factory,
            uniswapV3Factory: v3Factory,
            minimumLockedShares: 1,
            minimumInitialNav: 1
        });
        StrategyConfig memory strategy = StrategyConfig({
            minRebalanceCooldown: 0,
            enterMediumBps: 100,
            exitMediumBps: 50,
            enterHighBps: 300,
            exitHighBps: 200,
            enterExtremeBps: 500,
            exitExtremeBps: 400,
            narrowRangeHalfWidthSteps: 10,
            wideRangeHalfWidthSteps: 10,
            minRecenterBps: 100,
            maxHealthyIdleBps: 500,
            maxSwapSlippageBps: 100,
            maxMigrationLossBps: 100
        });
        vaultConfig = config;
        strategyConfig = strategy;
        vault = new AdaptiveLPVault("Assessment Vault", "AV", config, AccessControlConfig(0, address(this)), strategy);
        VaultControl control = VaultControl(address(vault.vaultControl()));
        control.grantRole(control.MANAGER_ROLE(), address(this));
        address v2Pool = _pool("assessment v2 pool", v2Factory, 0);
        address highPool = _pool("assessment high pool", v3Factory, 3000);
        vm.mockCall(
            v2Factory,
            abi.encodeWithSignature("getPair(address,address)", address(token0), address(token1)),
            abi.encode(v2Pool)
        );
        vm.mockCall(
            v3Factory,
            abi.encodeWithSignature("getPool(address,address,uint24)", address(token0), address(token1), uint24(3000)),
            abi.encode(highPool)
        );
        v2Adapter = _adapter("assessment v2 adapter", VenueType.UNISWAP_V2, v2Pool, 0, 0);
        lowAdapter = _adapter("assessment low adapter", VenueType.UNISWAP_V3_LOW_FEE, lowPool, 500, 10);
        highAdapter = _adapter("assessment high adapter", VenueType.UNISWAP_V3_HIGH_FEE, highPool, 3000, 60);
        token0.mint(address(this), 1000);
        token1.mint(address(this), 1000);
        token0.approve(address(vault), 1000);
        token1.approve(address(vault), 1000);
        vault.bootstrap(1000, 1000, address(this));
        // EXTREME history transitions to HIGH, selecting V2 while the assets remain in IDLE.
        oracle.setDeviation(0);
    }

    function test_constructorReportsInvalidControlBinding() public {
        vm.mockCall(
            vaultConfig.componentFactory,
            abi.encodeWithSelector(IVaultComponentFactory.deployComponents.selector),
            abi.encode(address(0), address(0))
        );
        vm.expectRevert(IAdaptiveLPVault.InvalidControlBinding.selector);
        new AdaptiveLPVault("Invalid Vault", "IV", vaultConfig, AccessControlConfig(0, address(this)), strategyConfig);
    }

    function test_constructorReportsInvalidExecutorBinding() public {
        address control = _endpoint("invalid executor control");
        address nextVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        _mockAddress(control, "vault()", nextVault);
        _mockAddress(control, "token0()", address(token0));
        _mockAddress(control, "token1()", address(token1));
        _mockAddress(control, "uniswapV2Factory()", vaultConfig.uniswapV2Factory);
        _mockAddress(control, "uniswapV3Factory()", vaultConfig.uniswapV3Factory);
        vm.mockCall(
            vaultConfig.componentFactory,
            abi.encodeWithSelector(IVaultComponentFactory.deployComponents.selector),
            abi.encode(control, address(0))
        );
        vm.expectRevert(IAdaptiveLPVault.InvalidSwapExecutorBinding.selector);
        new AdaptiveLPVault("Invalid Vault", "IV", vaultConfig, AccessControlConfig(0, address(this)), strategyConfig);
    }

    function test_constructorReportsOracleTokenDecimalsMismatch() public {
        vm.mockCall(address(oracle), abi.encodeWithSignature("token0Decimals()"), abi.encode(uint8(17)));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAdaptiveLPVault.TokenDecimalsMismatch.selector, address(token0), uint8(17), uint8(18)
            )
        );
        new AdaptiveLPVault("Invalid Vault", "IV", vaultConfig, AccessControlConfig(0, address(this)), strategyConfig);
    }

    function test_constructorReportsToken1DecimalsMismatch() public {
        vm.mockCall(address(oracle), abi.encodeWithSignature("token1Decimals()"), abi.encode(uint8(17)));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAdaptiveLPVault.TokenDecimalsMismatch.selector, address(token1), uint8(17), uint8(18)
            )
        );
        new AdaptiveLPVault("Invalid Vault", "IV", vaultConfig, AccessControlConfig(0, address(this)), strategyConfig);
    }

    function test_planUsesConstructorPackedStrategyAndPreservesPublicConfig() public {
        uint256 packed = uint256(strategyConfig.enterMediumBps) | (uint256(strategyConfig.exitMediumBps) << 24)
            | (uint256(strategyConfig.enterHighBps) << 48) | (uint256(strategyConfig.exitHighBps) << 72)
            | (uint256(strategyConfig.enterExtremeBps) << 96) | (uint256(strategyConfig.exitExtremeBps) << 120)
            | (uint256(strategyConfig.narrowRangeHalfWidthSteps) << 144)
            | (uint256(strategyConfig.wideRangeHalfWidthSteps) << 168) | (uint256(strategyConfig.minRecenterBps) << 192);
        VaultStrategyMath.PlanInputs memory input;
        input.oracle = VaultStrategyMath.PlanOracleInputs({deviationBps: 0, twapTick: 17, spotTick: 0});
        input.strategy = packed;
        input.lastExecutedRegime = vault.lastExecutedPlan().marketRegime;
        input.activeVenue = vault.activeVenue();
        input.lowSpacing = 10;
        input.highSpacing = 60;
        input.planVersion = vault.planVersion();
        _previewUses(1000, 1000);
        vm.expectCall(
            address(VaultStrategyMath), abi.encodeWithSelector(VaultStrategyMath.getPlan.selector, input), uint64(1)
        );
        vault.previewRebalance();
        assertEq(vault.enterMediumBps(), strategyConfig.enterMediumBps);
        assertEq(vault.exitMediumBps(), strategyConfig.exitMediumBps);
        assertEq(vault.enterHighBps(), strategyConfig.enterHighBps);
        assertEq(vault.exitHighBps(), strategyConfig.exitHighBps);
        assertEq(vault.enterExtremeBps(), strategyConfig.enterExtremeBps);
        assertEq(vault.exitExtremeBps(), strategyConfig.exitExtremeBps);
        assertEq(vault.narrowRangeHalfWidthSteps(), strategyConfig.narrowRangeHalfWidthSteps);
        assertEq(vault.wideRangeHalfWidthSteps(), strategyConfig.wideRangeHalfWidthSteps);
        assertEq(vault.minRecenterBps(), strategyConfig.minRecenterBps);
    }

    function test_minDeployBpsIsDerivedAtConstruction() public view {
        assertEq(vault.minDeployBps(), 9500);
        assertEq(vault.minDeployBps() + vault.maxHealthyIdleBps(), 10_000);
    }

    function test_minDeployBpsAtConfigurationBounds() public {
        StrategyConfig memory strategy = strategyConfig;
        strategy.maxHealthyIdleBps = 0;
        AdaptiveLPVault fullyDeployed = new AdaptiveLPVault(
            "Full Deployment Vault", "FDV", vaultConfig, AccessControlConfig(0, address(this)), strategy
        );
        assertEq(fullyDeployed.minDeployBps(), 10_000);

        strategy.maxHealthyIdleBps = 9999;
        AdaptiveLPVault minimallyDeployed = new AdaptiveLPVault(
            "Minimum Deployment Vault", "MDV", vaultConfig, AccessControlConfig(0, address(this)), strategy
        );
        assertEq(minimallyDeployed.minDeployBps(), 1);
    }

    function test_constructorRejectsIdleLimitAtOrAboveBps() public {
        StrategyConfig memory strategy = strategyConfig;
        strategy.maxHealthyIdleBps = 10_000;
        vm.expectRevert(AdaptiveLPVault.InvalidConfiguration.selector);
        new AdaptiveLPVault("Invalid Vault", "IV", vaultConfig, AccessControlConfig(0, address(this)), strategy);

        strategy.maxHealthyIdleBps = 10_001;
        vm.expectRevert(AdaptiveLPVault.InvalidConfiguration.selector);
        new AdaptiveLPVault("Invalid Vault", "IV", vaultConfig, AccessControlConfig(0, address(this)), strategy);
    }

    function test_previewAtDeploymentThresholdUsesSingleAdapterPreviewWithoutUnusedValuation() public {
        _previewUses(900, 1000);
        vm.expectCall(v2Adapter, abi.encodeWithSelector(IPositionAdapter.previewDeposit.selector), uint64(1));
        vm.mockCallRevert(
            address(oracle),
            abi.encodeCall(ICanonicalV3Oracle.quoteToken0InToken1, (100, 17, false)),
            "unexpected unused valuation"
        );
        (, DeploymentAssessment memory assessment) = vault.previewRebalance();
        assertFalse(assessment.requiresSwap);
        assertEq(uint8(assessment.direction), uint8(SwapDirection.ZERO_FOR_ONE));
    }

    function test_fullDeploymentNeedsNoSwap() public {
        _previewUses(1000, 1000);
        (, DeploymentAssessment memory assessment) = vault.previewRebalance();
        assertFalse(assessment.requiresSwap);
        assertEq(uint8(assessment.direction), uint8(SwapDirection.NONE));
    }

    function test_belowDeploymentThresholdReportsSwapRequiredWithoutRevertingPreview() public {
        _previewUses(899, 1000);
        (, DeploymentAssessment memory assessment) = vault.previewRebalance();
        assertTrue(assessment.requiresSwap);
        assertEq(uint8(assessment.direction), uint8(SwapDirection.ZERO_FOR_ONE));
    }

    function test_dustDoesNotExemptMinimumDeploymentRatio() public {
        _balances(3, 1);
        _previewUses(2, 1);
        (, DeploymentAssessment memory assessment) = vault.previewRebalance();
        assertTrue(assessment.requiresSwap);
        assertEq(uint8(assessment.direction), uint8(SwapDirection.NONE));
        _balances(2, 1);
        _previewUses(1, 1);
        (, assessment) = vault.previewRebalance();
        assertTrue(assessment.requiresSwap);
        assertEq(uint8(assessment.direction), uint8(SwapDirection.NONE));
    }

    function test_deploymentUsesRoundedDeployedValueRatherThanComplementOfIdle() public {
        oracle.setQuoteDivisor(3);
        _balances(3, 1);
        _previewUses(2, 1);
        (, DeploymentAssessment memory assessment) = vault.previewRebalance();
        // Total NAV is two, deployed NAV is one, but the unused token0 quotes to zero.
        assertTrue(assessment.requiresSwap);
        assertEq(uint8(assessment.direction), uint8(SwapDirection.NONE));
    }

    function test_minimumDeploymentRatioRemainsStricterThanRoundedIdleLimit() public {
        _balances(50_000, 50_000);
        _previewUses(44_999, 50_000);
        (, DeploymentAssessment memory assessment) = vault.previewRebalance();
        // Deployment is 9499 bps while idle rounds to the allowed 500 bps.
        assertTrue(assessment.requiresSwap);
        assertEq(uint8(assessment.direction), uint8(SwapDirection.ZERO_FOR_ONE));
    }

    function test_zeroNavRequiresSwapWithoutDividingByZero() public {
        _balances(0, 0);
        _previewUses(0, 0);
        (, DeploymentAssessment memory assessment) = vault.previewRebalance();
        assertTrue(assessment.requiresSwap);
        assertEq(uint8(assessment.direction), uint8(SwapDirection.NONE));
    }

    function test_idlePlanNeedsNoSwapWithoutAdapterOrValuationQueries() public {
        oracle.setDeviation(1000);
        _rejectPreview(v2Adapter);
        _rejectPreview(lowAdapter);
        _rejectPreview(highAdapter);
        vm.mockCallRevert(
            address(oracle),
            abi.encodeWithSelector(ICanonicalV3Oracle.quoteToken0InToken1.selector),
            "unexpected valuation"
        );
        (PositionPlan memory plan, DeploymentAssessment memory assessment) = vault.previewRebalance();
        assertEq(uint8(plan.targetVenue), uint8(VenueType.IDLE));
        assertFalse(assessment.requiresSwap);
        assertEq(uint8(assessment.direction), uint8(SwapDirection.NONE));
    }

    function testFuzz_minimumDeploymentRatioImpliesIdleLimit(
        uint64 amount0,
        uint64 amount1,
        uint64 used0Seed,
        uint64 used1Seed,
        int24 tickSeed,
        uint16 maxIdleSeed
    ) public pure {
        int24 tick = int24(bound(int256(tickSeed), -887_272, 887_272));
        uint256 used0 = uint256(used0Seed) % (uint256(amount0) + 1);
        uint256 used1 = uint256(used1Seed) % (uint256(amount1) + 1);
        uint256 maxIdleBps = uint256(maxIdleSeed) % 10_000;
        uint256 totalNav = uint256(amount1) + PriceMath.quoteToken0InToken1(amount0, tick, false);
        if (totalNav == 0) return; // The vault rejects zero NAV through requiresSwap.
        uint256 deployedNav = used1 + PriceMath.quoteToken0InToken1(used0, tick, false);
        uint256 idleNav =
            uint256(amount1) - used1 + PriceMath.quoteToken0InToken1(uint256(amount0) - used0, tick, false);
        assertLe(deployedNav + idleNav, totalNav);
        uint256 deployBps = Math.mulDiv(deployedNav, 10_000, totalNav);
        uint256 idleBps = Math.mulDiv(idleNav, 10_000, totalNav);
        assertLe(deployBps + idleBps, 10_000);
        if (deployBps >= 10_000 - maxIdleBps) assertLe(idleBps, maxIdleBps);
    }

    function test_disabledTargetStillRevertsBeforePreview() public {
        vault.vaultControl().setAdapterEnabled(VenueType.UNISWAP_V2, false);
        _rejectPreview(v2Adapter);
        vm.expectRevert(IAdapterRegistry.AdapterDisabled.selector);
        vault.previewRebalance();
    }

    function test_adapterOveruseStillReverts() public {
        _previewUses(1001, 1000);
        vm.expectRevert(IAdaptiveLPVault.AdapterBalanceMismatch.selector);
        vault.previewRebalance();
    }

    function test_invalidPreviewRevertsBeforeOracleValuation() public {
        vm.mockCallRevert(
            address(oracle),
            abi.encodeWithSelector(ICanonicalV3Oracle.quoteToken0InToken1.selector),
            "valuation must not run for invalid preview"
        );
        _previewUses(1001, 1000);
        vm.expectRevert(IAdaptiveLPVault.AdapterBalanceMismatch.selector);
        vault.previewRebalance();
        _previewUses(998, 998);
        vm.expectRevert(IAdaptiveLPVault.InvalidDeploymentPreview.selector);
        vault.previewRebalance();
    }

    function test_bothExcessTokensStillRevert() public {
        _previewUses(998, 998);
        vm.expectRevert(IAdaptiveLPVault.InvalidDeploymentPreview.selector);
        vault.previewRebalance();
    }

    function test_simulatedDeploymentStillChecksRatioBeforeOppositeDirection() public {
        bytes32 planHash = _swapPlan();
        _simulatedPreviewUses(900, 900);
        vm.expectRevert(IAdaptiveLPVault.DeploymentRatioTooLow.selector);
        vault.rebalanceWithSwap(planHash, SwapDirection.ZERO_FOR_ONE, 100, 0, uint32(block.timestamp));
    }

    function test_simulatedDeploymentStillRejectsOppositeDirection() public {
        bytes32 planHash = _swapPlan();
        _simulatedPreviewUses(900, 1050);
        vm.expectRevert(AdaptiveLPVault.SwapAmountExceeded.selector);
        vault.rebalanceWithSwap(planHash, SwapDirection.ZERO_FOR_ONE, 100, 0, uint32(block.timestamp));
    }

    function test_healthySimulatedDeploymentReachesSwapExecution() public {
        bytes32 planHash = _swapPlan();
        _simulatedPreviewUses(850, 1099);
        bytes memory reachedSwap = abi.encodeWithSignature("Error(string)", "reached swap execution");
        vm.mockCallRevert(
            address(vault.swapExecutor()),
            abi.encodeWithSelector(IControlledSwapExecutor.executeSwap.selector),
            reachedSwap
        );
        vm.expectRevert(reachedSwap);
        vault.rebalanceWithSwap(planHash, SwapDirection.ZERO_FOR_ONE, 100, 0, uint32(block.timestamp));
    }

    function _swapPlan() private returns (bytes32) {
        _previewUses(500, 1000);
        (PositionPlan memory plan,) = vault.previewRebalance();
        return plan.planHash;
    }

    function _simulatedPreviewUses(uint256 used0, uint256 used1) private {
        vm.mockCall(
            v2Adapter,
            abi.encodeWithSelector(IPositionAdapter.previewDeposit.selector, uint256(900), uint256(1099)),
            abi.encode(used0, used1)
        );
    }

    function _balances(uint256 amount0, uint256 amount1) private {
        deal(address(token0), address(vault), amount0);
        deal(address(token1), address(vault), amount1);
    }

    function _previewUses(uint256 used0, uint256 used1) private {
        vm.mockCall(
            v2Adapter, abi.encodeWithSelector(IPositionAdapter.previewDeposit.selector), abi.encode(used0, used1)
        );
    }

    function _rejectPreview(address adapter) private {
        vm.mockCallRevert(
            adapter, abi.encodeWithSelector(IPositionAdapter.previewDeposit.selector), "unexpected preview"
        );
    }

    function _endpoint(string memory name) private returns (address endpoint) {
        endpoint = makeAddr(name);
        vm.etch(endpoint, hex"00");
    }

    function _mockAddress(address target, string memory signature, address value) private {
        vm.mockCall(target, abi.encodeWithSignature(signature), abi.encode(value));
    }

    function _pool(string memory name, address factory, uint24 fee) private returns (address pool) {
        pool = _endpoint(name);
        _mockAddress(pool, "token0()", address(token0));
        _mockAddress(pool, "token1()", address(token1));
        _mockAddress(pool, "factory()", factory);
        vm.mockCall(pool, abi.encodeWithSignature("fee()"), abi.encode(fee));
    }

    function _adapter(string memory name, VenueType venue, address pool, uint24 fee, int24 spacing)
        private
        returns (address adapter)
    {
        adapter = _endpoint(name);
        _mockAddress(adapter, "vault()", address(vault));
        _mockAddress(adapter, "pool()", pool);
        _mockAddress(adapter, "token0()", address(token0));
        _mockAddress(adapter, "token1()", address(token1));
        vm.mockCall(adapter, abi.encodeWithSignature("venue()"), abi.encode(venue));
        vm.mockCall(adapter, abi.encodeWithSignature("feeTier()"), abi.encode(fee));
        vm.mockCall(adapter, abi.encodeWithSignature("tickSpacing()"), abi.encode(spacing));
        vm.mockCall(pool, abi.encodeWithSignature("tickSpacing()"), abi.encode(spacing));
        PositionSnapshot memory empty;
        vm.mockCall(adapter, abi.encodeWithSelector(IPositionAdapter.snapshot.selector), abi.encode(empty));
        vault.vaultControl().configureAdapter(venue, adapter);
    }
}
