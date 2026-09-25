// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SwapDirection} from "../swap/SwapTypes.sol";

/// @notice Enumerates every asset location supported by the vault.
/// @dev `IDLE` means the assets are held directly by the vault and no adapter is active.
enum VenueType {
    /// @notice Assets are held directly by the vault.
    IDLE,
    /// @notice Assets are deployed in the configured Uniswap V2 pair.
    UNISWAP_V2,
    /// @notice Assets are deployed in the configured low-fee Uniswap V3 pool.
    UNISWAP_V3_LOW_FEE,
    /// @notice Assets are deployed in the configured high-fee Uniswap V3 pool.
    UNISWAP_V3_HIGH_FEE
}

/// @notice Enumerates the market-deviation regimes produced by the vault strategy.
/// @dev Oracle health is represented separately by `OracleSnapshot.healthy`.
enum MarketRegime {
    /// @notice Canonical-price deviation is in the low band.
    LOW_DEVIATION,
    /// @notice Canonical-price deviation is in the medium band.
    MEDIUM_DEVIATION,
    /// @notice Canonical-price deviation is in the high band.
    HIGH_DEVIATION,
    /// @notice Canonical-price deviation is in the extreme band.
    EXTREME_DEVIATION
}

/// @notice Contains the vault's immutable deployment configuration.
/// @param dustTolerance0 Maximum accepted token0 rounding residue in raw token units.
/// @param dustTolerance1 Maximum accepted token1 rounding residue in raw token units.
/// @param canonicalOracle Address of the canonical V3 oracle.
/// @param router Address of the approved exact-input router used by the vault-created swap executor.
/// @param uniswapV2Factory Address of the expected Uniswap V2 factory used to validate V2 pairs.
/// @param uniswapV3Factory Address of the expected Uniswap V3 factory used to validate V3 pools.
/// @param minimumLockedShares Number of shares permanently minted to the vault during bootstrap.
/// @param minimumInitialNav Minimum bootstrap net asset value, denominated in raw token1 units.
struct VaultConfig {
    uint256 dustTolerance0;
    uint256 dustTolerance1;
    address canonicalOracle;
    address router;
    address uniswapV2Factory;
    address uniswapV3Factory;
    uint256 minimumLockedShares;
    uint256 minimumInitialNav;
}

/// @notice Contains the OpenZeppelin default-admin-rules constructor configuration.
/// @param initialDefaultAdminDelay Initial delay, in seconds, for default-admin transfers.
/// @param initialDefaultAdmin Initial holder of `DEFAULT_ADMIN_ROLE`.
struct AccessControlConfig {
    uint48 initialDefaultAdminDelay;
    address initialDefaultAdmin;
}

/// @notice Contains immutable strategy thresholds and safety limits.
/// @param minRebalanceCooldown Minimum interval, in seconds, between planned position changes.
/// @param enterMediumBps Deviation threshold for entering the medium regime, in basis points.
/// @param exitMediumBps Deviation threshold for leaving the medium regime, in basis points.
/// @param enterHighBps Deviation threshold for entering the high regime, in basis points.
/// @param exitHighBps Deviation threshold for leaving the high regime, in basis points.
/// @param enterExtremeBps Deviation threshold for entering the extreme regime, in basis points.
/// @param exitExtremeBps Deviation threshold for leaving the extreme regime, in basis points.
/// @param narrowRangeHalfWidthSteps Half-width of a narrow V3 range, measured in tick-spacing steps.
/// @param wideRangeHalfWidthSteps Half-width of a wide V3 range, measured in tick-spacing steps.
/// @param minRecenterBps Minimum displacement required to recenter a V3 range, in basis points.
/// @param maxHealthyIdleBps Maximum idle-asset ratio after a healthy deployment, in basis points.
/// @param maxSwapSlippageBps Maximum protocol swap slippage, in basis points.
/// @param maxMigrationLossBps Maximum net asset value loss during migration, in basis points.
struct StrategyConfig {
    uint32 minRebalanceCooldown;
    uint24 enterMediumBps;
    uint24 exitMediumBps;
    uint24 enterHighBps;
    uint24 exitHighBps;
    uint24 enterExtremeBps;
    uint24 exitExtremeBps;
    uint24 narrowRangeHalfWidthSteps;
    uint24 wideRangeHalfWidthSteps;
    uint16 minRecenterBps;
    uint16 maxHealthyIdleBps;
    uint16 maxSwapSlippageBps;
    uint16 maxMigrationLossBps;
}

/// @notice Describes all vault assets at a single observation point.
/// @param idle0 Amount of token0 held directly by the vault.
/// @param idle1 Amount of token1 held directly by the vault.
/// @param position0 Amount of token0 represented by the active position.
/// @param position1 Amount of token1 represented by the active position.
/// @param total0 Sum of idle and position token0 assets.
/// @param total1 Sum of idle and position token1 assets.
/// @param totalShares Vault share supply at the observation point.
struct AssetSnapshot {
    uint256 idle0;
    uint256 idle1;
    uint256 position0;
    uint256 position1;
    uint256 total0;
    uint256 total1;
    uint256 totalShares;
}

/// @notice Describes a normalized and versioned strategy decision.
/// @param planHash Hash of all plan fields other than `planHash` itself.
/// @param targetVenue Venue in which assets should reside after execution.
/// @param marketRegime Market regime committed as hysteresis history.
/// @param tickLower Target lower tick for V3, or zero for V2 and IDLE.
/// @param tickUpper Target upper tick for V3, or zero for V2 and IDLE.
/// @param version Monotonically increasing position-plan version.
struct PositionPlan {
    bytes32 planHash;
    VenueType targetVenue;
    MarketRegime marketRegime;
    int24 tickLower;
    int24 tickUpper;
    uint64 version;
}

/// @notice Describes whether deployment requires an inventory-balancing swap.
/// @param requiresSwap Whether the target adapter cannot deploy the assets without a swap.
/// @param direction Required swap direction, or `NONE` when no swap is needed.
struct DeploymentAssessment {
    bool requiresSwap;
    SwapDirection direction;
}

/// @notice Identifies a pausable vault entry point.
enum PauseFlag {
    /// @notice Deposit entry point.
    DEPOSIT,
    /// @notice Rebalance entry point that does not perform a swap.
    PLAIN_REBALANCE,
    /// @notice Rebalance entry point that performs a controlled swap.
    SWAP_REBALANCE
}

/// @notice Contains the vault's runtime pause state.
/// @param depositPaused Whether deposits are paused.
/// @param plainRebalancePaused Whether rebalances without a swap are paused.
/// @param swapRebalancePaused Whether rebalances with a swap are paused.
struct PauseState {
    bool depositPaused;
    bool plainRebalancePaused;
    bool swapRebalancePaused;
}

/// @notice Contains a validated registry entry for one non-IDLE venue.
/// @param venue Venue used as the registry key.
/// @param adapter Address of the adapter registered for the venue.
/// @param tickSpacing Validated V3 tick spacing, or zero for V2.
/// @param enabled Whether the adapter may establish or increase liquidity.
struct AdapterConfig {
    VenueType venue;
    address adapter;
    int24 tickSpacing;
    bool enabled;
}
