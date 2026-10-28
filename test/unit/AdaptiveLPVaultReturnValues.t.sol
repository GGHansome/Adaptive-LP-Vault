// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AdaptiveLPVaultDonationsTest} from "./AdaptiveLPVaultDonations.t.sol";
import {AdaptiveLPVault} from "../../src/core/AdaptiveLPVault.sol";
import {PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {IAdapterRegistry} from "../../src/interfaces/IAdapterRegistry.sol";
import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";
import {IVaultControl} from "../../src/interfaces/IVaultControl.sol";
import {IControlledSwapExecutor} from "../../src/interfaces/IControlledSwapExecutor.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {SwapDirection, SwapPlan} from "../../src/swap/SwapTypes.sol";

import {MisreportingFullExitAdapter, SwapExecutorStub} from "./mocks/VaultReturnValueMocks.sol";

contract AdaptiveLPVaultReturnValuesTest is AdaptiveLPVaultDonationsTest {
    error UnexpectedExternalCall();

    function test_bootstrapRejectsZeroReceiverBeforeComponentValidation() public {
        vm.mockCallRevert(
            address(control),
            abi.encodeCall(IVaultControl.validateConfiguredAdapters, ()),
            abi.encodeWithSelector(UnexpectedExternalCall.selector)
        );
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vault.bootstrap(SEED, SEED, address(0));
        assertFalse(vault.initialized());
        assertEq(vault.totalSupply(), 0);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);
    }

    function testFuzz_bootstrapRejectsZeroSeed(bool zeroToken0, uint256 otherAmount) public {
        vm.expectRevert(IAdaptiveLPVault.ZeroAmount.selector);
        vault.bootstrap(zeroToken0 ? 0 : otherAmount, zeroToken0 ? otherAmount : 0, address(this));
    }

    function testFuzz_depositRejectsZeroMaximumBeforeDepositGate(bool zeroToken0, uint256 otherAmount) public {
        _bootstrap(0, SEED, SEED);
        _blockDepositGate();
        vm.expectRevert(IAdaptiveLPVault.ZeroAmount.selector);
        vault.deposit(zeroToken0 ? 0 : otherAmount, zeroToken0 ? otherAmount : 0, 0, address(this));
    }

    function test_depositRejectsBothZeroMaximumsBeforeDepositGate() public {
        _bootstrap(0, SEED, SEED);
        _blockDepositGate();
        vm.expectRevert(IAdaptiveLPVault.ZeroAmount.selector);
        vault.deposit(0, 0, 0, address(this));
    }

    function test_depositRejectsZeroReceiverBeforeDepositGate() public {
        _bootstrap(0, SEED, SEED);
        _blockDepositGate();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vault.deposit(100 ether, 100 ether, 0, address(0));
        assertEq(vault.totalSupply(), 2 * SEED);
        _assertFullSeedAssets();
    }

    function test_depositStillRejectsRoundedZeroActualAmount() public {
        _bootstrap(0, SEED, SEED);
        _mockPrincipal(address(low), SEED, 2 * SEED);
        vm.expectRevert(IAdaptiveLPVault.ZeroAmount.selector);
        vault.deposit(1, 1, 0, address(this));
    }

    function test_depositChecksInitializationBeforeZeroInputs() public {
        vm.expectRevert(IAdapterRegistry.NotInitialized.selector);
        vault.deposit(0, 0, 0, address(0));
    }

    function test_redeemRejectsZeroReceiverBeforeFeeSync() public {
        _bootstrap(0, SEED, SEED);
        _blockFeeSync();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vault.redeem(100 ether, 0, 0, address(0), address(this));
        assertEq(vault.totalSupply(), 2 * SEED);
        assertEq(vault.balanceOf(address(this)), 2 * SEED - LOCKED);
        assertEq(low.snapshot().amount0, SEED);
        assertEq(low.snapshot().amount1, SEED);
    }

    function test_redeemRejectsZeroReceiverWhileIdle() public {
        _bootstrap(1000, SEED, SEED);
        // Model tokens that accept zero-address transfers; the vault must reject independently.
        vm.mockCall(address(token0), abi.encodeCall(IERC20.transfer, (address(0), 50 ether)), abi.encode(true));
        vm.mockCall(address(token1), abi.encodeCall(IERC20.transfer, (address(0), 50 ether)), abi.encode(true));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vault.redeem(100 ether, 0, 0, address(0), address(this));
        assertEq(vault.totalSupply(), 2 * SEED);
        _assertFullSeedAssets();
    }

    function test_redeemRejectsZeroOwnerWithSpecificError() public {
        _bootstrap(0, SEED, SEED);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vault.redeem(100 ether, 0, 0, address(this), address(0));
    }

    function test_redeemRejectsZeroSharesBeforeFeeSync() public {
        _bootstrap(0, SEED, SEED);
        _blockFeeSync();
        vm.expectRevert(IAdaptiveLPVault.ZeroAmount.selector);
        vault.redeem(0, 0, 0, address(this), address(this));
    }

    function test_swapRejectsZeroInputBeforeOracleRead() public {
        PositionPlan memory plan = _prepareSwap();
        vm.mockCallRevert(
            address(oracle),
            abi.encodeCall(ICanonicalV3Oracle.snapshot, ()),
            abi.encodeWithSelector(UnexpectedExternalCall.selector)
        );
        vm.expectRevert(IAdaptiveLPVault.ZeroAmount.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 0, 0, uint32(block.timestamp));
        _assertSwapRolledBack();
    }

    function _blockDepositGate() private {
        vm.mockCallRevert(
            address(control),
            abi.encodeCall(IVaultControl.requireDepositEnabled, (vault.activeVenue())),
            abi.encodeWithSelector(UnexpectedExternalCall.selector)
        );
    }

    function _blockFeeSync() private {
        vm.mockCallRevert(
            address(low),
            abi.encodeCall(IPositionAdapter.syncFees, ()),
            abi.encodeWithSelector(UnexpectedExternalCall.selector)
        );
    }

    function test_depositRejectsV3SingleSidedPrincipalWithSpecificError() public {
        _bootstrap(0, SEED, SEED);
        _mockPrincipal(address(low), 0, SEED);
        vm.expectRevert(IAdaptiveLPVault.ActivePositionSingleSided.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
    }

    function test_depositRejectsV3ZeroPrincipalWithSpecificError() public {
        _bootstrap(0, SEED, SEED);
        _mockPrincipal(address(low), 0, 0);
        vm.expectRevert(IAdaptiveLPVault.InvalidPositionPrincipal.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
    }

    function test_depositRejectsV2ZeroPrincipalWithSpecificError() public {
        _bootstrap(350, SEED, SEED);
        _mockPrincipal(address(v2), 0, 0);
        vm.expectRevert(IAdaptiveLPVault.InvalidPositionPrincipal.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
    }

    function test_depositRejectsV2ZeroToken0PrincipalWithSpecificError() public {
        _bootstrap(350, SEED, SEED);
        _mockPrincipal(address(v2), 0, SEED);
        vm.expectRevert(IAdaptiveLPVault.InvalidPositionPrincipal.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
    }

    function test_depositRejectsV2ZeroToken1PrincipalWithSpecificError() public {
        _bootstrap(350, SEED, SEED);
        _mockPrincipal(address(v2), SEED, 0);
        vm.expectRevert(IAdaptiveLPVault.InvalidPositionPrincipal.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
    }

    function test_depositStillRejectsV2ZeroActualAmountWithZeroAmount() public {
        _bootstrap(350, SEED, SEED);
        vm.expectRevert(IAdaptiveLPVault.ZeroAmount.selector);
        vault.deposit(0, 100 ether, 0, address(this));
    }

    function test_depositStillEnforcesPreDepositIdleLimit() public {
        _bootstrap(0, SEED, SEED);
        token0.transfer(address(vault), 100 ether);
        token1.transfer(address(vault), 100 ether);
        vm.expectRevert(IAdaptiveLPVault.IdleLimitExceeded.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
    }

    function test_depositStillRequiresHealthyFinalDeployment() public {
        _bootstrap(0, SEED, SEED);
        vm.mockCall(address(low), abi.encodeWithSelector(IPositionAdapter.deposit.selector), abi.encode(0, 0, 0));
        vm.expectRevert(IAdaptiveLPVault.DeploymentRatioTooLow.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
        _assertFullSeedAssets();
    }

    function test_redeemCombinesAdapterReturnsWithPreWithdrawalIdleShare() public {
        _bootstrap(0, SEED, SEED);
        // Idle assets are distributed separately from the actual position withdrawal.
        token0.transfer(address(vault), 20 ether);
        token1.transfer(address(vault), 40 ether);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));

        // Only the pre-withdrawal Idle snapshot reads vault balances in this stateful adapter fixture.
        vm.expectCall(address(token0), abi.encodeCall(IERC20.balanceOf, (address(vault))), uint64(1));
        vm.expectCall(address(token1), abi.encodeCall(IERC20.balanceOf, (address(vault))), uint64(1));
        (uint256 amount0, uint256 amount1) = vault.redeem(100 ether, 51 ether, 52 ether, address(this), address(this));

        assertEq(amount0, 51 ether);
        assertEq(amount1, 52 ether);
        assertEq(token0.balanceOf(address(this)) - balance0Before, amount0);
        assertEq(token1.balanceOf(address(this)) - balance1Before, amount1);
        assertEq(low.snapshot().amount0, 950 ether);
        assertEq(low.snapshot().amount1, 950 ether);
    }

    function test_redeemStillEnforcesActualMinimumOutputs() public {
        _bootstrap(0, SEED, SEED);
        vm.expectRevert(abi.encodeWithSelector(IAdaptiveLPVault.AssetSlippage.selector, 50 ether, 50 ether));
        vault.redeem(100 ether, 51 ether, 0, address(this), address(this));
        assertEq(low.snapshot().amount0, SEED);
        assertEq(vault.totalSupply(), 2 * SEED);
    }

    function test_plainRebalanceIgnoresIncorrectWithdrawAllReturns() public {
        _installMisreportingFullExitAdapter();
        _bootstrap(0, SEED, SEED);
        PositionPlan memory plan = _plan(150);
        vault.rebalance(plan.planHash, uint32(block.timestamp));
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_HIGH_FEE));
        assertEq(low.snapshot().liquidity, 0);
        _assertFullSeedAssets();
    }

    function test_emergencyExitIgnoresIncorrectWithdrawAllReturns() public {
        _installMisreportingFullExitAdapter();
        _bootstrap(0, SEED, SEED);
        vault.emergencyExitToIdle();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
        assertEq(token0.balanceOf(address(vault)), SEED);
        assertEq(token1.balanceOf(address(vault)), SEED);
        assertEq(low.snapshot().liquidity, 0);
    }

    function test_fullExitStillEnforcesConservation() public {
        MisreportingFullExitAdapter adapter = _installMisreportingFullExitAdapter();
        _bootstrap(0, SEED, SEED);
        adapter.setExitBehavior(9900, false);
        vm.expectRevert(AdaptiveLPVault.AssetConservationViolation.selector);
        vault.emergencyExitToIdle();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_LOW_FEE));
        assertEq(low.snapshot().amount0, SEED);
        _assertFullSeedAssets();
    }

    function test_fullExitStillRequiresPositionCleared() public {
        MisreportingFullExitAdapter adapter = _installMisreportingFullExitAdapter();
        _bootstrap(0, SEED, SEED);
        adapter.setExitBehavior(10_000, true);
        vm.expectRevert(IAdaptiveLPVault.PositionNotCleared.selector);
        vault.emergencyExitToIdle();
        assertEq(low.snapshot().amount0, SEED);
        assertEq(token0.balanceOf(address(low)), SEED);
    }

    function test_swapUsesExecutorOutputWithoutDuplicateVaultOutputReads() public {
        PositionPlan memory plan = _prepareSwap();
        address executor = address(vault.swapExecutor());
        token0.mint(executor, 3 ether);
        token1.mint(executor, 7 ether);
        // Seven accounting/deposit reads, two executor reads and one final asset assertion; no Vault Swap output reads.
        vm.expectCall(address(token1), abi.encodeCall(IERC20.balanceOf, (address(vault))), uint64(10));

        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));

        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
        _assertFullSeedAssets();
        assertEq(token0.balanceOf(executor), 3 ether);
        assertEq(token1.balanceOf(executor), 7 ether);
        assertEq(token0.allowance(executor, address(router)), 0);
    }

    function test_swapStillEnforcesActualMinimumOutput() public {
        PositionPlan memory plan = _prepareSwap();
        _installExecutorStub(_normalSwapBehavior());
        vm.expectRevert(abi.encodeWithSelector(IControlledSwapExecutor.SwapSlippage.selector, 501 ether, 500 ether));
        vault.rebalanceWithSwap(
            plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 501 ether, uint32(block.timestamp)
        );
        _assertSwapRolledBack();
    }

    function test_swapStillEnforcesExactVaultInputDecrease() public {
        PositionPlan memory plan = _prepareSwap();
        SwapExecutorStub.Behavior memory behavior = _normalSwapBehavior();
        behavior.inputSpent = 499 ether;
        behavior.refundInput = true;
        _installExecutorStub(behavior);
        vm.expectRevert(IAdaptiveLPVault.SwapBalanceMismatch.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
        _assertSwapRolledBack();
    }

    function test_swapStillEnforcesExecutorInputBaseline() public {
        PositionPlan memory plan = _prepareSwap();
        SwapExecutorStub.Behavior memory behavior = _normalSwapBehavior();
        behavior.inputSpent = 499 ether;
        _installExecutorStub(behavior);
        vm.expectRevert(IAdaptiveLPVault.SwapBalanceMismatch.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
        _assertSwapRolledBack();
    }

    function test_swapStillEnforcesExecutorOutputBaseline() public {
        PositionPlan memory plan = _prepareSwap();
        SwapExecutorStub.Behavior memory behavior = _normalSwapBehavior();
        behavior.retainOutput = true;
        _installExecutorStub(behavior);
        vm.expectRevert(IAdaptiveLPVault.SwapBalanceMismatch.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
        _assertSwapRolledBack();
    }

    function test_swapStillRequiresRouterAllowanceCleared() public {
        PositionPlan memory plan = _prepareSwap();
        SwapExecutorStub.Behavior memory behavior = _normalSwapBehavior();
        behavior.leaveAllowance = true;
        _installExecutorStub(behavior);
        vm.expectRevert(IAdaptiveLPVault.SwapAllowanceNotCleared.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
        _assertSwapRolledBack();
        assertEq(token0.allowance(address(vault.swapExecutor()), address(router)), 0);
    }

    function _installMisreportingFullExitAdapter() private returns (MisreportingFullExitAdapter adapter) {
        adapter = new MisreportingFullExitAdapter(address(vault), low.pool(), address(token0), address(token1));
        low = adapter;
        control.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(adapter));
    }

    function _mockPrincipal(address adapter, uint256 principal0, uint256 principal1) private {
        PositionSnapshot memory position = IPositionAdapter(adapter).snapshot();
        position.principal0 = principal0;
        position.principal1 = principal1;
        position.claimableFee0 = 0;
        position.claimableFee1 = 0;
        position.amount0 = principal0;
        position.amount1 = principal1;
        vm.mockCall(adapter, abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(position));
    }

    function _prepareSwap() private returns (PositionPlan memory plan) {
        _bootstrap(150, 1500 ether, 500 ether);
        plan = _plan(350);
    }

    function _normalSwapBehavior() private pure returns (SwapExecutorStub.Behavior memory behavior) {
        behavior.outputAmount = 500 ether;
        behavior.inputSpent = 500 ether;
    }

    function _installExecutorStub(SwapExecutorStub.Behavior memory behavior) private {
        SwapExecutorStub executor =
            new SwapExecutorStub(address(vault), address(token0), address(token1), address(router), behavior);
        vm.etch(address(vault.swapExecutor()), address(executor).code);
    }

    function _assertFullSeedAssets() private view {
        (uint256 total0, uint256 total1) = vault.totalAssets();
        assertEq(total0, SEED);
        assertEq(total1, SEED);
    }

    function _assertSwapRolledBack() private view {
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_HIGH_FEE));
        (uint256 total0, uint256 total1) = vault.totalAssets();
        assertEq(total0, 1500 ether);
        assertEq(total1, 500 ether);
        assertEq(token0.balanceOf(address(vault.swapExecutor())), 0);
        assertEq(token1.balanceOf(address(vault.swapExecutor())), 0);
    }
}
