// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ForkRebalanceFixture} from "./helpers/ForkRebalanceFixture.sol";
import {AssetSnapshot, PauseState, PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {IUniswapV3Pool} from "../../src/interfaces/IUniswapV3External.sol";

contract EmergencyRecoveryForkTest is ForkRebalanceFixture {
    function test_lowFeeExitPausedAndDisabledThenRedeemAndRecover() public {
        _exitAndRecover(VenueType.UNISWAP_V3_LOW_FEE);
    }

    function test_highFeeExitPausedAndDisabledThenRedeemAndRecover() public {
        _exitAndRecover(VenueType.UNISWAP_V3_HIGH_FEE);
    }

    function test_v2ExitPausedAndDisabledThenRedeemAndRecover() public {
        _exitAndRecover(VenueType.UNISWAP_V2);
    }

    function _exitAndRecover(VenueType venue) private {
        _deployAndBootstrap(venue);
        uint256 shares = _deposit(alice, alice, seed0 / 5, seed1 / 5);
        if (venue != VenueType.UNISWAP_V2) {
            uint24 fee = venue == VenueType.UNISWAP_V3_LOW_FEE ? 500 : 3000;
            uint256 out = _tradeV3(fee, true, 10_000e6);
            _tradeV3(fee, false, out);
            assertGt(_adapter(venue).snapshot().claimableFee0, 0);
        }
        vm.startPrank(guardian);
        control.setAdapterEnabled(venue, false);
        control.setPauseState(PauseState(true, true, true));
        vm.stopPrank();
        // Redemption from the disabled real position must already work before emergency exit.
        _redeem(alice, alice, receiver, shares / 2);
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        PositionPlan memory history = vault.lastExecutedPlan();
        uint64 version = vault.planVersion();
        uint32 changedAt = vault.lastPositionChangeAt();
        uint256 oldId = low.positionId() != 0 ? low.positionId() : high.positionId();
        vm.prank(guardian);
        vault.emergencyExitToIdle();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
        assertApproxEqAbs(vault.assetSnapshot().total0, beforeAssets.total0, DUST0);
        assertApproxEqAbs(vault.assetSnapshot().total1, beforeAssets.total1, DUST1);
        assertEq(vault.planVersion(), version + 1);
        assertEq(vault.lastPositionChangeAt(), changedAt);
        assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), keccak256(abi.encode(history)));
        if (oldId != 0) {
            vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
            positionManager.ownerOf(oldId);
        }
        _assertAccounting();
        _redeem(alice, alice, alice, vault.balanceOf(alice));
        bytes32 exited = _stateHash();
        vm.recordLogs();
        vm.prank(guardian);
        vault.emergencyExitToIdle();
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(_stateHash(), exited, "repeat exit must be idempotent");
        PauseState memory paused = control.pauseState();
        assertTrue(paused.depositPaused && paused.plainRebalancePaused && paused.swapRebalancePaused);
        vm.prank(manager);
        control.setAdapterEnabled(venue, true);
        _resume();
        vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        _plain(venue);
        uint256 reentry = _deposit(bob, bob, seed0 / 10, seed1 / 10);
        _redeem(bob, bob, bob, reentry);
    }

    /// @dev Explicit fault injection, separate from the fully real-dependency scenarios above.
    function test_injectedObservationFailureBlocksEntryButPreservesRealExit() public {
        _deployAndBootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        uint256 shares = _deposit(alice, alice, seed0 / 5, seed1 / 5);
        vm.mockCallRevert(
            LOW_POOL,
            abi.encodeWithSelector(IUniswapV3Pool.observe.selector),
            abi.encodeWithSignature("Error(string)", "OLD")
        );
        assertFalse(oracle.snapshot().healthy);
        vm.prank(bob);
        vm.expectRevert(IAdaptiveLPVault.OracleUnhealthy.selector);
        vault.deposit(seed0 / 10, seed1 / 10, 1, bob);
        vm.expectRevert(IAdaptiveLPVault.OracleUnhealthy.selector);
        vault.previewRebalance();
        _redeem(alice, alice, receiver, shares);
        vm.prank(guardian);
        vault.emergencyExitToIdle();
        _assertAccounting();
        vm.clearMockedCalls();
        assertTrue(oracle.snapshot().healthy);
    }
}
