// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VaultInvariantFixture} from "./helpers/VaultInvariantFixture.sol";
import {VaultHandler} from "./handlers/VaultHandler.sol";
import {VenueType} from "../../src/core/VaultTypes.sol";

/// @dev Deterministic witnesses prove handler success/failure paths are reachable. They are
/// separate from random campaigns: a random run need not visit every action in every sequence.
contract InvariantHandlerReachabilityTest is VaultInvariantFixture {
    function test_handlerReachesAllVenuesFeesDonationsAndRedemptionModes() public {
        handler.deposit(1, 1, seed / 10, seed / 8);
        handler.accrueFees(seed / 1000, seed / 2000);
        handler.exerciseFailure(0, 1); // collect fees, then revert on min output
        handler.exerciseFailure(1, 1); // absent delegated allowance
        handler.deposit(2, 2, seed / 20, seed / 20); // collected fees priced only once
        handler.approveShares(1, 1, 123);
        handler.transferShares(1, 2, 1 ether, false);
        handler.transferShares(2, 1, 1 ether, true);
        handler.transferShares(1, 5, 17, false); // additional shares may be locked voluntarily
        handler.redeem(1, 3, 1 ether, 0);
        handler.redeem(2, 3, 1 ether, 1);
        handler.redeem(2, 3, 1 ether, 2);
        handler.donateTokens(100, 200);
        handler.donateLp(seed / 100);
        handler.advanceTime(60);
        handler.rebalance(150);
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_HIGH_FEE));
        handler.accrueFees(seed / 1000, seed / 1000);
        handler.advanceTime(60);
        handler.rebalance(350);
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
        handler.accrueFees(seed / 1000, seed / 2000);
        handler.deposit(1, 1, seed / 10, seed / 10);
        handler.redeem(1, 3, 1 ether, 0); // real native LP nested rounding
        handler.advanceTime(60);
        handler.rebalance(600);
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
        handler.redeem(2, 3, 1 ether, 0);
        handler.advanceTime(60);
        handler.rebalance(350);
        handler.advanceTime(60);
        handler.rebalance(150);
        handler.advanceTime(60);
        handler.rebalance(0);
        assertEq(handler.visitedVenues(), 15);
        assertGt(handler.successes(VaultHandler.deposit.selector), 0);
        assertGt(handler.successes(VaultHandler.redeem.selector), 0);
        assertGt(handler.successes(VaultHandler.accrueFees.selector), 0);
        assertGe(handler.checkedFailures(), 2);
        _assertGhostAccounting();
        handler.finish();
        _assertGhostAccounting();
    }

    function test_handlerExecutesBothRealRouterDirections() public {
        handler.advanceTime(60);
        handler.rebalanceWithSwap(true, seed / 5);
        assertEq(handler.swaps0(), 1);
        handler.advanceTime(60);
        handler.rebalanceWithSwap(false, seed / 5);
        assertEq(handler.swaps1(), 1);
        _assertGhostAccounting();
        handler.finish();
        _assertGhostAccounting();
    }

    function test_handlerChecksFaultsControlsRevocationAndEmergencyLiveness() public {
        handler.deposit(1, 1, seed / 10, seed / 10);
        for (uint256 bits; bits < 8; ++bits) {
            handler.setControls(bits, 0, true, false);
            handler.probeGates(1);
            handler.redeem(1, 1, 1, 0);
        }
        handler.setControls(0, 0, true, false);
        handler.exerciseFailure(5, 1); // initial shared cooldown
        handler.exerciseFailure(2, 1); // deadline
        handler.advanceTime(60);
        handler.exerciseFailure(3, 1); // bad plan hash
        handler.setMarket(150, false);
        handler.exerciseFailure(4, 1); // oracle unhealthy
        handler.setControls(0, 1, false, false); // disable active low-fee adapter
        handler.exerciseFailure(6, 1);
        handler.setControls(7, 0, false, true); // guardian can tighten only
        handler.guardianCannotRelax(0);
        for (uint256 i; i < 6; ++i) {
            handler.unauthorized(i, true);
            handler.unauthorized(i, false);
        }
        handler.redeem(1, 3, 1 ether, 1); // disabled + paused + unhealthy still permits exit
        handler.emergencyExit(true);
        uint64 version = vault.planVersion();
        handler.emergencyExit(false);
        assertEq(vault.planVersion(), version);
        handler.redeem(1, 1, 1 ether, 0);
        // Resume after emergency: history drives high-fee target despite activeVenue=IDLE.
        handler.setControls(0, 0, true, false);
        handler.setControls(0, 1, true, false);
        handler.setControls(0, 2, true, false);
        handler.setMarket(150, true);
        handler.advanceTime(60);
        handler.rebalance(150);
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_HIGH_FEE));
        assertGe(handler.checkedFailures(), 19);
        handler.finish();
        _assertGhostAccounting();
    }
}
