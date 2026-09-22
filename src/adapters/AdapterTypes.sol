// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VenueType} from "../core/VaultTypes.sol";

/// @notice Contains the immutable bindings supplied when deploying a position adapter.
/// @param vault Address of the only vault allowed to mutate adapter assets.
/// @param venue Venue represented by the adapter.
/// @param pool Address of the bound Uniswap pool or pair.
/// @param positionManager Address of the V3 position manager, or zero for a V2 adapter.
struct PositionAdapterConfig {
    address vault;
    VenueType venue;
    address pool;
    address positionManager;
}

/// @notice Describes the assets and native position state reported by one adapter.
/// @dev `amount0` and `amount1` must equal principal plus claimable fees for each token.
/// @param venue Venue represented by the snapshot.
/// @param adapter Address of the adapter that produced the snapshot.
/// @param principal0 Token0 principal currently deployed in the position.
/// @param principal1 Token1 principal currently deployed in the position.
/// @param claimableFee0 Token0 fees claimable by the position.
/// @param claimableFee1 Token1 fees claimable by the position.
/// @param amount0 Total token0 represented by the position.
/// @param amount1 Total token1 represented by the position.
/// @param liquidity Native liquidity units held by the adapter.
/// @param positionId Native position identifier; zero when the venue has no identifier.
/// @param tickLower Lower V3 tick; zero for V2 and an empty position.
/// @param tickUpper Upper V3 tick; zero for V2 and an empty position.
struct PositionSnapshot {
    VenueType venue;
    address adapter;
    uint256 principal0;
    uint256 principal1;
    uint256 claimableFee0;
    uint256 claimableFee1;
    uint256 amount0;
    uint256 amount1;
    uint256 liquidity;
    uint256 positionId;
    int24 tickLower;
    int24 tickUpper;
}
