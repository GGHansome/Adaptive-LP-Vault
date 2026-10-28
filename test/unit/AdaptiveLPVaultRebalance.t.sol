// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AdaptiveLPVaultFixture} from "./helpers/AdaptiveLPVaultFixture.sol";
import {PauseState, PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {IUniswapV3SwapRouter} from "../../src/interfaces/IUniswapV3External.sol";
import {SwapDirection, SwapPlan} from "../../src/swap/SwapTypes.sol";
import {IControlledSwapExecutor} from "../../src/interfaces/IControlledSwapExecutor.sol";

contract AdaptiveLPVaultRebalanceTest is AdaptiveLPVaultFixture {
    function _rebalanceCooldown() internal pure override returns (uint32) {
        return 1 hours;
    }

    function test_rebalancesShareNonzeroCooldownAndAcceptExactBoundary() public {
        vm.warp(10000);
        _bootstrap(0, 1500 ether, 500 ether);
        PositionPlan memory plan = _plan(150);
        uint256 available = vm.getBlockTimestamp() + 1 hours;
        vm.warp(available - 1);
        vm.expectRevert(abi.encodeWithSelector(IAdaptiveLPVault.CooldownActive.selector, available));
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        assertEq(vault.lastPositionChangeAt(), 10000);
        vm.warp(available);
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        assertEq(vault.lastPositionChangeAt(), available);
        assertEq(vault.planVersion(), 2);
        plan = _plan(350);
        available += 1 hours;
        vm.warp(available - 1);
        vm.expectRevert(abi.encodeWithSelector(IAdaptiveLPVault.CooldownActive.selector, available));
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(vm.getBlockTimestamp()));
        assertEq(vault.planVersion(), 2);
        vm.warp(available);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(vm.getBlockTimestamp()));
        assertEq(vault.lastPositionChangeAt(), available);
        assertEq(vault.planVersion(), 3);
        plan = _plan(0);
        available += 1 hours;
        vm.warp(available - 1);
        vm.expectRevert(abi.encodeWithSelector(IAdaptiveLPVault.CooldownActive.selector, available));
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        vm.warp(available);
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        assertEq(vault.planVersion(), 4);
        assertEq(vault.lastPositionChangeAt(), available);
        assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), keccak256(abi.encode(plan)));
    }

    function test_rebalanceRejectsBadHashAndExpiredDeadlineInBothEntrypoints() public {
        _readyForSwap();
        PositionPlan memory plan = _plan(350);
        bytes32 history = _history();
        bytes32[3] memory invalidHashes = [bytes32(0), bytes32(uint256(123)), vault.lastExecutedPlan().planHash];
        for (uint256 i; i < invalidHashes.length; ++i) {
            vm.expectRevert(IAdaptiveLPVault.InvalidPlanHash.selector);
            vault.rebalance(invalidHashes[i], uint32(vm.getBlockTimestamp()));
            vm.expectRevert(IAdaptiveLPVault.InvalidPlanHash.selector);
            vault.rebalanceWithSwap(
                invalidHashes[i], SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(vm.getBlockTimestamp())
            );
        }
        uint32[2] memory deadlines = [uint32(0), uint32(vm.getBlockTimestamp() - 1)];
        for (uint256 i; i < deadlines.length; ++i) {
            vm.expectRevert(IAdaptiveLPVault.DeadlineExpired.selector);
            vault.rebalance(plan.planHash, deadlines[i]);
            vm.expectRevert(IAdaptiveLPVault.DeadlineExpired.selector);
            vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, deadlines[i]);
        }
        vm.expectRevert(IAdaptiveLPVault.SwapRequired.selector);
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        assertEq(_history(), history);
        assertEq(high.snapshot().liquidity, 2000 ether);
        // Equal-to-now deadline is valid.
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(vm.getBlockTimestamp()));
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
    }

    function test_swapRejectsNoneAndOppositeDirectionBeforeExit() public {
        _readyForSwap();
        PositionPlan memory plan = _plan(350);
        bytes32 history = _history();
        vm.mockCallRevert(address(high), abi.encodeCall(IPositionAdapter.withdrawAll, ()), "must not exit");
        vm.expectRevert(IAdaptiveLPVault.InvalidSwapDirection.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.NONE, 500 ether, 0, uint32(vm.getBlockTimestamp()));
        vm.expectRevert(IAdaptiveLPVault.InvalidSwapDirection.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ONE_FOR_ZERO, 500 ether, 0, uint32(vm.getBlockTimestamp()));
        assertEq(_history(), history);
        assertEq(high.snapshot().principal0, 1500 ether);
    }

    function test_swapRejectsUnnecessarySwap() public {
        _bootstrap(0, SEED, SEED);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        PositionPlan memory plan = _plan(150);
        vm.expectRevert(IAdaptiveLPVault.SwapNotAllowed.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 1 ether, 0, uint32(vm.getBlockTimestamp()));
        assertEq(vault.planVersion(), 1);
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_LOW_FEE));
    }

    function test_protocolMinOutRoundsUpBothDirectionsAndKeeperOnlyRaisesIt() public {
        for (uint256 reverse; reverse < 2; ++reverse) {
            for (uint256 stricter; stricter < 2; ++stricter) {
                uint256 state = vm.snapshotState();
                vm.warp(10000);
                _bootstrap(150, reverse == 0 ? 1500 ether : 500 ether, reverse == 0 ? 500 ether : 1500 ether);
                vm.warp(vm.getBlockTimestamp() + 1 hours);
                PositionPlan memory plan = _plan(350);
                bytes32 history = _history();
                SwapDirection direction = reverse == 0 ? SwapDirection.ZERO_FOR_ONE : SwapDirection.ONE_FOR_ZERO;
                // A fractional oracle quote has already been rounded upward by the quote API.
                // 500e18+1 then needs a second upward rounding after multiplying by 9900/10000.
                vm.mockCall(
                    address(oracle),
                    abi.encodeWithSignature(
                        reverse == 0
                            ? "quoteToken0InToken1(uint256,int24,bool)"
                            : "quoteToken1InToken0(uint256,int24,bool)",
                        uint256(500 ether),
                        int24(17),
                        true
                    ),
                    abi.encode(uint256(500 ether + 1))
                );
                uint256 keeperMin = stricter == 0 ? 1 : 497 ether;
                uint256 expectedMin = stricter == 0 ? 495 ether + 1 : keeperMin;
                bytes memory execution = abi.encodeCall(
                    IControlledSwapExecutor.executeSwap,
                    (SwapPlan(direction, 500 ether, expectedMin, uint32(vm.getBlockTimestamp())))
                );
                vm.expectCall(address(vault.swapExecutor()), execution);
                vm.mockCallRevert(address(vault.swapExecutor()), execution, "exact minimum reached");
                vm.expectRevert(bytes("exact minimum reached"));
                vault.rebalanceWithSwap(plan.planHash, direction, 500 ether, keeperMin, uint32(vm.getBlockTimestamp()));
                assertEq(_history(), history);
                assertEq(token0.balanceOf(address(vault.swapExecutor())), 0);
                assertEq(token1.balanceOf(address(vault.swapExecutor())), 0);
                assertTrue(vm.revertToStateAndDelete(state));
            }
        }
    }

    function test_swapMigrationLossExactBoundaryWithoutDonation() public {
        _readyForSwap();
        PositionPlan memory plan = _plan(350);
        // 500 * 0.996 = 498; final NAV = 1998, exactly 99.9% of 2000.
        router.setOutputBps(9960);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(vm.getBlockTimestamp()));
        (uint256 total0, uint256 total1) = vault.totalAssets();
        assertEq(total0 + total1, 1998 ether);
        assertEq(vault.planVersion(), 2);
        assertEq(pair.balanceOf(address(v2)), 998 ether);
    }

    function test_swapMigrationLossOneUnitBelowBoundaryRollsBackEverything() public {
        _readyForSwap();
        PositionPlan memory plan = _plan(350);
        bytes32 history = _history();
        uint256 router0 = token0.balanceOf(address(router));
        uint256 router1 = token1.balanceOf(address(router));
        router.setOutputBps(9960);
        router.setOutputReduction(1);
        vm.expectRevert(IAdaptiveLPVault.MigrationLossExceeded.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(vm.getBlockTimestamp()));
        _assertMigrationRestored(history, router0, router1);
    }

    function test_finalDeploymentFailureRollsBackSuccessfulSwap() public {
        _readyForSwap();
        PositionPlan memory plan = _plan(350);
        bytes32 history = _history();
        uint256 router0 = token0.balanceOf(address(router));
        uint256 router1 = token1.balanceOf(address(router));
        PositionSnapshot memory empty;
        vm.mockCall(address(v2), abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(empty));
        // Call expectations prove the failure is after the swap, not at an earlier gate.
        vm.expectCall(address(router), abi.encodeWithSelector(IUniswapV3SwapRouter.exactInputSingle.selector));
        vm.expectRevert(IAdaptiveLPVault.ActivePositionMissing.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(vm.getBlockTimestamp()));
        _assertMigrationRestored(history, router0, router1);
    }

    function test_emergencyExitIgnoresOracleCooldownAndPreservesFullHistory() public {
        vm.warp(10000);
        _bootstrap(0, SEED, SEED);
        uint64 version = vault.planVersion();
        uint32 changedAt = vault.lastPositionChangeAt();
        bytes32 plan = keccak256(abi.encode(vault.lastExecutedPlan()));
        control.setPauseState(PauseState(true, true, true));
        control.setAdapterEnabled(VenueType.UNISWAP_V3_LOW_FEE, false);
        vm.mockCallRevert(address(oracle), bytes(""), "no oracle on exit");
        vault.emergencyExitToIdle();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
        assertEq(vault.planVersion(), version + 1);
        assertEq(vault.lastPositionChangeAt(), changedAt);
        assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), plan);
        assertEq(low.snapshot().liquidity, 0);
        assertEq(token0.balanceOf(address(vault)), SEED);
        assertEq(token1.balanceOf(address(vault)), SEED);
        vault.emergencyExitToIdle();
        assertEq(vault.planVersion(), version + 1);
        assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), plan);
    }

    function _readyForSwap() private {
        vm.warp(10000);
        _bootstrap(150, 1500 ether, 500 ether);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
    }

    function _assertMigrationRestored(bytes32 history, uint256 router0, uint256 router1) private view {
        assertEq(_history(), history);
        assertEq(vault.totalSupply(), 2000 ether);
        assertEq(high.snapshot().principal0, 1500 ether);
        assertEq(high.snapshot().principal1, 500 ether);
        assertEq(pair.balanceOf(address(v2)), 0);
        assertEq(token0.balanceOf(address(router)), router0);
        assertEq(token1.balanceOf(address(router)), router1);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);
        assertEq(token0.balanceOf(address(vault.swapExecutor())), 0);
        assertEq(token1.balanceOf(address(vault.swapExecutor())), 0);
        assertEq(token0.allowance(address(vault.swapExecutor()), address(router)), 0);
        assertEq(token1.allowance(address(vault.swapExecutor()), address(router)), 0);
        assertEq(token0.allowance(address(vault), address(v2)), 0);
        assertEq(token1.allowance(address(vault), address(v2)), 0);
    }

    function _history() private view returns (bytes32) {
        return keccak256(
            abi.encode(vault.activeVenue(), vault.planVersion(), vault.lastPositionChangeAt(), vault.lastExecutedPlan())
        );
    }
}
