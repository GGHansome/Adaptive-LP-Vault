// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MarketRegime, PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
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
        input.strategy = _withStrategyField(input.strategy, 144, 24, 0);
        _expectInvalidRange(input);
        input.oracle.deviationBps = 100;
        input.highSpacing = 0;
        _expectInvalidRange(input);
        input.highSpacing = 60;
        input.strategy = _withStrategyField(input.strategy, 168, 24, 0);
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
        input.strategy = _withStrategyField(input.strategy, 144, 24, 1);
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

    function test_planInputsEncodeOnlyTwelveWords() public pure {
        VaultStrategyMath.PlanInputs memory input = _inputs();
        assertEq(abi.encode(input).length, 12 * 32);
        assertEq(abi.encode(_legacyInputs(input)).length, 41 * 32);
    }

    function test_strategyUnpackingHasExactFieldBoundaries() public pure {
        for (uint256 i; i < 9; ++i) {
            uint256 offset = i * 24;
            uint256 width = i == 8 ? 16 : 24;
            uint256 mask = (uint256(1) << width) - 1;
            uint256 packed = mask << offset;
            VaultStrategyMath.PlanStrategyConfig memory config = VaultStrategyMath.unpackPlanStrategyConfig(packed);
            bytes memory encoded = abi.encode(config);
            uint256[9] memory fields = abi.decode(encoded, (uint256[9]));
            for (uint256 j; j < 9; ++j) {
                assertEq(fields[j], i == j ? mask : 0);
            }
        }
        VaultStrategyMath.PlanStrategyConfig memory zeros = VaultStrategyMath.unpackPlanStrategyConfig(0);
        assertEq(abi.encode(zeros), new bytes(9 * 32));
    }

    function testFuzz_strategyUnpackingPreservesAllFieldBits(uint256 packed) public pure {
        VaultStrategyMath.PlanStrategyConfig memory config = VaultStrategyMath.unpackPlanStrategyConfig(packed);
        uint256[9] memory fields = abi.decode(abi.encode(config), (uint256[9]));
        uint256 reconstructed;
        for (uint256 i; i < 9; ++i) {
            uint256 mask = i == 8 ? type(uint16).max : type(uint24).max;
            assertEq(fields[i], (packed >> (24 * i)) & mask);
            reconstructed |= fields[i] << (24 * i);
        }
        assertEq(reconstructed, packed & ((uint256(1) << 208) - 1));
    }

    function testFuzz_packedStrategyMatchesLegacyForArbitraryFields(
        uint256 packed,
        uint256 deviation,
        uint8 previous,
        uint64 version,
        int24 tick
    ) public view {
        VaultStrategyMath.PlanInputs memory input = _activeInputs();
        input.strategy = packed;
        input.oracle.deviationBps = deviation;
        input.lastExecutedRegime = MarketRegime(previous % 4);
        input.planVersion = version;
        input.oracle.twapTick = tick;
        input.oracle.spotTick = 100;
        (bool actualSuccess, bytes memory actual) =
            address(harness).staticcall(abi.encodeCall(harness.getPlan, (input)));
        (bool expectedSuccess, bytes memory expected) =
            address(legacy).staticcall(abi.encodeCall(legacy.getPlan, (_legacyInputs(input))));
        assertEq(actualSuccess, expectedSuccess);
        if (
            !actualSuccess
                && keccak256(actual) == keccak256(abi.encodeWithSelector(IAdaptiveLPVault.PlanVersionOverflow.selector))
        ) {
            assertEq(expected, abi.encodeWithSelector(IAdaptiveLPVault.InvalidTickRange.selector));
        } else {
            assertEq(actual, expected);
        }
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
        input.currentPosition.tickLower = center - width;
        input.currentPosition.tickUpper = center + width;
        input.currentPosition.liquidity = hasLiquidity ? 1 : 0;
        input.strategy = _withStrategyField(input.strategy, 192, 16, bound(uint256(recenterBps), 0, 10_000));

        (bool actualSuccess, bytes memory actual) =
            address(harness).staticcall(abi.encodeCall(harness.getPlan, (input)));
        (bool expectedSuccess, bytes memory expected) =
            address(legacy).staticcall(abi.encodeCall(legacy.getPlan, (_legacyInputs(input))));
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

    function _legacyInputs(VaultStrategyMath.PlanInputs memory input)
        private
        pure
        returns (LegacyPositionPlannerReference.PlanInputs memory full)
    {
        full.oracle.deviationBps = input.oracle.deviationBps;
        full.oracle.twapTick = input.oracle.twapTick;
        full.oracle.spotTick = input.oracle.spotTick;
        full.oracle.healthy = true;
        full.currentPosition.liquidity = input.currentPosition.liquidity;
        full.currentPosition.tickLower = input.currentPosition.tickLower;
        full.currentPosition.tickUpper = input.currentPosition.tickUpper;
        // Independently decode the wire layout instead of calling the production unpacker.
        full.strategy.enterMediumBps = uint24(input.strategy);
        full.strategy.exitMediumBps = uint24(input.strategy >> 24);
        full.strategy.enterHighBps = uint24(input.strategy >> 48);
        full.strategy.exitHighBps = uint24(input.strategy >> 72);
        full.strategy.enterExtremeBps = uint24(input.strategy >> 96);
        full.strategy.exitExtremeBps = uint24(input.strategy >> 120);
        full.strategy.narrowRangeHalfWidthSteps = uint24(input.strategy >> 144);
        full.strategy.wideRangeHalfWidthSteps = uint24(input.strategy >> 168);
        full.strategy.minRecenterBps = uint16(input.strategy >> 192);
        full.lastExecutedRegime = input.lastExecutedRegime;
        full.activeVenue = input.activeVenue;
        full.lowSpacing = input.lowSpacing;
        full.highSpacing = input.highSpacing;
        full.planVersion = input.planVersion;
    }

    function _inputs() private pure returns (VaultStrategyMath.PlanInputs memory input) {
        input.activeVenue = VenueType.IDLE;
        input.lowSpacing = 10;
        input.highSpacing = 60;
        input.strategy = uint256(100) | (uint256(50) << 24) | (uint256(300) << 48) | (uint256(200) << 72)
            | (uint256(500) << 96) | (uint256(400) << 120) | (uint256(10) << 144) | (uint256(10) << 168)
            | (uint256(5000) << 192);
    }

    function _withStrategyField(uint256 packed, uint256 offset, uint256 width, uint256 value)
        private
        pure
        returns (uint256)
    {
        uint256 mask = (uint256(1) << width) - 1;
        return (packed & ~(mask << offset)) | ((value & mask) << offset);
    }

    function _activeInputs() private pure returns (VaultStrategyMath.PlanInputs memory input) {
        input = _inputs();
        input.planVersion = 7;
        input.activeVenue = VenueType.UNISWAP_V3_LOW_FEE;
        input.currentPosition = VaultStrategyMath.PlanPositionInputs({liquidity: 1, tickLower: -100, tickUpper: 100});
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
