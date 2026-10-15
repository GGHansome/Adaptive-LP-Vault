// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {MarketRegime, PositionPlan, StrategyConfig, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {VaultStrategyMath} from "../../src/libraries/VaultStrategyMath.sol";
import {LegacyPositionPlannerReference} from "../helpers/LegacyPositionPlannerReference.sol";

/// @notice Exercises the same external-library call used by the vault, without its storage or dependencies.
contract VaultStrategyMathHarness {
    function getPlan(VaultStrategyMath.PlanInputs memory input) external pure returns (PositionPlan memory) {
        return VaultStrategyMath.getPlan(input);
    }
}

contract VaultStrategyMathTest is Test {
    VaultStrategyMathHarness private harness;
    LegacyPositionPlannerReference private legacy;

    function setUp() public {
        harness = new VaultStrategyMathHarness();
        legacy = new LegacyPositionPlannerReference();
    }

    function test_externalLibraryIsDeployedAndCalledFromPureEntryPoint() public {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        assertGt(address(VaultStrategyMath).code.length, 0);
        vm.expectCall(address(VaultStrategyMath), abi.encodeWithSelector(VaultStrategyMath.getPlan.selector, input));
        PositionPlan memory plan = harness.getPlan(input);
        _assertPlan(plan, MarketRegime.LOW_DEVIATION, VenueType.UNISWAP_V3_LOW_FEE, -100, 100, 1);
    }

    function test_linkedLibraryCanExecuteWithinStaticCall() public view {
        (bool success, bytes memory result) = address(harness).staticcall(abi.encodeCall(harness.getPlan, (_inputs())));
        assertTrue(success);
        _assertPlan(
            abi.decode(result, (PositionPlan)), MarketRegime.LOW_DEVIATION, VenueType.UNISWAP_V3_LOW_FEE, -100, 100, 1
        );
    }

    function test_bootstrapClassifiesAtCompleteEntryThresholds() public view {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        input.lastExecutedRegime = MarketRegime.EXTREME_DEVIATION;
        uint256[7] memory deviations = [uint256(0), 99, 100, 299, 300, 499, 500];
        MarketRegime[7] memory regimes = [
            MarketRegime.LOW_DEVIATION,
            MarketRegime.LOW_DEVIATION,
            MarketRegime.MEDIUM_DEVIATION,
            MarketRegime.MEDIUM_DEVIATION,
            MarketRegime.HIGH_DEVIATION,
            MarketRegime.HIGH_DEVIATION,
            MarketRegime.EXTREME_DEVIATION
        ];
        for (uint256 i; i < deviations.length; ++i) {
            input.oracle.deviationBps = deviations[i];
            PositionPlan memory plan = harness.getPlan(input);
            assertEq(uint8(plan.marketRegime), uint8(regimes[i]));
            assertEq(plan.version, 1);
            _assertHash(plan);
        }
    }

    function test_hysteresisUsesInclusiveBoundariesAndOnlyOneTransition() public view {
        _assertRegime(MarketRegime.LOW_DEVIATION, 99, MarketRegime.LOW_DEVIATION);
        _assertRegime(MarketRegime.LOW_DEVIATION, 100, MarketRegime.MEDIUM_DEVIATION);
        _assertRegime(MarketRegime.LOW_DEVIATION, 1000, MarketRegime.MEDIUM_DEVIATION);
        _assertRegime(MarketRegime.MEDIUM_DEVIATION, 50, MarketRegime.LOW_DEVIATION);
        _assertRegime(MarketRegime.MEDIUM_DEVIATION, 51, MarketRegime.MEDIUM_DEVIATION);
        _assertRegime(MarketRegime.MEDIUM_DEVIATION, 299, MarketRegime.MEDIUM_DEVIATION);
        _assertRegime(MarketRegime.MEDIUM_DEVIATION, 300, MarketRegime.HIGH_DEVIATION);
        _assertRegime(MarketRegime.HIGH_DEVIATION, 200, MarketRegime.MEDIUM_DEVIATION);
        _assertRegime(MarketRegime.HIGH_DEVIATION, 201, MarketRegime.HIGH_DEVIATION);
        _assertRegime(MarketRegime.HIGH_DEVIATION, 499, MarketRegime.HIGH_DEVIATION);
        _assertRegime(MarketRegime.HIGH_DEVIATION, 500, MarketRegime.EXTREME_DEVIATION);
        _assertRegime(MarketRegime.EXTREME_DEVIATION, 400, MarketRegime.HIGH_DEVIATION);
        _assertRegime(MarketRegime.EXTREME_DEVIATION, 401, MarketRegime.EXTREME_DEVIATION);
        _assertRegime(MarketRegime.EXTREME_DEVIATION, 0, MarketRegime.HIGH_DEVIATION);
    }

    function test_mediumRegimeUsesHighFeeSpacingAndWideRange() public view {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        input.oracle.deviationBps = 100;
        input.oracle.twapTick = 17;
        _assertPlan(harness.getPlan(input), MarketRegime.MEDIUM_DEVIATION, VenueType.UNISWAP_V3_HIGH_FEE, -600, 600, 1);
    }

    function test_nonV3PlansNormalizeTicksAndDoNotNeedSpacing() public view {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        input.lowSpacing = 0;
        input.highSpacing = 0;
        input.currentPosition.tickLower = -100;
        input.currentPosition.tickUpper = 100;
        input.currentPosition.liquidity = 1;
        input.oracle.deviationBps = 300;
        _assertPlan(harness.getPlan(input), MarketRegime.HIGH_DEVIATION, VenueType.UNISWAP_V2, 0, 0, 1);
        input.oracle.deviationBps = 500;
        _assertPlan(harness.getPlan(input), MarketRegime.EXTREME_DEVIATION, VenueType.IDLE, 0, 0, 1);
    }

    function test_rangeRoundingHandlesBothSignsAndTiesDownward() public view {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        int24[6] memory ticks = [int24(-17), -5, -4, 4, 5, 6];
        int24[6] memory centers = [int24(-20), -10, 0, 0, 0, 10];
        for (uint256 i; i < ticks.length; ++i) {
            input.oracle.twapTick = ticks[i];
            PositionPlan memory plan = harness.getPlan(input);
            assertEq(plan.tickLower, centers[i] - 100);
            assertEq(plan.tickUpper, centers[i] + 100);
        }
    }

    function test_sameVenueKeepsRangeWhenSpotIsInsideIncludingLowerBound() public view {
        VaultStrategyMath.PlanInputs memory input = _activeInputs();
        input.oracle.twapTick = 100;
        input.oracle.spotTick = -100;
        _assertPlan(harness.getPlan(input), MarketRegime.LOW_DEVIATION, VenueType.UNISWAP_V3_LOW_FEE, -100, 100, 8);
        input.oracle.spotTick = 99;
        assertEq(harness.getPlan(input).tickLower, -100);
    }

    function test_spotOutsideKeepsRangeBelowRecenterThreshold() public view {
        VaultStrategyMath.PlanInputs memory input = _activeInputs();
        input.oracle.spotTick = 100;
        input.oracle.twapTick = 40;
        assertEq(harness.getPlan(input).tickLower, -100);
    }

    function test_spotAtUpperBoundRecentersAtExactThreshold() public view {
        VaultStrategyMath.PlanInputs memory input = _activeInputs();
        input.oracle.spotTick = 100;
        input.oracle.twapTick = 50;
        _assertPlan(harness.getPlan(input), MarketRegime.LOW_DEVIATION, VenueType.UNISWAP_V3_LOW_FEE, -50, 150, 8);
    }

    function test_spotBelowLowerBoundRecentersAtExactThreshold() public view {
        VaultStrategyMath.PlanInputs memory input = _activeInputs();
        input.oracle.spotTick = -101;
        input.oracle.twapTick = -50;
        _assertPlan(harness.getPlan(input), MarketRegime.LOW_DEVIATION, VenueType.UNISWAP_V3_LOW_FEE, -150, 50, 8);
    }

    function test_widthChangeRecentersEvenWithSpotInside() public view {
        VaultStrategyMath.PlanInputs memory input = _activeInputs();
        input.currentPosition.tickLower = -200;
        input.currentPosition.tickUpper = 200;
        _assertPlan(harness.getPlan(input), MarketRegime.LOW_DEVIATION, VenueType.UNISWAP_V3_LOW_FEE, -100, 100, 8);
    }

    function test_zeroLiquidityAndDifferentVenueDoNotRetainOldRange() public view {
        VaultStrategyMath.PlanInputs memory input = _activeInputs();
        input.oracle.twapTick = 50;
        input.currentPosition.liquidity = 0;
        assertEq(harness.getPlan(input).tickLower, -50);
        input.currentPosition.liquidity = 1;
        input.activeVenue = VenueType.UNISWAP_V3_HIGH_FEE;
        assertEq(harness.getPlan(input).tickLower, -50);
    }

    function test_idleUsesHistoricalRegimeRatherThanCurrentVenue() public view {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        input.planVersion = 7;
        input.lastExecutedRegime = MarketRegime.EXTREME_DEVIATION;
        input.oracle.deviationBps = 0;
        _assertPlan(harness.getPlan(input), MarketRegime.HIGH_DEVIATION, VenueType.UNISWAP_V2, 0, 0, 8);
    }

    function test_rejectsNonPositiveSpacingAndZeroSteps() public {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        input.lowSpacing = 0;
        _expectInvalidRange(input);
        input.lowSpacing = -10;
        _expectInvalidRange(input);
        input.lowSpacing = 10;
        input.strategy.narrowRangeHalfWidthSteps = 0;
        _expectInvalidRange(input);
        input.oracle.deviationBps = 100;
        input.highSpacing = 0;
        _expectInvalidRange(input);
        input.highSpacing = 60;
        input.strategy.wideRangeHalfWidthSteps = 0;
        _expectInvalidRange(input);
    }

    function test_rejectsOutOfBoundsRangeInsteadOfClamping() public {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        input.oracle.twapTick = -887272;
        _expectInvalidRange(input);
        input.oracle.twapTick = 887272;
        _expectInvalidRange(input);
    }

    function test_acceptsExactV3TickBounds() public view {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        input.lowSpacing = 1;
        input.strategy.narrowRangeHalfWidthSteps = 1;
        input.oracle.twapTick = -887271;
        assertEq(harness.getPlan(input).tickLower, -887272);
        input.oracle.twapTick = 887271;
        assertEq(harness.getPlan(input).tickUpper, 887272);
    }

    function test_maximumVersionRevertsAndPenultimateVersionSucceeds() public {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        input.planVersion = type(uint64).max - 1;
        assertEq(harness.getPlan(input).version, type(uint64).max);
        input.planVersion = type(uint64).max;
        vm.expectRevert(IAdaptiveLPVault.PlanVersionOverflow.selector);
        harness.getPlan(input);
        input.lastExecutedRegime = MarketRegime.EXTREME_DEVIATION;
        input.oracle.deviationBps = 501;
        vm.expectRevert(IAdaptiveLPVault.PlanVersionOverflow.selector);
        harness.getPlan(input);
    }

    function test_positionAmountsAndOracleMetadataDoNotAffectPlan() public view {
        VaultStrategyMath.PlanInputs memory input = _activeInputs();
        bytes32 expected = keccak256(abi.encode(harness.getPlan(input)));
        input.currentPosition.adapter = address(123);
        input.currentPosition.principal0 = 1 ether;
        input.currentPosition.principal1 = 2 ether;
        input.currentPosition.claimableFee0 = 3;
        input.currentPosition.claimableFee1 = 4;
        input.currentPosition.amount0 = 1 ether + 3;
        input.currentPosition.amount1 = 2 ether + 4;
        input.currentPosition.positionId = 999;
        input.oracle.shortTwapTick = 999;
        input.oracle.spotPriceToken1 = 1 ether;
        input.oracle.twapPriceToken1 = 2 ether;
        input.oracle.shortTwapPriceToken1 = 3 ether;
        input.oracle.observedAt = 123;
        input.oracle.twapWindowSeconds = 1800;
        input.oracle.shortTwapWindowSeconds = 300;
        assertEq(keccak256(abi.encode(harness.getPlan(input))), expected);
    }

    function testFuzz_planMatchesPreExtractionAlgorithm(
        uint256 deviation,
        uint8 previous,
        uint8 venue,
        uint64 version,
        int24 twap,
        int24 spot,
        int24 oldCenter,
        uint24 halfWidth,
        bool hasLiquidity,
        uint16 recenterBps
    ) public view {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        input.oracle.deviationBps = bound(deviation, 0, 1000);
        input.oracle.twapTick = int24(bound(int256(twap), -887272, 887272));
        input.oracle.spotTick = int24(bound(int256(spot), -887272, 887272));
        input.lastExecutedRegime = MarketRegime(previous % 4);
        input.activeVenue = VenueType(venue % 4);
        input.planVersion = version;
        int24 center = int24(bound(int256(oldCenter), -800000, 800000));
        int24 width = int24(int256(bound(uint256(halfWidth), 1, 80000)));
        input.currentPosition.venue = input.activeVenue;
        input.currentPosition.tickLower = center - width;
        input.currentPosition.tickUpper = center + width;
        input.currentPosition.liquidity = hasLiquidity ? 1 : 0;
        input.strategy.minRecenterBps = uint16(bound(uint256(recenterBps), 0, 10_000));

        (bool actualSuccess, bytes memory actual) =
            address(harness).staticcall(abi.encodeCall(harness.getPlan, (input)));
        (bool expectedSuccess, bytes memory expected) =
            address(legacy).staticcall(abi.encodeCall(legacy.getPlan, (input)));
        assertEq(actualSuccess, expectedSuccess);
        // The frozen reference uses InvalidTickRange for version exhaustion; only that selector intentionally changed.
        if (
            !actualSuccess && input.planVersion == type(uint64).max
                && keccak256(actual) == keccak256(abi.encodeWithSelector(IAdaptiveLPVault.PlanVersionOverflow.selector))
        ) {
            assertEq(expected, abi.encodeWithSelector(IAdaptiveLPVault.InvalidTickRange.selector));
        } else {
            assertEq(actual, expected);
        }
    }

    function testFuzz_bootstrapRangesAreAlignedCoverTwapAndHaveStableHash(int24 tick, bool medium) public view {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        input.oracle.twapTick = int24(bound(int256(tick), -880000, 880000));
        input.oracle.deviationBps = medium ? 100 : 0;
        PositionPlan memory plan = harness.getPlan(input);
        int24 spacing = medium ? input.highSpacing : input.lowSpacing;
        assertEq(plan.tickLower % spacing, 0);
        assertEq(plan.tickUpper % spacing, 0);
        assertLe(plan.tickLower, input.oracle.twapTick);
        assertGe(plan.tickUpper, input.oracle.twapTick);
        assertLt(plan.tickLower, plan.tickUpper);
        assertEq(int256(plan.tickUpper) - int256(plan.tickLower), medium ? int256(1200) : int256(200));
        _assertHash(plan);
        assertEq(keccak256(abi.encode(harness.getPlan(input))), keccak256(abi.encode(plan)));
    }

    function _inputs() private pure returns (VaultStrategyMath.PlanInputs memory input) {
        input.oracle.healthy = true;
        input.currentPosition.venue = VenueType.IDLE;
        input.activeVenue = VenueType.IDLE;
        input.lowSpacing = 10;
        input.highSpacing = 60;
        input.strategy = StrategyConfig({
            minRebalanceCooldown: 300,
            enterMediumBps: 100,
            exitMediumBps: 50,
            enterHighBps: 300,
            exitHighBps: 200,
            enterExtremeBps: 500,
            exitExtremeBps: 400,
            narrowRangeHalfWidthSteps: 10,
            wideRangeHalfWidthSteps: 10,
            minRecenterBps: 5000,
            maxHealthyIdleBps: 100,
            maxSwapSlippageBps: 100,
            maxMigrationLossBps: 100
        });
    }

    function _activeInputs() private pure returns (VaultStrategyMath.PlanInputs memory input) {
        input = _inputs();
        input.planVersion = 7;
        input.activeVenue = VenueType.UNISWAP_V3_LOW_FEE;
        input.currentPosition = PositionSnapshot({
            venue: input.activeVenue,
            adapter: address(0),
            principal0: 0,
            principal1: 0,
            claimableFee0: 0,
            claimableFee1: 0,
            amount0: 0,
            amount1: 0,
            liquidity: 1,
            positionId: 1,
            tickLower: -100,
            tickUpper: 100
        });
    }

    function _assertRegime(MarketRegime previous, uint256 deviation, MarketRegime expected) private view {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        input.planVersion = 7;
        input.lastExecutedRegime = previous;
        input.oracle.deviationBps = deviation;
        assertEq(uint8(harness.getPlan(input).marketRegime), uint8(expected));
    }

    function _assertPlan(
        PositionPlan memory plan,
        MarketRegime regime,
        VenueType venue,
        int24 lower,
        int24 upper,
        uint64 version
    ) private pure {
        assertEq(uint8(plan.marketRegime), uint8(regime));
        assertEq(uint8(plan.targetVenue), uint8(venue));
        assertEq(plan.tickLower, lower);
        assertEq(plan.tickUpper, upper);
        assertEq(plan.version, version);
        _assertHash(plan);
    }

    function _assertHash(PositionPlan memory plan) private pure {
        assertEq(
            plan.planHash,
            keccak256(
                abi.encode(
                    uint8(plan.targetVenue), uint8(plan.marketRegime), plan.tickLower, plan.tickUpper, plan.version
                )
            )
        );
    }

    function _expectInvalidRange(VaultStrategyMath.PlanInputs memory input) private {
        vm.expectRevert(IAdaptiveLPVault.InvalidTickRange.selector);
        harness.getPlan(input);
    }
}
