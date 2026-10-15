// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AssessmentOracle} from "./AdaptiveLPVaultAssessment.t.sol";
import {MockV2ERC20, MockV2Factory, MockV2Pair} from "./UniswapV2Adapter.t.sol";
import {UniswapV2Adapter} from "../../src/adapters/UniswapV2Adapter.sol";
import {PositionAdapterConfig, PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {AdaptiveLPVault} from "../../src/core/AdaptiveLPVault.sol";
import {VaultComponentFactory} from "../../src/core/VaultComponentFactory.sol";
import {VaultControl} from "../../src/core/VaultControl.sol";
import {
    AccessControlConfig,
    AssetSnapshot,
    PauseState,
    PositionPlan,
    StrategyConfig,
    VaultConfig,
    VenueType
} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {IUniswapV3SwapRouter} from "../../src/interfaces/IUniswapV3External.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";

/// @dev Stateful V3 stand-in. Real V2 adapter/pair balances and real vault/executor flows stay under test.
contract DonationV3Adapter {
    address public immutable vault;
    address public immutable pool;
    address public immutable token0;
    address public immutable token1;
    VenueType public immutable venue;
    uint24 public immutable feeTier;
    int24 public immutable tickSpacing;
    PositionSnapshot internal _position;

    constructor(address vault_, address pool_, address token0_, address token1_, VenueType venue_) {
        vault = vault_;
        pool = pool_;
        token0 = token0_;
        token1 = token1_;
        venue = venue_;
        feeTier = venue_ == VenueType.UNISWAP_V3_LOW_FEE ? 500 : 3000;
        tickSpacing = venue_ == VenueType.UNISWAP_V3_LOW_FEE ? int24(10) : int24(60);
    }

    function snapshot() external view returns (PositionSnapshot memory) {
        return _position;
    }

    function syncFees() external virtual returns (uint256, uint256) {
        return (0, 0);
    }

    function previewDeposit(uint256 amount0, uint256 amount1, PositionPlan calldata)
        external
        pure
        returns (uint256, uint256)
    {
        return (amount0, amount1);
    }

    function deposit(uint256 amount0, uint256 amount1, PositionPlan calldata plan)
        external
        returns (uint256, uint256, uint256)
    {
        require(msg.sender == vault);
        require(IERC20(token0).transferFrom(vault, address(this), amount0));
        require(IERC20(token1).transferFrom(vault, address(this), amount1));
        _position.venue = venue;
        _position.adapter = address(this);
        _position.positionId = 1;
        _position.tickLower = plan.tickLower;
        _position.tickUpper = plan.tickUpper;
        _position.liquidity += amount0 + amount1;
        _position.principal0 += amount0;
        _position.principal1 += amount1;
        _position.amount0 = _position.principal0;
        _position.amount1 = _position.principal1;
        return (amount0, amount1, amount0 + amount1);
    }

    function withdraw(uint256 shares, uint256 supply) external returns (uint256 amount0, uint256 amount1) {
        require(msg.sender == vault);
        amount0 = Math.mulDiv(_position.amount0, shares, supply);
        amount1 = Math.mulDiv(_position.amount1, shares, supply);
        _position.principal0 -= amount0;
        _position.principal1 -= amount1;
        _position.amount0 -= amount0;
        _position.amount1 -= amount1;
        _position.liquidity = _position.amount0 + _position.amount1;
        require(IERC20(token0).transfer(vault, amount0));
        require(IERC20(token1).transfer(vault, amount1));
    }

    function withdrawAll() external virtual returns (uint256 amount0, uint256 amount1) {
        require(msg.sender == vault);
        amount0 = _position.amount0;
        amount1 = _position.amount1;
        delete _position;
        require(IERC20(token0).transfer(vault, amount0));
        require(IERC20(token1).transfer(vault, amount1));
    }
}

contract DonationRouter {
    address public immutable factory;
    uint256 public outputBps = 10_000;

    constructor(address factory_) {
        factory = factory_;
    }

    function setOutputBps(uint256 bps) external {
        outputBps = bps;
    }

    function exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut)
    {
        require(IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn));
        amountOut = Math.mulDiv(params.amountIn, outputBps, 10_000);
        require(IERC20(params.tokenOut).transfer(params.recipient, amountOut));
    }
}

contract AdaptiveLPVaultDonationsTest is Test {
    uint256 internal constant SEED = 1000 ether;
    uint256 internal constant LOCKED = 1 ether;
    AdaptiveLPVault internal vault;
    VaultControl internal control;
    AssessmentOracle internal oracle;
    MockV2ERC20 internal token0;
    MockV2ERC20 internal token1;
    MockV2Pair internal pair;
    UniswapV2Adapter internal v2;
    DonationV3Adapter internal low;
    DonationV3Adapter internal high;
    DonationRouter internal router;

    function setUp() public virtual {
        MockV2ERC20 a = new MockV2ERC20("Donation A", "DA");
        MockV2ERC20 b = new MockV2ERC20("Donation B", "DB");
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);
        MockV2Factory v2Factory = new MockV2Factory();
        pair = MockV2Pair(v2Factory.createPair(address(token0), address(token1)));
        token0.mint(address(this), 2_000_000 ether);
        token1.mint(address(this), 2_000_000 ether);
        token0.transfer(address(pair), 1_000_000 ether);
        token1.transfer(address(pair), 1_000_000 ether);
        pair.mint(address(this));

        address v3Factory = makeAddr("donation v3 factory");
        vm.etch(v3Factory, hex"00");
        address lowPool = _pool("donation low pool", v3Factory, 500, 10);
        address highPool = _pool("donation high pool", v3Factory, 3000, 60);
        router = new DonationRouter(v3Factory);
        token0.mint(address(router), 100_000 ether);
        token1.mint(address(router), 100_000 ether);
        oracle = new AssessmentOracle(lowPool, address(token0), address(token1));
        VaultConfig memory config = VaultConfig({
            dustTolerance0: 1,
            dustTolerance1: 1,
            canonicalOracle: address(oracle),
            componentFactory: address(new VaultComponentFactory()),
            router: address(router),
            uniswapV2Factory: address(v2Factory),
            uniswapV3Factory: v3Factory,
            minimumLockedShares: LOCKED,
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
            maxMigrationLossBps: 10
        });
        vault = new AdaptiveLPVault("Donation Vault", "DV", config, AccessControlConfig(0, address(this)), strategy);
        control = VaultControl(address(vault.vaultControl()));
        control.grantRole(control.MANAGER_ROLE(), address(this));
        v2 = new UniswapV2Adapter(
            PositionAdapterConfig({
                vault: address(vault),
                venue: VenueType.UNISWAP_V2,
                pool: address(pair),
                factory: address(v2Factory),
                positionManager: address(0)
            })
        );
        low = new DonationV3Adapter(
            address(vault), lowPool, address(token0), address(token1), VenueType.UNISWAP_V3_LOW_FEE
        );
        high = new DonationV3Adapter(
            address(vault), highPool, address(token0), address(token1), VenueType.UNISWAP_V3_HIGH_FEE
        );
        control.configureAdapter(VenueType.UNISWAP_V2, address(v2));
        control.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(low));
        control.configureAdapter(VenueType.UNISWAP_V3_HIGH_FEE, address(high));
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
    }

    function test_bootstrapV3IgnoresPreexistingV2Donation() public {
        _donate(1);
        _bootstrap(0, SEED, SEED);
        _assertAssets(SEED, SEED);
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_LOW_FEE));
        assertEq(pair.balanceOf(address(v2)), 1);
    }

    function test_bootstrapIdleIgnoresPreexistingV2DonationAndRedeemsOnlyIdle() public {
        _donate(100 ether);
        _bootstrap(1000, SEED, SEED);
        _assertAssets(SEED, SEED);
        uint256 shares = 100 ether;
        (uint256 amount0, uint256 amount1) = vault.redeem(shares, 0, 0, address(this), address(this));
        assertEq(amount0, 50 ether);
        assertEq(amount1, 50 ether);
        assertEq(pair.balanceOf(address(v2)), 100 ether);
    }

    function test_bootstrapV2RecognizesDonationWithoutMintingExtraShares() public {
        _donate(100 ether);
        _bootstrap(350, SEED, SEED);
        _assertAssets(1100 ether, 1100 ether);
        assertEq(vault.totalSupply(), 2 * SEED);
        assertEq(vault.balanceOf(address(this)), 2 * SEED - LOCKED);
        assertEq(vault.balanceOf(address(vault)), LOCKED);
        assertEq(pair.balanceOf(address(v2)), 1100 ether);
    }

    function test_bootstrapStillRejectsManagedV3Position() public {
        PositionSnapshot memory position;
        position.liquidity = 1;
        vm.mockCall(address(high), abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(position));
        _donate(1);
        oracle.setDeviation(0);
        vm.expectRevert(IAdaptiveLPVault.ActivePositionExists.selector);
        vault.bootstrap(SEED, SEED, address(this));
        assertFalse(vault.initialized());
        assertEq(vault.totalSupply(), 0);
    }

    function test_nonActiveV2DonationDoesNotAffectDepositPricingOrRedeem() public {
        _bootstrap(0, SEED, SEED);
        _donate(100 ether);
        _assertAssets(SEED, SEED);
        (,, uint256 shares) = vault.deposit(100 ether, 100 ether, 0, address(this));
        assertEq(shares, 200 ether);
        _assertAssets(1100 ether, 1100 ether);
        (uint256 amount0, uint256 amount1) = vault.redeem(shares, 0, 0, address(this), address(this));
        assertEq(amount0, 100 ether);
        assertEq(amount1, 100 ether);
        assertEq(pair.balanceOf(address(v2)), 100 ether);
        _assertAssets(SEED, SEED);
    }

    function test_nonActiveV2DonationDoesNotBlockV3MigrationOrIdle() public {
        _bootstrap(0, SEED, SEED);
        _donate(1);
        _rebalance(150, VenueType.UNISWAP_V3_HIGH_FEE);
        _assertAssets(SEED, SEED);
        // Hysteresis transitions one regime at a time: MEDIUM -> HIGH -> EXTREME.
        _rebalance(350, VenueType.UNISWAP_V2);
        _rebalance(1000, VenueType.IDLE);
        assertEq(pair.balanceOf(address(v2)), 0);
        _donate(1);
        _assertAssets(SEED + 1, SEED + 1);
        vault.emergencyExitToIdle();
        assertEq(pair.balanceOf(address(v2)), 1);
    }

    function test_nonActiveV2DonationDoesNotBlockEmergencyExitAndRemainsUnrecognized() public {
        _bootstrap(0, SEED, SEED);
        _donate(100 ether);
        uint64 version = vault.planVersion();
        uint32 changedAt = vault.lastPositionChangeAt();
        vault.emergencyExitToIdle();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
        assertEq(vault.planVersion(), version + 1);
        assertEq(vault.lastPositionChangeAt(), changedAt);
        assertEq(low.snapshot().liquidity, 0);
        assertEq(pair.balanceOf(address(v2)), 100 ether);
        _assertAssets(SEED, SEED);
        PauseState memory pause = control.pauseState();
        assertTrue(pause.depositPaused && pause.plainRebalancePaused && pause.swapRebalancePaused);
        vault.emergencyExitToIdle();
        assertEq(vault.planVersion(), version + 1);
        assertEq(pair.balanceOf(address(v2)), 100 ether);
    }

    function test_nonActiveManagedV3PositionStillBlocksDeposit() public {
        _bootstrap(0, SEED, SEED);
        _donate(1);
        PositionSnapshot memory position;
        position.liquidity = 1;
        vm.mockCall(address(high), abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(position));
        vm.expectRevert(IAdaptiveLPVault.ActivePositionExists.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
        _assertAssets(SEED, SEED);
    }

    function test_plainActivationRecognizesDonationAndEventIncludesFullAssets() public {
        _bootstrap(150, SEED, SEED);
        _donate(100 ether);
        PositionPlan memory plan = _plan(350);
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.PositionPlanCommitted(plan.planHash, plan.version, plan.targetVenue, plan.marketRegime);
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.RebalanceExecuted(
            address(this),
            plan.planHash,
            VenueType.UNISWAP_V3_HIGH_FEE,
            VenueType.UNISWAP_V2,
            false,
            1100 ether,
            1100 ether,
            2200 ether,
            0
        );
        vault.rebalance(plan.planHash, uint32(block.timestamp));
        _assertAssets(1100 ether, 1100 ether);
        assertEq(vault.totalSupply(), 2 * SEED);
    }

    function test_usersEnteringBeforeActivationShareDonationAndLaterDepositsAreFair() public {
        _bootstrap(150, SEED, SEED);
        _donate(100 ether);
        address user = makeAddr("new donation shareholder");
        token0.mint(user, 100 ether);
        token1.mint(user, 100 ether);
        vm.startPrank(user);
        token0.approve(address(vault), 100 ether);
        token1.approve(address(vault), 100 ether);
        vault.deposit(100 ether, 100 ether, 0, user);
        vm.stopPrank();
        assertEq(vault.balanceOf(user), 200 ether);
        _rebalance(350, VenueType.UNISWAP_V2);
        _assertAssets(1200 ether, 1200 ether);
        uint256 expectedOut = Math.mulDiv(1200 ether, 200 ether, 2200 ether);
        vm.prank(user);
        (uint256 amount0, uint256 amount1) = vault.redeem(200 ether, 0, 0, user, user);
        assertEq(amount0, expectedOut);
        assertEq(amount1, expectedOut);
        assertGt(amount0, 100 ether);
        (uint256 total0, uint256 total1) = vault.totalAssets();
        uint256 expectedShares = Math.mulDiv(200 ether, vault.totalSupply(), total0 + total1);
        (,, uint256 minted) = vault.deposit(100 ether, 100 ether, 0, address(this));
        assertEq(minted, expectedShares);
        assertLt(minted, 200 ether);
    }

    function test_activeV2DonationIsImmediatelyRecognizedAndExitedOnMigration() public {
        _bootstrap(350, SEED, SEED);
        _donate(100 ether);
        _assertAssets(1100 ether, 1100 ether);
        _rebalance(0, VenueType.UNISWAP_V3_HIGH_FEE);
        assertEq(pair.balanceOf(address(v2)), 0);
        _assertAssets(1100 ether, 1100 ether);
        _donate(50 ether);
        _assertAssets(1100 ether, 1100 ether);
        _rebalance(350, VenueType.UNISWAP_V2);
        _assertAssets(1150 ether, 1150 ether);
    }

    function test_emergencyExitFromV2ClearsRecognizedDonations() public {
        _bootstrap(350, SEED, SEED);
        _donate(100 ether);
        vault.emergencyExitToIdle();
        assertEq(pair.balanceOf(address(v2)), 0);
        _assertAssets(1100 ether, 1100 ether);
    }

    function test_idleActivationRecognizesDonation() public {
        _bootstrap(1000, SEED, SEED);
        _donate(100 ether);
        _assertAssets(SEED, SEED);
        _rebalance(0, VenueType.UNISWAP_V2);
        _assertAssets(1100 ether, 1100 ether);
    }

    function test_swapActivationRecognizesDonationWithoutCorruptingAccountingSnapshot() public {
        _bootstrap(150, 1500 ether, 500 ether);
        _donate(100 ether);
        PositionPlan memory plan = _plan(350);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
        _assertAssets(1100 ether, 1100 ether);
        assertEq(pair.balanceOf(address(v2)), 1100 ether);
    }

    function test_donationCanOffsetExcessiveSwapMigrationLossAndMigrationSucceeds() public {
        _bootstrap(150, 1500 ether, 500 ether);
        _donate(100 ether);
        router.setOutputBps(9900);
        PositionPlan memory plan = _plan(350);
        uint64 version = vault.planVersion();

        // The swap loses 5 of 2000, but the newly confirmed donation leaves the final NAV above the cap.
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));

        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
        assertEq(vault.planVersion(), version + 1);
        assertEq(pair.balanceOf(address(v2)), 1095 ether);
        _assertAssets(1100 ether, 1095 ether);
        assertEq(token0.balanceOf(address(vault.swapExecutor())), 0);
        assertEq(token1.balanceOf(address(vault.swapExecutor())), 0);
    }

    function test_insufficientDonationDoesNotMaskExcessiveSwapMigrationLoss() public {
        _bootstrap(150, 1500 ether, 500 ether);
        router.setOutputBps(9900);
        PositionPlan memory plan = _plan(350);
        uint64 version = vault.planVersion();

        vm.expectRevert(IAdaptiveLPVault.MigrationLossExceeded.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));

        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_HIGH_FEE));
        assertEq(vault.planVersion(), version);
        _assertAssets(1500 ether, 500 ether);
    }

    function test_plainMigrationUsesCompleteSnapshotForAssetConservation() public {
        _bootstrap(150, SEED, SEED);
        _donate(100 ether);
        PositionPlan memory plan = _plan(350);
        PositionSnapshot memory reported;
        reported.venue = VenueType.UNISWAP_V2;
        reported.adapter = address(v2);
        reported.liquidity = 1000 ether;
        reported.principal0 = 980 ether;
        reported.principal1 = 980 ether;
        reported.amount0 = 980 ether;
        reported.amount1 = 980 ether;
        vm.mockCall(address(v2), abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(reported));

        vm.expectRevert(AdaptiveLPVault.AssetConservationViolation.selector);
        vault.rebalance(plan.planHash, uint32(block.timestamp));
        _assertAssets(SEED, SEED);
        assertEq(pair.balanceOf(address(v2)), 100 ether);
    }

    function test_bootstrapUsesCompleteSnapshotForAssetConservation() public {
        _donate(100 ether);
        oracle.setDeviation(350);
        PositionSnapshot memory reported;
        reported.venue = VenueType.UNISWAP_V2;
        reported.adapter = address(v2);
        reported.liquidity = 1000 ether;
        reported.principal0 = 980 ether;
        reported.principal1 = 980 ether;
        reported.amount0 = 980 ether;
        reported.amount1 = 980 ether;
        vm.mockCall(address(v2), abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(reported));

        vm.expectRevert(AdaptiveLPVault.AssetConservationViolation.selector);
        vault.bootstrap(SEED, SEED, address(this));
        assertEq(vault.totalSupply(), 0);
        assertEq(pair.balanceOf(address(v2)), 100 ether);
    }

    function test_donationCanSupportBootstrapDeployment() public {
        // A 1:2 pair uses only half the seeded token0; the confirmed LP donation supplies the remainder.
        token1.mint(address(this), 1_000_000 ether);
        token1.transfer(address(pair), 1_000_000 ether);
        pair.sync();
        _donate(100_000 ether);
        oracle.setDeviation(350);
        vm.mockCall(
            address(v2), abi.encodeWithSelector(IPositionAdapter.previewDeposit.selector), abi.encode(SEED, SEED)
        );
        vault.bootstrap(SEED, SEED, address(this));
        assertTrue(vault.initialized());
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
        (uint256 total0, uint256 total1) = vault.totalAssets();
        assertGt(total0, SEED);
        assertGt(total1, SEED);
    }

    function test_donationCanSupportPlainMigrationDeployment() public {
        _bootstrap(150, SEED, SEED);
        token1.mint(address(this), 1_000_000 ether);
        token1.transfer(address(pair), 1_000_000 ether);
        pair.sync();
        _donate(100_000 ether);
        vm.mockCall(
            address(v2), abi.encodeWithSelector(IPositionAdapter.previewDeposit.selector), abi.encode(SEED, SEED)
        );
        PositionPlan memory plan = _plan(350);
        vault.rebalance(plan.planHash, uint32(block.timestamp));
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
        (uint256 total0, uint256 total1) = vault.totalAssets();
        assertGt(total0, SEED);
        assertGt(total1, SEED);
    }

    function test_preexistingDonationCannotStandInForNewlyMintedLiquidity() public {
        _donate(100 ether);
        oracle.setDeviation(350);
        vm.mockCall(address(v2), abi.encodeWithSelector(IPositionAdapter.deposit.selector), abi.encode(0, 0, 0));
        vm.expectRevert(IAdaptiveLPVault.DeploymentRatioTooLow.selector);
        vault.bootstrap(SEED, SEED, address(this));
        assertEq(pair.balanceOf(address(v2)), 100 ether);
    }

    function test_reportedLiquidityMustMatchActualLpIncrease() public {
        _donate(100 ether);
        oracle.setDeviation(350);
        vm.mockCall(address(pair), abi.encodeWithSignature("mint(address)", address(v2)), abi.encode(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionAdapter.AdapterBalanceMismatch.selector, address(pair), 100 ether + 1, 100 ether
            )
        );
        vault.bootstrap(SEED, SEED, address(this));
        assertEq(pair.balanceOf(address(v2)), 100 ether);
        assertEq(vault.totalSupply(), 0);
        assertFalse(vault.initialized());
        assertEq(token0.allowance(address(vault), address(v2)), 0);
        assertEq(token1.allowance(address(vault), address(v2)), 0);
    }

    function test_v2DepositRejectsMintMismatchAndRollsBack() public {
        _donate(100 ether);
        _bootstrap(350, SEED, SEED);
        uint256 lpBefore = pair.balanceOf(address(v2));
        uint256 supplyBefore = vault.totalSupply();
        uint256 user0Before = token0.balanceOf(address(this));
        uint256 user1Before = token1.balanceOf(address(this));
        vm.mockCall(address(pair), abi.encodeWithSignature("mint(address)", address(v2)), abi.encode(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionAdapter.AdapterBalanceMismatch.selector, address(pair), lpBefore + 1, lpBefore
            )
        );
        vault.deposit(100 ether, 100 ether, 0, address(this));

        assertEq(pair.balanceOf(address(v2)), lpBefore);
        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(token0.balanceOf(address(this)), user0Before);
        assertEq(token1.balanceOf(address(this)), user1Before);
        assertEq(token0.allowance(address(vault), address(v2)), 0);
        assertEq(token1.allowance(address(vault), address(v2)), 0);
        _assertAssets(1100 ether, 1100 ether);
    }

    function test_v2PlainMigrationRejectsMintMismatchAndRestoresOldPosition() public {
        _bootstrap(150, SEED, SEED);
        _donate(100 ether);
        PositionPlan memory plan = _plan(350);
        vm.mockCall(address(pair), abi.encodeWithSignature("mint(address)", address(v2)), abi.encode(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionAdapter.AdapterBalanceMismatch.selector, address(pair), 100 ether + 1, 100 ether
            )
        );
        vault.rebalance(plan.planHash, uint32(block.timestamp));

        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_HIGH_FEE));
        assertEq(high.snapshot().principal0, SEED);
        assertEq(high.snapshot().principal1, SEED);
        assertEq(pair.balanceOf(address(v2)), 100 ether);
        _assertAssets(SEED, SEED);
    }

    function test_v2SwapMigrationRejectsMintMismatchAndRestoresOldPosition() public {
        _bootstrap(150, 1500 ether, 500 ether);
        _donate(100 ether);
        PositionPlan memory plan = _plan(350);
        uint256 router0Before = token0.balanceOf(address(router));
        uint256 router1Before = token1.balanceOf(address(router));
        vm.mockCall(address(pair), abi.encodeWithSignature("mint(address)", address(v2)), abi.encode(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionAdapter.AdapterBalanceMismatch.selector, address(pair), 100 ether + 1, 100 ether
            )
        );
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));

        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_HIGH_FEE));
        assertEq(high.snapshot().principal0, 1500 ether);
        assertEq(high.snapshot().principal1, 500 ether);
        assertEq(pair.balanceOf(address(v2)), 100 ether);
        assertEq(token0.balanceOf(address(router)), router0Before);
        assertEq(token1.balanceOf(address(router)), router1Before);
        _assertAssets(1500 ether, 500 ether);
    }

    function test_nonActiveV2IsNotQueriedForTopologyEvenWhenSnapshotFails() public {
        _donate(1);
        vm.mockCallRevert(address(v2), abi.encodeCall(IPositionAdapter.snapshot, ()), "inactive V2 snapshot");
        _bootstrap(0, SEED, SEED);
        vault.deposit(100 ether, 100 ether, 0, address(this));
        _rebalance(150, VenueType.UNISWAP_V3_HIGH_FEE);
        control.setAdapterEnabled(VenueType.UNISWAP_V2, false);
        vault.emergencyExitToIdle();
        _assertAssets(1100 ether, 1100 ether);
        assertEq(pair.balanceOf(address(v2)), 1);
    }

    function test_reverseSwapActivationRecognizesDonation() public {
        _bootstrap(150, 500 ether, 1500 ether);
        _donate(100 ether);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("quoteToken1InToken0(uint256,int24,bool)", uint256(500 ether), int24(17), true),
            abi.encode(500 ether)
        );
        PositionPlan memory plan = _plan(350);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ONE_FOR_ZERO, 500 ether, 0, uint32(block.timestamp));
        _assertAssets(1100 ether, 1100 ether);
    }

    function test_donationCanSupportSwapMigrationDeployment() public {
        _bootstrap(150, 1500 ether, 500 ether);
        token1.mint(address(this), 1_000_000 ether);
        token1.transfer(address(pair), 1_000_000 ether);
        pair.sync();
        _donate(100_000 ether);
        // The worst-case preview passes, and the confirmed donation also participates in the final deployment check.
        vm.mockCall(
            address(v2),
            abi.encodeWithSelector(IPositionAdapter.previewDeposit.selector, uint256(1000 ether), uint256(995 ether)),
            abi.encode(1000 ether, 995 ether)
        );
        PositionPlan memory plan = _plan(350);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
        (uint256 total0, uint256 total1) = vault.totalAssets();
        assertGt(total0, 1000 ether);
        assertGt(total1, 500 ether);
    }

    function test_swapLossExactlyAtCapSucceedsAndDonationIsStillFullyRecognized() public {
        _bootstrap(150, 1500 ether, 500 ether);
        _donate(100 ether);
        router.setOutputBps(9960);
        PositionPlan memory plan = _plan(350);
        // Output is 498: loss is exactly 2 / 2000 = 0.1%, with 2 token0 left idle.
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
        _assertAssets(1100 ether, 1098 ether);
        assertEq(vault.assetSnapshot().idle0, 2 ether);
        assertEq(pair.balanceOf(address(v2)), 1098 ether);
    }

    function test_allCirculatingSharesRedeemedRetainsLockedShareOfConfirmedDonation() public {
        _donate(100 ether);
        _bootstrap(350, SEED, SEED);
        vault.redeem(vault.balanceOf(address(this)), 0, 0, address(this), address(this));
        assertEq(vault.totalSupply(), LOCKED);
        assertEq(vault.balanceOf(address(vault)), LOCKED);
        assertEq(pair.balanceOf(address(v2)), 0.55 ether);
        _assertAssets(0.55 ether, 0.55 ether);
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
    }

    function test_completeSnapshotStillEnforcesSwapTokenConservation() public {
        _bootstrap(150, 1500 ether, 500 ether);
        _donate(100 ether);
        PositionPlan memory plan = _plan(350);
        PositionSnapshot memory reported;
        reported.venue = VenueType.UNISWAP_V2;
        reported.adapter = address(v2);
        reported.liquidity = 1000 ether;
        reported.principal0 = 1000 ether;
        reported.principal1 = 998 ether;
        reported.amount0 = 1000 ether;
        reported.amount1 = 998 ether;
        vm.mockCall(address(v2), abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(reported));

        vm.expectRevert(AdaptiveLPVault.AssetConservationViolation.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
        _assertAssets(1500 ether, 500 ether);
        assertEq(pair.balanceOf(address(v2)), 100 ether);
    }

    function testFuzz_activationConfirmsExactlyThePreexistingLp(uint96 donated) public {
        donated = uint96(bound(donated, 0, 100_000 ether));
        _bootstrap(150, SEED, SEED);
        _donate(donated);
        _assertAssets(SEED, SEED);
        _rebalance(350, VenueType.UNISWAP_V2);
        _assertAssets(SEED + donated, SEED + donated);
        assertEq(vault.totalSupply(), 2 * SEED);
    }

    function testFuzz_nonActiveDonationNeverChangesV3Assets(uint96 donated) public {
        donated = uint96(bound(donated, 0, 100_000 ether));
        _bootstrap(0, SEED, SEED);
        _donate(donated);
        _assertAssets(SEED, SEED);
        vault.deposit(100 ether, 100 ether, 0, address(this));
        vault.emergencyExitToIdle();
        _assertAssets(1100 ether, 1100 ether);
        assertEq(pair.balanceOf(address(v2)), donated);
    }

    function _bootstrap(uint256 deviation, uint256 amount0, uint256 amount1) internal {
        oracle.setDeviation(deviation);
        vault.bootstrap(amount0, amount1, address(this));
    }

    function _donate(uint256 liquidity) private {
        assertTrue(pair.transfer(address(v2), liquidity));
    }

    function _plan(uint256 deviation) internal returns (PositionPlan memory plan) {
        oracle.setDeviation(deviation);
        (plan,) = vault.previewRebalance();
    }

    function _rebalance(uint256 deviation, VenueType target) private {
        PositionPlan memory plan = _plan(deviation);
        assertEq(uint8(plan.targetVenue), uint8(target));
        vault.rebalance(plan.planHash, uint32(block.timestamp));
    }

    function _assertAssets(uint256 amount0, uint256 amount1) private view {
        (uint256 actual0, uint256 actual1) = vault.totalAssets();
        assertEq(actual0, amount0);
        assertEq(actual1, amount1);
        AssetSnapshot memory assets = vault.assetSnapshot();
        assertEq(assets.total0, actual0);
        assertEq(assets.total1, actual1);
    }

    function _pool(string memory name, address factory, uint24 fee, int24 spacing) private returns (address pool) {
        pool = makeAddr(name);
        vm.etch(pool, hex"00");
        vm.mockCall(pool, abi.encodeWithSignature("token0()"), abi.encode(address(token0)));
        vm.mockCall(pool, abi.encodeWithSignature("token1()"), abi.encode(address(token1)));
        vm.mockCall(pool, abi.encodeWithSignature("factory()"), abi.encode(factory));
        vm.mockCall(pool, abi.encodeWithSignature("fee()"), abi.encode(fee));
        vm.mockCall(pool, abi.encodeWithSignature("tickSpacing()"), abi.encode(spacing));
        vm.mockCall(
            factory,
            abi.encodeWithSignature("getPool(address,address,uint24)", address(token0), address(token1), fee),
            abi.encode(pool)
        );
    }
}
