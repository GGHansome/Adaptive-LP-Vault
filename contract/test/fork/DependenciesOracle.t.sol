// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MainnetForkFixture, IForkV2Pair, IForkV2Factory} from "./helpers/MainnetForkFixture.sol";
import {IUniswapV3Pool, IUniswapV3Factory} from "../../src/interfaces/IUniswapV3External.sol";
import {CanonicalV3Oracle} from "../../src/oracle/CanonicalV3Oracle.sol";
import {OracleConfig, OracleSnapshot} from "../../src/oracle/OracleTypes.sol";

contract DependenciesOracleForkTest is MainnetForkFixture {
    function test_realDeploymentsAndPoolBindings() public view {
        address[9] memory dependencies =
            [USDC, WETH, V2_FACTORY, V3_FACTORY, PAIR, LOW_POOL, HIGH_POOL, ROUTER, POSITION_MANAGER];
        for (uint256 i; i < dependencies.length; ++i) {
            assertGt(dependencies[i].code.length, 0);
        }
        assertEq(IERC20Metadata(USDC).decimals(), 6);
        assertEq(IERC20Metadata(WETH).decimals(), 18);
        assertEq(IForkV2Pair(PAIR).token0(), USDC);
        assertEq(IForkV2Pair(PAIR).token1(), WETH);
        assertEq(IForkV2Pair(PAIR).factory(), V2_FACTORY);
        assertEq(IForkV2Factory(V2_FACTORY).getPair(USDC, WETH), PAIR);
        (uint112 reserve0, uint112 reserve1,) = IForkV2Pair(PAIR).getReserves();
        assertGt(reserve0, 0);
        assertGt(reserve1, 0);
        assertEq(router.factory(), V3_FACTORY);
        assertEq(positionManager.factory(), V3_FACTORY);
        _checkV3(LOW_POOL, 500, 10);
        _checkV3(HIGH_POOL, 3000, 60);
        assertEq(oracle.canonicalPool(), LOW_POOL);
        assertEq(oracle.token0(), USDC);
        assertEq(oracle.token1(), WETH);
        assertEq(oracle.token0Decimals(), 6);
        assertEq(oracle.token1Decimals(), 18);
    }

    function _checkV3(address pool, uint24 fee, int24 spacing) private view {
        IUniswapV3Pool p = IUniswapV3Pool(pool);
        assertEq(p.factory(), V3_FACTORY);
        assertEq(p.token0(), USDC);
        assertEq(p.token1(), WETH);
        assertEq(p.fee(), fee);
        assertEq(p.tickSpacing(), spacing);
        assertEq(IUniswapV3Factory(V3_FACTORY).getPool(USDC, WETH, fee), pool);
        assertGt(p.liquidity(), 0);
    }

    function test_realHistoryMatchesIndependentMeanTicks() public view {
        uint32[] memory windows = new uint32[](3);
        windows[0] = 1800;
        windows[1] = 300;
        (int56[] memory cumulatives,) = IUniswapV3Pool(LOW_POOL).observe(windows);
        OracleSnapshot memory observed = oracle.snapshot();
        (, int24 spot,,,,,) = IUniswapV3Pool(LOW_POOL).slot0();
        assertTrue(observed.healthy);
        assertEq(observed.spotTick, spot);
        assertEq(observed.twapTick, _mean(cumulatives[2] - cumulatives[0], 1800));
        assertEq(observed.shortTwapTick, _mean(cumulatives[2] - cumulatives[1], 300));
        assertEq(observed.observedAt, vm.getBlockTimestamp());
        assertEq(observed.twapWindowSeconds, 1800);
        assertEq(observed.shortTwapWindowSeconds, 300);
        uint256 diff = observed.shortTwapPriceToken1 > observed.twapPriceToken1
            ? observed.shortTwapPriceToken1 - observed.twapPriceToken1
            : observed.twapPriceToken1 - observed.shortTwapPriceToken1;
        assertEq(observed.deviationBps, diff * 10_000 / observed.twapPriceToken1);
        if (block.number == BASELINE_BLOCK) {
            assertEq(observed.twapTick, 197543);
            assertEq(observed.shortTwapTick, 197548);
        }
    }

    function _mean(int56 delta, int56 window) private pure returns (int56) {
        // Floor division expressed independently from the production implementation.
        return delta >= 0 ? delta / window : -((-delta + window - 1) / window);
    }

    function test_mixedDecimalSpotQuotesAgreeWithRawPoolPrice() public view {
        (uint160 sqrtPrice, int24 tick,,,,,) = IUniswapV3Pool(LOW_POOL).slot0();
        // Historical USDC/WETH price fits this Q128 branch; use pool sqrtPrice, not project tick math.
        uint256 ratioX128 = Math.mulDiv(uint256(sqrtPrice), sqrtPrice, 1 << 64);
        uint256 raw0 = 10_000e6;
        uint256 raw1 = 1 ether;
        uint256 poolQuote1 = Math.mulDiv(raw0, ratioX128, 1 << 128);
        uint256 poolQuote0 = Math.mulDiv(raw1, 1 << 128, ratioX128);
        uint256 tickQuote1 = oracle.quoteToken0InToken1(raw0, tick, false);
        uint256 tickQuote0 = oracle.quoteToken1InToken0(raw1, tick, false);
        // slot0 price is within the current tick: at most one tick (approximately 1 bp).
        assertLe(tickQuote1, poolQuote1);
        assertLe(poolQuote1, Math.mulDiv(tickQuote1, 10001, 10000, Math.Rounding.Ceil));
        assertGe(tickQuote0, poolQuote0);
        assertLe(tickQuote0, Math.mulDiv(poolQuote0, 10001, 10000, Math.Rounding.Ceil));
        assertGe(oracle.quoteToken0InToken1(raw0, tick, true), tickQuote1);
        assertLe(oracle.quoteToken0InToken1(raw0, tick, true) - tickQuote1, 1);
        assertGe(oracle.quoteToken1InToken0(raw1, tick, true), tickQuote0);
        assertLe(oracle.quoteToken1InToken0(raw1, tick, true) - tickQuote0, 1);
    }

    function test_insufficientRealHistoryIsUnhealthyWithoutMocks() public {
        CanonicalV3Oracle unavailable = new CanonicalV3Oracle(OracleConfig(LOW_POOL, V3_FACTORY, type(uint32).max, 300));
        assertFalse(unavailable.snapshot().healthy);
        assertFalse(unavailable.isHealthy());
    }

    function test_timePassageUsesRealPoolObservations() public {
        vm.warp(vm.getBlockTimestamp() + 1801);
        OracleSnapshot memory settled = oracle.snapshot();
        assertTrue(settled.healthy);
        assertEq(settled.twapTick, settled.spotTick);
        assertEq(settled.shortTwapTick, settled.spotTick);
        assertEq(settled.deviationBps, 0);
    }
}
