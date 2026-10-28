// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {AdaptiveLPVault} from "../../src/core/AdaptiveLPVault.sol";
import {AssetSnapshot, DeploymentAssessment, PauseState, PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";

import {AdaptiveLPVaultFixture} from "./helpers/AdaptiveLPVaultFixture.sol";

contract AdaptiveLPVaultDonationsTest is AdaptiveLPVaultFixture {
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

    function test_donationDoesNotBypassBootstrapSwapRequirement() public {
        _setV2ReserveRatioToOneToTwo();
        _donate(100_000 ether);
        oracle.setDeviation(350);
        PositionPlan memory plan;
        plan.targetVenue = VenueType.UNISWAP_V2;
        (uint256 used0, uint256 used1) = v2.previewDeposit(SEED, SEED, plan);
        assertEq(used0, SEED / 2);
        assertEq(used1, SEED);
        uint256 user0Before = token0.balanceOf(address(this));
        uint256 user1Before = token1.balanceOf(address(this));

        vm.expectRevert(IAdaptiveLPVault.SwapRequired.selector);
        vault.bootstrap(SEED, SEED, address(this));

        assertFalse(vault.initialized());
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.planVersion(), 0);
        assertEq(pair.balanceOf(address(v2)), 100_000 ether);
        assertEq(token0.balanceOf(address(this)), user0Before);
        assertEq(token1.balanceOf(address(this)), user1Before);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);
        assertEq(token0.allowance(address(vault), address(v2)), 0);
        assertEq(token1.allowance(address(vault), address(v2)), 0);
    }

    function test_donationDoesNotBypassPlainMigrationSwapRequirement() public {
        _bootstrap(150, SEED, SEED);
        _setV2ReserveRatioToOneToTwo();
        _donate(100_000 ether);
        oracle.setDeviation(350);
        (PositionPlan memory plan, DeploymentAssessment memory assessment) = vault.previewRebalance();
        assertEq(uint8(plan.targetVenue), uint8(VenueType.UNISWAP_V2));
        assertTrue(assessment.requiresSwap);
        assertEq(uint8(assessment.direction), uint8(SwapDirection.ZERO_FOR_ONE));
        (uint256 used0, uint256 used1) = v2.previewDeposit(SEED, SEED, plan);
        assertEq(used0, SEED / 2);
        assertEq(used1, SEED);
        bytes32 history = _migrationHistory();

        vm.expectRevert(IAdaptiveLPVault.SwapRequired.selector);
        vault.rebalance(plan.planHash, uint32(block.timestamp));

        _assertRejectedV2Migration(SEED, SEED, history);
    }

    function test_donationIsRecognizedAfterSwapPassesRealDeploymentAssessment() public {
        _bootstrap(150, SEED, SEED);
        _setV2ReserveRatioToOneToTwo();
        _donate(100_000 ether);
        PositionPlan memory plan = _plan(350);
        uint64 version = vault.planVersion();
        uint256 supply = vault.totalSupply();
        uint256 router0Before = token0.balanceOf(address(router));
        uint256 router1Before = token1.balanceOf(address(router));

        // The mock router exchanges 1:1. A 333-token swap nearly matches the target 1:2 reserve ratio.
        // Neither the initial preview nor the conservative post-swap preview is overridden.
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 333 ether, 0, uint32(block.timestamp));

        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
        assertEq(vault.planVersion(), version + 1);
        assertEq(vault.totalSupply(), supply);
        assertEq(high.snapshot().liquidity, 0);
        assertEq(token0.balanceOf(address(router)), router0Before + 333 ether);
        assertEq(token1.balanceOf(address(router)), router1Before - 333 ether);
        assertEq(pair.balanceOf(address(v2)), 100_666.5 ether);
        _assertAssets(100_667 ether, 201_333 ether);
        AssetSnapshot memory assets = vault.assetSnapshot();
        assertEq(assets.idle0, 0.5 ether);
        assertEq(assets.idle1, 0);
        assertEq(assets.position0, 100_666.5 ether);
        assertEq(assets.position1, 201_333 ether);
        assertEq(token0.allowance(address(vault), address(v2)), 0);
        assertEq(token1.allowance(address(vault), address(v2)), 0);
    }

    function test_finalBootstrapDeploymentCountsDonationWhenPreviewIsMocked() public {
        _setV2ReserveRatioToOneToTwo();
        _donate(100_000 ether);
        oracle.setDeviation(350);
        // Isolate the final deployment check by deliberately overstating the preview.
        // With the real preview, bootstrap reverts with SwapRequired (covered above).
        vm.mockCall(
            address(v2), abi.encodeWithSelector(IPositionAdapter.previewDeposit.selector), abi.encode(SEED, SEED)
        );
        vault.bootstrap(SEED, SEED, address(this));
        assertTrue(vault.initialized());
        _assertDonationBackedFinalDeployment();
    }

    function test_finalPlainMigrationDeploymentCountsDonationWhenPreviewIsMocked() public {
        _bootstrap(150, SEED, SEED);
        _setV2ReserveRatioToOneToTwo();
        _donate(100_000 ether);
        // This is an isolated final-check test, not a normally reachable plain migration.
        vm.mockCall(
            address(v2), abi.encodeWithSelector(IPositionAdapter.previewDeposit.selector), abi.encode(SEED, SEED)
        );
        PositionPlan memory plan = _plan(350);
        vault.rebalance(plan.planHash, uint32(block.timestamp));
        _assertDonationBackedFinalDeployment();
    }

    function test_finalPlainMigrationRejectsLowDeploymentWithoutDonationWhenPreviewIsMocked() public {
        _bootstrap(150, SEED, SEED);
        _setV2ReserveRatioToOneToTwo();
        // Same overstated preview as the donation case, but the actual 75% deployment must fail.
        vm.mockCall(
            address(v2), abi.encodeWithSelector(IPositionAdapter.previewDeposit.selector), abi.encode(SEED, SEED)
        );
        PositionPlan memory plan = _plan(350);
        bytes32 history = _migrationHistory();
        vm.expectCall(address(v2), abi.encodeWithSelector(IPositionAdapter.deposit.selector));
        vm.expectRevert(IAdaptiveLPVault.DeploymentRatioTooLow.selector);
        vault.rebalance(plan.planHash, uint32(block.timestamp));

        assertEq(_migrationHistory(), history);
        assertEq(high.snapshot().principal0, SEED);
        assertEq(high.snapshot().principal1, SEED);
        assertEq(pair.balanceOf(address(v2)), 0);
        assertEq(token0.balanceOf(address(pair)), 1_000_000 ether);
        assertEq(token1.balanceOf(address(pair)), 2_000_000 ether);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);
        assertEq(token0.allowance(address(vault), address(v2)), 0);
        assertEq(token1.allowance(address(vault), address(v2)), 0);
        _assertAssets(SEED, SEED);
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

    function test_donationDoesNotBypassInsufficientSwapDeploymentAssessment() public {
        _bootstrap(150, 1500 ether, 500 ether);
        _setV2ReserveRatioToOneToTwo();
        _donate(100_000 ether);
        PositionPlan memory plan = _plan(350);
        bytes32 history = _migrationHistory();
        uint256 router0Before = token0.balanceOf(address(router));
        uint256 router1Before = token1.balanceOf(address(router));
        // Swapping only 500 leaves roughly 1000:1000, still incompatible with the 1:2 pool.
        // Existing LP donations cannot make the conservative post-swap preview pass.
        vm.expectRevert(IAdaptiveLPVault.DeploymentRatioTooLow.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));

        _assertRejectedV2Migration(1500 ether, 500 ether, history);
        assertEq(token0.balanceOf(address(router)), router0Before);
        assertEq(token1.balanceOf(address(router)), router1Before);
        assertEq(token0.balanceOf(address(vault.swapExecutor())), 0);
        assertEq(token1.balanceOf(address(vault.swapExecutor())), 0);
    }

    function test_finalSwapMigrationDeploymentCountsDonationWhenSimulatedPreviewIsMocked() public {
        _bootstrap(150, 1500 ether, 500 ether);
        _setV2ReserveRatioToOneToTwo();
        _donate(100_000 ether);
        // Override only the conservative post-swap preview to isolate the final check.
        // Without this override, the same swap is rejected by the preceding test.
        vm.mockCall(
            address(v2),
            abi.encodeWithSelector(IPositionAdapter.previewDeposit.selector, uint256(1000 ether), uint256(995 ether)),
            abi.encode(1000 ether, 995 ether)
        );
        PositionPlan memory plan = _plan(350);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
        _assertDonationBackedFinalDeployment();
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

    function _setV2ReserveRatioToOneToTwo() private {
        token1.mint(address(this), 1_000_000 ether);
        token1.transfer(address(pair), 1_000_000 ether);
        pair.sync();
    }

    function _assertDonationBackedFinalDeployment() private view {
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
        assertEq(pair.balanceOf(address(v2)), 100_500 ether);
        _assertAssets(101_000 ether, 201_000 ether);
        AssetSnapshot memory assets = vault.assetSnapshot();
        assertEq(assets.idle0, 500 ether);
        assertEq(assets.idle1, 0);
        assertEq(assets.position0, 100_500 ether);
        assertEq(assets.position1, 201_000 ether);
        // The fixture oracle values token0 and token1 equally. Without the donation,
        // only 1500 / 2000 is deployed; counting the donation raises this above minDeployBps.
        assertLt(Math.mulDiv(1500 ether, 10_000, 2000 ether), vault.minDeployBps());
        assertGe(
            Math.mulDiv(assets.position0 + assets.position1, 10_000, assets.total0 + assets.total1),
            vault.minDeployBps()
        );
    }

    function _migrationHistory() private view returns (bytes32) {
        return keccak256(
            abi.encode(vault.activeVenue(), vault.planVersion(), vault.lastPositionChangeAt(), vault.lastExecutedPlan())
        );
    }

    function _assertRejectedV2Migration(uint256 amount0, uint256 amount1, bytes32 history) private view {
        assertEq(_migrationHistory(), history);
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_HIGH_FEE));
        assertEq(vault.totalSupply(), amount0 + amount1);
        assertEq(high.snapshot().principal0, amount0);
        assertEq(high.snapshot().principal1, amount1);
        assertEq(pair.balanceOf(address(v2)), 100_000 ether);
        assertEq(token0.balanceOf(address(pair)), 1_000_000 ether);
        assertEq(token1.balanceOf(address(pair)), 2_000_000 ether);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);
        assertEq(token0.allowance(address(vault), address(v2)), 0);
        assertEq(token1.allowance(address(vault), address(v2)), 0);
        _assertAssets(amount0, amount1);
    }

    function _donate(uint256 liquidity) private {
        assertTrue(pair.transfer(address(v2), liquidity));
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
}
