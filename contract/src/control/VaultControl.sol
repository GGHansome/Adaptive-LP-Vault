// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AdapterRegistry} from "./AdapterRegistry.sol";
import {VaultPause} from "./VaultPause.sol";
import {VaultRoles} from "./VaultRoles.sol";
import {AccessControlConfig, PauseFlag, VenueType} from "../core/VaultTypes.sol";
import {IAdapterRegistry} from "../interfaces/IAdapterRegistry.sol";
import {IAdaptiveLPVault} from "../interfaces/IAdaptiveLPVault.sol";
import {IVaultControl} from "../interfaces/IVaultControl.sol";
import {IVaultPause} from "../interfaces/IVaultPause.sol";
import {IVaultRoles} from "../interfaces/IVaultRoles.sol";

/// @title Vault Control
/// @notice Holds one vault's roles, pause flags, and adapter registry outside its asset-bearing runtime.
/// @dev The immutable bound vault is the only caller accepted by vault-only checks and lifecycle transitions.
contract VaultControl is AdapterRegistry, VaultPause, IVaultControl {
    address public immutable override vault;
    address public immutable override token0;
    address public immutable override token1;
    address public immutable override uniswapV2Factory;
    address public immutable override uniswapV3Factory;

    modifier onlyVault() {
        _checkVaultCaller();
        _;
    }

    function _checkVaultCaller() private view {
        if (msg.sender != vault) revert NotVaultCaller();
    }

    /// @notice Creates a control plane permanently bound to one vault and its canonical asset factories.
    /// @param vault_ Vault authorized to call vault-only control operations.
    /// @param accessConfig Initial default-administrator configuration.
    /// @param token0_ Lower-address canonical asset.
    /// @param token1_ Higher-address canonical asset.
    /// @param uniswapV2Factory_ Expected V2 factory used to validate adapters.
    /// @param uniswapV3Factory_ Expected V3 factory used to validate adapters.
    constructor(
        address vault_,
        AccessControlConfig memory accessConfig,
        address token0_,
        address token1_,
        address uniswapV2Factory_,
        address uniswapV3Factory_
    ) VaultRoles(accessConfig) {
        if (
            vault_ == address(0) || token0_ == address(0) || token1_ == address(0) || token0_ >= token1_
                || token0_.code.length == 0 || token1_.code.length == 0 || uniswapV2Factory_ == address(0)
                || uniswapV2Factory_.code.length == 0 || uniswapV3Factory_ == address(0)
                || uniswapV3Factory_.code.length == 0
        ) revert InvalidControlConfiguration();

        vault = vault_;
        token0 = token0_;
        token1 = token1_;
        uniswapV2Factory = uniswapV2Factory_;
        uniswapV3Factory = uniswapV3Factory_;
    }

    /// @inheritdoc IVaultControl
    function checkManager(address account) external view override onlyVault {
        _checkRole(MANAGER_ROLE, account);
    }

    /// @inheritdoc IVaultControl
    function checkManagerOrGuardian(address account) external view override onlyVault returns (bool callerIsManager) {
        callerIsManager = hasRole(MANAGER_ROLE, account);
        if (!callerIsManager && !hasRole(GUARDIAN_ROLE, account)) _checkRole(MANAGER_ROLE, account);
    }

    /// @inheritdoc IVaultControl
    function checkManagerOrKeeper(address account) external view override onlyVault returns (bool callerIsManager) {
        callerIsManager = hasRole(MANAGER_ROLE, account);
        if (!callerIsManager && !hasRole(KEEPER_ROLE, account)) _checkRole(MANAGER_ROLE, account);
    }

    /// @inheritdoc IVaultControl
    function requireNotPaused(PauseFlag flag) external view override onlyVault {
        _requireNotPaused(flag);
    }

    /// @inheritdoc IVaultControl
    function requireDepositEnabled(VenueType venue) external view override onlyVault returns (address adapter) {
        _requireNotPaused(PauseFlag.DEPOSIT);
        if (venue == VenueType.IDLE) revert AdapterDisabled();
        return _requireEnterEnabled(venue);
    }

    /// @inheritdoc IVaultControl
    function validateConfiguredAdapters() external view override onlyVault {
        _validateConfiguredAdapters();
    }

    /// @inheritdoc IVaultControl
    function getAdapterOrRevert(VenueType venue) external view override onlyVault returns (address adapter) {
        return _getAdapterOrRevert(venue);
    }

    /// @inheritdoc IVaultControl
    function requireEnterEnabled(VenueType venue) external view override onlyVault returns (address adapter) {
        return _requireEnterEnabled(venue);
    }

    /// @inheritdoc IVaultControl
    function adapterTickSpacings() external view override onlyVault returns (int24 lowSpacing, int24 highSpacing) {
        lowSpacing = _adapterTickSpacing(VenueType.UNISWAP_V3_LOW_FEE);
        highSpacing = _adapterTickSpacing(VenueType.UNISWAP_V3_HIGH_FEE);
    }

    /// @inheritdoc IVaultControl
    function pauseAll(address caller) external override onlyVault returns (bool changed) {
        return _pauseAll(caller);
    }

    /// @inheritdoc VaultRoles
    function supportsInterface(bytes4 interfaceId) public view override(VaultRoles) returns (bool) {
        return interfaceId == type(IVaultControl).interfaceId || interfaceId == type(IVaultRoles).interfaceId
            || interfaceId == type(IVaultPause).interfaceId || interfaceId == type(IAdapterRegistry).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function _vaultInitialized() internal view override(AdapterRegistry, VaultPause) returns (bool) {
        return IAdaptiveLPVault(vault).initialized();
    }

    function _registryVault() internal view override returns (address) {
        return vault;
    }

    function _registryToken0() internal view override returns (address) {
        return token0;
    }

    function _registryToken1() internal view override returns (address) {
        return token1;
    }

    function _registryV2Factory() internal view override returns (address) {
        return uniswapV2Factory;
    }

    function _registryV3Factory() internal view override returns (address) {
        return uniswapV3Factory;
    }
}
