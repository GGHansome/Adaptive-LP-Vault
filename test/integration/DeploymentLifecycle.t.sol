// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IntegrationTestFixture} from "./helpers/IntegrationTestFixture.sol";
import {VenueType, PauseState} from "../../src/core/VaultTypes.sol";
import {IAdapterRegistry} from "../../src/interfaces/IAdapterRegistry.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DeploymentLifecycleIntegrationTest is IntegrationTestFixture {
    function test_deployConfigureBootstrapAndFirstUserRoundTrip() public {
        assertEq(control.vault(), address(vault));
        assertEq(control.token0(), address(token0));
        assertEq(control.token1(), address(token1));
        assertEq(control.uniswapV2Factory(), v2Factory);
        assertEq(control.uniswapV3Factory(), v3Factory);
        assertEq(vault.swapExecutor().vault(), address(vault));
        assertEq(low.positionManager(), address(positionManager));
        assertEq(high.positionManager(), address(positionManager));
        assertEq(oracle.canonicalPool(), canonicalPool);
        assertTrue(oracle.snapshot().healthy);
        assertEq(oracle.snapshot().twapTick, 0);
        assertEq(oracle.token0Decimals(), token0.decimals());
        assertEq(oracle.token1Decimals(), token1.decimals());
        assertEq(vault.totalSupply(), 0);
        assertFalse(vault.initialized());
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        assertTrue(vault.initialized());
        assertEq(vault.totalSupply(), 2 * seed);
        assertEq(vault.balanceOf(manager), 2 * seed - LOCKED);
        (,, uint256 shares) = _deposit(alice, alice, seed / 10, seed / 10);
        _redeem(alice, alice, alice, shares);
        _plain(150, VenueType.UNISWAP_V3_HIGH_FEE);
        _redeem(manager, manager, manager, vault.balanceOf(manager) / 10);
    }

    function test_bootstrapFreezesIdentityConfiguration() public {
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        vm.prank(manager);
        vm.expectRevert(IAdapterRegistry.AlreadyInitialized.selector);
        control.configureAdapter(VenueType.UNISWAP_V2, address(v2));
        vm.prank(manager);
        vm.expectRevert(IAdapterRegistry.AlreadyInitialized.selector);
        vault.bootstrap(seed, seed, manager);
        _assertAccounting();
    }

    function test_rolesRemainSeparatedAcrossBusinessLifecycle() public {
        bytes32 managerRole = control.MANAGER_ROLE();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, managerRole)
        );
        vault.bootstrap(seed, seed, admin);
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        vm.prank(guardian);
        control.setPauseState(PauseState(true, false, false));
        vm.prank(manager);
        control.setPauseState(PauseState(false, false, false));
        _deposit(alice, alice, seed / 10, seed / 10);
        _plain(150, VenueType.UNISWAP_V3_HIGH_FEE);
        vm.prank(guardian);
        vault.emergencyExitToIdle();
        _redeem(alice, alice, alice, vault.balanceOf(alice));
    }
}
