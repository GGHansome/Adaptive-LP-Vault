// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PauseFlag, PauseState} from "../core/VaultTypes.sol";

/// @notice Exposes runtime pause controls implemented at the vault address.
interface IVaultPause {
    /// @notice Indicates that a guardian attempted to clear at least one active pause flag.
    error GuardianCannotUnpause();

    /// @notice Indicates that the requested vault operation is paused.
    /// @param flag Pause flag that blocked the operation.
    error Paused(PauseFlag flag);

    /// @notice Emitted after the stored pause state actually changes.
    /// @param caller Account that caused the pause-state change.
    /// @param depositPaused Whether deposits are paused after the change.
    /// @param plainRebalancePaused Whether rebalances without a swap are paused after the change.
    /// @param swapRebalancePaused Whether rebalances with a swap are paused after the change.
    event PauseStateChanged(
        address indexed caller, bool depositPaused, bool plainRebalancePaused, bool swapRebalancePaused
    );

    /// @notice Returns the current runtime pause state.
    /// @return state Current pause flags.
    function pauseState() external view returns (PauseState memory state);

    /// @notice Replaces the current runtime pause state.
    /// @dev Managers may tighten or relax flags; guardians may only tighten them.
    /// @param newState Desired pause state.
    function setPauseState(PauseState calldata newState) external;
}
