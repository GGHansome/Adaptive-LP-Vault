// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ForkRebalanceFixture} from "./helpers/ForkRebalanceFixture.sol";
import {DeploymentAssessment, PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {OracleSnapshot} from "../../src/oracle/OracleTypes.sol";

contract RebalanceForkTest is ForkRebalanceFixture {
    function test_realTwapConvergenceMigratesV2ToHighToLowAndBurnsOldNft() public {
        _deployAndBootstrap(VenueType.UNISWAP_V2);
        uint256 shares = _deposit(alice, alice, seed0 / 5, seed1 / 5);
        // Actual historical observations converge after both windows pass at unchanged pool tick.
        vm.warp(vm.getBlockTimestamp() + 1801);
        OracleSnapshot memory settled = oracle.snapshot();
        assertTrue(settled.healthy);
        assertEq(settled.deviationBps, 0);
        _plain(VenueType.UNISWAP_V3_HIGH_FEE);
        vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        _plain(VenueType.UNISWAP_V3_LOW_FEE);
        assertEq(vault.balanceOf(alice), shares);
        _redeem(alice, alice, receiver, shares);
    }

    function test_oldPlanIsRejectedAfterRealMigrationAndStateRemainsIntact() public {
        _deployAndBootstrap(VenueType.UNISWAP_V2);
        vm.warp(vm.getBlockTimestamp() + 1801);
        (PositionPlan memory oldPlan,) = vault.previewRebalance();
        _plain(VenueType.UNISWAP_V3_HIGH_FEE);
        vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        bytes32 beforeState = _stateHash();
        vm.expectRevert(IAdaptiveLPVault.InvalidPlanHash.selector);
        vault.rebalance(oldPlan.planHash, uint32(vm.getBlockTimestamp()));
        assertEq(_stateHash(), beforeState);
        _plain(VenueType.UNISWAP_V3_LOW_FEE);
    }

    function test_realPriceTradeDoesNotImmediatelyReplaceTwapRegime() public {
        _deployAndBootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        OracleSnapshot memory beforeTrade = oracle.snapshot();
        _tradeV3(500, true, 100_000e6);
        OracleSnapshot memory sameTimestamp = oracle.snapshot();
        assertLt(sameTimestamp.spotTick, beforeTrade.spotTick);
        assertEq(sameTimestamp.twapTick, beforeTrade.twapTick);
        assertEq(sameTimestamp.shortTwapTick, beforeTrade.shortTwapTick);
        assertEq(sameTimestamp.deviationBps, beforeTrade.deviationBps);
        vm.warp(vm.getBlockTimestamp() + 300);
        OracleSnapshot memory afterWindow = oracle.snapshot();
        assertEq(afterWindow.shortTwapTick, sameTimestamp.spotTick);
        assertTrue(afterWindow.twapTick != afterWindow.shortTwapTick);
    }

    function test_realOutOfRangePriceMoveRecentersLowFeeAndBurnsOldNft() public {
        // A narrower test range lets a real trade cross the boundary without artificial pool writes.
        _deployAndBootstrap(VenueType.UNISWAP_V3_LOW_FEE, 10);
        PositionPlan memory oldPlan = vault.lastExecutedPlan();
        uint256 oldId = low.positionId();
        _tradeV3(500, true, 4_000_000e6);
        OracleSnapshot memory moved = oracle.snapshot();
        assertLt(moved.spotTick, oldPlan.tickLower, "real trade must leave the old range");
        vm.warp(vm.getBlockTimestamp() + 1801);
        assertEq(oracle.snapshot().deviationBps, 0);
        (PositionPlan memory plan,) = vault.previewRebalance();
        assertEq(uint8(plan.targetVenue), uint8(VenueType.UNISWAP_V3_LOW_FEE));
        assertLt(plan.tickLower, oldPlan.tickLower);
        _plain(VenueType.UNISWAP_V3_LOW_FEE);
        assertTrue(low.positionId() != oldId);
        uint256 shares = _deposit(alice, alice, seed0 / 10, seed1 / 10);
        _redeem(alice, alice, alice, shares);
    }

    function test_cooldownAndDeadlineProtectRealPosition() public {
        _deployAndBootstrap(VenueType.UNISWAP_V2);
        vm.warp(vm.getBlockTimestamp() + 1801);
        _plain(VenueType.UNISWAP_V3_HIGH_FEE);
        (PositionPlan memory plan,) = vault.previewRebalance();
        bytes32 beforeState = _stateHash();
        vm.expectRevert(
            abi.encodeWithSelector(IAdaptiveLPVault.CooldownActive.selector, vm.getBlockTimestamp() + COOLDOWN)
        );
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        assertEq(_stateHash(), beforeState);
        vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        vm.expectRevert(IAdaptiveLPVault.DeadlineExpired.selector);
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp() - 1));
        _assertAccounting();
    }
}
