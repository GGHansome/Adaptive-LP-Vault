// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";

/// @dev Frozen pre-optimization V3 deposit math. Intentionally recomputes range prices for amounts.
library LegacyV3DepositMath {
    uint256 private constant Q96 = 1 << 96;

    function preview(uint160 price, int24 lower, int24 upper, uint256 amount0, uint256 amount1)
        internal
        pure
        returns (uint256 used0, uint256 used1)
    {
        if (amount0 == 0 && amount1 == 0) return (0, 0);
        uint128 liquidity = _liquidity(price, lower, upper, amount0, amount1);
        if (liquidity == 0) return (0, 0);
        uint160 a = PriceMath.sqrtRatioAtTick(lower);
        uint160 b = PriceMath.sqrtRatioAtTick(upper);
        if (price <= a) {
            used0 = _amount0(a, b, liquidity);
        } else if (price < b) {
            used0 = _amount0(price, b, liquidity);
            used1 = Math.mulDiv(uint256(liquidity), uint256(price) - a, Q96, Math.Rounding.Ceil);
        } else {
            used1 = Math.mulDiv(uint256(liquidity), uint256(b) - a, Q96, Math.Rounding.Ceil);
        }
    }

    function _liquidity(uint160 price, int24 lower, int24 upper, uint256 amount0, uint256 amount1)
        private
        pure
        returns (uint128)
    {
        uint160 a = PriceMath.sqrtRatioAtTick(lower);
        uint160 b = PriceMath.sqrtRatioAtTick(upper);
        uint256 liquidity;
        if (price <= a) {
            liquidity = _liquidity0(a, b, amount0);
        } else if (price < b) {
            liquidity = Math.min(_liquidity0(price, b, amount0), _liquidity1(a, price, amount1));
        } else {
            liquidity = _liquidity1(a, b, amount1);
        }
        if (liquidity > type(uint128).max) revert IPositionAdapter.LiquidityOverflow();
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128(liquidity);
    }

    function _liquidity0(uint160 a, uint160 b, uint256 amount) private pure returns (uint256) {
        if (amount == 0) return 0;
        return Math.mulDiv(amount, Math.mulDiv(uint256(a), uint256(b), Q96), uint256(b) - a);
    }

    function _liquidity1(uint160 a, uint160 b, uint256 amount) private pure returns (uint256) {
        if (amount == 0) return 0;
        return Math.mulDiv(amount, Q96, uint256(b) - a);
    }

    function _amount0(uint160 a, uint160 b, uint128 liquidity) private pure returns (uint256) {
        uint256 first = Math.mulDiv(uint256(liquidity) << 96, uint256(b) - a, uint256(b), Math.Rounding.Ceil);
        return Math.ceilDiv(first, uint256(a));
    }
}
