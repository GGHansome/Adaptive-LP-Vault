// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AdaptiveLPVaultDonationsTest, DonationV3Adapter} from "./AdaptiveLPVaultDonations.t.sol";
import {PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {IVaultControl} from "../../src/interfaces/IVaultControl.sol";
import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";
import {OracleSnapshot} from "../../src/oracle/OracleTypes.sol";
import {VaultControl} from "../../src/control/VaultControl.sol";
import {IAdapterRegistry} from "../../src/interfaces/IAdapterRegistry.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Disables the target during exit to verify that cached addresses never replace the entry-status gate.
contract ExitDisablingAdapter is DonationV3Adapter {
    VaultControl private immutable _control;

    constructor(address vault_, address pool_, address token0_, address token1_, VaultControl control_)
        DonationV3Adapter(vault_, pool_, token0_, token1_, VenueType.UNISWAP_V3_LOW_FEE)
    {
        _control = control_;
    }

    function withdrawAll() external override returns (uint256 amount0, uint256 amount1) {
        require(msg.sender == vault);
        amount0 = _position.amount0;
        amount1 = _position.amount1;
        delete _position;
        require(IERC20(token0).transfer(vault, amount0));
        require(IERC20(token1).transfer(vault, amount1));
        _control.setAdapterEnabled(VenueType.UNISWAP_V3_HIGH_FEE, false);
    }
}

/// @dev Adds real fee transfers to the stateful V3 stand-in; no pool math is modeled here.
contract FeeDonationV3Adapter is DonationV3Adapter {
    constructor(address vault_, address pool_, address token0_, address token1_, VenueType venue_)
        DonationV3Adapter(vault_, pool_, token0_, token1_, venue_)
    {}

    function accrueFees(uint256 fee0, uint256 fee1) external {
        _position.claimableFee0 += fee0;
        _position.claimableFee1 += fee1;
        _position.amount0 += fee0;
        _position.amount1 += fee1;
    }

    function syncFees() external override returns (uint256 fee0, uint256 fee1) {
        require(msg.sender == vault);
        fee0 = _position.claimableFee0;
        fee1 = _position.claimableFee1;
        _position.claimableFee0 = 0;
        _position.claimableFee1 = 0;
        _position.amount0 = _position.principal0;
        _position.amount1 = _position.principal1;
        if (fee0 != 0) require(IERC20(token0).transfer(vault, fee0));
        if (fee1 != 0) require(IERC20(token1).transfer(vault, fee1));
    }
}

/// @dev Use --isolate: snapshotGasLastCall measures only the vault call, not fixture setup/assertions.
///      V2 uses the real adapter and a mock pair; V3 and oracle/router use local stateful stand-ins.
contract AdaptiveLPVaultGasTest is AdaptiveLPVaultDonationsTest {
    function setUp() public override {
        super.setUp();
        low = new FeeDonationV3Adapter(
            address(vault), low.pool(), address(token0), address(token1), VenueType.UNISWAP_V3_LOW_FEE
        );
        high = new FeeDonationV3Adapter(
            address(vault), high.pool(), address(token0), address(token1), VenueType.UNISWAP_V3_HIGH_FEE
        );
        control.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(low));
        control.configureAdapter(VenueType.UNISWAP_V3_HIGH_FEE, address(high));
    }

    function testGas_bootstrapV3() public {
        oracle.setDeviation(0);
        vault.bootstrap(SEED, SEED, address(this));
        _record("bootstrapV3");
    }

    function testGas_bootstrapV2() public {
        oracle.setDeviation(350);
        vault.bootstrap(SEED, SEED, address(this));
        _record("bootstrapV2");
    }

    function testGas_bootstrapIdle() public {
        oracle.setDeviation(1000);
        vault.bootstrap(SEED, SEED, address(this));
        _record("bootstrapIdle");
    }

    function testGas_depositV3NoFees() public {
        _bootstrap(0, SEED, SEED);
        vault.deposit(100 ether, 100 ether, 0, address(this));
        _record("depositV3NoFees");
    }

    function testGas_depositV3WithFees() public {
        _bootstrap(0, SEED, SEED);
        _accrueFees(10 ether, 10 ether);
        vault.deposit(100 ether, 100 ether, 0, address(this));
        _record("depositV3WithFees");
    }

    function testGas_depositV2() public {
        _bootstrap(350, SEED, SEED);
        vault.deposit(100 ether, 100 ether, 0, address(this));
        _record("depositV2");
    }

    function testGas_redeemV3NoFees() public {
        _bootstrap(0, SEED, SEED);
        vault.redeem(100 ether, 0, 0, address(this), address(this));
        _record("redeemV3NoFees");
    }

    function testGas_redeemV3WithFees() public {
        _bootstrap(0, SEED, SEED);
        _accrueFees(10 ether, 10 ether);
        vault.redeem(100 ether, 0, 0, address(this), address(this));
        _record("redeemV3WithFees");
    }

    function testGas_redeemIdle() public {
        _bootstrap(1000, SEED, SEED);
        vault.redeem(100 ether, 0, 0, address(this), address(this));
        _record("redeemIdle");
    }

    function testGas_rebalanceV3ToV3() public {
        _bootstrap(0, SEED, SEED);
        PositionPlan memory plan = _plan(150);
        vault.rebalance(plan.planHash, uint32(block.timestamp));
        _record("rebalanceV3ToV3");
    }

    function testGas_rebalanceV3WithFees() public {
        _bootstrap(0, SEED, SEED);
        _accrueFees(10 ether, 10 ether);
        PositionPlan memory plan = _plan(150);
        vault.rebalance(plan.planHash, uint32(block.timestamp));
        _record("rebalanceV3WithFees");
    }

    function testGas_rebalanceToIdle() public {
        _bootstrap(350, SEED, SEED);
        PositionPlan memory plan = _plan(1000);
        vault.rebalance(plan.planHash, uint32(block.timestamp));
        _record("rebalanceToIdle");
    }

    function testGas_swapZeroForOne() public {
        _bootstrap(150, 1500 ether, 500 ether);
        PositionPlan memory plan = _plan(350);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
        _record("swapZeroForOne");
    }

    function testGas_swapOneForZero() public {
        _bootstrap(150, 500 ether, 1500 ether);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("quoteToken1InToken0(uint256,int24,bool)", uint256(500 ether), int24(17), true),
            abi.encode(500 ether)
        );
        PositionPlan memory plan = _plan(350);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ONE_FOR_ZERO, 500 ether, 0, uint32(block.timestamp));
        _record("swapOneForZero");
    }

    function testGas_emergencyV3WithFees() public {
        _bootstrap(0, SEED, SEED);
        _accrueFees(10 ether, 10 ether);
        vault.emergencyExitToIdle();
        _record("emergencyV3WithFees");
    }

    function test_bootstrapReusesEstablishedSnapshotAndSkipsUnusedV2Address() public {
        vm.mockCallRevert(
            address(control),
            abi.encodeCall(IVaultControl.getAdapterOrRevert, (VenueType.UNISWAP_V2)),
            "unused V2 address"
        );
        vm.expectCall(address(low), abi.encodeCall(IPositionAdapter.snapshot, ()), uint64(2));
        vm.expectCall(address(high), abi.encodeCall(IPositionAdapter.snapshot, ()), uint64(2));
        _bootstrap(0, SEED, SEED);
    }

    function test_depositReusesPostFeeAndPostDepositSnapshots() public {
        _bootstrap(0, SEED, SEED);
        _accrueFees(10 ether, 10 ether);
        vm.expectCall(address(low), abi.encodeCall(IPositionAdapter.snapshot, ()), uint64(2));
        vm.expectCall(address(high), abi.encodeCall(IPositionAdapter.snapshot, ()), uint64(1));
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.FeesSynchronized(address(low), 10 ether, 10 ether, 1010 ether, 1010 ether);
        (,, uint256 shares) = vault.deposit(100 ether, 100 ether, 0, address(this));
        assertEq(shares, Math.mulDiv(200 ether, 2 * SEED, 2020 ether));
        assertEq(token0.balanceOf(address(vault)), 10 ether);
        assertEq(token1.balanceOf(address(vault)), 10 ether);
    }

    function test_depositReadsFreshBalancesAtAccountingBoundaries() public {
        _bootstrap(0, SEED, SEED);
        _accrueFees(10 ether, 10 ether);
        // Fee event, pre-deposit assets, two exact-pull reads, adapter pre/post checks, final assets.
        vm.expectCall(address(token0), abi.encodeCall(IERC20.balanceOf, (address(vault))), uint64(7));
        vm.expectCall(address(token1), abi.encodeCall(IERC20.balanceOf, (address(vault))), uint64(7));
        vault.deposit(100 ether, 100 ether, 0, address(this));
    }

    function test_exitReadsFreshBalancesAtAccountingBoundaries() public {
        _bootstrap(0, SEED, SEED);
        _accrueFees(10 ether, 10 ether);
        // Fee event, pre-exit assets, final IDLE assets; no withdrawal return-value comparison reads.
        vm.expectCall(address(token0), abi.encodeCall(IERC20.balanceOf, (address(vault))), uint64(3));
        vm.expectCall(address(token1), abi.encodeCall(IERC20.balanceOf, (address(vault))), uint64(3));
        vault.emergencyExitToIdle();
    }

    function test_singleTokenFeePreservesEventAndDepositPricing() public {
        _bootstrap(0, SEED, SEED);
        _accrueFees(0, 5 ether);
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.FeesSynchronized(address(low), 0, 5 ether, SEED, SEED + 5 ether);
        (,, uint256 shares) = vault.deposit(100 ether, 100 ether, 0, address(this));
        assertEq(shares, Math.mulDiv(200 ether, 2 * SEED, 2 * SEED + 5 ether));
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 5 ether);
    }

    function test_zeroFeeRedeemDoesNotEmitFeeEvent() public {
        _bootstrap(0, SEED, SEED);
        vm.recordLogs();
        (uint256 amount0, uint256 amount1) = vault.redeem(100 ether, 0, 0, address(this), address(this));
        assertEq(amount0, 50 ether);
        assertEq(amount1, 50 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 feeEvent = keccak256("FeesSynchronized(address,uint256,uint256,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(vault)) assertNotEq(logs[i].topics[0], feeEvent);
        }
    }

    function test_feeSnapshotIncludesExistingIdleDonation() public {
        _bootstrap(0, SEED, SEED);
        token0.transfer(address(vault), 1 ether);
        _accrueFees(3 ether, 5 ether);
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.FeesSynchronized(address(low), 3 ether, 5 ether, 1004 ether, 1005 ether);
        (uint256 amount0, uint256 amount1) = vault.redeem(100 ether, 0, 0, address(this), address(this));
        assertEq(amount0, 50.2 ether);
        assertEq(amount1, 50.25 ether);
    }

    function test_emergencyPreservesFeeAndExitEvents() public {
        _bootstrap(0, SEED, SEED);
        _accrueFees(3 ether, 5 ether);
        vm.expectCall(address(low), abi.encodeCall(IPositionAdapter.snapshot, ()), uint64(3));
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.FeesSynchronized(address(low), 3 ether, 5 ether, 1003 ether, 1005 ether);
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.EmergencyExit(address(this), VenueType.UNISWAP_V3_LOW_FEE, 1003 ether, 1005 ether);
        vault.emergencyExitToIdle();
        assertEq(token0.balanceOf(address(vault)), 1003 ether);
        assertEq(token1.balanceOf(address(vault)), 1005 ether);
    }

    function test_sameVenueRecenterReusesPreviewAndPreservesRangeEvent() public {
        _bootstrap(0, SEED, SEED);
        PositionPlan memory oldPlan = vault.lastExecutedPlan();
        OracleSnapshot memory snapshot;
        snapshot.healthy = true;
        snapshot.spotTick = 1000;
        snapshot.twapTick = 1000;
        vm.mockCall(address(oracle), abi.encodeCall(ICanonicalV3Oracle.snapshot, ()), abi.encode(snapshot));
        (PositionPlan memory plan,) = vault.previewRebalance();
        vm.expectCall(address(low), abi.encodeCall(IPositionAdapter.snapshot, ()), uint64(4));
        vm.expectCall(address(high), abi.encodeCall(IPositionAdapter.snapshot, ()), uint64(1));
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.PositionPlanCommitted(plan.planHash, plan.version, plan.targetVenue, plan.marketRegime);
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.V3RangeChanged(
            plan.planHash, oldPlan.tickLower, oldPlan.tickUpper, plan.tickLower, plan.tickUpper
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.RebalanceExecuted(
            address(this),
            plan.planHash,
            VenueType.UNISWAP_V3_LOW_FEE,
            VenueType.UNISWAP_V3_LOW_FEE,
            false,
            SEED,
            SEED,
            2 * SEED,
            0
        );
        vault.rebalance(plan.planHash, uint32(block.timestamp));
    }

    function test_cachedSnapshotStillRejectsWrongRange() public {
        _bootstrap(0, SEED, SEED);
        PositionSnapshot memory position = low.snapshot();
        position.tickUpper += 10;
        vm.mockCall(address(low), abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(position));
        vm.expectRevert(IAdaptiveLPVault.PositionRangeMismatch.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
    }

    function test_cachedSnapshotStillRejectsUncollectedFees() public {
        _bootstrap(0, SEED, SEED);
        PositionSnapshot memory position = low.snapshot();
        position.claimableFee0 = 1;
        position.amount0 += 1;
        vm.mockCall(address(low), abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(position));
        vm.expectRevert(IAdaptiveLPVault.FeesNotCleared.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
    }

    function test_rebalanceRejectsUnchangedRangeUsingPreviewSnapshot() public {
        _bootstrap(0, SEED, SEED);
        (PositionPlan memory plan,) = vault.previewRebalance();
        vm.expectRevert(IAdaptiveLPVault.NoStateChangeRequired.selector);
        vault.rebalance(plan.planHash, uint32(block.timestamp));
    }

    function test_rebalanceRejectsActualRangeMismatchBeforeCommit() public {
        _bootstrap(0, SEED, SEED);
        PositionPlan memory plan = _plan(150);
        PositionSnapshot memory position;
        position.venue = VenueType.UNISWAP_V3_HIGH_FEE;
        position.adapter = address(high);
        position.positionId = 1;
        position.liquidity = 2 * SEED;
        position.principal0 = SEED;
        position.principal1 = SEED;
        position.amount0 = SEED;
        position.amount1 = SEED;
        position.tickLower = plan.tickLower;
        position.tickUpper = plan.tickUpper + 60;
        vm.mockCall(address(high), abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(position));
        vm.expectRevert(IAdaptiveLPVault.PositionRangeMismatch.selector);
        vault.rebalance(plan.planHash, uint32(block.timestamp));
        assertEq(vault.planVersion(), 1);
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_LOW_FEE));
    }

    function test_targetEnabledIsRecheckedAfterExitCallback() public {
        low = new ExitDisablingAdapter(address(vault), low.pool(), address(token0), address(token1), control);
        control.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(low));
        control.grantRole(control.GUARDIAN_ROLE(), address(low));
        _bootstrap(0, SEED, SEED);
        PositionPlan memory plan = _plan(150);
        vm.expectRevert(IAdapterRegistry.AdapterDisabled.selector);
        vault.rebalance(plan.planHash, uint32(block.timestamp));
        assertTrue(control.isEnterEnabled(VenueType.UNISWAP_V3_HIGH_FEE));
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_LOW_FEE));
        assertEq(token0.balanceOf(address(low)), SEED);
    }

    function _accrueFees(uint256 fee0, uint256 fee1) internal {
        token0.mint(address(low), fee0);
        token1.mint(address(low), fee1);
        FeeDonationV3Adapter(address(low)).accrueFees(fee0, fee1);
    }

    function _record(string memory name) private {
        emit log_named_uint(name, vm.snapshotGasLastCall(name));
    }
}
