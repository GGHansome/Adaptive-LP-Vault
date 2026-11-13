// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IAccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";

/// @notice Exposes the vault's OpenZeppelin access-control surface and business role identifiers.
interface IVaultRoles is IAccessControlDefaultAdminRules {
    /// @notice Returns the identifier of the unique default-administrator role.
    /// @return role The default-administrator role identifier.
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32 role);

    /// @notice Returns the identifier of the manager role.
    /// @return role The manager role identifier.
    function MANAGER_ROLE() external view returns (bytes32 role);

    /// @notice Returns the identifier of the keeper role.
    /// @return role The keeper role identifier.
    function KEEPER_ROLE() external view returns (bytes32 role);

    /// @notice Returns the identifier of the guardian role.
    /// @return role The guardian role identifier.
    function GUARDIAN_ROLE() external view returns (bytes32 role);
}
