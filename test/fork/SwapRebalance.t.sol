// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ForkRebalanceFixture} from "./helpers/ForkRebalanceFixture.sol";
import {AssetSnapshot, DeploymentAssessment, PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IUniswapV3SwapRouter} from "../../src/interfaces/IUniswapV3External.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";

contract SwapRebalanceForkTest is ForkRebalanceFixture {
    function test_realUsdcToWethSwapMigratesV2ToHighFee() public {
        _successfulSwap(VenueType.UNISWAP_V3_HIGH_FEE, true);
    }

    function test_realWethToUsdcSwapMigratesV2ToHighFee() public {
        _successfulSwap(VenueType.UNISWAP_V3_HIGH_FEE, false);
    }

    function test_realUsdcToWethSwapReactivatesLowFee() public {
        _successfulSwap(VenueType.UNISWAP_V3_LOW_FEE, true);
    }

    function test_realWethToUsdcSwapReactivatesLowFee() public {
        _successfulSwap(VenueType.UNISWAP_V3_LOW_FEE, false);
    }

    function test_realUsdcToWethSwapReactivatesV2() public {
        _successfulSwap(VenueType.UNISWAP_V2, true);
    }

    function test_realWethToUsdcSwapReactivatesV2() public {
        _successfulSwap(VenueType.UNISWAP_V2, false);
    }

    function _successfulSwap(VenueType target, bool zeroForOne) private {
        (PositionPlan memory plan, SwapDirection direction, uint256 amountIn) = _prepareSwap(target, zeroForOne);
        _executeAndAssert(plan, direction, amountIn);
        uint256 shares = _deposit(alice, alice, seed0 / 10, seed1 / 10);
        _redeem(alice, alice, receiver, shares);
    }

    function _executeAndAssert(PositionPlan memory plan, SwapDirection direction, uint256 amountIn) private {
        bool zeroForOne = direction == SwapDirection.ZERO_FOR_ONE;
        IERC20 input = zeroForOne ? token0 : token1;
        IERC20 output = zeroForOne ? token1 : token0;
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        int24 valuationTick = oracle.snapshot().twapTick;
        uint256 beforeNav = _nav(beforeAssets.total0, beforeAssets.total1, valuationTick);
        uint256 poolIn = input.balanceOf(LOW_POOL);
        uint256 poolOut = output.balanceOf(LOW_POOL);
        vm.expectCall(ROUTER, abi.encodeWithSelector(IUniswapV3SwapRouter.exactInputSingle.selector));
        vm.prank(keeper);
        vault.rebalanceWithSwap(plan.planHash, direction, amountIn, 0, uint32(vm.getBlockTimestamp()));
        AssetSnapshot memory afterAssets = vault.assetSnapshot();
        // LOW is also the canonical swap pool. LP exit/mint can touch its balances, so only
        // a HIGH destination (from V2) isolates exact swap-pool deltas.
        if (plan.targetVenue == VenueType.UNISWAP_V3_HIGH_FEE) {
            uint256 actualOut = poolOut - output.balanceOf(LOW_POOL);
            assertEq(input.balanceOf(LOW_POOL) - poolIn, amountIn);
            assertGe(actualOut, _minimumOut(direction, amountIn, valuationTick));
            assertApproxEqAbs(
                afterAssets.total0, zeroForOne ? beforeAssets.total0 - amountIn : beforeAssets.total0 + actualOut, DUST0
            );
            assertApproxEqAbs(
                afterAssets.total1, zeroForOne ? beforeAssets.total1 + actualOut : beforeAssets.total1 - amountIn, DUST1
            );
        } else {
            uint256 actualOut =
                zeroForOne ? afterAssets.total1 - beforeAssets.total1 : afterAssets.total0 - beforeAssets.total0;
            assertGe(actualOut + (zeroForOne ? DUST1 : DUST0), _minimumOut(direction, amountIn, valuationTick));
            if (zeroForOne) assertApproxEqAbs(afterAssets.total0, beforeAssets.total0 - amountIn, DUST0);
            else assertApproxEqAbs(afterAssets.total1, beforeAssets.total1 - amountIn, DUST1);
        }
        assertEq(afterAssets.totalShares, beforeAssets.totalShares);
        assertEq(vault.planVersion(), plan.version);
        assertEq(uint8(vault.activeVenue()), uint8(plan.targetVenue));
        assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), keccak256(abi.encode(plan)));
        uint256 afterNav = _nav(afterAssets.total0, afterAssets.total1, valuationTick);
        assertGe(afterNav, Math.mulDiv(beforeNav, 10_000 - vault.maxMigrationLossBps(), 10_000, Math.Rounding.Ceil));
        uint256 idleNav = _nav(afterAssets.idle0, afterAssets.idle1, valuationTick);
        assertLe(Math.mulDiv(idleNav, 10_000, afterNav, Math.Rounding.Ceil), vault.maxHealthyIdleBps());
        _assertAccounting();
    }

    function test_routerSlippageRestoresOldPositionAndAllowsRetry() public {
        _slippageFailure(true);
    }

    function test_reverseRouterSlippageRestoresOldPositionAndAllowsRetry() public {
        _slippageFailure(false);
    }

    function _slippageFailure(bool zeroForOne) private {
        (PositionPlan memory plan, SwapDirection direction, uint256 amountIn) =
            _prepareSwap(VenueType.UNISWAP_V3_HIGH_FEE, zeroForOne);
        bytes32 beforeState = _stateHash();
        vm.expectCall(ROUTER, abi.encodeWithSelector(IUniswapV3SwapRouter.exactInputSingle.selector));
        vm.prank(keeper);
        vm.expectRevert(bytes("Too little received"));
        vault.rebalanceWithSwap(plan.planHash, direction, amountIn, type(uint256).max, uint32(vm.getBlockTimestamp()));
        assertEq(_stateHash(), beforeState);
        _assertAccounting();
        _executeAndAssert(plan, direction, amountIn);
    }

    /// @dev Only target mint fails; old V2 exit and the preceding real router swap must roll back.
    function test_injectedTargetMintFailureRollsBackRealSwapAndAllowsRetry() public {
        (PositionPlan memory plan, SwapDirection direction, uint256 amountIn) =
            _prepareSwap(VenueType.UNISWAP_V3_HIGH_FEE, true);
        bytes32 beforeState = _stateHash();
        vm.mockCallRevert(
            HIGH_POOL,
            abi.encodeWithSelector(bytes4(keccak256("mint(address,int24,int24,uint128,bytes)"))),
            abi.encodeWithSignature("Error(string)", "injected target mint failure")
        );
        vm.expectCall(ROUTER, abi.encodeWithSelector(IUniswapV3SwapRouter.exactInputSingle.selector));
        vm.prank(keeper);
        vm.expectRevert(bytes("injected target mint failure"));
        vault.rebalanceWithSwap(plan.planHash, direction, amountIn, 0, uint32(vm.getBlockTimestamp()));
        assertEq(_stateHash(), beforeState);
        vm.clearMockedCalls();
        _executeAndAssert(plan, direction, amountIn);
    }

    function test_realCompetingTradeAfterPreviewStillRespectsExecutionBounds() public {
        (PositionPlan memory plan, SwapDirection direction, uint256 amountIn) =
            _prepareSwap(VenueType.UNISWAP_V3_HIGH_FEE, true);
        _tradeV3(500, true, 1000e6);
        // Plan identity is not a price commitment; execution must recheck real output/deployment.
        (PositionPlan memory fresh,) = vault.previewRebalance();
        assertEq(fresh.planHash, plan.planHash);
        _executeAndAssert(plan, direction, amountIn);
    }

    function _prepareSwap(VenueType target, bool zeroForOne)
        private
        returns (PositionPlan memory plan, SwapDirection direction, uint256 amountIn)
    {
        if (target == VenueType.UNISWAP_V3_HIGH_FEE) {
            _deployAndBootstrap(VenueType.UNISWAP_V2);
            vm.warp(vm.getBlockTimestamp() + 1801);
        } else {
            _deployAndBootstrap(target);
            vm.prank(guardian);
            vault.emergencyExitToIdle();
            _resume();
            vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        }
        (plan,) = vault.previewRebalance();
        assertEq(uint8(plan.targetVenue), uint8(target));
        _fundTargetRatio(plan);
        assertTrue((zeroForOne ? token0 : token1).transfer(address(vault), (zeroForOne ? seed0 : seed1) * 2));
        DeploymentAssessment memory assessment;
        (plan, assessment) = vault.previewRebalance();
        assertTrue(assessment.requiresSwap);
        direction = zeroForOne ? SwapDirection.ZERO_FOR_ONE : SwapDirection.ONE_FOR_ZERO;
        assertEq(uint8(assessment.direction), uint8(direction));
        amountIn = _findConservativeInput(plan, direction);
    }

    function _minimumOut(SwapDirection direction, uint256 amountIn, int24 tick) private view returns (uint256) {
        uint256 quote = direction == SwapDirection.ZERO_FOR_ONE
            ? oracle.quoteToken0InToken1(amountIn, tick, true)
            : oracle.quoteToken1InToken0(amountIn, tick, true);
        return Math.mulDiv(quote, 10_000 - vault.maxSwapSlippageBps(), 10_000, Math.Rounding.Ceil);
    }

    /// @dev Test-side sizing only. Search real adapter previews under the protocol's minimum output,
    /// then leave 0.5% of the optimal input unswapped to avoid an opposite-direction overshoot.
    function _findConservativeInput(PositionPlan memory plan, SwapDirection direction) private view returns (uint256) {
        AssetSnapshot memory assets = vault.assetSnapshot();
        bool zeroForOne = direction == SwapDirection.ZERO_FOR_ONE;
        int24 tick = oracle.snapshot().twapTick;
        uint256 left;
        uint256 right = zeroForOne ? assets.total0 : assets.total1;
        for (uint256 i; i < 64 && right - left > 1; ++i) {
            uint256 mid = (left + right) / 2;
            uint256 minOut = _minimumOut(direction, mid, tick);
            uint256 balance0 = zeroForOne ? assets.total0 - mid : assets.total0 + minOut;
            uint256 balance1 = zeroForOne ? assets.total1 + minOut : assets.total1 - mid;
            (uint256 used0, uint256 used1) = _adapter(plan.targetVenue).previewDeposit(balance0, balance1, plan);
            bool excessInput = zeroForOne ? balance0 - used0 > DUST0 : balance1 - used1 > DUST1;
            if (excessInput) left = mid;
            else right = mid;
        }
        uint256 amountIn = left * 995 / 1000;
        assertGt(amountIn, 0);
        return amountIn;
    }
}
