// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IntegrationTestFixture} from "./helpers/IntegrationTestFixture.sol";
import {VenueType, AssetSnapshot, PositionPlan, PauseState} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {IUniswapV3Pool} from "../../src/interfaces/IUniswapV3External.sol";
import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";

contract EmergencyRecoveryIntegrationTest is IntegrationTestFixture {
    function test_lowFeeV3EmergencyExitRedeemAndRecovery() public {
        _exitAndRecover(VenueType.UNISWAP_V3_LOW_FEE, 0, 500);
    }

    function test_highFeeV3EmergencyExitRedeemAndRecovery() public {
        _exitAndRecover(VenueType.UNISWAP_V3_HIGH_FEE, 150, 3000);
    }

    function test_v2EmergencyExitRedeemAndRecovery() public {
        _exitAndRecover(VenueType.UNISWAP_V2, 350, 0);
    }

    function _exitAndRecover(VenueType venue, uint256 deviation, uint24 fee) private {
        _bootstrap(venue);
        _deposit(alice, alice, seed / 10, seed / 10);
        if (fee != 0) {
            uint256 out = _tradeV3(fee, true, seed / 2);
            _tradeV3(fee, false, out);
            assertGt(_adapter(venue).snapshot().claimableFee0, 0);
        }
        vm.startPrank(guardian);
        control.setAdapterEnabled(venue, false);
        control.setPauseState(PauseState(true, true, true));
        vm.stopPrank();
        // An unavailable oracle must not prevent the exit, even during cooldown.
        vm.mockCallRevert(
            address(oracle),
            abi.encodeCall(ICanonicalV3Oracle.snapshot, ()),
            abi.encodeWithSignature("Error(string)", "oracle unavailable")
        );
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        PositionPlan memory history = vault.lastExecutedPlan();
        uint64 version = vault.planVersion();
        uint32 changedAt = vault.lastPositionChangeAt();
        vm.prank(guardian);
        vault.emergencyExitToIdle();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
        AssetSnapshot memory exited = vault.assetSnapshot();
        assertApproxEqAbs(exited.total0, beforeAssets.total0, DUST);
        assertApproxEqAbs(exited.total1, beforeAssets.total1, DUST);
        assertEq(exited.totalShares, beforeAssets.totalShares);
        assertEq(vault.planVersion(), version + 1);
        assertEq(vault.lastPositionChangeAt(), changedAt);
        assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), keccak256(abi.encode(history)));
        PauseState memory paused = control.pauseState();
        assertTrue(paused.depositPaused && paused.plainRebalancePaused && paused.swapRebalancePaused);
        _assertAccounting();
        _redeem(alice, alice, receiver, vault.balanceOf(alice));
        AssetSnapshot memory beforeRepeat = vault.assetSnapshot();
        vm.recordLogs();
        vm.prank(guardian);
        vault.emergencyExitToIdle();
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(vault.planVersion(), version + 1);
        assertEq(keccak256(abi.encode(vault.assetSnapshot())), keccak256(abi.encode(beforeRepeat)));
        _market(deviation); // Restore observation access and select the historical regime.
        vm.startPrank(manager);
        control.setAdapterEnabled(venue, true);
        control.setPauseState(PauseState(false, false, false));
        vm.stopPrank();
        _plain(deviation, venue);
        _deposit(bob, bob, seed / 10, seed / 10);
        _redeem(bob, bob, bob, vault.balanceOf(bob));
    }

    function test_realOracleNormalizesObservationFailureWhileExitPathsRemainOpen() public {
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        _deposit(alice, alice, seed / 10, seed / 10);
        vm.mockCallRevert(
            canonicalPool,
            abi.encodeWithSelector(IUniswapV3Pool.observe.selector),
            abi.encodeWithSignature("Error(string)", "OLD")
        );
        assertFalse(oracle.snapshot().healthy);
        vm.prank(bob);
        vm.expectRevert(IAdaptiveLPVault.OracleUnhealthy.selector);
        vault.deposit(seed / 10, seed / 10, 1, bob);
        vm.expectRevert(IAdaptiveLPVault.OracleUnhealthy.selector);
        vault.previewRebalance();
        _redeem(alice, alice, alice, vault.balanceOf(alice));
        vm.prank(guardian);
        vault.emergencyExitToIdle();
        _assertAccounting();
        vm.clearMockedCalls();
        assertTrue(oracle.snapshot().healthy);
    }

    function test_idleBootstrapCanRedeemThenActivateV2() public {
        _bootstrap(VenueType.IDLE);
        _redeem(manager, manager, receiver, vault.balanceOf(manager) / 5);
        _plain(350, VenueType.UNISWAP_V2);
        _deposit(alice, alice, seed / 10, seed / 10);
        _redeem(alice, alice, alice, vault.balanceOf(alice));
    }
}
