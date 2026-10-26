// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAdapterRegistry} from "../interfaces/IAdapterRegistry.sol";
import {IVaultPause} from "../interfaces/IVaultPause.sol";
import {PauseFlag, PauseState} from "../core/VaultTypes.sol";
import {VaultRoles} from "./VaultRoles.sol";

/// @title Vault Pause Controls
/// @notice Stores and enforces the vault's three independent runtime pause flags.
/// @dev Managers may replace the state freely. Guardians may only change false flags to true.
abstract contract VaultPause is VaultRoles, IVaultPause {
    PauseState private _pauseState;

    /// @inheritdoc IVaultPause
    function pauseState() external view override returns (PauseState memory state) {
        return _pauseState;
    }

    /// @inheritdoc IVaultPause
    function setPauseState(PauseState calldata newState) external override {
        bool callerIsManager = _checkManagerOrGuardian();

        // Role-gated lifecycle methods deliberately authorize before revealing lifecycle state.
        if (!_vaultInitialized()) revert IAdapterRegistry.NotInitialized();

        if (
            !callerIsManager
                && ((_pauseState.depositPaused && !newState.depositPaused)
                    || (_pauseState.plainRebalancePaused && !newState.plainRebalancePaused)
                    || (_pauseState.swapRebalancePaused && !newState.swapRebalancePaused))
        ) {
            revert GuardianCannotUnpause();
        }

        _setPauseState(newState, _msgSender());
    }

    /// @notice Returns whether the final vault has completed bootstrap.
    /// @dev The final vault overrides this hook with its lifecycle storage.
    function _vaultInitialized() internal view virtual returns (bool);

    /// @notice Reverts when the requested operation's pause flag is active.
    /// @param flag Entry-point pause flag to enforce.
    function _requireNotPaused(PauseFlag flag) internal view {
        if (flag == PauseFlag.DEPOSIT) {
            if (_pauseState.depositPaused) revert Paused(flag);
        } else if (flag == PauseFlag.PLAIN_REBALANCE) {
            if (_pauseState.plainRebalancePaused) revert Paused(flag);
        } else if (_pauseState.swapRebalancePaused) {
            revert Paused(flag);
        }
    }

    /// @notice Replaces pause storage and emits only when at least one bit changes.
    /// @param newState Desired pause state.
    /// @param caller Account responsible for the state transition.
    /// @return changed Whether storage changed.
    function _setPauseState(PauseState memory newState, address caller) internal returns (bool changed) {
        PauseState memory current = _pauseState;
        changed = current.depositPaused != newState.depositPaused
            || current.plainRebalancePaused != newState.plainRebalancePaused
            || current.swapRebalancePaused != newState.swapRebalancePaused;

        if (!changed) return false;

        _pauseState = newState;
        emit PauseStateChanged(
            caller, newState.depositPaused, newState.plainRebalancePaused, newState.swapRebalancePaused
        );
    }

    /// @notice Sets all runtime pause flags, as required after an emergency exit.
    /// @param caller Account responsible for the emergency pause.
    /// @return changed Whether storage changed.
    function _pauseAll(address caller) internal returns (bool changed) {
        return _setPauseState(
            PauseState({depositPaused: true, plainRebalancePaused: true, swapRebalancePaused: true}), caller
        );
    }
}
