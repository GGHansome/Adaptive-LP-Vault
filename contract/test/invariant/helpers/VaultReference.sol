// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UniswapV3Adapter} from "../../../src/adapters/UniswapV3Adapter.sol";
import {INonfungiblePositionManager, IUniswapV3Pool} from "../../../src/interfaces/IUniswapV3External.sol";
import {IUniswapV2Pair} from "../../../src/interfaces/IUniswapV2External.sol";
import {PriceMath} from "../../../src/libraries/PriceMath.sol";

/// @dev Independent accounting from official Pair/Pool/Manager storage, never adapter.snapshot().
/// Shares only the tick-to-sqrt-price primitive with production. The campaign keeps venue pool
/// prices at tick zero; canonical router swaps execute in a separate pool. Real V3 flash donations
/// grow fees without moving venue prices. This deliberately does not model price/IL risk.
library VaultReference {
    struct Position {
        uint256 principal0;
        uint256 principal1;
        uint256 fee0;
        uint256 fee1;
        uint256 units;
        uint256 id;
        int24 lower;
        int24 upper;
    }

    function v2(address pair, address adapter) internal view returns (Position memory p) {
        p.units = IERC20(pair).balanceOf(adapter);
        if (p.units == 0) return p;
        (uint112 r0, uint112 r1,) = IUniswapV2Pair(pair).getReserves();
        uint256 supply = IERC20(pair).totalSupply();
        p.principal0 = Math.mulDiv(r0, p.units, supply);
        p.principal1 = Math.mulDiv(r1, p.units, supply);
    }

    function v3(UniswapV3Adapter adapter) internal view returns (Position memory p) {
        p.id = adapter.positionId();
        if (p.id == 0) return p;
        uint128 liquidity;
        uint128 owed0;
        uint128 owed1;
        uint256 last0;
        uint256 last1;
        (,,,,, p.lower, p.upper, liquidity, last0, last1, owed0, owed1) =
            INonfungiblePositionManager(adapter.positionManager()).positions(p.id);
        p.units = liquidity;
        IUniswapV3Pool pool = IUniswapV3Pool(adapter.pool());
        (uint160 price, int24 tick,,,,,) = pool.slot0();
        (p.principal0, p.principal1) = amounts(price, p.lower, p.upper, liquidity);
        (,, uint256 lower0, uint256 lower1,,,,) = pool.ticks(p.lower);
        (,, uint256 upper0, uint256 upper1,,,,) = pool.ticks(p.upper);
        uint256 g0 = pool.feeGrowthGlobal0X128();
        uint256 g1 = pool.feeGrowthGlobal1X128();
        uint256 delta0;
        uint256 delta1;
        unchecked {
            // Equivalent piecewise inside growth, written independently of the adapter.
            if (tick < p.lower) {
                delta0 = lower0 - upper0 - last0;
                delta1 = lower1 - upper1 - last1;
            } else if (tick >= p.upper) {
                delta0 = upper0 - lower0 - last0;
                delta1 = upper1 - lower1 - last1;
            } else {
                delta0 = g0 - lower0 - upper0 - last0;
                delta1 = g1 - lower1 - upper1 - last1;
            }
        }
        p.fee0 = uint256(owed0) + Math.mulDiv(delta0, liquidity, 1 << 128);
        p.fee1 = uint256(owed1) + Math.mulDiv(delta1, liquidity, 1 << 128);
    }

    function amounts(uint160 price, int24 lower, int24 upper, uint256 units)
        internal
        pure
        returns (uint256 a0, uint256 a1)
    {
        uint160 a = PriceMath.sqrtRatioAtTick(lower);
        uint160 b = PriceMath.sqrtRatioAtTick(upper);
        uint256 clamped = Math.min(Math.max(price, a), b);
        // Canonical burn math floors token0 in two stages and token1 once.
        a0 = Math.mulDiv(units << 96, uint256(b) - clamped, b) / clamped;
        a1 = Math.mulDiv(units, clamped - a, 1 << 96);
    }
}
