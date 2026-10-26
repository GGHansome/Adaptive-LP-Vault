// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

import {AccessControlConfig} from "../core/VaultTypes.sol";
import {IVaultRoles} from "../interfaces/IVaultRoles.sol";

/// @title Vault Roles
/// @notice Supplies the vault's default-administrator lifecycle and fixed business roles.
/// @dev The default administrator manages role membership but receives no business role implicitly.
abstract contract VaultRoles is AccessControlDefaultAdminRules {
    /// @notice Role authorized to initialize and manage the vault's business controls.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Role authorized to execute keeper-gated rebalances.
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @notice Role authorized to tighten emergency controls and exit positions.
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    /// @notice Initializes the single default administrator and its transfer delay.
    /// @param config OpenZeppelin default-administrator configuration.
    constructor(AccessControlConfig memory config)
        AccessControlDefaultAdminRules(config.initialDefaultAdminDelay, config.initialDefaultAdmin)
    {}

    /// @notice Reverts unless the caller holds the manager role.
    function _checkManager() internal view {
        _checkRole(MANAGER_ROLE);
    }

    /// @notice Reverts unless the caller holds either the manager or guardian role.
    /// @return callerIsManager Whether the caller has unrestricted manager authority.
    function _checkManagerOrGuardian() internal view returns (bool callerIsManager) {
        address caller = _msgSender();
        callerIsManager = hasRole(MANAGER_ROLE, caller);
        if (!callerIsManager && !hasRole(GUARDIAN_ROLE, caller)) _checkRole(MANAGER_ROLE, caller);
    }

    /// @notice Reverts unless the caller holds either the manager or keeper role.
    /// @return callerIsManager Whether the caller has manager authority.
    function _checkManagerOrKeeper() internal view returns (bool callerIsManager) {
        address caller = _msgSender();
        callerIsManager = hasRole(MANAGER_ROLE, caller);
        if (!callerIsManager && !hasRole(KEEPER_ROLE, caller)) _checkRole(MANAGER_ROLE, caller);
    }

    /// @inheritdoc AccessControlDefaultAdminRules
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IVaultRoles).interfaceId || super.supportsInterface(interfaceId);
    }
}
