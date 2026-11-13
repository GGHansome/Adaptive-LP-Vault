// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VaultEdgeFixture} from "./helpers/VaultEdgeFixtures.sol";
import {EdgeToken, EdgeReentryProbe} from "./mocks/VaultEdgeMocks.sol";
import {AdaptiveLPVault} from "../../src/core/AdaptiveLPVault.sol";
import {PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";

contract AdaptiveLPVaultCallbackSafetyTest is VaultEdgeFixture {
    PositionPlan private _candidate;
    bool private _reverse;
    uint256 private _user0;
    uint256 private _user1;
    uint256 private _router0;
    uint256 private _router1;
    bytes32 private _historicalPlan;
    uint32 private _changedAt;

    function setUp() public {
        _deploy(18, 18, 1, LOCKED);
    }

    function test_bootstrapTokenTransfersBlockAllAssetEntrypoints() public {
        for (uint256 side; side < 2; ++side) {
            uint256 saved = vm.snapshotState();
            EdgeToken token = side == 0 ? token0 : token1;
            _armToken(token, address(this), address(vault));
            uint256 user0 = token0.balanceOf(address(this));
            uint256 user1 = token1.balanceOf(address(this));
            _bootstrap(SEED, SEED);
            _assertProbe(1);
            assertEq(probe.observedSupply(), 0);
            assertEq(probe.observedOwnerShares(), 0);
            assertEq(vault.totalSupply(), 2 * SEED);
            assertEq(vault.balanceOf(address(this)), 2 * SEED - LOCKED);
            assertEq(vault.balanceOf(address(vault)), LOCKED);
            assertEq(token0.balanceOf(address(this)), user0 - SEED);
            assertEq(token1.balanceOf(address(this)), user1 - SEED);
            assertEq(low.snapshot().principal0, SEED);
            assertEq(low.snapshot().principal1, SEED);
            assertEq(vault.planVersion(), 1);
            assertTrue(vm.revertToStateAndDelete(saved));
        }
    }

    function test_depositUserAndAdapterTokenPullsBlockAllAssetEntrypoints() public {
        _start(0, false, false);
        for (uint256 boundary; boundary < 2; ++boundary) {
            for (uint256 side; side < 2; ++side) {
                uint256 saved = vm.snapshotState();
                token0.approve(address(vault), 100 ether);
                token1.approve(address(vault), 100 ether);
                _armToken(
                    side == 0 ? token0 : token1,
                    boundary == 0 ? address(this) : address(vault),
                    boundary == 0 ? address(vault) : address(low)
                );
                _execute(0);
                _assertProbe(1);
                assertEq(probe.observedSupply(), 2000 ether);
                _assertOperation(0, false);
                assertEq(token0.allowance(address(this), address(vault)), 0);
                assertEq(token1.allowance(address(this), address(vault)), 0);
                assertTrue(vm.revertToStateAndDelete(saved));
            }
        }
    }

    function test_feeTransferCallbacksBlockAllAssetEntrypoints() public {
        for (uint8 operation; operation < 5; ++operation) {
            for (uint256 side; side < 2; ++side) {
                uint256 saved = vm.snapshotState();
                _start(operation, true, false);
                _armToken(side == 0 ? token0 : token1, address(low), address(vault));
                _execute(operation);
                _assertProbe(1);
                assertEq(probe.observedSupply(), 2000 ether);
                _assertOperation(operation, true);
                assertTrue(vm.revertToStateAndDelete(saved));
            }
        }
    }

    function test_partialWithdrawalCallbackBlocksAllAssetEntrypoints() public {
        _start(1, false, false);
        low.setHook(address(probe), abi.encodeCall(EdgeReentryProbe.attackAll, ()));
        low.setHookMask(4);
        _execute(1);
        _assertProbe(1);
        assertEq(probe.observedSupply(), 2000 ether); // Adapter withdrawal precedes burning owner shares.
        assertEq(probe.observedOwnerShares(), 1999 ether);
        _assertOperation(1, false);
    }

    function test_fullExitCallbacksBlockAllAssetEntrypoints() public {
        for (uint8 operation = 2; operation < 5; ++operation) {
            uint256 saved = vm.snapshotState();
            _start(operation, false, false);
            low.setHook(address(probe), abi.encodeCall(EdgeReentryProbe.attackAll, ()));
            low.setHookMask(8);
            _execute(operation);
            _assertProbe(1);
            _assertOperation(operation, false);
            assertTrue(vm.revertToStateAndDelete(saved));
        }
    }

    function test_exitTokenTransfersBlockAllAssetEntrypoints() public {
        for (uint8 operation = 1; operation < 5; ++operation) {
            for (uint256 side; side < 2; ++side) {
                uint256 saved = vm.snapshotState();
                _start(operation, false, false);
                _armToken(side == 0 ? token0 : token1, address(low), address(vault));
                _execute(operation);
                _assertProbe(1);
                _assertOperation(operation, false);
                assertTrue(vm.revertToStateAndDelete(saved));
            }
        }
    }

    function test_routerCallbacksBlockAllAssetEntrypointsInBothDirections() public {
        for (uint256 reverse; reverse < 2; ++reverse) {
            uint256 saved = vm.snapshotState();
            _start(3, false, reverse != 0);
            router.setHook(address(probe), abi.encodeCall(EdgeReentryProbe.attackAll, ()));
            _execute(3);
            _assertProbe(1);
            _assertOperation(3, false);
            assertTrue(vm.revertToStateAndDelete(saved));
        }
    }

    function test_swapInputRouterPullAndOutputCallbacksBlockAllAssetEntrypoints() public {
        for (uint256 reverse; reverse < 2; ++reverse) {
            for (uint256 boundary; boundary < 3; ++boundary) {
                uint256 saved = vm.snapshotState();
                _start(3, false, reverse != 0);
                EdgeToken input = reverse == 0 ? token0 : token1;
                EdgeToken output = reverse == 0 ? token1 : token0;
                if (boundary == 0) _armToken(input, address(vault), address(vault.swapExecutor()));
                else if (boundary == 1) _armToken(input, address(vault.swapExecutor()), address(router));
                else _armToken(output, address(router), address(vault));
                _execute(3);
                _assertProbe(1);
                assertEq(probe.observedSupply(), 2000 ether);
                _assertOperation(3, false);
                assertTrue(vm.revertToStateAndDelete(saved));
            }
        }
    }

    function test_receiverTransferCallbacksObserveBurnedSharesAndBlockReentry() public {
        _start(1, false, false);
        for (uint256 side; side < 2; ++side) {
            uint256 saved = vm.snapshotState();
            _armToken(side == 0 ? token0 : token1, address(vault), address(probe));
            _execute(1);
            _assertProbe(1);
            assertEq(probe.observedSupply(), 1900 ether);
            assertEq(probe.observedOwnerShares(), 1899 ether);
            _assertOperation(1, false);
            assertTrue(vm.revertToStateAndDelete(saved));
        }
    }

    function test_revertingReceiverTransferRestoresFeesBurnAndSpentAllowance() public {
        _start(1, true, false);
        vault.approve(address(probe), 100 ether);
        for (uint256 side; side < 2; ++side) {
            uint256 saved = vm.snapshotState();
            EdgeToken token = side == 0 ? token0 : token1;
            token.setTransferBoundary(address(vault), address(probe));
            token.setHook(address(probe), abi.encodeCall(EdgeReentryProbe.rejectTransfer, ()));
            bytes32 beforeState = _stateDigest();
            vm.expectCall(address(low), abi.encodeCall(IPositionAdapter.withdraw, (100 ether, 2000 ether)));
            vm.expectCall(address(probe), abi.encodeCall(EdgeReentryProbe.rejectTransfer, ()));
            vm.prank(address(probe));
            vm.expectRevert(EdgeReentryProbe.ReceiverRejected.selector);
            vault.redeem(100 ether, 0, 0, address(probe), address(this));
            assertEq(_stateDigest(), beforeState);
            assertEq(low.snapshot().claimableFee0, 10 ether);
            assertEq(low.snapshot().claimableFee1, 10 ether);
            assertEq(vault.allowance(address(this), address(probe)), 100 ether);
            assertEq(token.hookTarget(), address(probe));
            assertTrue(vm.revertToStateAndDelete(saved));
        }
    }

    function test_postSwapFailureRestoresStateAfterAllReentryAttempts() public {
        for (uint256 reverse; reverse < 2; ++reverse) {
            uint256 saved = vm.snapshotState();
            _start(3, false, reverse != 0);
            router.setHook(address(probe), abi.encodeCall(EdgeReentryProbe.attackAll, ()));
            high.setLosses(2, 0, 0, 0);
            bytes32 beforeState = _stateDigest();
            vm.expectCall(address(probe), abi.encodeCall(EdgeReentryProbe.attackAll, ()));
            vm.expectCall(address(high), abi.encodeWithSelector(IPositionAdapter.deposit.selector));
            vm.expectRevert(AdaptiveLPVault.AssetConservationViolation.selector);
            _execute(3);
            assertEq(_stateDigest(), beforeState);
            assertEq(probe.batches(), 0); // Even the probe's six recorded failures roll back with the outer call.
            assertTrue(vm.revertToStateAndDelete(saved));
        }
    }

    function test_guardReleasesAfterReceiverCallbackAndAllowsLaterRedemption() public {
        _start(1, false, false);
        _armToken(token0, address(vault), address(probe));
        _execute(1);
        _assertProbe(1);
        vm.prank(address(probe));
        vault.redeem(100 ether, 50 ether, 50 ether, address(probe), address(this));
        assertEq(vault.totalSupply(), 1800 ether);
        assertEq(vault.balanceOf(address(this)), 1799 ether);
        assertEq(token0.balanceOf(address(probe)), 100 ether);
        assertEq(token1.balanceOf(address(probe)), 100 ether);
        assertEq(vault.planVersion(), 1);
    }

    function _start(uint8 operation, bool fees, bool reverse) private {
        _reverse = reverse;
        _bootstrap(
            operation == 3 ? reverse ? 500 ether : 1500 ether : SEED,
            operation == 3 ? reverse ? 1500 ether : 500 ether : SEED
        );
        if (fees) {
            token0.mint(address(low), 10 ether);
            token1.mint(address(low), 10 ether);
            low.accrueFees(10 ether, 10 ether);
        }
        if (operation == 3) high.setBalancedPreview(true);
        if (operation == 2 || operation == 3) _candidate = _plan(150);
        token0.mint(address(vault.swapExecutor()), 13);
        token1.mint(address(vault.swapExecutor()), 17);
        _user0 = token0.balanceOf(address(this));
        _user1 = token1.balanceOf(address(this));
        _router0 = token0.balanceOf(address(router));
        _router1 = token1.balanceOf(address(router));
        _historicalPlan = keccak256(abi.encode(vault.lastExecutedPlan()));
        _changedAt = vault.lastPositionChangeAt();
    }

    function _execute(uint8 operation) private {
        if (operation == 0) {
            vault.deposit(100 ether, 100 ether, 0, address(probe));
        } else if (operation == 1) {
            vault.redeem(100 ether, 0, 0, address(probe), address(this));
        } else if (operation == 2) {
            vault.rebalance(_candidate.planHash, uint32(vm.getBlockTimestamp()));
        } else if (operation == 3) {
            vault.rebalanceWithSwap(
                _candidate.planHash,
                _reverse ? SwapDirection.ONE_FOR_ZERO : SwapDirection.ZERO_FOR_ONE,
                500 ether,
                0,
                uint32(vm.getBlockTimestamp())
            );
        } else {
            vault.emergencyExitToIdle();
        }
    }

    function _armToken(EdgeToken token, address from, address to) private {
        token.setTransferBoundary(from, to);
        token.setHook(address(probe), abi.encodeCall(EdgeReentryProbe.attackAll, ()));
    }

    function _assertOperation(uint8 operation, bool fees) private view {
        uint256 fee = fees ? 10 ether : 0;
        uint256 expected0 = SEED + fee;
        uint256 expected1 = SEED + fee;
        if (operation == 0) {
            uint256 shares = Math.mulDiv(200 ether, 2000 ether, 2000 ether + fee * 2);
            expected0 += 100 ether;
            expected1 += 100 ether;
            assertEq(vault.totalSupply(), 2000 ether + shares);
            assertEq(vault.balanceOf(address(probe)), shares);
            assertEq(token0.balanceOf(address(this)), _user0 - 100 ether);
            assertEq(token1.balanceOf(address(this)), _user1 - 100 ether);
            assertEq(low.snapshot().principal0, 1100 ether);
            assertEq(low.snapshot().principal1, 1100 ether);
        } else if (operation == 1) {
            uint256 out = 50 ether + fee / 20;
            expected0 -= out;
            expected1 -= out;
            assertEq(token0.balanceOf(address(probe)), out);
            assertEq(token1.balanceOf(address(probe)), out);
            assertEq(vault.totalSupply(), 1900 ether);
            assertEq(vault.balanceOf(address(this)), 1899 ether);
            assertEq(low.snapshot().principal0, 950 ether);
            assertEq(low.snapshot().principal1, 950 ether);
        } else {
            assertEq(vault.totalSupply(), 2000 ether);
            assertEq(vault.balanceOf(address(this)), 1999 ether);
            assertEq(low.snapshot().liquidity, 0);
            assertEq(vault.planVersion(), 2);
            if (operation == 4) {
                assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
                assertEq(token0.balanceOf(address(vault)), expected0);
                assertEq(token1.balanceOf(address(vault)), expected1);
                assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), _historicalPlan);
                assertEq(vault.lastPositionChangeAt(), _changedAt);
                assertTrue(control.pauseState().depositPaused);
                assertTrue(control.pauseState().plainRebalancePaused);
                assertTrue(control.pauseState().swapRebalancePaused);
            } else {
                assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_HIGH_FEE));
                assertEq(high.snapshot().principal0, expected0);
                assertEq(high.snapshot().principal1, expected1);
                assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), keccak256(abi.encode(_candidate)));
            }
        }
        if (operation <= 1) {
            assertEq(vault.planVersion(), 1);
            assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), _historicalPlan);
        }
        if (operation != 0) {
            assertEq(token0.balanceOf(address(this)), _user0);
            assertEq(token1.balanceOf(address(this)), _user1);
        }
        if (operation == 3) {
            assertEq(router.swapCalls(), 1);
            assertEq(router.lastMinimum(), 495 ether);
            assertEq(token0.balanceOf(address(router)), _reverse ? _router0 - 500 ether : _router0 + 500 ether);
            assertEq(token1.balanceOf(address(router)), _reverse ? _router1 + 500 ether : _router1 - 500 ether);
        } else {
            assertEq(router.swapCalls(), 0);
            assertEq(token0.balanceOf(address(router)), _router0);
            assertEq(token1.balanceOf(address(router)), _router1);
        }
        (uint256 actual0, uint256 actual1) = vault.totalAssets();
        assertEq(actual0, expected0);
        assertEq(actual1, expected1);
        assertEq(vault.balanceOf(address(vault)), LOCKED);
        assertEq(token0.balanceOf(address(vault.swapExecutor())), 13);
        assertEq(token1.balanceOf(address(vault.swapExecutor())), 17);
        assertEq(token0.allowance(address(vault), address(low)), 0);
        assertEq(token1.allowance(address(vault), address(low)), 0);
        assertEq(token0.allowance(address(vault), address(high)), 0);
        assertEq(token1.allowance(address(vault), address(high)), 0);
        assertEq(token0.allowance(address(vault.swapExecutor()), address(router)), 0);
        assertEq(token1.allowance(address(vault.swapExecutor()), address(router)), 0);
        assertEq(token0.balanceOf(low.LOSS_SINK()), 0);
        assertEq(token1.balanceOf(low.LOSS_SINK()), 0);
    }
}
