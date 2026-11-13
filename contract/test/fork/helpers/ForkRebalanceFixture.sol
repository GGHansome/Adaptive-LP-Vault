// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MainnetForkFixture} from "./MainnetForkFixture.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV3Pool} from "../../../src/interfaces/IUniswapV3External.sol";
import {
    AssetSnapshot,
    DeploymentAssessment,
    PauseState,
    PositionPlan,
    VenueType
} from "../../../src/core/VaultTypes.sol";

abstract contract ForkRebalanceFixture is MainnetForkFixture {
    function _resume() internal {
        vm.prank(manager);
        control.setPauseState(PauseState(false, false, false));
    }

    /// @dev Explicit top-up isolates plain migration from inventory optimization. No pool state is edited.
    function _fundTargetRatio(PositionPlan memory plan) internal {
        AssetSnapshot memory assets = vault.assetSnapshot();
        // Use a sufficiently large reference inventory: an out-of-range old position can
        // hold only one asset, making its current-inventory preview zero on both sides.
        (uint256 used0, uint256 used1) = _adapter(plan.targetVenue).previewDeposit(100_000e6, 100 ether, plan);
        assertGt(used0, 0);
        assertGt(used1, 0);
        uint256 required1 = Math.mulDiv(assets.total0, used1, used0, Math.Rounding.Ceil);
        if (required1 > assets.total1) {
            assertTrue(token1.transfer(address(vault), required1 - assets.total1));
        } else {
            uint256 required0 = Math.mulDiv(assets.total1, used0, used1, Math.Rounding.Ceil);
            if (required0 > assets.total0) assertTrue(token0.transfer(address(vault), required0 - assets.total0));
        }
    }

    function _plain(VenueType expected) internal {
        (PositionPlan memory plan,) = vault.previewRebalance();
        assertEq(uint8(plan.targetVenue), uint8(expected));
        _fundTargetRatio(plan);
        DeploymentAssessment memory assessment;
        (plan, assessment) = vault.previewRebalance();
        assertFalse(assessment.requiresSwap);
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        uint256 oldId = low.positionId() != 0 ? low.positionId() : high.positionId();
        vm.prank(bob); // Plain execution remains permissionless.
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        AssetSnapshot memory afterAssets = vault.assetSnapshot();
        assertApproxEqAbs(afterAssets.total0, beforeAssets.total0, DUST0);
        assertApproxEqAbs(afterAssets.total1, beforeAssets.total1, DUST1);
        assertEq(afterAssets.totalShares, beforeAssets.totalShares);
        assertEq(uint8(vault.activeVenue()), uint8(expected));
        assertEq(vault.planVersion(), plan.version);
        assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), keccak256(abi.encode(plan)));
        assertEq(vault.lastPositionChangeAt(), vm.getBlockTimestamp());
        if (oldId != 0) {
            vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
            positionManager.ownerOf(oldId);
        }
        _assertAccounting();
    }

    function _stateHash() internal view returns (bytes32) {
        bytes32 balances;
        address[9] memory accounts = [
            address(vault),
            address(v2),
            address(low),
            address(high),
            PAIR,
            LOW_POOL,
            HIGH_POOL,
            ROUTER,
            address(vault.swapExecutor())
        ];
        for (uint256 i; i < accounts.length; ++i) {
            balances = keccak256(abi.encode(balances, token0.balanceOf(accounts[i]), token1.balanceOf(accounts[i])));
        }
        (uint160 price, int24 tick,,,,,) = IUniswapV3Pool(LOW_POOL).slot0();
        return keccak256(
            abi.encode(
                balances,
                vault.assetSnapshot(),
                v2.snapshot(),
                low.snapshot(),
                high.snapshot(),
                vault.lastExecutedPlan(),
                vault.planVersion(),
                vault.lastPositionChangeAt(),
                price,
                tick,
                IUniswapV3Pool(LOW_POOL).feeGrowthGlobal0X128(),
                IUniswapV3Pool(LOW_POOL).feeGrowthGlobal1X128(),
                token0.allowance(address(vault.swapExecutor()), ROUTER),
                token1.allowance(address(vault.swapExecutor()), ROUTER)
            )
        );
    }
}
