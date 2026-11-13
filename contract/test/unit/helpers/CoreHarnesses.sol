// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AdapterRegistry} from "../../../src/control/AdapterRegistry.sol";
import {VaultPause} from "../../../src/control/VaultPause.sol";
import {VaultRoles} from "../../../src/control/VaultRoles.sol";
import {AccessControlConfig, PauseFlag, VenueType} from "../../../src/core/VaultTypes.sol";

contract VaultRolesHarness is VaultRoles {
    constructor(AccessControlConfig memory config) VaultRoles(config) {}
}

contract VaultPauseHarness is VaultPause {
    bool private _initialized;

    constructor(AccessControlConfig memory config) VaultRoles(config) {}

    function setInitialized(bool initialized_) external {
        _initialized = initialized_;
    }

    function requireNotPaused(PauseFlag flag) external view {
        _requireNotPaused(flag);
    }

    function pauseAll(address caller) external returns (bool changed) {
        return _pauseAll(caller);
    }

    function _vaultInitialized() internal view override returns (bool) {
        return _initialized;
    }
}

contract AdapterRegistryHarness is AdapterRegistry {
    bool private _initialized;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    address private immutable _V2_FACTORY;
    address private immutable _V3_FACTORY;

    constructor(
        AccessControlConfig memory config,
        address token0_,
        address token1_,
        address v2Factory_,
        address v3Factory_
    ) VaultRoles(config) {
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _V2_FACTORY = v2Factory_;
        _V3_FACTORY = v3Factory_;
    }

    function setInitialized(bool initialized_) external {
        _initialized = initialized_;
    }

    function validateConfiguredAdapters() external view {
        _validateConfiguredAdapters();
    }

    function requireEnterEnabled(VenueType venue) external view returns (address) {
        return _requireEnterEnabled(venue);
    }

    function adapterTickSpacing(VenueType venue) external view returns (int24) {
        return _adapterTickSpacing(venue);
    }

    function _vaultInitialized() internal view override returns (bool) {
        return _initialized;
    }

    function _registryVault() internal view override returns (address) {
        return address(this);
    }

    function _registryToken0() internal view override returns (address) {
        return _TOKEN0;
    }

    function _registryToken1() internal view override returns (address) {
        return _TOKEN1;
    }

    function _registryV2Factory() internal view override returns (address) {
        return _V2_FACTORY;
    }

    function _registryV3Factory() internal view override returns (address) {
        return _V3_FACTORY;
    }
}

contract CombinedCoreHarness is VaultPause, AdapterRegistry {
    bool private _initialized;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    address private immutable _V2_FACTORY;
    address private immutable _V3_FACTORY;

    constructor(
        AccessControlConfig memory config,
        address token0_,
        address token1_,
        address v2Factory_,
        address v3Factory_
    ) VaultRoles(config) {
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _V2_FACTORY = v2Factory_;
        _V3_FACTORY = v3Factory_;
    }

    function setInitialized(bool initialized_) external {
        _initialized = initialized_;
    }

    function _vaultInitialized() internal view override(VaultPause, AdapterRegistry) returns (bool) {
        return _initialized;
    }

    function _registryVault() internal view override returns (address) {
        return address(this);
    }

    function _registryToken0() internal view override returns (address) {
        return _TOKEN0;
    }

    function _registryToken1() internal view override returns (address) {
        return _TOKEN1;
    }

    function _registryV2Factory() internal view override returns (address) {
        return _V2_FACTORY;
    }

    function _registryV3Factory() internal view override returns (address) {
        return _V3_FACTORY;
    }
}
