// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PositionAdapterConfig, PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {UniswapV2Adapter} from "../../src/adapters/UniswapV2Adapter.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {MarketRegime, PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";

contract MockV2ERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockV2Factory {
    mapping(address tokenA => mapping(address tokenB => address pair)) public getPair;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        MockV2Pair deployed = new MockV2Pair(token0, token1, address(this));
        pair = address(deployed);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
    }

    function registerPair(address tokenA, address tokenB, address pair) external {
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
    }
}

contract MockV2Pair is ERC20 {
    using SafeERC20 for IERC20;

    address private immutable _FACTORY;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;

    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32 private _blockTimestampLast;

    bool private _overrideMintLiquidity;
    uint256 private _reportedMintLiquidity;

    address private _reentryTarget;
    bytes private _reentryData;
    bool public lastReentrySucceeded;
    bytes4 public lastReentryRevertSelector;

    constructor(address token0_, address token1_, address factory_) ERC20("Mock V2 LP", "MV2LP") {
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _FACTORY = factory_;
    }

    function factory() external view returns (address) {
        return _FACTORY;
    }

    function token0() external view returns (address) {
        return _TOKEN0;
    }

    function token1() external view returns (address) {
        return _TOKEN1;
    }

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    function mint(address to) external returns (uint256 liquidity) {
        _attemptReentry();

        uint256 balance0 = IERC20(_TOKEN0).balanceOf(address(this));
        uint256 balance1 = IERC20(_TOKEN1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;
        uint256 supply = totalSupply();

        if (supply == 0) {
            liquidity = Math.sqrt(amount0 * amount1);
        } else {
            liquidity = Math.min(Math.mulDiv(amount0, supply, _reserve0), Math.mulDiv(amount1, supply, _reserve1));
        }
        require(liquidity != 0, "INSUFFICIENT_LIQUIDITY_MINTED");

        _mint(to, liquidity);
        _updateReserves(balance0, balance1);
        if (_overrideMintLiquidity) liquidity = _reportedMintLiquidity;
    }

    function setReportedMintLiquidity(uint256 liquidity) external {
        _overrideMintLiquidity = true;
        _reportedMintLiquidity = liquidity;
    }

    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        uint256 liquidity = balanceOf(address(this));
        uint256 supply = totalSupply();
        uint256 balance0 = IERC20(_TOKEN0).balanceOf(address(this));
        uint256 balance1 = IERC20(_TOKEN1).balanceOf(address(this));

        amount0 = Math.mulDiv(liquidity, balance0, supply);
        amount1 = Math.mulDiv(liquidity, balance1, supply);
        require(amount0 != 0 && amount1 != 0, "INSUFFICIENT_LIQUIDITY_BURNED");

        _burn(address(this), liquidity);
        IERC20(_TOKEN0).safeTransfer(to, amount0);
        IERC20(_TOKEN1).safeTransfer(to, amount1);
        _updateReserves(IERC20(_TOKEN0).balanceOf(address(this)), IERC20(_TOKEN1).balanceOf(address(this)));
    }

    function armReentry(address target, bytes calldata data) external {
        _reentryTarget = target;
        _reentryData = data;
    }

    function sync() external {
        _updateReserves(IERC20(_TOKEN0).balanceOf(address(this)), IERC20(_TOKEN1).balanceOf(address(this)));
    }

    function _attemptReentry() internal {
        address target = _reentryTarget;
        if (target == address(0)) return;

        bytes memory data = _reentryData;
        delete _reentryTarget;
        delete _reentryData;

        (bool success, bytes memory returnData) = target.call(data);
        lastReentrySucceeded = success;
        if (!success && returnData.length >= 4) {
            bytes4 revertSelector;
            assembly ("memory-safe") {
                revertSelector := mload(add(returnData, 0x20))
            }
            lastReentryRevertSelector = revertSelector;
        }
    }

    function _updateReserves(uint256 balance0, uint256 balance1) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "RESERVE_OVERFLOW");
        // forge-lint: disable-next-line(unsafe-typecast)
        _reserve0 = uint112(balance0);
        // forge-lint: disable-next-line(unsafe-typecast)
        _reserve1 = uint112(balance1);
        _blockTimestampLast = uint32(block.timestamp);
    }
}

contract UniswapV2AdapterTest is Test {
    uint256 private constant INITIAL_RESERVE0 = 1_000 ether;
    uint256 private constant INITIAL_RESERVE1 = 2_000 ether;

    MockV2ERC20 private tokenA;
    MockV2ERC20 private tokenB;
    MockV2ERC20 private token0;
    MockV2ERC20 private token1;
    MockV2Factory private factory;
    MockV2Pair private pair;
    UniswapV2Adapter private adapter;
    PositionPlan private plan;

    function setUp() external {
        tokenA = new MockV2ERC20("Token A", "TKA");
        tokenB = new MockV2ERC20("Token B", "TKB");
        (token0, token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        factory = new MockV2Factory();
        pair = MockV2Pair(factory.createPair(address(token0), address(token1)));

        token0.mint(address(this), 10_000 ether);
        token1.mint(address(this), 20_000 ether);
        assertTrue(token0.transfer(address(pair), INITIAL_RESERVE0));
        assertTrue(token1.transfer(address(pair), INITIAL_RESERVE1));
        pair.mint(address(0xBEEF));

        adapter = _deployAdapter(address(this), address(pair));
        token0.approve(address(adapter), type(uint256).max);
        token1.approve(address(adapter), type(uint256).max);

        plan = PositionPlan({
            planHash: bytes32(0),
            targetVenue: VenueType.UNISWAP_V2,
            marketRegime: MarketRegime.LOW_DEVIATION,
            tickLower: 0,
            tickUpper: 0,
            version: 1
        });
    }

    function test_constructorStoresAndExposesValidatedBindings() external view {
        assertEq(adapter.vault(), address(this));
        assertEq(uint8(adapter.venue()), uint8(VenueType.UNISWAP_V2));
        assertEq(adapter.pool(), address(pair));
        assertEq(adapter.token0(), address(token0));
        assertEq(adapter.token1(), address(token1));
        assertEq(adapter.feeTier(), 0);
        assertEq(adapter.tickSpacing(), 0);
    }

    function test_constructorRejectsWrongAdapterKind() external {
        PositionAdapterConfig memory config = PositionAdapterConfig({
            vault: address(this),
            venue: VenueType.UNISWAP_V3_LOW_FEE,
            pool: address(pair),
            factory: address(factory),
            positionManager: address(1)
        });

        vm.expectRevert(IPositionAdapter.InvalidAdapterConfiguration.selector);
        new UniswapV2Adapter(config);
    }

    function test_constructorRejectsReversedTokenOrder() external {
        MockV2Pair reversedPair = new MockV2Pair(address(token1), address(token0), address(factory));
        factory.registerPair(address(token0), address(token1), address(reversedPair));

        vm.expectRevert(IPositionAdapter.InvalidTokenOrder.selector);
        _deployAdapter(address(this), address(reversedPair));
    }

    function test_constructorRejectsPairNotRegisteredByFactory() external {
        MockV2Pair unregisteredPair = new MockV2Pair(address(token0), address(token1), address(factory));

        vm.expectRevert(IPositionAdapter.InvalidPoolBinding.selector);
        _deployAdapter(address(this), address(unregisteredPair));
    }

    function test_constructorRejectsSelfCertifiedPairFromUnexpectedFactory() external {
        MockV2Factory unexpectedFactory = new MockV2Factory();
        address unexpectedPair = unexpectedFactory.createPair(address(token0), address(token1));

        vm.expectRevert(IPositionAdapter.InvalidPoolBinding.selector);
        _deployAdapter(address(this), unexpectedPair);
    }

    function test_constructorRejectsExpectedFactoryWithoutCode() external {
        vm.expectRevert(IPositionAdapter.InvalidAdapterConfiguration.selector);
        _deployAdapterWithFactory(address(this), address(pair), address(0xBEEF));
    }

    function test_snapshotIsCanonicalEmptySnapshotWithoutLpTokens() external view {
        PositionSnapshot memory position = adapter.snapshot();

        assertEq(uint8(position.venue), uint8(VenueType.UNISWAP_V2));
        assertEq(position.adapter, address(adapter));
        assertEq(position.principal0, 0);
        assertEq(position.principal1, 0);
        assertEq(position.claimableFee0, 0);
        assertEq(position.claimableFee1, 0);
        assertEq(position.amount0, 0);
        assertEq(position.amount1, 0);
        assertEq(position.liquidity, 0);
        assertEq(position.positionId, 0);
        assertEq(position.tickLower, 0);
        assertEq(position.tickUpper, 0);
    }

    function test_previewRejectsPlanForAnotherVenue() external {
        PositionPlan memory invalidPlan = plan;
        invalidPlan.targetVenue = VenueType.UNISWAP_V3_LOW_FEE;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionAdapter.InvalidPlanVenue.selector, VenueType.UNISWAP_V2, VenueType.UNISWAP_V3_LOW_FEE
            )
        );
        adapter.previewDeposit(100 ether, 200 ether, invalidPlan);
    }

    function test_depositRejectsPlanForAnotherVenue() external {
        PositionPlan memory invalidPlan = plan;
        invalidPlan.targetVenue = VenueType.UNISWAP_V3_HIGH_FEE;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionAdapter.InvalidPlanVenue.selector, VenueType.UNISWAP_V2, VenueType.UNISWAP_V3_HIGH_FEE
            )
        );
        adapter.deposit(100 ether, 200 ether, invalidPlan);
    }

    function test_previewUsesToken1AsTheLimitingSide() external view {
        (uint256 used0, uint256 used1) = adapter.previewDeposit(100 ether, 50 ether, plan);

        assertEq(used0, 25 ether);
        assertEq(used1, 50 ether);
    }

    function testFuzz_previewNeverExceedsEitherMaximum(uint256 amount0Max, uint256 amount1Max) external view {
        amount0Max = bound(amount0Max, 0, type(uint224).max);
        amount1Max = bound(amount1Max, 0, type(uint224).max);

        (uint256 used0, uint256 used1) = adapter.previewDeposit(amount0Max, amount1Max, plan);

        assertLe(used0, amount0Max);
        assertLe(used1, amount1Max);
    }

    function test_previewAndDepositUseOnlyTheReserveRatio() external {
        (uint256 preview0, uint256 preview1) = adapter.previewDeposit(100 ether, 300 ether, plan);
        assertEq(preview0, 100 ether);
        assertEq(preview1, 200 ether);

        uint256 vault0Before = token0.balanceOf(address(this));
        uint256 vault1Before = token1.balanceOf(address(this));
        (uint256 used0, uint256 used1, uint256 liquidity) = adapter.deposit(100 ether, 300 ether, plan);

        assertEq(used0, preview0);
        assertEq(used1, preview1);
        assertGt(liquidity, 0);
        assertEq(vault0Before - token0.balanceOf(address(this)), 100 ether);
        assertEq(vault1Before - token1.balanceOf(address(this)), 200 ether);
        assertGt(pair.balanceOf(address(adapter)), 0);
    }

    function test_depositMeasuresLpIncreaseWithExistingPositionAndDonation() external {
        adapter.deposit(100 ether, 200 ether, plan);
        vm.prank(address(0xBEEF));
        assertTrue(pair.transfer(address(adapter), 50 ether));
        uint256 lpBefore = pair.balanceOf(address(adapter));

        (uint256 used0, uint256 used1, uint256 liquidity) = adapter.deposit(25 ether, 50 ether, plan);

        assertEq(used0, 25 ether);
        assertEq(used1, 50 ether);
        assertGt(liquidity, 0);
        assertEq(pair.balanceOf(address(adapter)), lpBefore + liquidity);
    }

    function testFuzz_depositRejectsIncorrectMintReturnAndRollsBack(bool overreported) external {
        adapter.deposit(100 ether, 200 ether, plan);
        vm.prank(address(0xBEEF));
        assertTrue(pair.transfer(address(adapter), 50 ether));
        uint256 lpBefore = pair.balanceOf(address(adapter));
        uint256 supplyBefore = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 minted =
            Math.min(Math.mulDiv(100 ether, supplyBefore, reserve0), Math.mulDiv(200 ether, supplyBefore, reserve1));
        uint256 reported = overreported ? minted + 1 : minted - 1;
        pair.setReportedMintLiquidity(reported);
        uint256 vault0Before = token0.balanceOf(address(this));
        uint256 vault1Before = token1.balanceOf(address(this));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionAdapter.AdapterBalanceMismatch.selector, address(pair), lpBefore + reported, lpBefore + minted
            )
        );
        adapter.deposit(100 ether, 200 ether, plan);

        assertEq(pair.balanceOf(address(adapter)), lpBefore);
        assertEq(pair.totalSupply(), supplyBefore);
        assertEq(token0.balanceOf(address(this)), vault0Before);
        assertEq(token1.balanceOf(address(this)), vault1Before);
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();
        assertEq(reserve0After, reserve0);
        assertEq(reserve1After, reserve1);
        assertEq(token0.balanceOf(address(pair)), reserve0);
        assertEq(token1.balanceOf(address(pair)), reserve1);
    }

    function test_depositRejectsMintReturnWithoutActualLpIncrease() external {
        vm.prank(address(0xBEEF));
        assertTrue(pair.transfer(address(adapter), 50 ether));
        vm.mockCall(address(pair), abi.encodeWithSignature("mint(address)", address(adapter)), abi.encode(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionAdapter.AdapterBalanceMismatch.selector, address(pair), 50 ether + 1, 50 ether
            )
        );
        adapter.deposit(100 ether, 200 ether, plan);

        assertEq(pair.balanceOf(address(adapter)), 50 ether);
        assertEq(token0.balanceOf(address(pair)), INITIAL_RESERVE0);
        assertEq(token1.balanceOf(address(pair)), INITIAL_RESERVE1);
    }

    function test_depositRejectsLpBalanceDecreaseWithAdapterError() external {
        bytes[] memory balances = new bytes[](2);
        balances[0] = abi.encode(50 ether);
        balances[1] = abi.encode(49 ether);
        vm.mockCalls(address(pair), abi.encodeCall(IERC20.balanceOf, (address(adapter))), balances);
        vm.mockCall(address(pair), abi.encodeWithSignature("mint(address)", address(adapter)), abi.encode(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionAdapter.AdapterBalanceMismatch.selector, address(pair), 50 ether + 1, 49 ether
            )
        );
        adapter.deposit(100 ether, 200 ether, plan);
    }

    function test_depositBlocksCrossFunctionReentrancy() external {
        pair.armReentry(address(this), abi.encodeCall(this.reenterWithdraw, ()));

        (,, uint256 liquidity) = adapter.deposit(100 ether, 200 ether, plan);

        assertGt(liquidity, 0);
        assertFalse(pair.lastReentrySucceeded());
        assertEq(pair.lastReentryRevertSelector(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
    }

    function test_previewUsesPoolReserveRatioEvenWhenPositionIsTiny() external {
        adapter.deposit(100 ether, 200 ether, plan);
        uint256 lpBalance = pair.balanceOf(address(adapter));

        vm.prank(address(adapter));
        assertTrue(pair.transfer(address(0xDEAD), lpBalance - 1));

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        (uint256 used0, uint256 used1) = adapter.previewDeposit(25 ether, 100 ether, plan);

        assertEq(used0, 25 ether);
        assertEq(used1, Math.mulDiv(25 ether, reserve1, reserve0));
    }

    function test_snapshotReportsReserveEquityAndIncludesReserveGrowth() external {
        adapter.deposit(100 ether, 200 ether, plan);

        assertTrue(token0.transfer(address(pair), 11 ether));
        assertTrue(token1.transfer(address(pair), 22 ether));
        pair.sync();

        uint256 lpBalance = pair.balanceOf(address(adapter));
        uint256 supply = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        PositionSnapshot memory position = adapter.snapshot();

        uint256 expected0 = Math.mulDiv(lpBalance, reserve0, supply);
        uint256 expected1 = Math.mulDiv(lpBalance, reserve1, supply);
        assertEq(position.principal0, expected0);
        assertEq(position.principal1, expected1);
        assertEq(position.claimableFee0, 0);
        assertEq(position.claimableFee1, 0);
        assertEq(position.amount0, expected0);
        assertEq(position.amount1, expected1);
        assertEq(position.liquidity, lpBalance);
    }

    function test_snapshotIncludesDonatedLpAndRoundsReserveEquityDown() external {
        (,, uint256 minted) = adapter.deposit(100 ether, 200 ether, plan);
        vm.prank(address(0xBEEF));
        assertTrue(pair.transfer(address(adapter), 50 ether));
        assertTrue(token0.transfer(address(pair), 11 ether));
        assertTrue(token1.transfer(address(pair), 22 ether));
        pair.sync();

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 supply = pair.totalSupply();
        PositionSnapshot memory position = adapter.snapshot();
        uint256 expectedLiquidity = minted + 50 ether;
        assertEq(position.liquidity, expectedLiquidity);
        assertEq(position.principal0, Math.mulDiv(expectedLiquidity, reserve0, supply));
        assertEq(position.principal1, Math.mulDiv(expectedLiquidity, reserve1, supply));
        assertEq(position.amount0, position.principal0);
        assertEq(position.amount1, position.principal1);
    }

    function test_snapshotWithZeroLpDoesNotReadPairReservesOrSupply() external {
        vm.mockCallRevert(address(pair), abi.encodeWithSignature("getReserves()"), "unexpected reserves");
        vm.mockCallRevert(address(pair), abi.encodeWithSignature("totalSupply()"), "unexpected supply");
        PositionSnapshot memory position = adapter.snapshot();
        assertEq(position.liquidity, 0);
        assertEq(position.amount0, 0);
        assertEq(position.amount1, 0);
    }

    function test_syncFeesReturnsZeroAndDoesNotMoveAssets() external {
        adapter.deposit(100 ether, 200 ether, plan);
        uint256 vault0Before = token0.balanceOf(address(this));
        uint256 vault1Before = token1.balanceOf(address(this));

        (uint256 fee0, uint256 fee1) = adapter.syncFees();

        assertEq(fee0, 0);
        assertEq(fee1, 0);
        assertEq(token0.balanceOf(address(this)), vault0Before);
        assertEq(token1.balanceOf(address(this)), vault1Before);
    }

    function test_withdrawBurnsFloorRoundedLpShareAndReturnsActualBalanceDeltas() external {
        adapter.deposit(100 ether, 200 ether, plan);

        uint256 lpBefore = pair.balanceOf(address(adapter));
        uint256 supplyBefore = pair.totalSupply();
        uint256 pairBalance0 = token0.balanceOf(address(pair));
        uint256 pairBalance1 = token1.balanceOf(address(pair));
        uint256 liquidityToBurn = Math.mulDiv(lpBefore, 3, 7);
        uint256 expected0 = Math.mulDiv(liquidityToBurn, pairBalance0, supplyBefore);
        uint256 expected1 = Math.mulDiv(liquidityToBurn, pairBalance1, supplyBefore);
        uint256 vault0Before = token0.balanceOf(address(this));
        uint256 vault1Before = token1.balanceOf(address(this));

        (uint256 amount0, uint256 amount1) = adapter.withdraw(3, 7);

        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
        assertEq(token0.balanceOf(address(this)) - vault0Before, amount0);
        assertEq(token1.balanceOf(address(this)) - vault1Before, amount1);
        assertEq(pair.balanceOf(address(adapter)), lpBefore - liquidityToBurn);
    }

    function test_withdrawRejectsZeroPreBurnShareSupply() external {
        vm.expectRevert(IPositionAdapter.InvalidShareSupply.selector);
        adapter.withdraw(1, 0);
    }

    function test_withdrawRejectsSharesAbovePreBurnSupply() external {
        vm.expectRevert(IPositionAdapter.InvalidShareSupply.selector);
        adapter.withdraw(2, 1);
    }

    function test_withdrawReturnsZeroWhenProRataLpUnitsRoundToZero() external {
        adapter.deposit(100 ether, 200 ether, plan);
        uint256 lpBefore = pair.balanceOf(address(adapter));
        uint256 vault0Before = token0.balanceOf(address(this));
        uint256 vault1Before = token1.balanceOf(address(this));

        (uint256 amount0, uint256 amount1) = adapter.withdraw(1, type(uint256).max);

        assertEq(amount0, 0);
        assertEq(amount1, 0);
        assertEq(pair.balanceOf(address(adapter)), lpBefore);
        assertEq(token0.balanceOf(address(this)), vault0Before);
        assertEq(token1.balanceOf(address(this)), vault1Before);
    }

    function test_withdrawAllClearsPositionAndReturnsActualBalanceDeltas() external {
        adapter.deposit(100 ether, 200 ether, plan);
        uint256 vault0Before = token0.balanceOf(address(this));
        uint256 vault1Before = token1.balanceOf(address(this));

        (uint256 amount0, uint256 amount1) = adapter.withdrawAll();

        assertGt(amount0, 0);
        assertGt(amount1, 0);
        assertEq(token0.balanceOf(address(this)) - vault0Before, amount0);
        assertEq(token1.balanceOf(address(this)) - vault1Before, amount1);
        assertEq(pair.balanceOf(address(adapter)), 0);
        assertEq(adapter.snapshot().liquidity, 0);
    }

    function test_assetMutatingMethodsRejectNonVaultCaller() external {
        address stranger = address(0xCAFE);

        vm.startPrank(stranger);
        vm.expectRevert(IPositionAdapter.NotVaultCaller.selector);
        adapter.syncFees();
        vm.expectRevert(IPositionAdapter.NotVaultCaller.selector);
        adapter.deposit(1 ether, 2 ether, plan);
        vm.expectRevert(IPositionAdapter.NotVaultCaller.selector);
        adapter.withdraw(1, 1);
        vm.expectRevert(IPositionAdapter.NotVaultCaller.selector);
        adapter.withdrawAll();
        vm.stopPrank();
    }

    function test_previewDepositRemainsPermissionless() external {
        vm.prank(address(0xCAFE));
        (uint256 used0, uint256 used1) = adapter.previewDeposit(10 ether, 20 ether, plan);

        assertEq(used0, 10 ether);
        assertEq(used1, 20 ether);
    }

    function reenterWithdraw() external {
        require(msg.sender == address(pair), "ONLY_PAIR");
        adapter.withdraw(1, 1);
    }

    function _deployAdapter(address vault, address pool) internal returns (UniswapV2Adapter deployed) {
        return _deployAdapterWithFactory(vault, pool, address(factory));
    }

    function _deployAdapterWithFactory(address vault, address pool, address expectedFactory)
        internal
        returns (UniswapV2Adapter deployed)
    {
        PositionAdapterConfig memory config = PositionAdapterConfig({
            vault: vault, venue: VenueType.UNISWAP_V2, pool: pool, factory: expectedFactory, positionManager: address(0)
        });
        deployed = new UniswapV2Adapter(config);
    }
}
