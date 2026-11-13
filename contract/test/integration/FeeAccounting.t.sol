// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IntegrationTestFixture} from "./helpers/IntegrationTestFixture.sol";
import {IIntegrationV2Pair} from "../helpers/LocalUniswapFixture.sol";
import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {VenueType, AssetSnapshot, PositionPlan} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";

contract FeeAccountingIntegrationTest is IntegrationTestFixture {
    function test_realV3FeesArePricedBeforeNewSharesAndPaidOnRedemption() public {
        _v3FeeLifecycle(VenueType.UNISWAP_V3_LOW_FEE, 500);
    }

    function test_realHighFeeV3FeesArePricedBeforeNewSharesAndPaidOnRedemption() public {
        _v3FeeLifecycle(VenueType.UNISWAP_V3_HIGH_FEE, 3000);
    }

    function _v3FeeLifecycle(VenueType venue, uint24 fee) private {
        _bootstrap(venue);
        _deposit(alice, alice, seed / 10, seed / 10);
        uint256 received = _tradeV3(fee, true, seed / 2);
        _tradeV3(fee, false, received);
        PositionSnapshot memory accrued = _adapter(venue).snapshot();
        assertGt(accrued.claimableFee0, 0);
        assertGt(accrued.claimableFee1, 0);
        AssetSnapshot memory beforeDeposit = vault.assetSnapshot();
        (uint256 used0, uint256 used1, uint256 bobShares) = _deposit(bob, bob, seed / 10, seed / 10);
        PositionSnapshot memory collected = _adapter(venue).snapshot();
        assertEq(collected.claimableFee0, 0);
        assertEq(collected.claimableFee1, 0);
        // Existing fee value is in the denominator; the entrant cannot buy at principal-only NAV.
        uint256 principalOnlyNav =
            beforeDeposit.total0 + beforeDeposit.total1 - accrued.claimableFee0 - accrued.claimableFee1;
        assertLt(bobShares, Math.mulDiv(used0 + used1, beforeDeposit.totalShares, principalOnlyNav));
        assertEq(accrued.positionId, collected.positionId);
        uint256 aliceShares = vault.balanceOf(alice);
        _redeem(alice, alice, receiver, aliceShares);
        _redeem(bob, bob, bob, bobShares);
        // No new swaps: another deposit must not recognize the same fees a second time.
        _deposit(alice, alice, seed / 20, seed / 20);
        assertEq(_adapter(venue).snapshot().claimableFee0, 0);
        assertEq(_adapter(venue).snapshot().claimableFee1, 0);
    }

    function test_realV3FeesAreCollectedAndOldNftBurnedDuringMigration() public {
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        uint256 out = _tradeV3(500, true, seed / 2);
        _tradeV3(500, false, out);
        uint256 oldId = low.positionId();
        assertGt(low.snapshot().claimableFee0, 0);
        _plain(150, VenueType.UNISWAP_V3_HIGH_FEE);
        vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
        positionManager.ownerOf(oldId);
        _deposit(alice, alice, seed / 10, seed / 10);
        _redeem(alice, alice, alice, vault.balanceOf(alice));
    }

    function test_redeemSlippageRestoresRealFeeCollectionLiquidityAndAllowance() public {
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        _deposit(alice, alice, seed / 10, seed / 10);
        uint256 out = _tradeV3(500, true, seed / 2);
        _tradeV3(500, false, out);
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.approve(operator, shares);
        bytes32 state =
            keccak256(abi.encode(vault.assetSnapshot(), low.snapshot(), vault.totalSupply(), vault.balanceOf(alice)));
        uint256 pool0 = token0.balanceOf(lowPool);
        uint256 pool1 = token1.balanceOf(lowPool);
        vm.prank(operator);
        vm.expectPartialRevert(IAdaptiveLPVault.AssetSlippage.selector);
        vault.redeem(shares, type(uint256).max, 0, receiver, alice);
        assertEq(vault.allowance(alice, operator), shares);
        assertEq(
            keccak256(abi.encode(vault.assetSnapshot(), low.snapshot(), vault.totalSupply(), vault.balanceOf(alice))),
            state
        );
        assertEq(token0.balanceOf(lowPool), pool0);
        assertEq(token1.balanceOf(lowPool), pool1);
        _redeem(operator, alice, receiver, shares);
        assertEq(vault.allowance(alice, operator), 0);
    }

    function test_realV2TradingFeesIncreaseLpEquityWithoutSeparateFeeClaims() public {
        _bootstrap(VenueType.UNISWAP_V2);
        _deposit(alice, alice, seed / 10, seed / 10);
        AssetSnapshot memory beforeTrades = vault.assetSnapshot();
        uint256 received = _tradeV2(true, seed / 2);
        _tradeV2(false, received);
        AssetSnapshot memory afterTrades = vault.assetSnapshot();
        assertGt(afterTrades.total0 + afterTrades.total1, beforeTrades.total0 + beforeTrades.total1);
        assertEq(v2.snapshot().claimableFee0, 0);
        assertEq(v2.snapshot().claimableFee1, 0);
        _deposit(bob, bob, seed / 10, seed / 10);
        _redeem(alice, alice, alice, vault.balanceOf(alice));
        _plain(150, VenueType.UNISWAP_V3_HIGH_FEE);
        assertEq(IERC20(pair).balanceOf(address(v2)), 0);
        _redeem(bob, bob, bob, vault.balanceOf(bob));
    }

    function test_nonActiveLpDonationIsRecognizedOnlyWhenV2IsActivated() public {
        _bootstrap(VenueType.UNISWAP_V3_HIGH_FEE);
        AssetSnapshot memory beforeDonation = vault.assetSnapshot();
        uint256 donation = IERC20(pair).balanceOf(address(this)) / 100_000;
        IERC20(pair).transfer(address(v2), donation);
        AssetSnapshot memory afterDonation = vault.assetSnapshot();
        assertEq(afterDonation.total0, beforeDonation.total0);
        assertEq(afterDonation.total1, beforeDonation.total1);
        // _plain asserts conservation within dust, so activate explicitly: LP donation is
        // newly recognized value and is expected to increase both asset totals here.
        _market(350);
        vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        (bytes32 hash) = _v2PlanHash();
        vault.rebalance(hash, uint32(vm.getBlockTimestamp()));
        AssetSnapshot memory activated = vault.assetSnapshot();
        assertGt(activated.total0, beforeDonation.total0);
        assertGt(activated.total1, beforeDonation.total1);
        assertEq(activated.totalShares, beforeDonation.totalShares);
        _assertAccounting();
        _deposit(alice, alice, seed / 10, seed / 10);
        _redeem(alice, alice, alice, vault.balanceOf(alice));
    }

    function _v2PlanHash() private view returns (bytes32) {
        (PositionPlan memory plan,) = vault.previewRebalance();
        assertEq(uint8(plan.targetVenue), uint8(VenueType.UNISWAP_V2));
        return plan.planHash;
    }

    function _tradeV2(bool zeroForOne, uint256 amountIn) private returns (uint256 amountOut) {
        (uint112 reserve0, uint112 reserve1,) = IIntegrationV2Pair(pair).getReserves();
        uint256 reserveIn = zeroForOne ? reserve0 : reserve1;
        uint256 reserveOut = zeroForOne ? reserve1 : reserve0;
        amountOut = amountIn * 997 * reserveOut / (reserveIn * 1000 + amountIn * 997);
        (zeroForOne ? token0 : token1).transfer(pair, amountIn);
        IIntegrationV2Pair(pair).swap(zeroForOne ? 0 : amountOut, zeroForOne ? amountOut : 0, address(this), "");
        assertGt(amountOut, 0);
    }
}
