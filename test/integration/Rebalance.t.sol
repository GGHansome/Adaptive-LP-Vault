// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IntegrationTestFixture} from "./helpers/IntegrationTestFixture.sol";
import {VenueType, PositionPlan, DeploymentAssessment, AssetSnapshot} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {IUniswapV3Pool} from "../../src/interfaces/IUniswapV3External.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";
import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";
import {OracleSnapshot} from "../../src/oracle/OracleTypes.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";

contract RebalanceIntegrationTest is IntegrationTestFixture {
    function test_fullStrategyCycleAcrossAllVenuesAndBack() public {
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        _deposit(alice, alice, seed / 10, seed / 10);
        uint256 shares = vault.balanceOf(alice);
        uint256 oldLowId = low.positionId();
        _plain(150, VenueType.UNISWAP_V3_HIGH_FEE);
        vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
        positionManager.ownerOf(oldLowId);
        uint256 oldHighId = high.positionId();
        _plain(350, VenueType.UNISWAP_V2);
        vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
        positionManager.ownerOf(oldHighId);
        _plain(600, VenueType.IDLE);
        assertEq(vault.assetSnapshot().position0, 0);
        assertEq(vault.assetSnapshot().position1, 0);
        _plain(350, VenueType.UNISWAP_V2);
        _plain(150, VenueType.UNISWAP_V3_HIGH_FEE);
        _plain(0, VenueType.UNISWAP_V3_LOW_FEE);
        assertEq(vault.balanceOf(alice), shares);
        _redeem(alice, alice, alice, shares);
    }

    function test_previewThenAnotherExecutionMakesOldPlanStale() public {
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        _market(150);
        vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        (PositionPlan memory oldPlan,) = vault.previewRebalance();
        vm.prank(alice);
        vault.rebalance(oldPlan.planHash, uint32(vm.getBlockTimestamp()));
        _market(350);
        vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        bytes32 beforeState =
            keccak256(abi.encode(vault.assetSnapshot(), vault.lastExecutedPlan(), vault.planVersion()));
        vm.prank(bob);
        vm.expectRevert(IAdaptiveLPVault.InvalidPlanHash.selector);
        vault.rebalance(oldPlan.planHash, uint32(vm.getBlockTimestamp()));
        assertEq(
            keccak256(abi.encode(vault.assetSnapshot(), vault.lastExecutedPlan(), vault.planVersion())), beforeState
        );
        _plain(350, VenueType.UNISWAP_V2);
    }

    function test_bothRebalanceEntrypointsRespectSharedCooldown() public {
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        _plain(150, VenueType.UNISWAP_V3_HIGH_FEE);
        _market(350);
        (PositionPlan memory plan,) = vault.previewRebalance();
        vm.expectRevert(
            abi.encodeWithSelector(IAdaptiveLPVault.CooldownActive.selector, vm.getBlockTimestamp() + COOLDOWN)
        );
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(IAdaptiveLPVault.CooldownActive.selector, vm.getBlockTimestamp() + COOLDOWN)
        );
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, seed / 10, 0, uint32(vm.getBlockTimestamp()));
        _plain(350, VenueType.UNISWAP_V2);
    }

    function test_realPriceMoveCanRecenterSameV3VenueAndClearOldNft() public {
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        uint256 oldId = low.positionId();
        // Move the actual low-fee pool beyond the old narrow range using a real trade.
        _tradeV3(500, false, seed * 10);
        (, int24 spot,,,,,) = IUniswapV3Pool(lowPool).slot0();
        assertGt(spot, 100);
        // Only market observation is controlled; both old and new positions use actual pool math.
        OracleSnapshot memory observation = oracle.snapshot();
        observation.spotTick = spot;
        observation.twapTick = spot;
        observation.shortTwapTick = spot;
        observation.spotPriceToken1 = PriceMath.quoteToken0InToken1(1 ether, spot, false);
        observation.twapPriceToken1 = observation.spotPriceToken1;
        observation.shortTwapPriceToken1 = observation.spotPriceToken1;
        observation.deviationBps = 0;
        vm.mockCall(address(oracle), abi.encodeCall(ICanonicalV3Oracle.snapshot, ()), abi.encode(observation));
        // Balance inventory for the proposed range using real preview amounts. This isolates
        // recentering from swap sizing while retaining a real out-of-range old position.
        vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        (PositionPlan memory plan,) = vault.previewRebalance();
        assertEq(uint8(plan.targetVenue), uint8(VenueType.UNISWAP_V3_LOW_FEE));
        assertGt(plan.tickLower, vault.lastExecutedPlan().tickLower);
        (uint256 target0, uint256 target1) = low.previewDeposit(seed * 10, seed * 10, plan);
        AssetSnapshot memory current = vault.assetSnapshot();
        token0.transfer(address(vault), target0 - current.total0);
        token1.transfer(address(vault), target1 - current.total1);
        DeploymentAssessment memory assessment;
        (plan, assessment) = vault.previewRebalance();
        assertFalse(assessment.requiresSwap);
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        assertTrue(low.positionId() != oldId);
        vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
        positionManager.ownerOf(oldId);
        AssetSnapshot memory afterAssets = vault.assetSnapshot();
        assertApproxEqAbs(afterAssets.total0, beforeAssets.total0, DUST);
        assertApproxEqAbs(afterAssets.total1, beforeAssets.total1, DUST);
        _assertAccounting();
    }
}
