// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VaultEdgeFixture} from "./helpers/VaultEdgeFixtures.sol";
import {EdgeAdapter, EdgeOracle} from "./mocks/VaultEdgeMocks.sol";
import {AdaptiveLPVault} from "../../src/core/AdaptiveLPVault.sol";
import {PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";
import {IControlledSwapExecutor} from "../../src/interfaces/IControlledSwapExecutor.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {IUniswapV3SwapRouter} from "../../src/interfaces/IUniswapV3External.sol";
import {SwapDirection, SwapPlan} from "../../src/swap/SwapTypes.sol";

contract AdaptiveLPVaultMigrationSafetyTest is VaultEdgeFixture {
    function setUp() public {
        _deploy(18, 18, 1, LOCKED);
    }

    function testFuzz_plainRebalanceUsesCapturedTwapAcrossCallbacks(uint8 stage) public {
        stage = uint8(bound(stage, 0, 2));
        _bootstrap(SEED, SEED);
        _accrueFees();
        PositionPlan memory plan = _plan(150);
        _changeOracleDuring(stage == 2 ? 3 : stage);
        oracle.setRestrictQuoteTick(true);
        vm.expectCall(address(oracle), abi.encodeCall(ICanonicalV3Oracle.snapshot, ()), uint64(1));
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.RebalanceExecuted(
            address(this),
            plan.planHash,
            VenueType.UNISWAP_V3_LOW_FEE,
            VenueType.UNISWAP_V3_HIGH_FEE,
            false,
            1010 ether,
            1010 ether,
            2020 ether,
            0
        );
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        _assertCapturedPlan(plan);
        assertEq(high.snapshot().principal0, 1010 ether);
        assertEq(high.snapshot().principal1, 1010 ether);
        assertEq(router.swapCalls(), 0);
    }

    function testFuzz_swapRebalanceUsesCapturedTwapAcrossCallbacks(uint8 stage, bool reverse) public {
        stage = uint8(bound(stage, 0, 3));
        _bootstrap(reverse ? 500 ether : 1500 ether, reverse ? 1500 ether : 500 ether);
        _accrueFees();
        high.setBalancedPreview(true);
        PositionPlan memory plan = _plan(150);
        _changeOracleDuring(stage);
        oracle.setRestrictQuoteTick(true);
        SwapDirection direction = reverse ? SwapDirection.ONE_FOR_ZERO : SwapDirection.ZERO_FOR_ONE;
        vm.expectCall(address(oracle), abi.encodeCall(ICanonicalV3Oracle.snapshot, ()), uint64(1));
        vm.expectCall(
            address(vault.swapExecutor()),
            abi.encodeCall(
                IControlledSwapExecutor.executeSwap,
                (SwapPlan(direction, 500 ether, 495 ether, uint32(vm.getBlockTimestamp())))
            )
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.RebalanceExecuted(
            address(this),
            plan.planHash,
            VenueType.UNISWAP_V3_LOW_FEE,
            VenueType.UNISWAP_V3_HIGH_FEE,
            true,
            1010 ether,
            1010 ether,
            2020 ether,
            0
        );
        vault.rebalanceWithSwap(plan.planHash, direction, 500 ether, 0, uint32(vm.getBlockTimestamp()));
        _assertCapturedPlan(plan);
        assertEq(router.swapCalls(), 1);
        assertEq(router.lastMinimum(), 495 ether);
        _assertAssets(1010 ether, 1010 ether);
    }

    function testFuzz_bootstrapConservationDustBoundary(bool token1Side) public {
        _exerciseDust(0, token1Side, false);
    }

    function testFuzz_depositConservationDustBoundary(bool token1Side) public {
        _exerciseDust(1, token1Side, false);
    }

    function testFuzz_plainRebalanceExitDustBoundary(bool token1Side) public {
        _exerciseDust(2, token1Side, false);
    }

    function testFuzz_plainRebalanceDepositDustBoundary(bool token1Side) public {
        _exerciseDust(3, token1Side, false);
    }

    function testFuzz_emergencyExitConservationDustBoundary(bool token1Side) public {
        _exerciseDust(4, token1Side, false);
    }

    function testFuzz_swapExitConservationDustBoundary(bool token1Side, bool reverse) public {
        _exerciseDust(5, token1Side, reverse);
    }

    function testFuzz_swapFinalConservationDustBoundary(bool token1Side, bool reverse) public {
        _exerciseDust(6, token1Side, reverse);
    }

    function test_plainRebalanceAcceptsMaximumTimestamp() public {
        _maximumTimestamp(false);
    }

    function test_swapRebalanceAcceptsMaximumTimestamp() public {
        _maximumTimestamp(true);
    }

    function test_rebalancesPastMaximumTimestampRejectDeadlineBeforeAssets() public {
        _bootstrap(1500 ether, 500 ether);
        high.setBalancedPreview(true);
        PositionPlan memory plan = _plan(150);
        bytes32 beforeState = _stateDigest();
        vm.warp(uint256(type(uint32).max) + 1);
        vm.mockCallRevert(address(low), abi.encodeCall(IPositionAdapter.syncFees, ()), "must not synchronize");
        vm.expectRevert(IAdaptiveLPVault.DeadlineExpired.selector);
        vault.rebalance(plan.planHash, type(uint32).max);
        vm.expectRevert(IAdaptiveLPVault.DeadlineExpired.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, type(uint32).max);
        assertEq(_stateDigest(), beforeState);
    }

    function test_plainRebalanceCommitTimestampOverflowRollsBack() public {
        _commitTimestampOverflow(false);
    }

    function test_swapRebalanceCommitTimestampOverflowRollsBack() public {
        _commitTimestampOverflow(true);
    }

    /// @dev Deliberate fault injection: a real EVM transaction cannot change its own timestamp.
    /// Normal calls above uint32.max are already rejected by the uint32 deadline check.
    function warpPastTimestampLimit() external {
        require(msg.sender == address(high));
        vm.warp(uint256(type(uint32).max) + 1);
    }

    function _exerciseDust(uint8 operation, bool token1Side, bool reverse) private {
        bool swap = operation >= 5;
        if (operation != 0) {
            _bootstrap(
                swap && !reverse ? 1500 ether : swap ? 500 ether : SEED,
                swap && reverse ? 1500 ether : swap ? 500 ether : SEED
            );
        }
        if (swap) high.setBalancedPreview(true);
        PositionPlan memory plan;
        if (operation == 2 || operation == 3 || swap) plan = _plan(150);
        token0.mint(address(vault.swapExecutor()), 13);
        token1.mint(address(vault.swapExecutor()), 17);
        token0.approve(address(vault), operation == 0 ? SEED : 100 ether);
        token1.approve(address(vault), operation == 0 ? SEED : 100 ether);
        for (uint256 loss = 1; loss <= 2; ++loss) {
            uint256 saved = vm.snapshotState();
            uint256 loss0 = token1Side ? 0 : loss;
            uint256 loss1 = token1Side ? loss : 0;
            if (operation <= 1) low.setLosses(loss0, loss1, 0, 0);
            else if (operation == 3 || operation == 6) high.setLosses(loss0, loss1, 0, 0);
            else low.setLosses(0, 0, loss0, loss1);
            bytes32 beforeState = _stateDigest();
            if (operation == 6) {
                // The final conservation branch must be reached after a real swap and target deposit.
                vm.expectCall(address(router), abi.encodeWithSelector(IUniswapV3SwapRouter.exactInputSingle.selector));
                vm.expectCall(address(high), abi.encodeWithSelector(IPositionAdapter.deposit.selector));
            }
            if (loss == 2 && operation == 5) {
                vm.mockCallRevert(
                    address(router),
                    abi.encodeWithSelector(IUniswapV3SwapRouter.exactInputSingle.selector),
                    "exit loss must fail before router"
                );
            }
            if (loss == 2) vm.expectRevert(AdaptiveLPVault.AssetConservationViolation.selector);
            _executeDustOperation(operation, plan, reverse);
            if (loss == 2) {
                assertEq(_stateDigest(), beforeState);
            } else {
                uint256 total = operation == 1 ? 1100 ether : SEED;
                _assertAssets(total - loss0, total - loss1);
                assertEq(token0.balanceOf(low.LOSS_SINK()), loss0);
                assertEq(token1.balanceOf(low.LOSS_SINK()), loss1);
                assertEq(vault.totalSupply(), operation == 1 ? 2200 ether : 2000 ether);
                assertEq(vault.planVersion(), operation <= 1 ? 1 : 2);
                assertEq(token0.balanceOf(address(vault.swapExecutor())), 13);
                assertEq(token1.balanceOf(address(vault.swapExecutor())), 17);
                assertEq(token0.allowance(address(vault), address(low)), 0);
                assertEq(token1.allowance(address(vault), address(low)), 0);
                assertEq(token0.allowance(address(vault), address(high)), 0);
                assertEq(token1.allowance(address(vault), address(high)), 0);
                assertEq(token0.allowance(address(vault.swapExecutor()), address(router)), 0);
                assertEq(token1.allowance(address(vault.swapExecutor()), address(router)), 0);
            }
            assertTrue(vm.revertToStateAndDelete(saved));
        }
    }

    function _executeDustOperation(uint8 operation, PositionPlan memory plan, bool reverse) private {
        if (operation == 0) {
            _bootstrap(SEED, SEED);
        } else if (operation == 1) {
            vault.deposit(100 ether, 100 ether, 0, address(this));
        } else if (operation <= 3) {
            vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        } else if (operation == 4) {
            vault.emergencyExitToIdle();
        } else {
            vault.rebalanceWithSwap(
                plan.planHash,
                reverse ? SwapDirection.ONE_FOR_ZERO : SwapDirection.ZERO_FOR_ONE,
                500 ether,
                0,
                uint32(vm.getBlockTimestamp())
            );
        }
    }

    function _maximumTimestamp(bool swap) private {
        _bootstrap(swap ? 1500 ether : SEED, swap ? 500 ether : SEED);
        high.setBalancedPreview(swap);
        PositionPlan memory plan = _plan(150);
        vm.warp(type(uint32).max);
        if (swap) vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, type(uint32).max);
        else vault.rebalance(plan.planHash, type(uint32).max);
        assertEq(vault.lastPositionChangeAt(), type(uint32).max);
        assertEq(vault.planVersion(), 2);
        assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), keccak256(abi.encode(plan)));
        _assertAssets(SEED, SEED);
    }

    function _commitTimestampOverflow(bool swap) private {
        _bootstrap(swap ? 1500 ether : SEED, swap ? 500 ether : SEED);
        high.setBalancedPreview(swap);
        PositionPlan memory plan = _plan(150);
        high.setHook(address(this), abi.encodeCall(this.warpPastTimestampLimit, ()));
        high.setHookMask(2);
        bytes32 beforeState = _stateDigest();
        vm.warp(type(uint32).max);
        vm.expectCall(address(this), abi.encodeCall(this.warpPastTimestampLimit, ()));
        if (swap) {
            vm.expectCall(address(router), abi.encodeWithSelector(IUniswapV3SwapRouter.exactInputSingle.selector));
        }
        vm.expectRevert(IAdaptiveLPVault.TimestampOverflow.selector);
        if (swap) vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, type(uint32).max);
        else vault.rebalance(plan.planHash, type(uint32).max);
        assertEq(_stateDigest(), beforeState);
    }

    function _changeOracleDuring(uint8 stage) private {
        bytes memory data = abi.encodeCall(EdgeOracle.setState, (1000, 217, false));
        if (stage == 0 || stage == 1) {
            low.setHook(address(oracle), data);
            low.setHookMask(stage == 0 ? 1 : 8);
        } else if (stage == 2) {
            router.setHook(address(oracle), data);
        } else {
            high.setHook(address(oracle), data);
            high.setHookMask(2);
        }
    }

    function _accrueFees() private {
        token0.mint(address(low), 10 ether);
        token1.mint(address(low), 10 ether);
        low.accrueFees(10 ether, 10 ether);
    }

    function _assertCapturedPlan(PositionPlan memory plan) private view {
        assertEq(oracle.currentTick(), 217);
        assertEq(vault.planVersion(), 2);
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_HIGH_FEE));
        assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), keccak256(abi.encode(plan)));
        assertEq(low.snapshot().liquidity, 0);
        assertEq(vault.totalSupply(), 2000 ether);
    }

    function _assertAssets(uint256 expected0, uint256 expected1) private view {
        (uint256 total0, uint256 total1) = vault.totalAssets();
        assertEq(total0, expected0);
        assertEq(total1, expected1);
    }
}
