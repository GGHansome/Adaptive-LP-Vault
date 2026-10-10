// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAdapterRegistry} from "../interfaces/IAdapterRegistry.sol";
import {IPositionAdapter} from "../interfaces/IPositionAdapter.sol";
import {IUniswapV2Factory, IUniswapV2Pair} from "../interfaces/IUniswapV2External.sol";
import {IUniswapV3Factory, IUniswapV3Pool} from "../interfaces/IUniswapV3External.sol";
import {AdapterConfig, VenueType} from "./VaultTypes.sol";
import {VaultRoles} from "./VaultRoles.sol";

/// @title Vault Adapter Registry
/// @notice Validates and stores the vault's fixed adapter identities and mutable entry status.
/// @dev Adapter identities may be replaced before bootstrap. After bootstrap only `enabled` may change.
abstract contract AdapterRegistry is VaultRoles, IAdapterRegistry {
    mapping(VenueType venue => AdapterConfig config) private _adapterByVenue;

    struct ValidatedBinding {
        address pool;
        uint24 feeTier;
        int24 tickSpacing;
    }

    /// @inheritdoc IAdapterRegistry
    function configureAdapter(VenueType venue, address adapter) external override {
        _checkManager();
        if (_vaultInitialized()) revert AlreadyInitialized();

        ValidatedBinding memory binding = _validateAdapterBinding(venue, adapter);
        _adapterByVenue[venue] =
            AdapterConfig({venue: venue, adapter: adapter, tickSpacing: binding.tickSpacing, enabled: true});

        emit AdapterConfigured(venue, adapter, binding.pool, binding.feeTier, binding.tickSpacing);
    }

    /// @inheritdoc IAdapterRegistry
    function getAdapter(VenueType venue) public view override returns (address adapter) {
        if (venue == VenueType.IDLE) return address(0);
        return _adapterByVenue[venue].adapter;
    }

    /// @inheritdoc IAdapterRegistry
    function getConfig(VenueType venue) public view override returns (AdapterConfig memory config) {
        if (venue == VenueType.IDLE) return config;
        return _adapterByVenue[venue];
    }

    /// @inheritdoc IAdapterRegistry
    function isEnterEnabled(VenueType venue) public view override returns (bool enabled) {
        if (venue == VenueType.IDLE) return false;
        AdapterConfig storage config = _adapterByVenue[venue];
        return config.adapter != address(0) && config.enabled;
    }

    /// @inheritdoc IAdapterRegistry
    function setAdapterEnabled(VenueType venue, bool enabled) external override {
        if (enabled) {
            _checkManager();
        } else {
            _checkManagerOrGuardian();
        }

        // Role-gated lifecycle methods deliberately authorize before revealing lifecycle state.
        if (!_vaultInitialized()) revert NotInitialized();

        AdapterConfig storage config = _adapterByVenue[venue];
        if (venue == VenueType.IDLE || config.adapter == address(0)) revert AdapterNotRegistered();
        if (config.enabled == enabled) return;

        config.enabled = enabled;
        emit AdapterStatusChanged(venue, config.adapter, enabled);
    }

    /// @notice Returns whether the final vault has completed bootstrap.
    /// @dev The final vault overrides this hook with its lifecycle storage.
    function _vaultInitialized() internal view virtual returns (bool);

    /// @notice Returns the asset-bearing vault that every adapter must be bound to.
    function _registryVault() internal view virtual returns (address);

    /// @notice Returns the vault's immutable token0 binding.
    function _registryToken0() internal view virtual returns (address);

    /// @notice Returns the vault's immutable token1 binding.
    function _registryToken1() internal view virtual returns (address);

    /// @notice Returns the expected Uniswap V2 factory used to validate registered pairs.
    function _registryV2Factory() internal view virtual returns (address);

    /// @notice Returns the expected Uniswap V3 factory used to validate registered pools.
    function _registryV3Factory() internal view virtual returns (address);

    /// @notice Revalidates every required v1 adapter and its cached spacing before bootstrap commits.
    function _validateConfiguredAdapters() internal view {
        _revalidateConfiguredAdapter(VenueType.UNISWAP_V2);
        _revalidateConfiguredAdapter(VenueType.UNISWAP_V3_LOW_FEE);
        _revalidateConfiguredAdapter(VenueType.UNISWAP_V3_HIGH_FEE);
    }

    /// @notice Returns a registered adapter or reverts for IDLE and missing entries.
    function _getAdapterOrRevert(VenueType venue) internal view returns (address adapter) {
        adapter = getAdapter(venue);
        if (adapter == address(0)) revert AdapterNotRegistered();
    }

    /// @notice Enforces that a non-IDLE venue can establish or increase liquidity.
    function _requireEnterEnabled(VenueType venue) internal view returns (address adapter) {
        adapter = _getAdapterOrRevert(venue);
        if (!_adapterByVenue[venue].enabled) revert AdapterDisabled();
    }

    /// @notice Returns the validated cached tick spacing for a registered venue.
    function _adapterTickSpacing(VenueType venue) internal view returns (int24 spacing) {
        AdapterConfig storage config = _adapterByVenue[venue];
        if (venue == VenueType.IDLE || config.adapter == address(0)) revert AdapterNotRegistered();
        return config.tickSpacing;
    }

    function _revalidateConfiguredAdapter(VenueType venue) private view {
        AdapterConfig storage config = _adapterByVenue[venue];
        if (config.adapter == address(0)) revert AdapterNotRegistered();

        ValidatedBinding memory binding = _validateAdapterBinding(venue, config.adapter);
        if (binding.tickSpacing != config.tickSpacing) revert InvalidTickSpacing();
    }

    function _validateAdapterBinding(VenueType venue, address adapter)
        private
        view
        returns (ValidatedBinding memory binding)
    {
        if (venue == VenueType.IDLE || adapter == address(0) || adapter.code.length == 0) {
            revert IPositionAdapter.InvalidAdapterConfiguration();
        }

        IPositionAdapter candidate = IPositionAdapter(adapter);
        address adapterVault;
        VenueType adapterVenue;
        address adapterPool;
        address adapterToken0;
        address adapterToken1;
        uint24 adapterFeeTier;
        int24 adapterTickSpacing;

        try candidate.vault() returns (address value) {
            adapterVault = value;
        } catch {
            revert IPositionAdapter.InvalidAdapterConfiguration();
        }
        try candidate.venue() returns (VenueType value) {
            adapterVenue = value;
        } catch {
            revert IPositionAdapter.InvalidAdapterConfiguration();
        }
        if (adapterVault != _registryVault() || adapterVenue != venue) {
            revert IPositionAdapter.InvalidAdapterConfiguration();
        }

        try candidate.pool() returns (address value) {
            adapterPool = value;
        } catch {
            revert IPositionAdapter.InvalidPoolBinding();
        }
        if (adapterPool == address(0) || adapterPool.code.length == 0) {
            revert IPositionAdapter.InvalidPoolBinding();
        }

        try candidate.token0() returns (address value) {
            adapterToken0 = value;
        } catch {
            revert InvalidAssetPair();
        }
        try candidate.token1() returns (address value) {
            adapterToken1 = value;
        } catch {
            revert InvalidAssetPair();
        }

        address poolToken0;
        address poolToken1;
        try IUniswapV2Pair(adapterPool).token0() returns (address value) {
            poolToken0 = value;
        } catch {
            revert IPositionAdapter.InvalidPoolBinding();
        }
        try IUniswapV2Pair(adapterPool).token1() returns (address value) {
            poolToken1 = value;
        } catch {
            revert IPositionAdapter.InvalidPoolBinding();
        }
        _validateAssetPair(poolToken0, poolToken1);
        if (adapterToken0 != poolToken0 || adapterToken1 != poolToken1) revert InvalidAssetPair();

        try candidate.feeTier() returns (uint24 value) {
            adapterFeeTier = value;
        } catch {
            revert IPositionAdapter.InvalidPoolBinding();
        }
        try candidate.tickSpacing() returns (int24 value) {
            adapterTickSpacing = value;
        } catch {
            revert InvalidTickSpacing();
        }

        address expectedFactory = venue == VenueType.UNISWAP_V2 ? _registryV2Factory() : _registryV3Factory();
        if (expectedFactory == address(0) || expectedFactory.code.length == 0) {
            revert IPositionAdapter.InvalidPoolBinding();
        }

        if (venue == VenueType.UNISWAP_V2) {
            _validateV2Pool(adapterPool, poolToken0, poolToken1, adapterFeeTier, adapterTickSpacing, expectedFactory);
        } else {
            _validateV3Pool(adapterPool, poolToken0, poolToken1, adapterFeeTier, adapterTickSpacing, expectedFactory);
        }

        binding = ValidatedBinding({pool: adapterPool, feeTier: adapterFeeTier, tickSpacing: adapterTickSpacing});
    }

    function _validateAssetPair(address actualToken0, address actualToken1) private view {
        if (
            actualToken0 == address(0) || actualToken1 == address(0) || actualToken0 == actualToken1
                || actualToken0 >= actualToken1
        ) {
            revert IPositionAdapter.InvalidTokenOrder();
        }
        if (actualToken0 != _registryToken0() || actualToken1 != _registryToken1()) revert InvalidAssetPair();
    }

    function _validateV2Pool(
        address pool,
        address poolToken0,
        address poolToken1,
        uint24 adapterFeeTier,
        int24 adapterTickSpacing,
        address expectedFactory
    ) private view {
        if (adapterFeeTier != 0) revert IPositionAdapter.InvalidPoolBinding();
        if (adapterTickSpacing != 0) revert InvalidTickSpacing();

        address poolFactory;
        try IUniswapV2Pair(pool).factory() returns (address value) {
            poolFactory = value;
        } catch {
            revert IPositionAdapter.InvalidPoolBinding();
        }
        if (poolFactory != expectedFactory) revert IPositionAdapter.InvalidPoolBinding();

        address registeredPool;
        try IUniswapV2Factory(expectedFactory).getPair(poolToken0, poolToken1) returns (address value) {
            registeredPool = value;
        } catch {
            revert IPositionAdapter.InvalidPoolBinding();
        }
        if (registeredPool != pool) revert IPositionAdapter.InvalidPoolBinding();
    }

    function _validateV3Pool(
        address pool,
        address poolToken0,
        address poolToken1,
        uint24 adapterFeeTier,
        int24 adapterTickSpacing,
        address expectedFactory
    ) private view {
        uint24 poolFeeTier;
        int24 poolTickSpacing;
        address poolFactory;

        try IUniswapV3Pool(pool).fee() returns (uint24 value) {
            poolFeeTier = value;
        } catch {
            revert IPositionAdapter.InvalidPoolBinding();
        }
        try IUniswapV3Pool(pool).tickSpacing() returns (int24 value) {
            poolTickSpacing = value;
        } catch {
            revert InvalidTickSpacing();
        }
        if (adapterFeeTier == 0 || adapterFeeTier != poolFeeTier) {
            revert IPositionAdapter.InvalidPoolBinding();
        }
        if (adapterTickSpacing <= 0 || adapterTickSpacing != poolTickSpacing) revert InvalidTickSpacing();

        try IUniswapV3Pool(pool).factory() returns (address value) {
            poolFactory = value;
        } catch {
            revert IPositionAdapter.InvalidPoolBinding();
        }
        if (poolFactory != expectedFactory) revert IPositionAdapter.InvalidPoolBinding();

        address registeredPool;
        try IUniswapV3Factory(expectedFactory).getPool(poolToken0, poolToken1, poolFeeTier) returns (address value) {
            registeredPool = value;
        } catch {
            revert IPositionAdapter.InvalidPoolBinding();
        }
        if (registeredPool != pool) revert IPositionAdapter.InvalidPoolBinding();
    }
}
