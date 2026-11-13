// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Contains immutable canonical-oracle configuration.
/// @param canonicalPool Address of the canonical Uniswap V3 pool.
/// @param factory Address of the expected Uniswap V3 factory used to validate the canonical pool.
/// @param twapWindowSeconds Long time-weighted-average window in seconds.
/// @param shortTwapWindowSeconds Short time-weighted-average window in seconds.
struct OracleConfig {
    address canonicalPool;
    address factory;
    uint32 twapWindowSeconds;
    uint32 shortTwapWindowSeconds;
}

/// @notice Describes a canonical V3 pool observation used by value-sensitive vault operations.
/// @param spotTick Current pool tick.
/// @param twapTick Tick derived from the long time-weighted-average window.
/// @param shortTwapTick Tick derived from the short time-weighted-average window.
/// @param spotPriceToken1 Token1 raw units per whole token0 at the spot tick.
/// @param twapPriceToken1 Token1 raw units per whole token0 at the long-window tick.
/// @param shortTwapPriceToken1 Token1 raw units per whole token0 at the short-window tick.
/// @param deviationBps Strategy deviation derived from the canonical observations, in basis points.
/// @param twapWindowSeconds Long observation window used for the snapshot.
/// @param shortTwapWindowSeconds Short observation window used for the snapshot.
/// @param observedAt Timestamp at which the snapshot was produced.
/// @param healthy Whether all required observations and price calculations succeeded.
struct OracleSnapshot {
    int24 spotTick;
    int24 twapTick;
    int24 shortTwapTick;
    uint256 spotPriceToken1;
    uint256 twapPriceToken1;
    uint256 shortTwapPriceToken1;
    uint256 deviationBps;
    uint32 twapWindowSeconds;
    uint32 shortTwapWindowSeconds;
    uint32 observedAt;
    bool healthy;
}
