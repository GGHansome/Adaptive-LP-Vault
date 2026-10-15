// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AdaptiveLPVaultDonationsTest} from "./AdaptiveLPVaultDonations.t.sol";
import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";

contract AdaptiveLPVaultErrorsTest is AdaptiveLPVaultDonationsTest {
    using stdStorage for StdStorage;

    function test_emergencyExitReportsPlanVersionOverflowAndRollsBack() public {
        _bootstrap(0, SEED, SEED);
        stdstore.target(address(vault)).sig("planVersion()").enable_packed_slots().checked_write(type(uint64).max);
        vm.expectRevert(IAdaptiveLPVault.PlanVersionOverflow.selector);
        vault.emergencyExitToIdle();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V3_LOW_FEE));
        assertEq(low.snapshot().amount0, SEED);
        assertEq(vault.planVersion(), type(uint64).max);
    }

    function test_bootstrapDistinguishesLockedSharesFromMinimumNav() public {
        oracle.setDeviation(1000);
        vm.expectRevert(abi.encodeWithSelector(IAdaptiveLPVault.InitialSharesTooLow.selector, 2, LOCKED));
        vault.bootstrap(1, 1, address(this));
        assertFalse(vault.initialized());
    }

    function test_bootstrapReportsTimestampOverflow() public {
        oracle.setDeviation(1000);
        vm.warp(uint256(type(uint32).max) + 1);
        vm.expectRevert(IAdaptiveLPVault.TimestampOverflow.selector);
        vault.bootstrap(SEED, SEED, address(this));
        assertFalse(vault.initialized());
        assertEq(vault.totalSupply(), 0);
    }

    function test_bootstrapReportsMissingActivePosition() public {
        oracle.setDeviation(350);
        PositionSnapshot memory empty;
        _snapshot(address(v2), empty);
        vm.expectRevert(IAdaptiveLPVault.ActivePositionMissing.selector);
        vault.bootstrap(SEED, SEED, address(this));
    }

    function test_depositReportsUncollectedFees() public {
        _bootstrap(0, SEED, SEED);
        PositionSnapshot memory position = low.snapshot();
        position.claimableFee0 = 1;
        _snapshot(address(low), position);
        vm.expectRevert(IAdaptiveLPVault.FeesNotCleared.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
    }

    function test_depositReportsMissingV3PositionId() public {
        _bootstrap(0, SEED, SEED);
        PositionSnapshot memory position = low.snapshot();
        position.positionId = 0;
        _snapshot(address(low), position);
        vm.expectRevert(IAdaptiveLPVault.InvalidPositionId.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
        assertEq(vault.totalSupply(), 2 * SEED);
    }

    function test_depositReportsRangeMismatchRatherThanInvalidRange() public {
        _bootstrap(0, SEED, SEED);
        PositionSnapshot memory position = low.snapshot();
        position.tickLower -= 10;
        position.tickUpper -= 10;
        _snapshot(address(low), position);
        vm.expectRevert(IAdaptiveLPVault.PositionRangeMismatch.selector);
        vault.deposit(100 ether, 100 ether, 0, address(this));
    }

    function test_depositReportsZeroMintedSharesSeparatelyFromZeroAssets() public {
        _bootstrap(0, SEED, SEED);
        PositionSnapshot memory position = low.snapshot();
        position.principal0 *= 10;
        position.principal1 *= 10;
        position.amount0 = position.principal0;
        position.amount1 = position.principal1;
        _snapshot(address(low), position);
        vm.expectRevert(IAdaptiveLPVault.ZeroShares.selector);
        vault.deposit(1, 1, 0, address(this));
    }

    function test_redeemReportsMissingLiquidityRatherThanUnclearedPosition() public {
        _bootstrap(0, SEED, SEED);
        PositionSnapshot memory position = low.snapshot();
        position.liquidity = 0;
        _snapshot(address(low), position);
        vm.expectRevert(IAdaptiveLPVault.ActivePositionMissing.selector);
        vault.redeem(100 ether, 0, 0, address(this), address(this));
        assertEq(vault.totalSupply(), 2 * SEED);
    }

    function test_bootstrapReportsShortTokenTransfer() public {
        oracle.setDeviation(1000);
        vm.mockCall(
            address(token0),
            abi.encodeCall(IERC20.transferFrom, (address(this), address(vault), SEED)),
            abi.encode(true)
        );
        vm.expectRevert(
            abi.encodeWithSelector(IAdaptiveLPVault.TokenTransferMismatch.selector, address(token0), SEED, 0, 0)
        );
        vault.bootstrap(SEED, SEED, address(this));
    }

    function test_bootstrapReportsBalanceDecreaseWithoutArithmeticPanic() public {
        oracle.setDeviation(1000);
        uint256[] memory balances = new uint256[](2);
        balances[0] = 10;
        balances[1] = 9;
        _mockVaultBalances(address(token0), balances);
        vm.expectRevert(
            abi.encodeWithSelector(IAdaptiveLPVault.TokenTransferMismatch.selector, address(token0), SEED, 10, 9)
        );
        vault.bootstrap(SEED, SEED, address(this));
    }

    function test_swapReportsZeroOracleOutput() public {
        _bootstrap(150, 1500 ether, 500 ether);
        PositionPlan memory plan = _plan(350);
        vm.mockCall(
            address(oracle),
            abi.encodeCall(ICanonicalV3Oracle.quoteToken0InToken1, (500 ether, 17, true)),
            abi.encode(0)
        );
        vm.expectRevert(IAdaptiveLPVault.ZeroSwapOutput.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
    }

    function test_swapReportsInputBalanceIncreaseWithoutArithmeticPanic() public {
        _bootstrap(150, 1500 ether, 500 ether);
        PositionPlan memory plan = _plan(350);
        // Preview and pre-migration snapshots, exited inventory, pre-swap balance, then post-swap balance.
        uint256[] memory balances = new uint256[](5);
        balances[0] = 0;
        balances[1] = 0;
        balances[2] = 1500 ether;
        balances[3] = 1500 ether;
        balances[4] = 1500 ether + 1;
        _mockVaultBalances(address(token0), balances);
        vm.expectRevert(IAdaptiveLPVault.SwapBalanceMismatch.selector);
        vault.rebalanceWithSwap(plan.planHash, SwapDirection.ZERO_FOR_ONE, 500 ether, 0, uint32(block.timestamp));
    }

    function _snapshot(address adapter, PositionSnapshot memory position) private {
        vm.mockCall(adapter, abi.encodeCall(IPositionAdapter.snapshot, ()), abi.encode(position));
    }

    function _mockVaultBalances(address token, uint256[] memory balances) private {
        bytes[] memory responses = new bytes[](balances.length);
        for (uint256 i; i < balances.length; ++i) {
            responses[i] = abi.encode(balances[i]);
        }
        vm.mockCalls(token, abi.encodeCall(IERC20.balanceOf, (address(vault))), responses);
    }
}
