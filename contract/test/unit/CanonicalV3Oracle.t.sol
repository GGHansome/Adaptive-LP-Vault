// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";
import {CanonicalV3Oracle} from "../../src/oracle/CanonicalV3Oracle.sol";
import {OracleConfig, OracleSnapshot} from "../../src/oracle/OracleTypes.sol";

import {
    MockOracleToken,
    MockTokenWithoutMetadata,
    MockOracleV3Factory,
    MockOracleV3Pool,
    MockOracleV3PoolWithFailingLiquidity
} from "./mocks/CanonicalV3OracleMocks.sol";

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
