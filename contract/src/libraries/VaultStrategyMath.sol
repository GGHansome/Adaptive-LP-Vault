// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {DeploymentAssessment, MarketRegime, PositionPlan, VenueType} from "../core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../interfaces/IAdaptiveLPVault.sol";
import {ICanonicalV3Oracle} from "../interfaces/ICanonicalV3Oracle.sol";
import {IPositionAdapter} from "../interfaces/IPositionAdapter.sol";
import {SwapDirection} from "../swap/SwapTypes.sol";

/// @title Vault Strategy Math
/// @notice Position planning and read-only deployment assessment for the vault.
/// @dev Deploy and link this library before deploying the vault. External entry points keep this logic out of
///      the vault runtime. Planning is pure; assessment queries only the adapter and oracle supplied by the vault.
///      Asset operations, execution gates and state commits stay in the vault.
library VaultStrategyMath {
    uint256 private constant BPS = 10_000;
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = 887272;

    /// @notice Only the canonical observation fields consumed by position planning.
    struct PlanOracleInputs {
        uint256 deviationBps;
        int24 twapTick;
        int24 spotTick;
    }

    /// @notice Only the active position fields consumed by range retention.
    struct PlanPositionInputs {
        uint256 liquidity;
        int24 tickLower;
        int24 tickUpper;
    }

    /// @notice Only immutable strategy parameters consumed by position planning.
    struct PlanStrategyConfig {
        uint24 enterMediumBps;
        uint24 exitMediumBps;
        uint24 enterHighBps;
        uint24 exitHighBps;
        uint24 enterExtremeBps;
        uint24 exitExtremeBps;
        uint24 narrowRangeHalfWidthSteps;
        uint24 wideRangeHalfWidthSteps;
        uint16 minRecenterBps;
    }

    /// @notice Contains exactly the fields consumed by the plan calculation.
    /// @param oracle Required fields from a healthy canonical snapshot already checked by the vault.
    /// @param currentPosition Active position liquidity and range, or zeros for IDLE/bootstrap.
    /// @param strategy Immutable strategy parameters validated and packed by the vault; see unpackPlanStrategyConfig.
    /// @param lastExecutedRegime Last committed strategy regime, independent of the current asset venue.
    /// @param activeVenue Current asset venue.
    /// @param lowSpacing Validated low-fee V3 pool tick spacing.
    /// @param highSpacing Validated high-fee V3 pool tick spacing.
    /// @param planVersion Current position-structure version; zero selects bootstrap classification.
    struct PlanInputs {
        PlanOracleInputs oracle;
        PlanPositionInputs currentPosition;
        uint256 strategy;
        MarketRegime lastExecutedRegime;
        VenueType activeVenue;
        int24 lowSpacing;
        int24 highSpacing;
        uint64 planVersion;
    }

    /// @notice Trusted assessment dependencies resolved by the vault for one observation phase.
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

    /// @notice Returns a candidate plan without committing its version or hysteresis history.
    /// @dev Oracle health, input provenance, configuration validity and execution gates are vault responsibilities.
    /// @param input Complete strategy inputs assembled by the vault from trusted on-chain sources.
    /// @return plan Normalized target venue, regime, ticks, next version and stable identity hash.
    function getPlan(PlanInputs memory input) external pure returns (PositionPlan memory plan) {
        PlanStrategyConfig memory strategy = unpackPlanStrategyConfig(input.strategy);
        MarketRegime regime =
            _nextRegime(input.oracle.deviationBps, input.planVersion, input.lastExecutedRegime, strategy);
        VenueType targetVenue = _venueForRegime(regime);
        int24 tickLower;
        int24 tickUpper;
        if (_isV3Venue(targetVenue)) {
            int24 spacing = targetVenue == VenueType.UNISWAP_V3_LOW_FEE ? input.lowSpacing : input.highSpacing;
            uint24 steps = regime == MarketRegime.LOW_DEVIATION
                ? strategy.narrowRangeHalfWidthSteps
                : strategy.wideRangeHalfWidthSteps;
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
                uint256 threshold = Math.mulDiv(uint256(currentWidth / 2), strategy.minRecenterBps, BPS);
                if (!widthChanged && !(spotOutside && delta >= threshold)) {
                    tickLower = input.currentPosition.tickLower;
                    tickUpper = input.currentPosition.tickUpper;
                }
            }
        }
        if (input.planVersion == type(uint64).max) revert IAdaptiveLPVault.PlanVersionOverflow();
        plan = PositionPlan({
            planHash: bytes32(0),
            targetVenue: targetVenue,
            marketRegime: regime,
            tickLower: tickLower,
            tickUpper: tickUpper,
            version: input.planVersion + 1
        });
        plan.planHash = _computePlanHash(plan);
    }

    /// @notice Assesses deployment using one adapter preview and independently rounded oracle valuations.
    /// @dev The vault resolves the enter-enabled adapter and supplies a healthy snapshot's TWAP tick.
    ///      Invalid previews revert before oracle queries; IDLE performs neither preview nor valuation.
    function assessDeployment(AssessmentInputs memory input)
        external
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
        uint256 assessmentNav =
            input.amount1 + ICanonicalV3Oracle(input.oracle).quoteToken0InToken1(input.amount0, input.twapTick, false);
        uint256 deployableNav =
            used1 + ICanonicalV3Oracle(input.oracle).quoteToken0InToken1(used0, input.twapTick, false);
        // The same formula applies to the initial assessment and the conservative swap simulation.
        uint256 deployableBps = assessmentNav == 0 ? 0 : Math.mulDiv(deployableNav, BPS, assessmentNav);
        assessment.requiresSwap = assessmentNav == 0 || deployableBps < input.minDeployBps;
        assessment.direction =
            excess0 ? SwapDirection.ZERO_FOR_ONE : excess1 ? SwapDirection.ONE_FOR_ZERO : SwapDirection.NONE;
    }

    /// @notice Decodes the fixed-width planning fields; unused high bits are ignored.
    /// @dev Configuration validity remains a vault constructor responsibility, as for the unpacked input.
    function unpackPlanStrategyConfig(uint256 packed) internal pure returns (PlanStrategyConfig memory config) {
        config = PlanStrategyConfig({
            enterMediumBps: uint24(packed),
            exitMediumBps: uint24(packed >> 24),
            enterHighBps: uint24(packed >> 48),
            exitHighBps: uint24(packed >> 72),
            enterExtremeBps: uint24(packed >> 96),
            exitExtremeBps: uint24(packed >> 120),
            narrowRangeHalfWidthSteps: uint24(packed >> 144),
            wideRangeHalfWidthSteps: uint24(packed >> 168),
            minRecenterBps: uint16(packed >> 192)
        });
    }

    /// @notice Hashes every plan field except `planHash` itself using the protocol-defined ABI encoding.
    function _computePlanHash(PositionPlan memory plan) private pure returns (bytes32) {
        return keccak256(
            abi.encode(uint8(plan.targetVenue), uint8(plan.marketRegime), plan.tickLower, plan.tickUpper, plan.version)
        );
    }

    function _nextRegime(uint256 deviation, uint64 version, MarketRegime previous, PlanStrategyConfig memory config)
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
