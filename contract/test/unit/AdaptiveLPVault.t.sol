// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AdaptiveLPVaultFixture} from "./helpers/AdaptiveLPVaultFixture.sol";
import {FeeDonationV3Adapter} from "./mocks/VaultFeeMocks.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";
import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {IAdapterRegistry} from "../../src/interfaces/IAdapterRegistry.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";

contract AdaptiveLPVaultTest is AdaptiveLPVaultFixture {
    function test_bootstrapOnlyManagerAndOnlyOnce() public {
        address outsider = makeAddr("outsider");
        bytes32 managerRole = control.MANAGER_ROLE();
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, managerRole)
        );
        vault.bootstrap(SEED, SEED, outsider);
        control.revokeRole(managerRole, address(this));
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), managerRole)
        );
        vault.bootstrap(SEED, SEED, address(this));
        control.grantRole(managerRole, address(this));
        _bootstrap(0, SEED, SEED);
        assertTrue(vault.initialized());
        assertEq(vault.totalSupply(), 2 * SEED);
        assertEq(vault.balanceOf(address(vault)), LOCKED);
        assertEq(vault.balanceOf(address(this)), 2 * SEED - LOCKED);
        assertEq(vault.planVersion(), 1);
        assertEq(vault.lastPositionChangeAt(), vm.getBlockTimestamp());
        vm.expectRevert(IAdapterRegistry.AlreadyInitialized.selector);
        vault.bootstrap(SEED, SEED, outsider);
    }

    function testFuzz_bootstrapCommitsEachInitialRegime(uint8 regime) public {
        regime = uint8(bound(regime, 0, 3));
        uint256[4] memory deviations = [uint256(0), 150, 350, 1000];
        VenueType[4] memory venues =
            [VenueType.UNISWAP_V3_LOW_FEE, VenueType.UNISWAP_V3_HIGH_FEE, VenueType.UNISWAP_V2, VenueType.IDLE];
        _bootstrap(deviations[regime], SEED, SEED);
        PositionPlan memory plan = vault.lastExecutedPlan();
        assertEq(uint8(vault.activeVenue()), uint8(venues[regime]));
        assertEq(uint8(plan.targetVenue), uint8(venues[regime]));
        assertEq(uint8(plan.marketRegime), regime);
        assertEq(plan.version, 1);
        assertNotEq(plan.planHash, bytes32(0));
        assertEq(vault.lastPositionChangeAt(), vm.getBlockTimestamp());
        assertEq(vault.totalSupply(), 2 * SEED);
        (uint256 total0, uint256 total1) = vault.totalAssets();
        assertEq(total0, SEED);
        assertEq(total1, SEED);
    }

    function test_bootstrapSwapRequiredRollsBackAllState() public {
        oracle.setDeviation(350);
        uint256 before0 = token0.balanceOf(address(this));
        uint256 before1 = token1.balanceOf(address(this));
        vm.expectRevert(IAdaptiveLPVault.SwapRequired.selector);
        vault.bootstrap(1500 ether, 500 ether, address(this));
        assertFalse(vault.initialized());
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.planVersion(), 0);
        assertEq(vault.lastPositionChangeAt(), 0);
        assertEq(token0.balanceOf(address(this)), before0);
        assertEq(token1.balanceOf(address(this)), before1);
        assertEq(pair.balanceOf(address(v2)), 0);
    }

    function test_depositUsesPrincipalRatioForBothLimitingSides() public {
        _bootstrap(0, 1500 ether, 500 ether);
        // Direct donation changes NAV, but must not change the 3:1 principal ratio.
        token1.mint(address(vault), 1 ether);
        uint256[3] memory max0 = [uint256(90 ether + 1), 120 ether, 90 ether];
        uint256[3] memory max1 = [uint256(40 ether), 30 ether + 1, 30 ether];
        for (uint256 i; i < 3; ++i) {
            uint256 state = vm.snapshotState();
            uint256 expected0;
            uint256 expected1;
            if (i == 0) {
                expected0 = max0[i];
                expected1 = max0[i] / 3;
            } else {
                expected0 = max1[i] * 3;
                expected1 = max1[i];
            }
            uint256 before0 = token0.balanceOf(address(this));
            uint256 before1 = token1.balanceOf(address(this));
            (uint256 used0, uint256 used1,) = vault.deposit(max0[i], max1[i], 0, address(this));
            assertEq(used0, expected0);
            assertEq(used1, expected1);
            assertEq(before0 - token0.balanceOf(address(this)), used0);
            assertEq(before1 - token1.balanceOf(address(this)), used1);
            assertTrue(vm.revertToStateAndDelete(state));
        }
    }

    function test_depositMinSharesAndSeparateReceiver() public {
        _bootstrap(0, SEED, SEED);
        address receiver = makeAddr("share receiver");
        bytes32 history = _history();
        uint256 before0 = token0.balanceOf(address(this));
        uint256 before1 = token1.balanceOf(address(this));
        vm.expectRevert(abi.encodeWithSelector(IAdaptiveLPVault.SharesSlippage.selector, 200 ether, 200 ether + 1));
        vault.deposit(100 ether, 100 ether, 200 ether + 1, receiver);
        assertEq(vault.totalSupply(), 2 * SEED);
        assertEq(token0.balanceOf(address(this)), before0);
        assertEq(token1.balanceOf(address(this)), before1);
        assertEq(vault.balanceOf(receiver), 0);
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.Deposit(address(this), receiver, 100 ether, 100 ether, 200 ether);
        (uint256 used0, uint256 used1, uint256 shares) = vault.deposit(100 ether, 100 ether, 200 ether, receiver);
        assertEq(used0, 100 ether);
        assertEq(used1, 100 ether);
        assertEq(shares, 200 ether);
        assertEq(vault.balanceOf(receiver), shares);
        assertEq(vault.balanceOf(address(this)), 2 * SEED - LOCKED);
        assertEq(_history(), history);
    }

    function test_redeemOwnerDoesNotSpendSelfAllowance() public {
        _bootstrap(0, SEED, SEED);
        vault.approve(address(this), 7);
        vault.redeem(100 ether, 0, 0, address(this), address(this));
        assertEq(vault.allowance(address(this), address(this)), 7);
    }

    function test_redeemFiniteAllowanceAndDistinctParties() public {
        _bootstrap(0, SEED, SEED);
        address spender = makeAddr("spender");
        address receiver = makeAddr("asset receiver");
        vault.approve(spender, 150 ether);
        bytes32 history = _history();
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAdaptiveLPVault.Redeem(spender, receiver, address(this), 100 ether, 50 ether, 50 ether);
        vm.prank(spender);
        (uint256 amount0, uint256 amount1) = vault.redeem(100 ether, 50 ether, 50 ether, receiver, address(this));
        assertEq(amount0, 50 ether);
        assertEq(amount1, 50 ether);
        assertEq(token0.balanceOf(receiver), amount0);
        assertEq(token1.balanceOf(receiver), amount1);
        assertEq(vault.allowance(address(this), spender), 50 ether);
        assertEq(vault.balanceOf(address(this)), 2 * SEED - LOCKED - 100 ether);
        assertEq(vault.totalSupply(), 2 * SEED - 100 ether);
        assertEq(_history(), history);
    }

    function test_redeemInfiniteAllowanceIsNotDecremented() public {
        _bootstrap(0, SEED, SEED);
        address spender = makeAddr("spender");
        vault.approve(spender, type(uint256).max);
        vm.prank(spender);
        vault.redeem(100 ether, 0, 0, spender, address(this));
        assertEq(vault.allowance(address(this), spender), type(uint256).max);
        assertEq(token0.balanceOf(spender), 50 ether);
        assertEq(token1.balanceOf(spender), 50 ether);
    }

    function test_redeemRejectsInsufficientAllowanceOrBalanceBeforeFees() public {
        _bootstrap(0, SEED, SEED);
        address spender = makeAddr("spender");
        vm.mockCallRevert(address(low), abi.encodeCall(IPositionAdapter.syncFees, ()), "must not synchronize");
        vault.approve(spender, 99 ether);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 99 ether, 100 ether)
        );
        vault.redeem(100 ether, 0, 0, spender, address(this));
        uint256 balance = vault.balanceOf(address(this));
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), balance, balance + 1)
        );
        vault.redeem(balance + 1, 0, 0, spender, address(this));
        assertEq(vault.allowance(address(this), spender), 99 ether);
        assertEq(vault.totalSupply(), 2 * SEED);
        assertEq(low.snapshot().liquidity, 2 * SEED);
    }

    function test_redeemSlippageRestoresAllowanceSharesAndPosition() public {
        _bootstrap(0, SEED, SEED);
        address spender = makeAddr("spender");
        vault.approve(spender, 100 ether);
        for (uint256 side; side < 2; ++side) {
            vm.prank(spender);
            vm.expectRevert(abi.encodeWithSelector(IAdaptiveLPVault.AssetSlippage.selector, 50 ether, 50 ether));
            vault.redeem(
                100 ether, 50 ether + (side == 0 ? 1 : 0), 50 ether + (side == 1 ? 1 : 0), spender, address(this)
            );
            assertEq(vault.allowance(address(this), spender), 100 ether);
            assertEq(vault.totalSupply(), 2 * SEED);
            assertEq(vault.balanceOf(address(this)), 2 * SEED - LOCKED);
            assertEq(low.snapshot().principal0, SEED);
            assertEq(low.snapshot().principal1, SEED);
            assertEq(token0.balanceOf(spender), 0);
            assertEq(token1.balanceOf(spender), 0);
        }
    }

    function test_idleRedeemNeverCallsAdaptersOrOracle() public {
        _bootstrap(1000, SEED, SEED);
        vm.mockCallRevert(address(low), bytes(""), "no adapter calls");
        vm.mockCallRevert(address(high), bytes(""), "no adapter calls");
        vm.mockCallRevert(address(v2), bytes(""), "no adapter calls");
        vm.mockCallRevert(address(oracle), bytes(""), "no oracle calls");
        address receiver = makeAddr("idle receiver");
        (uint256 amount0, uint256 amount1) = vault.redeem(100 ether, 50 ether, 50 ether, receiver, address(this));
        assertEq(amount0, 50 ether);
        assertEq(amount1, 50 ether);
        assertEq(token0.balanceOf(receiver), amount0);
        assertEq(token1.balanceOf(receiver), amount1);
        assertEq(vault.totalSupply(), 1900 ether);
    }

    function test_idleRedeemAllowsOneOrBothOutputsToRoundToZero() public {
        _bootstrap(1000, SEED, SEED);
        // Huge share supply versus raw-unit asset inventory, e.g. after external token loss.
        deal(address(token0), address(vault), 0);
        deal(address(token1), address(vault), 2);
        address receiver = makeAddr("tiny receiver");
        (uint256 amount0, uint256 amount1) = vault.redeem(1, 0, 0, receiver, address(this));
        assertEq(amount0, 0);
        assertEq(amount1, 0);
        (amount0, amount1) = vault.redeem(1000 ether, 0, 1, receiver, address(this));
        assertEq(amount0, 0);
        assertEq(amount1, 1);
        assertEq(token1.balanceOf(receiver), 1);
    }

    function testFuzz_allCirculatingSharesRedeemedPreservesLifecycleAndPlan(uint8 venue) public {
        venue = uint8(bound(venue, 0, 2));
        uint256[3] memory deviations = [uint256(0), 350, 1000];
        _bootstrap(deviations[venue], SEED, SEED);
        bytes32 history = _history();
        uint256 shares = vault.balanceOf(address(this));
        vault.redeem(shares, 0, 0, address(this), address(this));
        assertEq(vault.totalSupply(), LOCKED);
        assertEq(vault.balanceOf(address(vault)), LOCKED);
        assertTrue(vault.initialized());
        assertEq(_history(), history);
        (uint256 total0, uint256 total1) = vault.totalAssets();
        assertEq(total0, LOCKED / 2);
        assertEq(total1, LOCKED / 2);
        if (venue != 2) {
            (,, uint256 minted) = vault.deposit(100 ether, 100 ether, 200 ether, address(this));
            assertEq(minted, 200 ether);
        } else {
            // Resume from IDLE via an ordinary permissionless rebalance.
            PositionPlan memory plan = _plan(0);
            vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
            assertEq(uint8(vault.activeVenue()), uint8(VenueType.UNISWAP_V2));
        }
    }

    function test_redeemV2UsesNestedLpRounding() public {
        _bootstrap(350, SEED, SEED);
        token0.mint(address(pair), 1234567);
        token1.mint(address(pair), 7654321);
        pair.sync();
        // shares=3 -> floor(1000e18 * 3 / 2000e18)=1 LP, not 1.5 LP.
        uint256 expected0 = Math.mulDiv(token0.balanceOf(address(pair)), 1, pair.totalSupply());
        uint256 expected1 = Math.mulDiv(token1.balanceOf(address(pair)), 1, pair.totalSupply());
        uint256 lpBefore = pair.balanceOf(address(v2));
        address receiver = makeAddr("nested receiver");
        (uint256 amount0, uint256 amount1) = vault.redeem(3, expected0, expected1, receiver, address(this));
        assertEq(lpBefore - pair.balanceOf(address(v2)), 1);
        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
        assertEq(token0.balanceOf(receiver), amount0);
        assertEq(token1.balanceOf(receiver), amount1);
        assertEq(vault.totalSupply(), 2 * SEED - 3);
    }

    function test_redeemSlippageRestoresSynchronizedFeesAndAllowance() public {
        FeeDonationV3Adapter feeAdapter = new FeeDonationV3Adapter(
            address(vault), low.pool(), address(token0), address(token1), VenueType.UNISWAP_V3_LOW_FEE
        );
        low = feeAdapter;
        control.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(low));
        _bootstrap(0, SEED, SEED);
        token0.mint(address(low), 10 ether);
        token1.mint(address(low), 10 ether);
        feeAdapter.accrueFees(10 ether, 10 ether);
        address spender = makeAddr("fee spender");
        vault.approve(spender, 100 ether);
        bytes32 positionBefore = keccak256(abi.encode(low.snapshot()));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IAdaptiveLPVault.AssetSlippage.selector, 50.5 ether, 50.5 ether));
        vault.redeem(100 ether, 50.5 ether + 1, 0, spender, address(this));
        assertEq(keccak256(abi.encode(low.snapshot())), positionBefore);
        assertEq(token0.balanceOf(address(low)), 1010 ether);
        assertEq(token1.balanceOf(address(low)), 1010 ether);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);
        assertEq(vault.allowance(address(this), spender), 100 ether);
        assertEq(vault.totalSupply(), 2000 ether);
        vm.prank(spender);
        vault.redeem(100 ether, 50.5 ether, 50.5 ether, spender, address(this));
        assertEq(token0.balanceOf(spender), 50.5 ether);
        assertEq(token1.balanceOf(spender), 50.5 ether);
        assertEq(low.snapshot().claimableFee0, 0);
        assertEq(low.snapshot().claimableFee1, 0);
    }

    function test_vaultBlocksAllAssetEntrypointReentryDuringBootstrap() public {
        bytes[6] memory calls = _assetEntrypointCalls();
        oracle.setDeviation(350);
        for (uint256 i; i < calls.length; ++i) {
            uint256 state = vm.snapshotState();
            pair.armReentry(address(vault), calls[i]);
            vault.bootstrap(SEED, SEED, address(this));
            _assertCallbackBlocked();
            assertEq(vault.totalSupply(), 2 * SEED);
            assertEq(vault.planVersion(), 1);
            assertTrue(vm.revertToStateAndDelete(state));
        }
    }

    function test_vaultBlocksAllAssetEntrypointReentryDuringDeposit() public {
        _bootstrap(350, SEED, SEED);
        bytes32 history = _history();
        bytes[6] memory calls = _assetEntrypointCalls();
        for (uint256 i; i < calls.length; ++i) {
            pair.armReentry(address(vault), calls[i]);
            (,, uint256 shares) = vault.deposit(100 ether, 100 ether, 200 ether, address(this));
            _assertCallbackBlocked();
            assertEq(shares, 200 ether);
            assertEq(_history(), history);
        }
        assertEq(vault.totalSupply(), 3200 ether);
    }

    function _assetEntrypointCalls() private view returns (bytes[6] memory calls) {
        calls[0] = abi.encodeCall(vault.bootstrap, (1, 1, address(this)));
        calls[1] = abi.encodeCall(vault.deposit, (1, 1, 0, address(this)));
        calls[2] = abi.encodeCall(vault.redeem, (1, 0, 0, address(this), address(this)));
        calls[3] = abi.encodeCall(vault.rebalance, (bytes32(0), uint32(vm.getBlockTimestamp())));
        calls[4] = abi.encodeCall(
            vault.rebalanceWithSwap, (bytes32(0), SwapDirection.ZERO_FOR_ONE, 1, 0, uint32(vm.getBlockTimestamp()))
        );
        calls[5] = abi.encodeCall(vault.emergencyExitToIdle, ());
    }

    function _assertCallbackBlocked() private view {
        assertFalse(pair.lastReentrySucceeded());
        assertEq(pair.lastReentryRevertSelector(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
    }

    function _history() private view returns (bytes32) {
        return keccak256(
            abi.encode(vault.activeVenue(), vault.planVersion(), vault.lastPositionChangeAt(), vault.lastExecutedPlan())
        );
    }
}
