// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ICanonicalV3Oracle} from "../interfaces/ICanonicalV3Oracle.sol";
import {IUniswapV3Factory, IUniswapV3Pool} from "../interfaces/IUniswapV3External.sol";
import {PriceMath} from "../libraries/PriceMath.sol";
import {OracleConfig, OracleSnapshot} from "./OracleTypes.sol";

/// @title Canonical Uniswap V3 Oracle
/// @notice Produces immutable-pool spot, long-TWAP, short-TWAP, and bidirectional quote data.
contract CanonicalV3Oracle is ICanonicalV3Oracle {
    uint256 private constant BPS = 10_000;

    address private immutable _CANONICAL_POOL;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    uint8 private immutable _TOKEN0_DECIMALS;
    uint8 private immutable _TOKEN1_DECIMALS;
    uint32 private immutable _TWAP_WINDOW_SECONDS;
    uint32 private immutable _SHORT_TWAP_WINDOW_SECONDS;

    IUniswapV3Pool private immutable _POOL;

    /// @notice Deploys an oracle bound permanently to one factory-registered Uniswap V3 pool.
    /// @param config Canonical pool, expected V3 factory, and long/short observation windows.
    constructor(OracleConfig memory config) {
        if (
            config.factory == address(0) || config.factory.code.length == 0 || config.twapWindowSeconds == 0
                || config.shortTwapWindowSeconds == 0 || config.shortTwapWindowSeconds >= config.twapWindowSeconds
        ) {
            revert InvalidOracleConfiguration();
        }
        if (config.canonicalPool == address(0) || config.canonicalPool.code.length == 0) {
            revert InvalidCanonicalPool();
        }

        IUniswapV3Pool pool_ = IUniswapV3Pool(config.canonicalPool);
        address token0_;
        address token1_;
        address factory_;
        uint24 fee_;
        int24 tickSpacing_;

        try pool_.token0() returns (address value) {
            token0_ = value;
        } catch {
            revert InvalidCanonicalPool();
        }
        try pool_.token1() returns (address value) {
            token1_ = value;
        } catch {
            revert InvalidCanonicalPool();
        }

        if (token0_ == address(0) || token1_ == address(0) || token0_ == token1_ || token0_ >= token1_) {
            revert InvalidTokenOrder();
        }

        try pool_.factory() returns (address value) {
            factory_ = value;
        } catch {
            revert InvalidCanonicalPool();
        }
        try pool_.fee() returns (uint24 value) {
            fee_ = value;
        } catch {
            revert InvalidCanonicalPool();
        }
        try pool_.tickSpacing() returns (int24 value) {
            tickSpacing_ = value;
        } catch {
            revert InvalidCanonicalPool();
        }

        if (factory_ != config.factory || fee_ == 0 || tickSpacing_ <= 0) {
            revert InvalidCanonicalPool();
        }

        address registeredPool;
        try IUniswapV3Factory(config.factory).getPool(token0_, token1_, fee_) returns (address value) {
            registeredPool = value;
        } catch {
            revert InvalidCanonicalPool();
        }
        if (registeredPool != config.canonicalPool) revert InvalidCanonicalPool();

        uint8 token0Decimals_ = _readDecimals(token0_);
        uint8 token1Decimals_ = _readDecimals(token1_);

        _CANONICAL_POOL = config.canonicalPool;
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _TOKEN0_DECIMALS = token0Decimals_;
        _TOKEN1_DECIMALS = token1Decimals_;
        _TWAP_WINDOW_SECONDS = config.twapWindowSeconds;
        _SHORT_TWAP_WINDOW_SECONDS = config.shortTwapWindowSeconds;
        _POOL = pool_;
    }

    /// @inheritdoc ICanonicalV3Oracle
    function canonicalPool() external view override returns (address pool) {
        return _CANONICAL_POOL;
    }

    /// @inheritdoc ICanonicalV3Oracle
    function token0() external view override returns (address token) {
        return _TOKEN0;
    }

    /// @inheritdoc ICanonicalV3Oracle
    function token1() external view override returns (address token) {
        return _TOKEN1;
    }

    /// @inheritdoc ICanonicalV3Oracle
    function token0Decimals() external view override returns (uint8 decimals) {
        return _TOKEN0_DECIMALS;
    }

    /// @inheritdoc ICanonicalV3Oracle
    function token1Decimals() external view override returns (uint8 decimals) {
        return _TOKEN1_DECIMALS;
    }

    /// @notice Returns the immutable long TWAP window.
    function twapWindowSeconds() external view returns (uint32 window) {
        return _TWAP_WINDOW_SECONDS;
    }

    /// @notice Returns the immutable short TWAP window.
    function shortTwapWindowSeconds() external view returns (uint32 window) {
        return _SHORT_TWAP_WINDOW_SECONDS;
    }

    /// @inheritdoc ICanonicalV3Oracle
    function snapshot() public view override returns (OracleSnapshot memory oracleSnapshot) {
        oracleSnapshot.twapWindowSeconds = _TWAP_WINDOW_SECONDS;
        oracleSnapshot.shortTwapWindowSeconds = _SHORT_TWAP_WINDOW_SECONDS;
        // Uniswap V3 timestamps use uint32 wrapping semantics. Current Ethereum timestamps fit uint32.
        // forge-lint: disable-next-line(unsafe-typecast)
        oracleSnapshot.observedAt = uint32(block.timestamp);

        int24 spotTick;
        try _POOL.slot0() returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, uint8, bool) {
            if (sqrtPriceX96 == 0 || tick < PriceMath.MIN_TICK || tick > PriceMath.MAX_TICK) {
                return oracleSnapshot;
            }
            spotTick = tick;
        } catch {
            return oracleSnapshot;
        }

        try _POOL.liquidity() returns (uint128 activeLiquidity) {
            if (activeLiquidity == 0) return oracleSnapshot;
        } catch {
            return oracleSnapshot;
        }

        uint32[] memory secondsAgos = new uint32[](3);
        secondsAgos[0] = _TWAP_WINDOW_SECONDS;
        secondsAgos[1] = _SHORT_TWAP_WINDOW_SECONDS;

        int56[] memory tickCumulatives;
        uint160[] memory secondsPerLiquidityCumulativeX128s;
        try _POOL.observe(secondsAgos) returns (int56[] memory ticks, uint160[] memory secondsPerLiquidity) {
            tickCumulatives = ticks;
            secondsPerLiquidityCumulativeX128s = secondsPerLiquidity;
        } catch {
            return oracleSnapshot;
        }

        if (tickCumulatives.length != 3 || secondsPerLiquidityCumulativeX128s.length != 3) {
            return oracleSnapshot;
        }

        int56 twapDelta;
        int56 shortTwapDelta;
        unchecked {
            // Uniswap cumulative ticks intentionally wrap in int56; subtraction must preserve that behavior.
            twapDelta = tickCumulatives[2] - tickCumulatives[0];
            shortTwapDelta = tickCumulatives[2] - tickCumulatives[1];
        }

        (bool validTwap, int24 twapTick) = _arithmeticMeanTick(twapDelta, _TWAP_WINDOW_SECONDS);
        (bool validShortTwap, int24 shortTwapTick) = _arithmeticMeanTick(shortTwapDelta, _SHORT_TWAP_WINDOW_SECONDS);
        if (!validTwap || !validShortTwap) return oracleSnapshot;

        uint256 referenceAmount0 = 10 ** uint256(_TOKEN0_DECIMALS);
        uint256 spotPriceToken1 = PriceMath.quoteToken0InToken1(referenceAmount0, spotTick, false);
        uint256 twapPriceToken1 = PriceMath.quoteToken0InToken1(referenceAmount0, twapTick, false);
        uint256 shortTwapPriceToken1 = PriceMath.quoteToken0InToken1(referenceAmount0, shortTwapTick, false);
        if (spotPriceToken1 == 0 || twapPriceToken1 == 0 || shortTwapPriceToken1 == 0) {
            return oracleSnapshot;
        }

        uint256 priceDifference = shortTwapPriceToken1 > twapPriceToken1
            ? shortTwapPriceToken1 - twapPriceToken1
            : twapPriceToken1 - shortTwapPriceToken1;

        oracleSnapshot.spotTick = spotTick;
        oracleSnapshot.twapTick = twapTick;
        oracleSnapshot.shortTwapTick = shortTwapTick;
        oracleSnapshot.spotPriceToken1 = spotPriceToken1;
        oracleSnapshot.twapPriceToken1 = twapPriceToken1;
        oracleSnapshot.shortTwapPriceToken1 = shortTwapPriceToken1;
        oracleSnapshot.deviationBps = Math.mulDiv(priceDifference, BPS, twapPriceToken1);
        oracleSnapshot.healthy = true;
    }

    /// @inheritdoc ICanonicalV3Oracle
    function quoteToken0InToken1(uint256 amount0, int24 tick, bool roundUp)
        external
        pure
        override
        returns (uint256 amount1)
    {
        return PriceMath.quoteToken0InToken1(amount0, tick, roundUp);
    }

    /// @inheritdoc ICanonicalV3Oracle
    function quoteToken1InToken0(uint256 amount1, int24 tick, bool roundUp)
        external
        pure
        override
        returns (uint256 amount0)
    {
        return PriceMath.quoteToken1InToken0(amount1, tick, roundUp);
    }

    /// @inheritdoc ICanonicalV3Oracle
    function isHealthy() external view override returns (bool healthy) {
        return snapshot().healthy;
    }

    function _readDecimals(address token) private view returns (uint8 decimals_) {
        try IERC20Metadata(token).decimals() returns (uint8 value) {
            decimals_ = value;
        } catch {
            revert InvalidTokenMetadata(token);
        }
        if (decimals_ > 18) revert InvalidTokenDecimals(token, decimals_);
    }

    function _arithmeticMeanTick(int56 tickDelta, uint32 window) private pure returns (bool valid, int24 tick) {
        int56 divisor = int56(uint56(window));
        int56 mean = tickDelta / divisor;
        if (tickDelta < 0 && tickDelta % divisor != 0) --mean;
        if (mean < int56(PriceMath.MIN_TICK) || mean > int56(PriceMath.MAX_TICK)) return (false, 0);

        // The explicit bounds check above guarantees the narrowing conversion.
        // forge-lint: disable-next-line(unsafe-typecast)
        return (true, int24(mean));
    }
}
