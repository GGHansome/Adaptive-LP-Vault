// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAdapterRegistry} from "./IAdapterRegistry.sol";
import {IVaultPause} from "./IVaultPause.sol";
import {PauseFlag, VenueType} from "../core/VaultTypes.sol";

/// @notice Defines the one-to-one control plane for an adaptive liquidity vault.
interface IVaultControl is IVaultPause, IAdapterRegistry {
    /// @notice Indicates that a vault-only control operation was called by another address.
    error NotVaultCaller();

    /// @notice Indicates that immutable control bindings are invalid.
    error InvalidControlConfiguration();

    /// @notice Returns the only vault authorized to use vault-only control operations.
    function vault() external view returns (address);

    /// @notice Returns the immutable ordered token pair validated by the control contract.
    function token0() external view returns (address);
    function token1() external view returns (address);

    /// @notice Returns the immutable factories used for adapter validation.
    function uniswapV2Factory() external view returns (address);
    function uniswapV3Factory() external view returns (address);

    /// @notice Reverts unless `account` has the manager role.
    function checkManager(address account) external view;

    /// @notice Reverts unless `account` has the manager or guardian role.
    function checkManagerOrGuardian(address account) external view returns (bool callerIsManager);

    /// @notice Reverts unless `account` has the manager or keeper role.
    function checkManagerOrKeeper(address account) external view returns (bool callerIsManager);

    /// @notice Reverts when the selected vault operation is paused.
    function requireNotPaused(PauseFlag flag) external view;

    /// @notice Enforces the deposit pause and adapter-entry gates in one vault-only call.
    function requireDepositEnabled(VenueType venue) external view returns (address adapter);

    /// @notice Revalidates all three required adapters before bootstrap.
    function validateConfiguredAdapters() external view;

    /// @notice Returns a configured non-IDLE adapter or reverts.
    function getAdapterOrRevert(VenueType venue) external view returns (address adapter);

    /// @notice Returns an enabled adapter for a non-IDLE venue or reverts.
    function requireEnterEnabled(VenueType venue) external view returns (address adapter);

    /// @notice Returns both configured V3 tick spacings in one vault-only call.
    function adapterTickSpacings() external view returns (int24 lowSpacing, int24 highSpacing);

    /// @notice Sets every pause flag after the bound vault completes an emergency exit.
    function pauseAll(address caller) external returns (bool changed);
}
