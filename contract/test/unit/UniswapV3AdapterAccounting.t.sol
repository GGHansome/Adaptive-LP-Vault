// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MockV3ERC20, MockV3Factory, MockV3Pool} from "./mocks/UniswapV3Mocks.sol";
import {AccountingV3PositionManager} from "./mocks/AccountingV3PositionManager.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
import {PositionAdapterConfig, PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {MarketRegime, PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";

contract UniswapV3AdapterAccountingTest is Test {
    uint256 private constant Q128 = 1 << 128;
    MockV3ERC20 private token0;
    MockV3ERC20 private token1;
    MockV3Pool private pool;
    AccountingV3PositionManager private manager;
    UniswapV3Adapter private adapter;
    PositionPlan private plan;

    function setUp() public {
        MockV3ERC20 a = new MockV3ERC20("Accounting A", "AA");
        MockV3ERC20 b = new MockV3ERC20("Accounting B", "AB");
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);
        MockV3Factory factory = new MockV3Factory();
        pool = new MockV3Pool(address(factory), address(token0), address(token1), 3000, 60);
        factory.registerPool(address(token0), address(token1), 3000, address(pool));
        manager = new AccountingV3PositionManager(address(factory));
        adapter = new UniswapV3Adapter(
            PositionAdapterConfig(
                address(this), VenueType.UNISWAP_V3_HIGH_FEE, address(pool), address(factory), address(manager)
            )
        );
        token0.mint(address(this), 1000 ether);
        token1.mint(address(this), 1000 ether);
        token0.approve(address(adapter), type(uint256).max);
        token1.approve(address(adapter), type(uint256).max);
        plan = PositionPlan(bytes32(0), VenueType.UNISWAP_V3_HIGH_FEE, MarketRegime.MEDIUM_DEVIATION, -60, 60, 1);
    }

    function test_snapshotSeparatesPrincipalOwedAndFeeGrowth() public {
        adapter.deposit(100 ether, 100 ether, plan);
        manager.setAccounting(1, 10001, Q128, 2 * Q128, 7, 11);
        _growth(4 * Q128, 7 * Q128);
        PositionSnapshot memory p = adapter.snapshot();
        // Frozen small-liquidity vector: floor(10001 * (1 - sqrt(1.0001^-60))) = 29.
        assertEq(p.principal0, 29);
        assertEq(p.principal1, 29);
        assertEq(p.claimableFee0, 7 + 3 * 10001);
        assertEq(p.claimableFee1, 11 + 5 * 10001);
        assertEq(p.amount0, 29 + p.claimableFee0);
        assertEq(p.amount1, 29 + p.claimableFee1);
        assertEq(p.positionId, 1);
        assertEq(p.liquidity, 10001);
    }

    function test_feeGrowthInsideHandlesAllPriceRegionsAndWraparound() public {
        adapter.deposit(100 ether, 100 ether, plan);
        _growth(20 * Q128, 30 * Q128);
        _outside(-60, 7 * Q128, 11 * Q128);
        _outside(60, 2 * Q128, 3 * Q128);
        _assertFeesAtTick(-61, 5 * 10001, 8 * 10001);
        _assertFeesAtTick(-60, 11 * 10001, 16 * 10001);
        _assertFeesAtTick(0, 11 * 10001, 16 * 10001);
        // Change outside records to a valid above-range accounting vector.
        _outside(60, 15 * Q128, 24 * Q128);
        _assertFeesAtTick(60, 8 * 10001, 13 * 10001);
        _assertFeesAtTick(61, 8 * 10001, 13 * 10001);
        _outside(-60, 0, 0);
        _outside(60, 0, 0);
        manager.setAccounting(1, 10001, type(uint256).max - Q128 + 1, type(uint256).max - 2 * Q128 + 1, 0, 0);
        _growth(Q128, Q128);
        _assertFeesAtTick(0, 2 * 10001, 3 * 10001);
        // Subtraction inside the range itself also crosses uint256, not just the last-growth delta.
        manager.setAccounting(1, 10001, 0, 0, 0, 0);
        _outside(-60, type(uint256).max - Q128 + 1, type(uint256).max - 2 * Q128 + 1);
        _assertFeesAtTick(0, 2 * 10001, 3 * 10001);
    }

    function test_syncFeesCollectsActualDeltasAndPreservesPrincipal() public {
        adapter.deposit(100 ether, 100 ether, plan);
        manager.setAccounting(1, 10001, 0, 0, 7, 11);
        _growth(2 * Q128, 3 * Q128);
        PositionSnapshot memory beforePosition = adapter.snapshot();
        uint256 before0 = token0.balanceOf(address(this));
        uint256 before1 = token1.balanceOf(address(this));
        (uint256 fee0, uint256 fee1) = adapter.syncFees();
        assertEq(fee0, 20009);
        assertEq(fee1, 30014);
        assertEq(token0.balanceOf(address(this)) - before0, fee0);
        assertEq(token1.balanceOf(address(this)) - before1, fee1);
        PositionSnapshot memory afterPosition = adapter.snapshot();
        assertEq(afterPosition.claimableFee0, 0);
        assertEq(afterPosition.claimableFee1, 0);
        assertEq(afterPosition.principal0, beforePosition.principal0);
        assertEq(afterPosition.principal1, beforePosition.principal1);
        assertEq(afterPosition.liquidity, beforePosition.liquidity);
        (fee0, fee1) = adapter.syncFees();
        assertEq(fee0, 0);
        assertEq(fee1, 0);
    }

    function test_depositMintAndIncreaseUseActualAmountsAndClearAllowances() public {
        token0.mint(address(adapter), 13);
        token1.mint(address(adapter), 17);
        for (uint256 i; i < 2; ++i) {
            (uint256 desired0, uint256 desired1) = adapter.previewDeposit(100 ether, 80 ether, plan);
            uint256 before0 = token0.balanceOf(address(this));
            uint256 before1 = token1.balanceOf(address(this));
            (uint256 used0, uint256 used1, uint256 liquidity) = adapter.deposit(100 ether, 80 ether, plan);
            assertGt(used0, 0);
            assertGt(used1, 0);
            assertEq(used0, desired0 / 2);
            assertEq(used1, desired1 / 2);
            assertEq(before0 - token0.balanceOf(address(this)), used0);
            assertEq(before1 - token1.balanceOf(address(this)), used1);
            assertEq(token0.balanceOf(address(adapter)), 13);
            assertEq(token1.balanceOf(address(adapter)), 17);
            assertEq(token0.allowance(address(adapter), address(manager)), 0);
            assertEq(token1.allowance(address(adapter), address(manager)), 0);
            assertEq(liquidity, 10001);
            assertEq(adapter.positionId(), 1);
            assertEq(adapter.snapshot().liquidity, (i + 1) * 10001);
        }
        assertEq(manager.nextId(), 2);
    }

    function test_depositRejectsManagerOveruseAndBalanceMismatchAtomically() public {
        for (uint256 side; side < 2; ++side) {
            for (uint256 kind; kind < 2; ++kind) {
                uint256 state = vm.snapshotState();
                (uint256 desired0, uint256 desired1) = adapter.previewDeposit(100 ether, 100 ether, plan);
                uint256 desired = side == 0 ? desired0 : desired1;
                address token = side == 0 ? address(token0) : address(token1);
                uint256 extra = kind == 0 ? desired + 1 : 1;
                manager.configureUsage(5000, side == 0 ? extra : 0, side == 1 ? extra : 0);
                uint256 before0 = token0.balanceOf(address(this));
                uint256 before1 = token1.balanceOf(address(this));
                if (kind == 0) {
                    vm.expectRevert(
                        abi.encodeWithSelector(
                            IPositionAdapter.UsedAmountExceedsDesired.selector, token, desired, desired / 2 + extra
                        )
                    );
                } else {
                    vm.expectRevert(
                        abi.encodeWithSelector(IPositionAdapter.AdapterBalanceMismatch.selector, token, 0, 1)
                    );
                }
                adapter.deposit(100 ether, 100 ether, plan);
                assertEq(adapter.positionId(), 0);
                assertEq(manager.nextId(), 1);
                assertEq(token0.balanceOf(address(this)), before0);
                assertEq(token1.balanceOf(address(this)), before1);
                assertEq(token0.balanceOf(address(manager)), 0);
                assertEq(token1.balanceOf(address(manager)), 0);
                assertEq(token0.allowance(address(adapter), address(manager)), 0);
                assertEq(token1.allowance(address(adapter), address(manager)), 0);
                assertTrue(vm.revertToStateAndDelete(state));
            }
        }
    }

    function test_withdrawUsesFloorLiquidityAndActualTokenDeltas() public {
        adapter.deposit(100 ether, 100 ether, plan);
        uint256 before0 = token0.balanceOf(address(this));
        uint256 before1 = token1.balanceOf(address(this));
        (uint256 amount0, uint256 amount1) = adapter.withdraw(1, 3);
        assertEq(manager.lastRemoved(), 3333);
        assertEq(amount0, 6666);
        assertEq(amount1, 9999);
        assertEq(token0.balanceOf(address(this)) - before0, amount0);
        assertEq(token1.balanceOf(address(this)) - before1, amount1);
        assertEq(adapter.snapshot().liquidity, 6668);
        assertEq(adapter.positionId(), 1);
        assertEq(manager.burnCalls(), 0);
    }

    function test_withdrawHandlesZeroUnitsAndInvalidShareSupply() public {
        _assertZeroWithdrawal(0, 0);
        _assertZeroWithdrawal(1, 1); // No managed NFT.
        vm.expectRevert(IPositionAdapter.InvalidShareSupply.selector);
        adapter.withdraw(1, 0);
        vm.expectRevert(IPositionAdapter.InvalidShareSupply.selector);
        adapter.withdraw(2, 1);
        adapter.deposit(100 ether, 100 ether, plan);
        _assertZeroWithdrawal(0, 0);
        _assertZeroWithdrawal(1, 10002);
        assertEq(manager.decreaseCalls(), 0);
        assertEq(manager.collectCalls(), 0);
        assertEq(adapter.snapshot().liquidity, 10001);
    }

    function test_withdrawAllTransfersAllOwedAndClearsManagedNft() public {
        adapter.deposit(100 ether, 100 ether, plan);
        manager.setAccounting(1, 10001, 0, 0, 7, 11);
        _growth(Q128, 2 * Q128);
        uint256 before0 = token0.balanceOf(address(this));
        uint256 before1 = token1.balanceOf(address(this));
        (uint256 amount0, uint256 amount1) = adapter.withdrawAll();
        assertEq(amount0, 30010);
        assertEq(amount1, 50016);
        assertEq(token0.balanceOf(address(this)) - before0, amount0);
        assertEq(token1.balanceOf(address(this)) - before1, amount1);
        assertEq(manager.lastRemoved(), 10001);
        assertEq(manager.burnCalls(), 1);
        assertEq(manager.ownerOf(1), address(0));
        assertEq(adapter.positionId(), 0);
        assertEq(adapter.snapshot().amount0, 0);
        assertEq(adapter.snapshot().amount1, 0);
        (amount0, amount1) = adapter.withdrawAll();
        assertEq(amount0, 0);
        assertEq(amount1, 0);
        assertEq(manager.collectCalls(), 1);
    }

    function test_withdrawAllCollectsOwedWithZeroLiquidity() public {
        adapter.deposit(100 ether, 100 ether, plan);
        manager.setAccounting(1, 0, 0, 0, 7, 11);
        (uint256 amount0, uint256 amount1) = adapter.withdrawAll();
        assertEq(amount0, 7);
        assertEq(amount1, 11);
        assertEq(manager.decreaseCalls(), 0);
        assertEq(manager.collectCalls(), 1);
        assertEq(manager.burnCalls(), 1);
        assertEq(adapter.positionId(), 0);
    }

    function test_assetMethodsRejectNonVaultCaller() public {
        address outsider = makeAddr("outsider");
        vm.startPrank(outsider);
        vm.expectRevert(IPositionAdapter.NotVaultCaller.selector);
        adapter.deposit(1, 1, plan);
        vm.expectRevert(IPositionAdapter.NotVaultCaller.selector);
        adapter.syncFees();
        vm.expectRevert(IPositionAdapter.NotVaultCaller.selector);
        adapter.withdraw(1, 1);
        vm.expectRevert(IPositionAdapter.NotVaultCaller.selector);
        adapter.withdrawAll();
        adapter.previewDeposit(1 ether, 1 ether, plan);
        vm.stopPrank();
    }

    function test_managerCallbackBlocksCrossFunctionReentry() public {
        manager.setCallback(address(this), abi.encodeCall(this.reenter, ()));
        adapter.deposit(100 ether, 100 ether, plan);
        assertFalse(manager.callbackSucceeded());
        assertEq(
            manager.callbackResult(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
        );
        assertEq(adapter.positionId(), 1);
        assertEq(adapter.snapshot().liquidity, 10001);
        assertEq(token0.allowance(address(adapter), address(manager)), 0);
        adapter.syncFees();
        assertFalse(manager.callbackSucceeded());
        assertEq(
            manager.callbackResult(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
        );
    }

    function reenter() external {
        require(msg.sender == address(manager));
        adapter.withdrawAll(); // Caller is the legitimate bound vault, so this tests the guard, not onlyVault.
    }

    function test_depositRejectsChangedRangeWithActiveLiquidity() public {
        adapter.deposit(100 ether, 100 ether, plan);
        plan.tickUpper = 120;
        vm.expectRevert(IPositionAdapter.ActivePositionExists.selector);
        adapter.deposit(100 ether, 100 ether, plan);
        assertEq(adapter.positionId(), 1);
        assertEq(adapter.snapshot().tickUpper, 60);
        assertEq(manager.nextId(), 2);
    }

    function test_depositReplacesOnlyClearedEmptyNft() public {
        adapter.deposit(100 ether, 100 ether, plan);
        manager.setAccounting(1, 0, 0, 0, 1, 0);
        vm.expectRevert(IPositionAdapter.ActivePositionExists.selector);
        adapter.deposit(100 ether, 100 ether, plan);
        assertEq(manager.burnCalls(), 0);
        manager.setAccounting(1, 0, 0, 0, 0, 0);
        plan.tickUpper = 120;
        adapter.deposit(100 ether, 100 ether, plan);
        assertEq(manager.burnCalls(), 1);
        assertEq(adapter.positionId(), 2);
        assertEq(manager.ownerOf(1), address(0));
        assertEq(adapter.snapshot().tickUpper, 120);
    }

    function test_previewAndDepositRejectWrongVenueAndInvalidRanges() public {
        plan.targetVenue = VenueType.UNISWAP_V2;
        bytes memory wrongVenue = abi.encodeWithSelector(
            IPositionAdapter.InvalidPlanVenue.selector, VenueType.UNISWAP_V3_HIGH_FEE, VenueType.UNISWAP_V2
        );
        vm.expectRevert(wrongVenue);
        adapter.previewDeposit(1, 1, plan);
        vm.expectRevert(wrongVenue);
        adapter.deposit(1, 1, plan);
        plan.targetVenue = VenueType.UNISWAP_V3_HIGH_FEE;
        int24[5] memory lowers = [int24(60), int24(-59), int24(-887280), int24(-60), int24(120)];
        int24[5] memory uppers = [int24(60), int24(60), int24(60), int24(887280), int24(60)];
        for (uint256 i; i < lowers.length; ++i) {
            plan.tickLower = lowers[i];
            plan.tickUpper = uppers[i];
            vm.expectRevert(IPositionAdapter.InvalidTickRange.selector);
            adapter.previewDeposit(1, 1, plan);
            vm.expectRevert(IPositionAdapter.InvalidTickRange.selector);
            adapter.deposit(1, 1, plan);
        }
        assertEq(adapter.positionId(), 0);
        assertEq(manager.nextId(), 1);
    }

    function _growth(uint256 value0, uint256 value1) private {
        manager.setGrowth(value0, value1);
        vm.mockCall(address(pool), abi.encodeWithSignature("feeGrowthGlobal0X128()"), abi.encode(value0));
        vm.mockCall(address(pool), abi.encodeWithSignature("feeGrowthGlobal1X128()"), abi.encode(value1));
    }

    function _outside(int24 tick, uint256 value0, uint256 value1) private {
        vm.mockCall(
            address(pool),
            abi.encodeWithSignature("ticks(int24)", tick),
            abi.encode(uint128(0), int128(0), value0, value1, int56(0), uint160(0), uint32(0), true)
        );
    }

    function _assertFeesAtTick(int24 tick, uint256 fee0, uint256 fee1) private {
        vm.mockCall(
            address(pool),
            abi.encodeWithSignature("slot0()"),
            abi.encode(PriceMath.sqrtRatioAtTick(tick), tick, uint16(0), uint16(0), uint16(0), uint8(0), true)
        );
        PositionSnapshot memory p = adapter.snapshot();
        assertEq(p.claimableFee0, fee0);
        assertEq(p.claimableFee1, fee1);
    }

    function _assertZeroWithdrawal(uint256 shares, uint256 supply) private {
        (uint256 amount0, uint256 amount1) = adapter.withdraw(shares, supply);
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }
}
