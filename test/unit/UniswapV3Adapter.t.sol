// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PositionAdapterConfig} from "../../src/adapters/AdapterTypes.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
import {MarketRegime, PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/IUniswapV3External.sol";
import {LegacyV3DepositMath} from "../helpers/LegacyV3DepositMath.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";

contract MockV3ERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockV3Factory {
    mapping(address tokenA => mapping(address tokenB => mapping(uint24 fee => address pool))) public getPool;

    function registerPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        getPool[tokenA][tokenB][fee] = pool;
        getPool[tokenB][tokenA][fee] = pool;
    }
}

contract MockV3Pool {
    uint160 private constant Q96 = 0x1000000000000000000000000;

    address private immutable _FACTORY;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    uint24 private immutable _FEE;
    int24 private immutable _TICK_SPACING;

    constructor(address factory_, address token0_, address token1_, uint24 fee_, int24 tickSpacing_) {
        _FACTORY = factory_;
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _FEE = fee_;
        _TICK_SPACING = tickSpacing_;
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

    function fee() external view returns (uint24) {
        return _FEE;
    }

    function tickSpacing() external view returns (int24) {
        return _TICK_SPACING;
    }

    function slot0() external pure returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (Q96, 0, 0, 0, 0, 0, true);
    }

    function feeGrowthGlobal0X128() external pure returns (uint256) {
        return 0;
    }

    function feeGrowthGlobal1X128() external pure returns (uint256) {
        return 0;
    }

    function ticks(int24) external pure returns (uint128, int128, uint256, uint256, int56, uint160, uint32, bool) {
        return (0, 0, 0, 0, 0, 0, 0, false);
    }
}

contract MockV3PositionManager {
    struct MockPosition {
        address owner;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    address private immutable _FACTORY;
    uint256 private _nextTokenId = 1;
    mapping(uint256 tokenId => MockPosition position) private _positions;

    bool public returnWrongOwner;
    bool public leaveFeesOnCollect;
    bool public leaveAssetsOnExit;

    constructor(address factory_) {
        _FACTORY = factory_;
    }

    function factory() external view returns (address) {
        return _FACTORY;
    }

    function setReturnWrongOwner(bool value) external {
        returnWrongOwner = value;
    }

    function setLeaveFeesOnCollect(bool value) external {
        leaveFeesOnCollect = value;
    }

    function setLeaveAssetsOnExit(bool value) external {
        leaveAssetsOnExit = value;
    }

    function setTokensOwed(uint256 tokenId, uint128 amount0, uint128 amount1) external {
        _positions[tokenId].tokensOwed0 = amount0;
        _positions[tokenId].tokensOwed1 = amount1;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        MockPosition memory position = _positions[tokenId];
        return (
            0,
            address(0),
            position.token0,
            position.token1,
            position.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            0,
            0,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    function mint(INonfungiblePositionManager.MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        tokenId = _nextTokenId++;
        liquidity = 1;
        _positions[tokenId] = MockPosition({
            owner: params.recipient,
            token0: params.token0,
            token1: params.token1,
            fee: params.fee,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
        return (tokenId, liquidity, 0, 0);
    }

    function increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        return (1, 0, 0);
    }

    function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        MockPosition storage position = _positions[params.tokenId];
        position.liquidity -= params.liquidity;
        if (leaveAssetsOnExit) position.tokensOwed0 = 1;
        return (0, 0);
    }

    function collect(INonfungiblePositionManager.CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        if (!leaveFeesOnCollect && !leaveAssetsOnExit) {
            _positions[params.tokenId].tokensOwed0 = 0;
            _positions[params.tokenId].tokensOwed1 = 0;
        }
        return (0, 0);
    }

    function burn(uint256 tokenId) external payable {
        MockPosition memory position = _positions[tokenId];
        require(position.liquidity == 0 && position.tokensOwed0 == 0 && position.tokensOwed1 == 0, "Not cleared");
        delete _positions[tokenId];
    }

    function ownerOf(uint256 tokenId) external view returns (address owner) {
        if (returnWrongOwner) return address(0xBEEF);
        return _positions[tokenId].owner;
    }
}

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
