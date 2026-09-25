// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OracleSnapshot} from "../oracle/OracleTypes.sol";

/// @notice Exposes canonical Uniswap V3 observations and bidirectional token quotes.
interface ICanonicalV3Oracle {
    /// @notice Indicates that the immutable oracle configuration is invalid.
    error InvalidOracleConfiguration();

    /// @notice Indicates that the configured canonical pool is not registered by the expected V3 factory.
    error InvalidCanonicalPool();

    /// @notice Indicates that pool tokens are zero, equal, or not ordered by address.
    error InvalidTokenOrder();

    /// @notice Indicates that a token's `decimals()` metadata could not be read.
    /// @param token Address of the token whose metadata read failed.
    error InvalidTokenMetadata(address token);

    /// @notice Indicates that a token reports more than 18 decimals.
    /// @param token Address of the token with an invalid decimal count.
    /// @param actual Decimal count returned by the token.
    error InvalidTokenDecimals(address token, uint8 actual);

    /// @notice Indicates that a supplied tick is outside the range supported by Uniswap V3.
    /// @param tick Invalid tick supplied to a quote function.
    error InvalidTick(int24 tick);

    /// @notice Returns one canonical spot and time-weighted observation.
    /// @dev Observation or dynamic-price failures are represented by `healthy == false` rather than bubbled reverts.
    /// @return oracleSnapshot Canonical observation in the pool's ordered token convention.
    function snapshot() external view returns (OracleSnapshot memory oracleSnapshot);

    /// @notice Quotes token0 in raw token1 units at a supplied tick.
    /// @param amount0 Amount of token0 in raw units.
    /// @param tick Tick used for the conversion.
    /// @param roundUp Whether to round the result upward instead of downward.
    /// @return amount1 Equivalent amount of token1 in raw units.
    function quoteToken0InToken1(uint256 amount0, int24 tick, bool roundUp) external view returns (uint256 amount1);

    /// @notice Quotes token1 in raw token0 units at a supplied tick.
    /// @param amount1 Amount of token1 in raw units.
    /// @param tick Tick used for the conversion.
    /// @param roundUp Whether to round the result upward instead of downward.
    /// @return amount0 Equivalent amount of token0 in raw units.
    function quoteToken1InToken0(uint256 amount1, int24 tick, bool roundUp) external view returns (uint256 amount0);

    /// @notice Reports whether the current canonical observation is healthy.
    /// @return healthy True when all required observations and price calculations succeed.
    function isHealthy() external view returns (bool healthy);

    /// @notice Returns the canonical Uniswap V3 pool.
    /// @return pool Address of the canonical pool.
    function canonicalPool() external view returns (address pool);

    /// @notice Returns the lower-address token bound to the oracle.
    /// @return token Address of token0.
    function token0() external view returns (address token);

    /// @notice Returns the higher-address token bound to the oracle.
    /// @return token Address of token1.
    function token1() external view returns (address token);

    /// @notice Returns the immutable decimal count of token0.
    /// @return decimals Decimal count of token0.
    function token0Decimals() external view returns (uint8 decimals);

    /// @notice Returns the immutable decimal count of token1.
    /// @return decimals Decimal count of token1.
    function token1Decimals() external view returns (uint8 decimals);
}
