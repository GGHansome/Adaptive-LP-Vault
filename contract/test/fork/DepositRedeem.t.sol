// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MainnetForkFixture} from "./helpers/MainnetForkFixture.sol";
import {VenueType} from "../../src/core/VaultTypes.sol";

contract DepositRedeemForkTest is MainnetForkFixture {
    function test_lowFeeRealTokenMultiUserLifecycle() public {
        _lifecycle(VenueType.UNISWAP_V3_LOW_FEE);
    }

    function test_highFeeRealTokenMultiUserLifecycle() public {
        _lifecycle(VenueType.UNISWAP_V3_HIGH_FEE);
    }

    function test_v2RealTokenMultiUserLifecycle() public {
        _lifecycle(VenueType.UNISWAP_V2);
    }

    function _lifecycle(VenueType venue) private {
        _deployAndBootstrap(venue);
        uint256 aliceShares = _deposit(alice, alice, seed0 / 5, seed1 / 5);
        uint256 bobShares = _deposit(bob, receiver, seed0 / 3, seed1 / 3);
        _redeem(alice, alice, receiver, aliceShares / 2);
        vm.prank(receiver);
        vault.approve(operator, bobShares);
        _redeem(operator, receiver, bob, bobShares);
        assertEq(vault.allowance(receiver, operator), 0);
        _redeem(alice, alice, alice, vault.balanceOf(alice));
        _redeem(manager, manager, manager, vault.balanceOf(manager));
        assertEq(vault.totalSupply(), LOCKED);
        assertEq(vault.balanceOf(address(vault)), LOCKED);
        assertGt(vault.assetSnapshot().total0 + vault.assetSnapshot().total1, 0);
        // The remaining locked liquidity must not prevent a new user from entering/exiting.
        uint256 reentry = _deposit(alice, alice, seed0 / 10, seed1 / 10);
        _redeem(alice, alice, alice, reentry);
        assertEq(vault.totalSupply(), LOCKED);
    }
}
