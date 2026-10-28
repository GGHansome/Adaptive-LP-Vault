// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {PositionAdapterConfig} from "../../src/adapters/AdapterTypes.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
import {MarketRegime, PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {LegacyV3DepositMath} from "./helpers/LegacyV3DepositMath.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";

import {MockV3ERC20, MockV3Factory, MockV3Pool, MockV3PositionManager} from "./mocks/UniswapV3Mocks.sol";

contract UniswapV3AdapterTest is Test {
    uint24 private constant FEE = 3_000;
    int24 private constant TICK_SPACING = 60;

    MockV3ERC20 private tokenA;
    MockV3ERC20 private tokenB;
    MockV3ERC20 private token0;
    MockV3ERC20 private token1;
    MockV3Factory private factory;
    MockV3Pool private pool;
    MockV3PositionManager private manager;
    UniswapV3Adapter private adapter;
    PositionPlan private plan;

    function setUp() external {
        tokenA = new MockV3ERC20("Token A", "TKA");
        tokenB = new MockV3ERC20("Token B", "TKB");
        (token0, token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        factory = new MockV3Factory();
        pool = new MockV3Pool(address(factory), address(token0), address(token1), FEE, TICK_SPACING);
        factory.registerPool(address(token0), address(token1), FEE, address(pool));
        manager = new MockV3PositionManager(address(factory));

        PositionAdapterConfig memory config = PositionAdapterConfig({
            vault: address(this),
            venue: VenueType.UNISWAP_V3_HIGH_FEE,
            pool: address(pool),
            factory: address(factory),
            positionManager: address(manager)
        });
        adapter = new UniswapV3Adapter(config);

        token0.mint(address(this), type(uint128).max);
        token1.mint(address(this), type(uint128).max);
        token0.approve(address(adapter), type(uint256).max);
        token1.approve(address(adapter), type(uint256).max);

        plan = PositionPlan({
            planHash: bytes32(0),
            targetVenue: VenueType.UNISWAP_V3_HIGH_FEE,
            marketRegime: MarketRegime.MEDIUM_DEVIATION,
            tickLower: -TICK_SPACING,
            tickUpper: TICK_SPACING,
            version: 1
        });
    }

    function test_constructorRejectsExpectedFactoryWithoutCode() external {
        PositionAdapterConfig memory config = PositionAdapterConfig({
            vault: address(this),
            venue: VenueType.UNISWAP_V3_HIGH_FEE,
            pool: address(pool),
            factory: address(0xBEEF),
            positionManager: address(manager)
        });

        vm.expectRevert(IPositionAdapter.InvalidAdapterConfiguration.selector);
        new UniswapV3Adapter(config);
    }

    function test_constructorRejectsSelfCertifiedPoolFromUnexpectedFactory() external {
        MockV3Factory unexpectedFactory = new MockV3Factory();
        MockV3Pool unexpectedPool =
            new MockV3Pool(address(unexpectedFactory), address(token0), address(token1), FEE, TICK_SPACING);
        unexpectedFactory.registerPool(address(token0), address(token1), FEE, address(unexpectedPool));
        MockV3PositionManager unexpectedManager = new MockV3PositionManager(address(unexpectedFactory));
        PositionAdapterConfig memory config = PositionAdapterConfig({
            vault: address(this),
            venue: VenueType.UNISWAP_V3_HIGH_FEE,
            pool: address(unexpectedPool),
            factory: address(factory),
            positionManager: address(unexpectedManager)
        });

        vm.expectRevert(IPositionAdapter.InvalidPoolBinding.selector);
        new UniswapV3Adapter(config);
    }

    function test_previewRejectsLiquidityAboveUint128() external {
        vm.expectRevert(IPositionAdapter.LiquidityOverflow.selector);
        adapter.previewDeposit(type(uint128).max, type(uint128).max, plan);
    }

    function test_depositRejectsInvalidMintedPositionOwner() external {
        manager.setReturnWrongOwner(true);

        vm.expectRevert(IPositionAdapter.InvalidManagedPosition.selector);
        adapter.deposit(100 ether, 100 ether, plan);
    }

    function test_syncFeesRejectsRemainingClaimableFees() external {
        _depositPosition();
        manager.setTokensOwed(adapter.positionId(), 1, 0);
        manager.setLeaveFeesOnCollect(true);

        vm.expectRevert(IPositionAdapter.FeeCollectionIncomplete.selector);
        adapter.syncFees();
    }

    function test_withdrawAllBubblesManagerNotClearedRevert() external {
        _depositPosition();
        manager.setLeaveAssetsOnExit(true);

        vm.expectRevert(bytes("Not cleared"));
        adapter.withdrawAll();
    }

    function test_withdrawAllBurnsClearedPosition() external {
        _depositPosition();

        adapter.withdrawAll();

        assertEq(adapter.positionId(), 0);
        assertEq(adapter.snapshot().liquidity, 0);
    }

    function testGas_v3Preview() public {
        adapter.previewDeposit(100 ether, 100 ether, plan);
        emit log_named_uint("v3Preview", vm.snapshotGasLastCall("v3Preview"));
    }

    function testGas_v3Mint() public {
        adapter.deposit(100 ether, 100 ether, plan);
        emit log_named_uint("v3Mint", vm.snapshotGasLastCall("v3Mint"));
    }

    function testFuzz_previewMatchesLegacyAcrossPricesAndRanges(
        uint96 amount0,
        uint96 amount1,
        int24 priceTick,
        int16 centerSteps,
        uint8 halfWidthSteps
    ) public {
        amount0 = uint96(bound(amount0, 0, 1e24));
        amount1 = uint96(bound(amount1, 0, 1e24));
        // Restrict price ratios to avoid uint128 liquidity overflow; include both sides and in-range prices.
        priceTick = int24(bound(int256(priceTick), -60000, 60000));
        int24 center = int24(bound(int256(centerSteps), -1000, 1000)) * TICK_SPACING;
        int24 halfWidth = int24(uint24(bound(halfWidthSteps, 1, 100))) * TICK_SPACING;
        plan.tickLower = center - halfWidth;
        plan.tickUpper = center + halfWidth;
        uint160 price = PriceMath.sqrtRatioAtTick(priceTick);
        _assertLegacyPreview(amount0, amount1, price, priceTick);
    }

    function test_previewMatchesLegacyAtBothRangeBoundariesAndZeroInputs() public {
        _assertLegacyPreview(100 ether, 100 ether, PriceMath.sqrtRatioAtTick(plan.tickLower), plan.tickLower);
        _assertLegacyPreview(100 ether, 100 ether, PriceMath.sqrtRatioAtTick(plan.tickUpper), plan.tickUpper);
        _assertLegacyPreview(0, 0, 1 << 96, 0);
        _assertLegacyPreview(0, 100 ether, 1 << 96, 0);
        _assertLegacyPreview(100 ether, 0, 1 << 96, 0);
    }

    function test_previewMatchesLegacyAtExtremeValidRanges() public {
        plan.tickLower = -887220;
        plan.tickUpper = -887160;
        _assertLegacyPreview(1, 1, PriceMath.sqrtRatioAtTick(-887190), -887190);
        plan.tickLower = 887160;
        plan.tickUpper = 887220;
        _assertLegacyPreview(1, 1, PriceMath.sqrtRatioAtTick(887190), 887190);
    }

    function _assertLegacyPreview(uint256 amount0, uint256 amount1, uint160 price, int24 tick) private {
        vm.mockCall(
            address(pool),
            abi.encodeWithSignature("slot0()"),
            abi.encode(price, tick, uint16(0), uint16(0), uint16(0), uint8(0), true)
        );
        (uint256 expected0, uint256 expected1) =
            LegacyV3DepositMath.preview(price, plan.tickLower, plan.tickUpper, amount0, amount1);
        (uint256 used0, uint256 used1) = adapter.previewDeposit(amount0, amount1, plan);
        assertEq(used0, expected0);
        assertEq(used1, expected1);
        assertLe(used0, amount0);
        assertLe(used1, amount1);
    }

    function _depositPosition() internal {
        (,, uint256 liquidity) = adapter.deposit(100 ether, 100 ether, plan);
        assertEq(liquidity, 1);
        assertEq(adapter.positionId(), 1);
    }
}
