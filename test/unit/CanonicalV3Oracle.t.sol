// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";
import {CanonicalV3Oracle} from "../../src/oracle/CanonicalV3Oracle.sol";
import {OracleConfig, OracleSnapshot} from "../../src/oracle/OracleTypes.sol";

contract MockOracleToken {
    uint8 private immutable _DECIMALS;

    constructor(uint8 decimals_) {
        _DECIMALS = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _DECIMALS;
    }
}

contract MockTokenWithoutMetadata {}

contract MockOracleV3Factory {
    mapping(address tokenA => mapping(address tokenB => mapping(uint24 fee => address pool))) public getPool;

    function register(address token0, address token1, uint24 fee, address pool) external {
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool;
    }
}

contract MockOracleV3Pool {
    address private immutable _FACTORY;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    uint24 private immutable _FEE;
    int24 private immutable _TICK_SPACING;

    uint128 public liquidity = 1 ether;
    uint160 public sqrtPriceX96 = uint160(1 << 96);
    int24 public currentTick;
    bool public unlocked = true;

    int56[3] private _tickCumulatives;
    bool public revertSlot0;
    bool public revertObserve;
    bool public malformedObservations;

    constructor(address factory_, address token0_, address token1_) {
        _FACTORY = factory_;
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _FEE = 3_000;
        _TICK_SPACING = 60;
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

    function setSlot0(int24 tick, uint160 sqrtPrice, bool unlocked_) external {
        currentTick = tick;
        sqrtPriceX96 = sqrtPrice;
        unlocked = unlocked_;
    }

    function setLiquidity(uint128 value) external {
        liquidity = value;
    }

    function setObservations(int56 longAgo, int56 shortAgo, int56 current) external {
        _tickCumulatives = [longAgo, shortAgo, current];
    }

    function setFailures(bool slot0Failure, bool observeFailure, bool malformed) external {
        revertSlot0 = slot0Failure;
        revertObserve = observeFailure;
        malformedObservations = malformed;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        if (revertSlot0) revert("SLOT0_FAILURE");
        return (sqrtPriceX96, currentTick, 0, 3, 3, 0, unlocked);
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        if (revertObserve) revert("OBSERVE_FAILURE");
        require(secondsAgos.length == 3 && secondsAgos[0] == 100 && secondsAgos[1] == 10 && secondsAgos[2] == 0);

        uint256 length = malformedObservations ? 2 : 3;
        tickCumulatives = new int56[](length);
        secondsPerLiquidityCumulativeX128s = new uint160[](length);
        for (uint256 i; i < length; ++i) {
            tickCumulatives[i] = _tickCumulatives[i];
            // The loop is bounded by the three-element mock observation array.
            // forge-lint: disable-next-line(unsafe-typecast)
            secondsPerLiquidityCumulativeX128s[i] = uint160(i + 1);
        }
    }
}

contract MockOracleV3PoolWithFailingLiquidity {
    MockOracleV3Pool private immutable _POOL;

    constructor(MockOracleV3Pool pool_) {
        _POOL = pool_;
    }

    function factory() external view returns (address) {
        return _POOL.factory();
    }

    function token0() external view returns (address) {
        return _POOL.token0();
    }

    function token1() external view returns (address) {
        return _POOL.token1();
    }

    function fee() external view returns (uint24) {
        return _POOL.fee();
    }

    function tickSpacing() external view returns (int24) {
        return _POOL.tickSpacing();
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return _POOL.slot0();
    }

    function liquidity() external pure returns (uint128) {
        revert("LIQUIDITY_FAILURE");
    }

    function observe(uint32[] calldata secondsAgos) external view returns (int56[] memory, uint160[] memory) {
        return _POOL.observe(secondsAgos);
    }
}

contract CanonicalV3OracleTest is Test {
    uint32 private constant LONG_WINDOW = 100;
    uint32 private constant SHORT_WINDOW = 10;

    MockOracleToken private _assetA;
    MockOracleToken private _assetB;
    MockOracleV3Factory private _factory;
    MockOracleV3Pool private _pool;
    CanonicalV3Oracle private _oracle;

    function setUp() external {
        _assetA = new MockOracleToken(6);
        _assetB = new MockOracleToken(18);
        _factory = new MockOracleV3Factory();

        (address token0, address token1) = address(_assetA) < address(_assetB)
            ? (address(_assetA), address(_assetB))
            : (address(_assetB), address(_assetA));
        _pool = new MockOracleV3Pool(address(_factory), token0, token1);
        _factory.register(token0, token1, _pool.fee(), address(_pool));
        _oracle = _deploy(address(_pool), LONG_WINDOW, SHORT_WINDOW);
    }

    function testConstructorBindsPoolTokensMetadataAndWindows() external view {
        assertEq(_oracle.canonicalPool(), address(_pool));
        assertEq(_oracle.token0(), _pool.token0());
        assertEq(_oracle.token1(), _pool.token1());
        assertEq(_oracle.token0Decimals(), MockOracleToken(_pool.token0()).decimals());
        assertEq(_oracle.token1Decimals(), MockOracleToken(_pool.token1()).decimals());
        assertEq(_oracle.twapWindowSeconds(), LONG_WINDOW);
        assertEq(_oracle.shortTwapWindowSeconds(), SHORT_WINDOW);
    }

    function testConstructorRejectsInvalidWindows() external {
        vm.expectRevert(ICanonicalV3Oracle.InvalidOracleConfiguration.selector);
        _deploy(address(_pool), 0, 0);

        vm.expectRevert(ICanonicalV3Oracle.InvalidOracleConfiguration.selector);
        _deploy(address(_pool), LONG_WINDOW, LONG_WINDOW);

        vm.expectRevert(ICanonicalV3Oracle.InvalidOracleConfiguration.selector);
        _deploy(address(_pool), SHORT_WINDOW, LONG_WINDOW);
    }

    function testConstructorRejectsInvalidExpectedFactory() external {
        vm.expectRevert(ICanonicalV3Oracle.InvalidOracleConfiguration.selector);
        _deployWithFactory(address(_pool), address(0xBEEF), LONG_WINDOW, SHORT_WINDOW);
    }

    function testConstructorRejectsInvalidPoolAddress() external {
        vm.expectRevert(ICanonicalV3Oracle.InvalidCanonicalPool.selector);
        _deploy(address(0), LONG_WINDOW, SHORT_WINDOW);

        address noCode = makeAddr("no-code-pool");
        vm.expectRevert(ICanonicalV3Oracle.InvalidCanonicalPool.selector);
        _deploy(noCode, LONG_WINDOW, SHORT_WINDOW);
    }

    function testConstructorRejectsUnregisteredPool() external {
        MockOracleV3Pool unregistered = new MockOracleV3Pool(address(_factory), _pool.token0(), _pool.token1());
        vm.expectRevert(ICanonicalV3Oracle.InvalidCanonicalPool.selector);
        _deploy(address(unregistered), LONG_WINDOW, SHORT_WINDOW);
    }

    function testConstructorRejectsSelfCertifiedPoolFromUnexpectedFactory() external {
        MockOracleV3Factory unexpectedFactory = new MockOracleV3Factory();
        MockOracleV3Pool unexpectedPool =
            new MockOracleV3Pool(address(unexpectedFactory), _pool.token0(), _pool.token1());
        unexpectedFactory.register(_pool.token0(), _pool.token1(), unexpectedPool.fee(), address(unexpectedPool));

        vm.expectRevert(ICanonicalV3Oracle.InvalidCanonicalPool.selector);
        _deploy(address(unexpectedPool), LONG_WINDOW, SHORT_WINDOW);
    }

    function testConstructorRejectsInvalidTokenOrder() external {
        MockOracleV3Pool reversed = new MockOracleV3Pool(address(_factory), _pool.token1(), _pool.token0());
        vm.expectRevert(ICanonicalV3Oracle.InvalidTokenOrder.selector);
        _deploy(address(reversed), LONG_WINDOW, SHORT_WINDOW);
    }

    function testConstructorRejectsMissingTokenMetadata() external {
        MockTokenWithoutMetadata broken = new MockTokenWithoutMetadata();
        MockOracleToken valid = new MockOracleToken(18);
        _expectMetadataDeploymentFailure(address(broken), address(valid), false);
    }

    function testConstructorRejectsDecimalsAboveEighteen() external {
        MockOracleToken invalid = new MockOracleToken(19);
        MockOracleToken valid = new MockOracleToken(18);
        _expectMetadataDeploymentFailure(address(invalid), address(valid), true);
    }

    function testBidirectionalQuotesAtTickZeroAreOneToOne() external view {
        uint256 amount = 123_456_789;
        assertEq(_oracle.quoteToken0InToken1(amount, 0, false), amount);
        assertEq(_oracle.quoteToken0InToken1(amount, 0, true), amount);
        assertEq(_oracle.quoteToken1InToken0(amount, 0, false), amount);
        assertEq(_oracle.quoteToken1InToken0(amount, 0, true), amount);
    }

    function testQuotesHonorExplicitRoundingDirection() external view {
        uint256 q1Down = _oracle.quoteToken0InToken1(1, 1, false);
        uint256 q1Up = _oracle.quoteToken0InToken1(1, 1, true);
        uint256 q0Down = _oracle.quoteToken1InToken0(1, 1, false);
        uint256 q0Up = _oracle.quoteToken1InToken0(1, 1, true);

        assertEq(q1Down, 1);
        assertEq(q1Up, 2);
        assertEq(q0Down, 0);
        assertEq(q0Up, 1);
    }

    function testFuzzQuotesRoundUpByAtMostOne(uint128 rawAmount, int24 rawTick) external view {
        uint256 amount = bound(uint256(rawAmount), 0, 1 ether);
        int24 tick = int24(bound(int256(rawTick), int256(PriceMath.MIN_TICK), int256(PriceMath.MAX_TICK)));

        uint256 q1Down = _oracle.quoteToken0InToken1(amount, tick, false);
        uint256 q1Up = _oracle.quoteToken0InToken1(amount, tick, true);
        uint256 q0Down = _oracle.quoteToken1InToken0(amount, tick, false);
        uint256 q0Up = _oracle.quoteToken1InToken0(amount, tick, true);

        assertGe(q1Up, q1Down);
        assertLe(q1Up - q1Down, 1);
        assertGe(q0Up, q0Down);
        assertLe(q0Up - q0Down, 1);
    }

    function testQuotesRejectTicksOutsideV3Bounds() external {
        vm.expectRevert(abi.encodeWithSelector(ICanonicalV3Oracle.InvalidTick.selector, int24(887273)));
        _oracle.quoteToken0InToken1(1, 887273, false);

        vm.expectRevert(abi.encodeWithSelector(ICanonicalV3Oracle.InvalidTick.selector, int24(-887273)));
        _oracle.quoteToken1InToken0(1, -887273, false);
    }

    function testSnapshotReturnsSpotLongAndShortTwapPrices() external {
        _pool.setSlot0(30, uint160(1 << 96), true);
        _pool.setObservations(-1_000, -200, 0);
        vm.warp(1_900_000_000);

        OracleSnapshot memory result = _oracle.snapshot();
        uint256 referenceAmount0 = 10 ** uint256(_oracle.token0Decimals());
        uint256 expectedSpot = _oracle.quoteToken0InToken1(referenceAmount0, 30, false);
        uint256 expectedTwap = _oracle.quoteToken0InToken1(referenceAmount0, 10, false);
        uint256 expectedShort = _oracle.quoteToken0InToken1(referenceAmount0, 20, false);
        uint256 expectedDeviation = Math.mulDiv(expectedShort - expectedTwap, 10_000, expectedTwap);

        assertTrue(result.healthy);
        assertEq(result.spotTick, 30);
        assertEq(result.twapTick, 10);
        assertEq(result.shortTwapTick, 20);
        assertEq(result.spotPriceToken1, expectedSpot);
        assertEq(result.twapPriceToken1, expectedTwap);
        assertEq(result.shortTwapPriceToken1, expectedShort);
        assertEq(result.deviationBps, expectedDeviation);
        assertEq(result.twapWindowSeconds, LONG_WINDOW);
        assertEq(result.shortTwapWindowSeconds, SHORT_WINDOW);
        assertEq(result.observedAt, 1_900_000_000);
    }

    function testSnapshotRoundsNegativeMeanTicksTowardNegativeInfinity() external {
        _pool.setSlot0(-3, uint160(1 << 96), true);
        _pool.setObservations(101, 11, 0);

        OracleSnapshot memory result = _oracle.snapshot();

        assertTrue(result.healthy);
        assertEq(result.twapTick, -2);
        assertEq(result.shortTwapTick, -2);
    }

    function testSnapshotNormalizesObserveFailureAndRecovers() external {
        _pool.setObservations(-1_000, -200, 0);
        _pool.setFailures(false, true, false);
        vm.warp(1_900_000_001);

        OracleSnapshot memory failed = _oracle.snapshot();
        _assertCanonicalUnhealthySnapshot(failed, 1_900_000_001);
        assertFalse(_oracle.isHealthy());

        _pool.setFailures(false, false, false);
        assertTrue(_oracle.isHealthy());
        assertTrue(_oracle.snapshot().healthy);
    }

    function testSnapshotNormalizesSlot0FailureWithoutPartialResults() external {
        _pool.setObservations(-1_000, -200, 0);
        _pool.setFailures(true, false, false);
        vm.warp(1_900_000_002);

        _assertCanonicalUnhealthySnapshot(_oracle.snapshot(), 1_900_000_002);
    }

    function testSnapshotRejectsMalformedObservationArrays() external {
        _pool.setFailures(false, false, true);
        vm.warp(1_900_000_003);

        _assertCanonicalUnhealthySnapshot(_oracle.snapshot(), 1_900_000_003);
    }

    function testSnapshotIsUnhealthyWhenCurrentLiquidityIsZero() external {
        _pool.setLiquidity(0);
        vm.warp(1_900_000_004);

        _assertCanonicalUnhealthySnapshot(_oracle.snapshot(), 1_900_000_004);
    }

    function testSnapshotIsUnhealthyWhenRequiredQuoteRoundsToZero() external {
        _pool.setSlot0(PriceMath.MIN_TICK, uint160(1 << 32), true);
        _pool.setObservations(88_727_200, 8_872_720, 0);
        vm.warp(1_900_000_005);

        _assertCanonicalUnhealthySnapshot(_oracle.snapshot(), 1_900_000_005);
    }

    function testSnapshotNormalizesLiquidityReadFailure() external {
        MockOracleV3PoolWithFailingLiquidity failing = new MockOracleV3PoolWithFailingLiquidity(_pool);
        _factory.register(_pool.token0(), _pool.token1(), _pool.fee(), address(failing));
        CanonicalV3Oracle oracle = _deploy(address(failing), LONG_WINDOW, SHORT_WINDOW);
        vm.warp(1_900_000_006);

        _assertCanonicalUnhealthySnapshot(oracle.snapshot(), 1_900_000_006);
    }

    function _deploy(address pool, uint32 longWindow, uint32 shortWindow) private returns (CanonicalV3Oracle oracle) {
        return _deployWithFactory(pool, address(_factory), longWindow, shortWindow);
    }

    function _deployWithFactory(address pool, address expectedFactory, uint32 longWindow, uint32 shortWindow)
        private
        returns (CanonicalV3Oracle oracle)
    {
        oracle = new CanonicalV3Oracle(
            OracleConfig({
                canonicalPool: pool,
                factory: expectedFactory,
                twapWindowSeconds: longWindow,
                shortTwapWindowSeconds: shortWindow
            })
        );
    }

    function _expectMetadataDeploymentFailure(address assetA, address assetB, bool excessiveDecimals) private {
        (address token0, address token1) = assetA < assetB ? (assetA, assetB) : (assetB, assetA);
        MockOracleV3Pool pool = new MockOracleV3Pool(address(_factory), token0, token1);
        _factory.register(token0, token1, pool.fee(), address(pool));

        if (excessiveDecimals) {
            address invalid = assetA;
            vm.expectRevert(
                abi.encodeWithSelector(ICanonicalV3Oracle.InvalidTokenDecimals.selector, invalid, uint8(19))
            );
        } else {
            vm.expectRevert(abi.encodeWithSelector(ICanonicalV3Oracle.InvalidTokenMetadata.selector, assetA));
        }
        _deploy(address(pool), LONG_WINDOW, SHORT_WINDOW);
    }

    function _assertCanonicalUnhealthySnapshot(OracleSnapshot memory result, uint32 observedAt) private pure {
        assertFalse(result.healthy);
        assertEq(result.spotTick, 0);
        assertEq(result.twapTick, 0);
        assertEq(result.shortTwapTick, 0);
        assertEq(result.spotPriceToken1, 0);
        assertEq(result.twapPriceToken1, 0);
        assertEq(result.shortTwapPriceToken1, 0);
        assertEq(result.deviationBps, 0);
        assertEq(result.twapWindowSeconds, LONG_WINDOW);
        assertEq(result.shortTwapWindowSeconds, SHORT_WINDOW);
        assertEq(result.observedAt, observedAt);
    }
}
