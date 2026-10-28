// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MarketRegime, PositionPlan, StrategyConfig, VenueType} from "../../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../../src/interfaces/IAdaptiveLPVault.sol";
import {PositionSnapshot} from "../../../src/adapters/AdapterTypes.sol";
import {OracleSnapshot} from "../../../src/oracle/OracleTypes.sol";

/// @notice Frozen reference for the pre-extraction vault plan algorithm, with chain reads supplied as inputs.
/// @dev Keep independent from the production library so differential tests detect extraction regressions.
contract LegacyPositionPlannerReference {
    // Preserve the original full input shape independently of the production library.
    struct PlanInputs {
        OracleSnapshot oracle;
        PositionSnapshot currentPosition;
        StrategyConfig strategy;
        MarketRegime lastExecutedRegime;
        VenueType activeVenue;
        int24 lowSpacing;
        int24 highSpacing;
        uint64 planVersion;
    }

    function getPlan(PlanInputs memory input) external pure returns (PositionPlan memory plan) {
        MarketRegime regime =
            _nextRegime(input.oracle.deviationBps, input.planVersion, input.lastExecutedRegime, input.strategy);
        VenueType targetVenue = _venueForRegime(regime);
        int24 tickLower;
        int24 tickUpper;
        if (targetVenue == VenueType.UNISWAP_V3_LOW_FEE || targetVenue == VenueType.UNISWAP_V3_HIGH_FEE) {
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
                uint256 threshold = Math.mulDiv(uint256(currentWidth / 2), input.strategy.minRecenterBps, 10_000);
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
        plan.planHash = keccak256(
            abi.encode(uint8(plan.targetVenue), uint8(plan.marketRegime), plan.tickLower, plan.tickUpper, plan.version)
        );
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
        if (lower < -887272 || upper > 887272 || lower >= upper || lower > tick || upper < tick) {
            revert IAdaptiveLPVault.InvalidTickRange();
        }
        lowerTick = int24(lower);
        upperTick = int24(upper);
    }
}
