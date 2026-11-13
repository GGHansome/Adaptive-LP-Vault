// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LocalUniswapFixture} from "../../helpers/LocalUniswapFixture.sol";
import {AssetSnapshot, DeploymentAssessment, PositionPlan, VenueType} from "../../../src/core/VaultTypes.sol";
import {IUniswapV3SwapRouter} from "../../../src/interfaces/IUniswapV3External.sol";

/// @dev Integration-only business actions and assertions; protocol deployment is shared with invariant tests.
abstract contract IntegrationTestFixture is LocalUniswapFixture {
    function _plain(uint256 deviation, VenueType expected) internal {
        _market(deviation);
        vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        (PositionPlan memory plan, DeploymentAssessment memory assessment) = vault.previewRebalance();
        assertEq(uint8(plan.targetVenue), uint8(expected));
        assertFalse(assessment.requiresSwap);
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        uint64 version = vault.planVersion();
        // Plain rebalancing is permissionless, unlike the swap entry point.
        vm.prank(bob);
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        AssetSnapshot memory afterAssets = vault.assetSnapshot();
        assertApproxEqAbs(afterAssets.total0, beforeAssets.total0, DUST);
        assertApproxEqAbs(afterAssets.total1, beforeAssets.total1, DUST);
        assertEq(afterAssets.totalShares, beforeAssets.totalShares);
        assertEq(vault.planVersion(), version + 1);
        assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), keccak256(abi.encode(plan)));
        assertEq(vault.lastPositionChangeAt(), vm.getBlockTimestamp());
        assertEq(uint8(vault.activeVenue()), uint8(expected));
        _assertAccounting();
    }

    function _deposit(address payer, address beneficiary, uint256 max0, uint256 max1)
        internal
        returns (uint256 used0, uint256 used1, uint256 shares)
    {
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        uint256 balance0 = token0.balanceOf(payer);
        uint256 balance1 = token1.balanceOf(payer);
        uint256 sharesBefore = vault.balanceOf(beneficiary);
        vm.prank(payer);
        (used0, used1, shares) = vault.deposit(max0, max1, 1, beneficiary);
        assertEq(balance0 - token0.balanceOf(payer), used0);
        assertEq(balance1 - token1.balanceOf(payer), used1);
        assertEq(vault.balanceOf(beneficiary) - sharesBefore, shares);
        assertEq(vault.totalSupply() - beforeAssets.totalShares, shares);
        // All standard scenarios have TWAP tick zero: independent NAV = raw amount0 + raw amount1.
        assertEq(
            shares, Math.mulDiv(used0 + used1, beforeAssets.totalShares, beforeAssets.total0 + beforeAssets.total1)
        );
        AssetSnapshot memory afterAssets = vault.assetSnapshot();
        assertApproxEqAbs(afterAssets.total0, beforeAssets.total0 + used0, DUST);
        assertApproxEqAbs(afterAssets.total1, beforeAssets.total1 + used1, DUST);
        _assertAccounting();
    }

    function _redeem(address caller, address owner, address recipient, uint256 shares)
        internal
        returns (uint256 out0, uint256 out1)
    {
        uint256 before0 = token0.balanceOf(recipient);
        uint256 before1 = token1.balanceOf(recipient);
        uint256 ownerShares = vault.balanceOf(owner);
        uint256 supply = vault.totalSupply();
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        vm.prank(caller);
        (out0, out1) = vault.redeem(shares, 0, 0, recipient, owner);
        assertEq(token0.balanceOf(recipient) - before0, out0);
        assertEq(token1.balanceOf(recipient) - before1, out1);
        assertEq(ownerShares - vault.balanceOf(owner), shares);
        assertEq(supply - vault.totalSupply(), shares);
        // Independent economic entitlement, including uncollected fees. The small bound
        // accounts for floor-rounded LP/liquidity units and separate idle distributions.
        assertApproxEqAbs(out0, Math.mulDiv(beforeAssets.total0, shares, supply), DUST);
        assertApproxEqAbs(out1, Math.mulDiv(beforeAssets.total1, shares, supply), DUST);
        AssetSnapshot memory afterAssets = vault.assetSnapshot();
        assertApproxEqAbs(afterAssets.total0 + out0, beforeAssets.total0, DUST);
        assertApproxEqAbs(afterAssets.total1 + out1, beforeAssets.total1, DUST);
        _assertAccounting();
    }

    function _tradeV3(uint24 fee, bool zeroForOne, uint256 amountIn) internal returns (uint256 out) {
        out = router.exactInputSingle(
            IUniswapV3SwapRouter.ExactInputSingleParams(
                zeroForOne ? address(token0) : address(token1),
                zeroForOne ? address(token1) : address(token0),
                fee,
                address(this),
                vm.getBlockTimestamp(),
                amountIn,
                1,
                0
            )
        );
        assertGt(out, 0);
    }
}
