// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    IAccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {VaultRolesHarness} from "./helpers/CoreHarnesses.sol";
import {AccessControlConfig} from "../../src/core/VaultTypes.sol";

contract VaultRolesTest is Test {
    VaultRolesHarness private roles;
    address private successor;

    function setUp() public {
        vm.warp(10000);
        roles = new VaultRolesHarness(AccessControlConfig(1 days, address(this)));
        successor = makeAddr("successor");
    }

    function test_defaultAdminTransferCancelAndDelayedAcceptance() public {
        bytes32 managerRole = roles.MANAGER_ROLE();
        roles.grantRole(managerRole, address(this));
        roles.beginDefaultAdminTransfer(successor);
        (address pending, uint48 schedule) = roles.pendingDefaultAdmin();
        assertEq(pending, successor);
        assertEq(schedule, vm.getBlockTimestamp() + 1 days);
        roles.cancelDefaultAdminTransfer();
        (pending, schedule) = roles.pendingDefaultAdmin();
        assertEq(pending, address(0));
        assertEq(schedule, 0);
        vm.prank(successor);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControlDefaultAdminRules.AccessControlInvalidDefaultAdmin.selector, successor)
        );
        roles.acceptDefaultAdminTransfer();
        roles.beginDefaultAdminTransfer(successor);
        (, schedule) = roles.pendingDefaultAdmin();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlInvalidDefaultAdmin.selector, address(this)
            )
        );
        roles.acceptDefaultAdminTransfer();
        vm.warp(schedule - 1);
        vm.prank(successor);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminDelay.selector, schedule
            )
        );
        roles.acceptDefaultAdminTransfer();
        vm.warp(schedule);
        vm.prank(successor);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminDelay.selector, schedule
            )
        );
        roles.acceptDefaultAdminTransfer();
        vm.warp(uint256(schedule) + 1);
        vm.prank(successor);
        roles.acceptDefaultAdminTransfer();
        assertEq(roles.defaultAdmin(), successor);
        assertEq(roles.owner(), successor);
        assertFalse(roles.hasRole(bytes32(0), address(this)));
        assertTrue(roles.hasRole(bytes32(0), successor));
        assertTrue(roles.hasRole(managerRole, address(this)));
        assertFalse(roles.hasRole(managerRole, successor));
        (pending, schedule) = roles.pendingDefaultAdmin();
        assertEq(pending, address(0));
        assertEq(schedule, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), bytes32(0))
        );
        roles.grantRole(managerRole, successor);
        vm.prank(successor);
        roles.revokeRole(managerRole, address(this));
        assertFalse(roles.hasRole(managerRole, address(this)));
    }

    function test_defaultAdminRenounceRequiresScheduledZeroTransfer() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminDelay.selector, uint48(0)
            )
        );
        roles.renounceRole(bytes32(0), address(this));
        roles.beginDefaultAdminTransfer(address(0));
        (, uint48 schedule) = roles.pendingDefaultAdmin();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminDelay.selector, schedule
            )
        );
        roles.renounceRole(bytes32(0), address(this));
        vm.warp(schedule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminDelay.selector, schedule
            )
        );
        roles.renounceRole(bytes32(0), address(this));
        vm.warp(uint256(schedule) + 1);
        vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
        roles.renounceRole(bytes32(0), successor);
        assertEq(roles.defaultAdmin(), address(this));
        roles.renounceRole(bytes32(0), address(this));
        assertEq(roles.defaultAdmin(), address(0));
        assertFalse(roles.hasRole(bytes32(0), address(this)));
    }

    function test_defaultAdminDelayIncreaseDecreaseAndRollback() public {
        roles.changeDefaultAdminDelay(3 days);
        (uint48 delay, uint48 schedule) = roles.pendingDefaultAdminDelay();
        assertEq(delay, 3 days);
        assertEq(schedule, vm.getBlockTimestamp() + 3 days);
        roles.rollbackDefaultAdminDelay();
        (delay, schedule) = roles.pendingDefaultAdminDelay();
        assertEq(delay, 0);
        assertEq(schedule, 0);
        assertEq(roles.defaultAdminDelay(), 1 days);
        roles.changeDefaultAdminDelay(3 days);
        (, schedule) = roles.pendingDefaultAdminDelay();
        vm.warp(schedule);
        assertEq(roles.defaultAdminDelay(), 1 days);
        vm.warp(uint256(schedule) + 1);
        assertEq(roles.defaultAdminDelay(), 3 days);
        roles.changeDefaultAdminDelay(1 days);
        (delay, schedule) = roles.pendingDefaultAdminDelay();
        assertEq(delay, 1 days);
        assertEq(schedule, vm.getBlockTimestamp() + 2 days);
        vm.warp(uint256(schedule) + 1);
        assertEq(roles.defaultAdminDelay(), 1 days);
        (delay, schedule) = roles.pendingDefaultAdminDelay();
        assertEq(delay, 0);
        assertEq(schedule, 0);
        roles.changeDefaultAdminDelay(30 days);
        (, schedule) = roles.pendingDefaultAdminDelay();
        assertEq(schedule, vm.getBlockTimestamp() + 5 days);
    }

    function test_singleAdminRuleAndNonzeroInitialAdmin() public {
        vm.expectRevert(IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminRules.selector);
        roles.grantRole(bytes32(0), successor);
        vm.expectRevert(IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminRules.selector);
        roles.revokeRole(bytes32(0), address(this));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlInvalidDefaultAdmin.selector, address(0)
            )
        );
        new VaultRolesHarness(AccessControlConfig(0, address(0)));
        assertEq(roles.defaultAdmin(), address(this));
    }

    function test_businessRoleGrantRevokeAndSelfRenounce() public {
        bytes32[3] memory businessRoles = [roles.MANAGER_ROLE(), roles.KEEPER_ROLE(), roles.GUARDIAN_ROLE()];
        for (uint256 i; i < businessRoles.length; ++i) {
            bytes32 role = businessRoles[i];
            roles.grantRole(role, successor);
            assertTrue(roles.hasRole(role, successor));
            vm.prank(successor);
            vm.expectRevert(
                abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, successor, bytes32(0))
            );
            roles.grantRole(role, address(this));
            roles.revokeRole(role, successor);
            assertFalse(roles.hasRole(role, successor));
            roles.grantRole(role, successor);
            vm.prank(successor);
            vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
            roles.renounceRole(role, address(this));
            vm.prank(successor);
            roles.renounceRole(role, successor);
            assertFalse(roles.hasRole(role, successor));
        }
    }
}
