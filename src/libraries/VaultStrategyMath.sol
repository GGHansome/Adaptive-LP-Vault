// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {PositionSnapshot} from "../adapters/AdapterTypes.sol";
import {MarketRegime, PositionPlan, StrategyConfig, VenueType} from "../core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../interfaces/IAdaptiveLPVault.sol";
import {OracleSnapshot} from "../oracle/OracleTypes.sol";
import {PositionPlanHash} from "./PositionPlanHash.sol";

/// @title Vault Strategy Math
/// @notice Pure calculations for vault strategy and deployment assessment; currently implements position planning.
/// @dev Deploy and link this library before deploying the vault. External pure entry points keep calculations
///      out of the vault runtime. Chain reads, external queries, asset operations and state commits stay in the vault.
library VaultStrategyMath {
    uint256 private constant BPS = 10_000;
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = 887272;

    /// @notice Contains every dependency of the plan calculation, without separate asset snapshots or valuations.
    /// @param oracle Healthy canonical snapshot already checked by the vault.
    /// @param currentPosition Active position, or the canonical empty IDLE/bootstrap snapshot.
    /// @param strategy Immutable strategy configuration already validated by the vault.
    /// @param lastExecutedRegime Last committed strategy regime, independent of the current asset venue.
    /// @param activeVenue Current asset venue.
    /// @param lowSpacing Validated low-fee V3 pool tick spacing.
    /// @param highSpacing Validated high-fee V3 pool tick spacing.
    /// @param planVersion Current position-structure version; zero selects bootstrap classification.
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

    /// @notice Returns a candidate plan without committing its version or hysteresis history.
    /// @dev Oracle health, input provenance, configuration validity and execution gates are vault responsibilities.
    /// @param input Complete strategy inputs assembled by the vault from trusted on-chain sources.
    /// @return plan Normalized target venue, regime, ticks, next version and stable identity hash.
    function getPlan(PlanInputs memory input) external pure returns (PositionPlan memory plan) {
        MarketRegime regime =
            _nextRegime(input.oracle.deviationBps, input.planVersion, input.lastExecutedRegime, input.strategy);
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

    function _isV3Venue(VenueType venue) private pure returns (bool) {
        return venue == VenueType.UNISWAP_V3_LOW_FEE || venue == VenueType.UNISWAP_V3_HIGH_FEE;
    }
}
