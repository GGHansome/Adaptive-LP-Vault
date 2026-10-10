// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AdapterConfig, VenueType} from "../core/VaultTypes.sol";

/// @notice Exposes adapter registration and entry-status controls at a vault's dedicated control address.
interface IAdapterRegistry {
    /// @notice Indicates that an initialization-only operation was called after bootstrap.
    error AlreadyInitialized();

    /// @notice Indicates that an operation requiring bootstrap was called before initialization.
    error NotInitialized();

    /// @notice Indicates that a component's ordered token pair differs from the vault pair.
    error InvalidAssetPair();

    /// @notice Indicates that the executor's swap pool is not the canonical pool.
    error InvalidSwapPool();

    /// @notice Indicates that an adapter exposes an invalid or inconsistent V3 tick spacing.
    error InvalidTickSpacing();

    /// @notice Indicates that no adapter is registered for the requested non-IDLE venue.
    error AdapterNotRegistered();

    /// @notice Indicates that an adapter may not establish or increase liquidity.
    error AdapterDisabled();

    /// @notice Emitted after an adapter is validated and registered for a venue.
    /// @param venue Non-IDLE venue assigned to the adapter.
    /// @param adapter Address of the validated adapter.
    /// @param pool Address of the pool bound to the adapter.
    /// @param feeTier Validated V3 fee tier, or zero for V2.
    /// @param tickSpacing Validated V3 tick spacing, or zero for V2.
    event AdapterConfigured(
        VenueType indexed venue, address indexed adapter, address indexed pool, uint24 feeTier, int24 tickSpacing
    );

    /// @notice Emitted after a registered adapter's entry status changes.
    /// @param venue Venue whose entry status changed.
    /// @param adapter Address currently registered for the venue.
    /// @param enabled Whether the adapter may establish or increase liquidity.
    event AdapterStatusChanged(VenueType indexed venue, address indexed adapter, bool enabled);

    /// @notice Validates and registers an independently deployed adapter before bootstrap.
    /// @dev Reconfiguration is permitted only before bootstrap and freezes after initialization.
    /// @param venue Non-IDLE venue to configure.
    /// @param adapter Address of the adapter to validate and register.
    function configureAdapter(VenueType venue, address adapter) external;

    /// @notice Returns the adapter registered for a venue.
    /// @dev Returns the zero address for `IDLE` and for an unregistered venue.
    /// @param venue Venue to query.
    /// @return adapter Address registered for the venue.
    function getAdapter(VenueType venue) external view returns (address adapter);

    /// @notice Returns the complete registry configuration for a venue.
    /// @param venue Venue to query.
    /// @return config Stored adapter configuration.
    function getConfig(VenueType venue) external view returns (AdapterConfig memory config);

    /// @notice Reports whether a venue's adapter may establish or increase liquidity.
    /// @param venue Venue to query.
    /// @return enabled True only when a nonzero registered adapter is enabled.
    function isEnterEnabled(VenueType venue) external view returns (bool enabled);

    /// @notice Changes whether a registered adapter may establish or increase liquidity.
    /// @dev Disabling an adapter does not prevent valuation, fee synchronization, or exit.
    /// @param venue Venue whose adapter status will change.
    /// @param enabled New entry status.
    function setAdapterEnabled(VenueType venue, bool enabled) external;
}
