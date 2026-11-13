// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IntegrationTestFixture} from "./helpers/IntegrationTestFixture.sol";
import {VenueType, AssetSnapshot} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";

/// @dev The same business scenarios intentionally run against all four decimal configurations.
abstract contract DepositRedeemScenarios is IntegrationTestFixture {
    function test_multiUserRoundTripV2() public {
        _multiUserRoundTrip(VenueType.UNISWAP_V2);
    }

    function test_multiUserRoundTripLowFeeV3() public {
        _multiUserRoundTrip(VenueType.UNISWAP_V3_LOW_FEE);
    }

    function test_multiUserRoundTripHighFeeV3() public {
        _multiUserRoundTrip(VenueType.UNISWAP_V3_HIGH_FEE);
    }

    function _multiUserRoundTrip(VenueType venue) internal {
        _bootstrap(venue);
        uint256 alice0 = token0.balanceOf(alice);
        uint256 alice1 = token1.balanceOf(alice);
        uint256 bob0 = token0.balanceOf(bob);
        uint256 bob1 = token1.balanceOf(bob);
        // Unequal maxima exercise both limiting sides without changing the principal ratio.
        (,, uint256 aliceShares) = _deposit(alice, alice, seed / 5, seed / 10);
        _deposit(bob, bob, seed / 4, seed / 2);
        _redeem(alice, alice, alice, aliceShares / 3);
        _redeem(bob, bob, bob, vault.balanceOf(bob));
        _redeem(alice, alice, alice, vault.balanceOf(alice));
        assertApproxEqAbs(token0.balanceOf(alice), alice0, 20);
        assertApproxEqAbs(token1.balanceOf(alice), alice1, 20);
        assertApproxEqAbs(token0.balanceOf(bob), bob0, 20);
        assertApproxEqAbs(token1.balanceOf(bob), bob1, 20);
        _redeem(manager, manager, manager, vault.balanceOf(manager));
        assertEq(vault.totalSupply(), LOCKED);
        assertGt(vault.assetSnapshot().total0, 0);
        assertGt(vault.assetSnapshot().total1, 0);
        // The vault remains usable after every circulating share has been redeemed.
        (,, uint256 newShares) = _deposit(bob, bob, seed / 10, seed / 10);
        _redeem(bob, bob, bob, newShares);
        assertEq(vault.totalSupply(), LOCKED);
    }

    function test_separatePayerShareOwnerOperatorAndAssetReceiver() public {
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        (,, uint256 shares) = _deposit(alice, bob, seed / 10, seed / 10);
        assertEq(vault.balanceOf(alice), 0);
        vm.prank(bob);
        vault.approve(operator, shares);
        _redeem(operator, bob, receiver, shares / 2);
        assertEq(vault.allowance(bob, operator), shares - shares / 2);
        _redeem(operator, bob, receiver, shares - shares / 2);
        assertEq(vault.allowance(bob, operator), 0);
        assertEq(vault.balanceOf(bob), 0);
        assertGt(token0.balanceOf(receiver), 0);
        assertGt(token1.balanceOf(receiver), 0);
    }
}

contract DepositRedeemIntegrationTest is DepositRedeemScenarios {
    function test_depositAndRedeemEventsMatchActualTransfers() public {
        _bootstrap(VenueType.UNISWAP_V2);
        uint256 amount = seed / 10;
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        uint256 expectedShares = 2 * amount * beforeAssets.totalShares / (beforeAssets.total0 + beforeAssets.total1);
        vm.expectEmit(true, true, false, true, address(vault));
        emit IAdaptiveLPVault.Deposit(alice, bob, amount, amount, expectedShares);
        _deposit(alice, bob, amount, amount);
        uint256 checkpoint = vm.snapshotState();
        (uint256 out0, uint256 out1) = _redeem(bob, bob, receiver, expectedShares);
        assertTrue(vm.revertToStateAndDelete(checkpoint));
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.Redeem(bob, receiver, bob, expectedShares, out0, out1);
        _redeem(bob, bob, receiver, expectedShares);
    }

    function testFuzz_depositRedeemAcrossRealVenues(uint8 venueIndex, uint96 amountSeed) public {
        VenueType venue = VenueType(bound(venueIndex, 1, 3));
        _bootstrap(venue);
        uint256 amount = bound(amountSeed, seed / 1000, seed * 5);
        uint256 before0 = token0.balanceOf(alice);
        uint256 before1 = token1.balanceOf(alice);
        (,, uint256 shares) = _deposit(alice, alice, amount, amount);
        _redeem(alice, alice, alice, shares);
        assertApproxEqAbs(token0.balanceOf(alice), before0, 20);
        assertApproxEqAbs(token1.balanceOf(alice), before1, 20);
    }
}

contract DepositRedeemSixEighteenIntegrationTest is DepositRedeemScenarios {
    function _tokenDecimals() internal pure override returns (uint8, uint8) {
        return (6, 18);
    }
}

contract DepositRedeemEighteenSixIntegrationTest is DepositRedeemScenarios {
    function _tokenDecimals() internal pure override returns (uint8, uint8) {
        return (18, 6);
    }
}

contract DepositRedeemSixSixIntegrationTest is DepositRedeemScenarios {
    function _tokenDecimals() internal pure override returns (uint8, uint8) {
        return (6, 6);
    }
}
