// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AdaptiveLPVaultFixture} from "./helpers/AdaptiveLPVaultFixture.sol";
import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {PauseFlag, PauseState, PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {IAdapterRegistry} from "../../src/interfaces/IAdapterRegistry.sol";
import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {IVaultPause} from "../../src/interfaces/IVaultPause.sol";
import {OracleSnapshot} from "../../src/oracle/OracleTypes.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";

contract AdaptiveLPVaultControlTest is AdaptiveLPVaultFixture {
    function testFuzz_threePauseFlagsGateOnlyTheirOwnEntrypoints(uint8 mask) public {
        mask = uint8(bound(mask, 0, 7));
        _bootstrap(150, 1500 ether, 500 ether);
        PositionPlan memory plan = _plan(350);
        PauseState memory pause = PauseState(mask & 1 != 0, mask & 2 != 0, mask & 4 != 0);
        control.setPauseState(pause);
        uint256 state = vm.snapshotState();
        if (pause.depositPaused) {
            vm.expectRevert(abi.encodeWithSelector(IVaultPause.Paused.selector, PauseFlag.DEPOSIT));
        }
        vault.deposit(30 ether, 10 ether, 0, address(this));
        assertTrue(vm.revertToStateAndDelete(state));
        state = vm.snapshotState();
        if (pause.plainRebalancePaused) {
            vm.expectRevert(abi.encodeWithSelector(IVaultPause.Paused.selector, PauseFlag.PLAIN_REBALANCE));
        } else {
            vm.expectRevert(IAdaptiveLPVault.SwapRequired.selector);
        }
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        assertTrue(vm.revertToStateAndDelete(state));
        state = vm.snapshotState();
        if (pause.swapRebalancePaused) {
            vm.expectRevert(abi.encodeWithSelector(IVaultPause.Paused.selector, PauseFlag.SWAP_REBALANCE));
        }
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(vm.getBlockTimestamp()));
        if (!pause.swapRebalancePaused) assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
        assertTrue(vm.revertToStateAndDelete(state));
        // Read-only planning and redemption remain available for every pause combination.
        vault.previewRebalance();
        (uint256 out0, uint256 out1) = vault.redeem(100 ether, 0, 0, address(this), address(this));
        assertEq(out0, 75 ether);
        assertEq(out1, 25 ether);
        vault.emergencyExitToIdle();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
    }

    function test_oracleUnhealthyBlocksValueSensitiveOperationsButAllowsExit() public {
        OracleSnapshot memory healthy = oracle.snapshot();
        OracleSnapshot memory unhealthy;
        vm.mockCall(address(oracle), abi.encodeCall(ICanonicalV3Oracle.snapshot, ()), abi.encode(unhealthy));
        vm.expectRevert(IAdaptiveLPVault.OracleUnhealthy.selector);
        vault.bootstrap(SEED, SEED, address(this));
        assertEq(vault.totalSupply(), 0);
        healthy.deviationBps = 0;
        vm.mockCall(address(oracle), abi.encodeCall(ICanonicalV3Oracle.snapshot, ()), abi.encode(healthy));
        vault.bootstrap(SEED, SEED, address(this));
        bytes32 history = _history();
        vm.mockCall(address(oracle), abi.encodeCall(ICanonicalV3Oracle.snapshot, ()), abi.encode(unhealthy));
        vm.expectRevert(IAdaptiveLPVault.OracleUnhealthy.selector);
        vault.deposit(1 ether, 1 ether, 0, address(this));
        vm.expectRevert(IAdaptiveLPVault.OracleUnhealthy.selector);
        vault.previewRebalance();
        vm.expectRevert(IAdaptiveLPVault.OracleUnhealthy.selector);
        vault.rebalance(bytes32(uint256(1)), uint32(vm.getBlockTimestamp()));
        vm.expectRevert(IAdaptiveLPVault.OracleUnhealthy.selector);
        vault.rebalanceWithSwap(bytes32(uint256(1)), SwapDirection.ZERO_FOR_ONE, 1, 0, uint32(vm.getBlockTimestamp()));
        assertEq(_history(), history);
        assertEq(vault.totalSupply(), 2 * SEED);
        PauseState memory pause = control.pauseState();
        assertFalse(pause.depositPaused || pause.plainRebalancePaused || pause.swapRebalancePaused);
        // Both an unhealthy response and a reverting oracle must leave exit paths usable.
        vault.redeem(100 ether, 0, 0, address(this), address(this));
        vm.mockCallRevert(address(oracle), bytes(""), "oracle unavailable");
        vault.redeem(100 ether, 0, 0, address(this), address(this));
        vault.emergencyExitToIdle();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
    }

    function test_disabledActiveAdapterBlocksDepositBeforeFeesButAllowsAccountingAndExit() public {
        _bootstrap(0, SEED, SEED);
        control.setAdapterEnabled(VenueType.UNISWAP_V3_LOW_FEE, false);
        bytes32 history = _history();
        vm.mockCallRevert(address(low), abi.encodeCall(IPositionAdapter.syncFees, ()), "must not synchronize");
        vm.expectRevert(IAdapterRegistry.AdapterDisabled.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
        assertEq(_history(), history);
        (uint256 total0, uint256 total1) = vault.totalAssets();
        assertEq(total0, SEED);
        assertEq(total1, SEED);
        vm.mockCall(address(low), abi.encodeCall(IPositionAdapter.syncFees, ()), abi.encode(uint256(0), uint256(0)));
        vault.redeem(100 ether, 0, 0, address(this), address(this));
        PositionPlan memory plan = _plan(150);
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_HIGH_FEE));
        vault.emergencyExitToIdle();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
    }

    function test_disabledTargetBlocksPreviewPlainAndSwapBeforeExit() public {
        _bootstrap(150, 1500 ether, 500 ether);
        PositionPlan memory plan = _plan(350);
        bytes32 history = _history();
        control.setAdapterEnabled(VenueType.UNISWAP_V2, false);
        vm.mockCallRevert(address(high), abi.encodeCall(IPositionAdapter.withdrawAll, ()), "must not exit");
        vm.expectRevert(IAdapterRegistry.AdapterDisabled.selector);
        vault.previewRebalance();
        vm.expectRevert(IAdapterRegistry.AdapterDisabled.selector);
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        vm.expectRevert(IAdapterRegistry.AdapterDisabled.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(vm.getBlockTimestamp()));
        assertEq(_history(), history);
        assertEq(high.snapshot().principal0, 1500 ether);
        assertEq(high.snapshot().principal1, 500 ether);
        assertEq(pair.balanceOf(address(v2)), 0);
    }

    function test_redeemIgnoresSingleSidedPrincipalHighIdleAndDisabledAdapter() public {
        _bootstrap(0, SEED, SEED);
        control.setAdapterEnabled(VenueType.UNISWAP_V3_LOW_FEE, false);
        control.setPauseState(PauseState(true, true, true));
        vm.mockCallRevert(address(oracle), bytes(""), "no valuation on exit");
        token0.mint(address(vault), 10000 ether);
        // Isolate the single-sided deposit gate while keeping position identity valid.
        PositionSnapshot memory p = low.snapshot();
        p.principal1 = 0;
        vm.mockCall(address(low), abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(p));
        address receiver = makeAddr("risk exit receiver");
        (uint256 out0, uint256 out1) = vault.redeem(100 ether, 0, 0, receiver, address(this));
        assertEq(out0, 550 ether);
        assertEq(out1, 50 ether);
        assertEq(token0.balanceOf(receiver), out0);
        assertEq(token1.balanceOf(receiver), out1);
    }

    function test_idleEmergencyExitIsStrictlyIdempotent() public {
        _bootstrap(1000, SEED, SEED);
        bytes32 history = _history();
        vm.mockCallRevert(address(low), bytes(""), "no adapter calls");
        vm.mockCallRevert(address(high), bytes(""), "no adapter calls");
        vm.mockCallRevert(address(v2), bytes(""), "no adapter calls");
        vm.recordLogs();
        vault.emergencyExitToIdle();
        assertEq(vm.getRecordedLogs().length, 1); // Only PauseStateChanged, from control.
        vm.recordLogs();
        vault.emergencyExitToIdle();
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(_history(), history);
        assertEq(vault.totalSupply(), 2 * SEED);
        PauseState memory pause = control.pauseState();
        assertTrue(pause.depositPaused && pause.plainRebalancePaused && pause.swapRebalancePaused);
    }

    function test_rootHasNoImplicitBusinessPrivilegesAndRevocationIsImmediate() public {
        _bootstrap(0, SEED, SEED);
        bytes32 managerRole = control.MANAGER_ROLE();
        control.revokeRole(managerRole, address(this));
        bytes memory unauthorized = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), managerRole
        );
        vm.expectRevert(unauthorized);
        vault.emergencyExitToIdle();
        vm.expectRevert(unauthorized);
        vault.rebalanceWithSwap(bytes32(0), SwapDirection.NONE, 1, 0, uint32(vm.getBlockTimestamp()));
        // Plain rebalance is permissionless even for a root account without business roles.
        PositionPlan memory plan = _plan(150);
        vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        bytes32 guardianRole = control.GUARDIAN_ROLE();
        address guardian = makeAddr("guardian");
        control.grantRole(guardianRole, guardian);
        vm.prank(guardian);
        vault.emergencyExitToIdle();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
    }

    function _history() private view returns (bytes32) {
        return keccak256(
            abi.encode(vault.activeVenue(), vault.planVersion(), vault.lastPositionChangeAt(), vault.lastExecutedPlan())
        );
    }
}
