// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Defines the Uniswap V3 factory read required to validate pool bindings.
interface IUniswapV3Factory {
    /// @notice Returns the pool registered for a token pair and fee tier.
    /// @param tokenA First token in the lookup.
    /// @param tokenB Second token in the lookup.
    /// @param fee Fee tier expressed in hundredths of a basis point.
    /// @return pool Address of the registered pool, or zero when no pool exists.
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

/// @notice Defines canonical Uniswap V3 pool reads used by the oracle, adapters, and executor.
interface IUniswapV3Pool {
    /// @notice Returns the factory that created the pool.
    /// @return factoryAddress Address of the pool factory.
    function factory() external view returns (address factoryAddress);

    /// @notice Returns the lower-address pool token.
    /// @return token Address of token0.
    function token0() external view returns (address token);

    /// @notice Returns the higher-address pool token.
    /// @return token Address of token1.
    function token1() external view returns (address token);

    /// @notice Returns the pool fee tier.
    /// @return feeTier Fee tier expressed in hundredths of a basis point.
    function fee() external view returns (uint24 feeTier);

    /// @notice Returns the minimum tick interval accepted by the pool.
    /// @return spacing Tick spacing of the pool.
    function tickSpacing() external view returns (int24 spacing);

    /// @notice Returns the maximum liquidity allowed within one tick.
    /// @return maximum Maximum liquidity per tick.
    function maxLiquidityPerTick() external view returns (uint128 maximum);

    /// @notice Returns the currently in-range pool liquidity.
    /// @return activeLiquidity Current in-range liquidity.
    function liquidity() external view returns (uint128 activeLiquidity);

    /// @notice Returns the all-time token0 fee growth per unit of liquidity.
    /// @return feeGrowth Global token0 fee growth as a Q128.128 value.
    function feeGrowthGlobal0X128() external view returns (uint256 feeGrowth);

    /// @notice Returns the all-time token1 fee growth per unit of liquidity.
    /// @return feeGrowth Global token1 fee growth as a Q128.128 value.
    function feeGrowthGlobal1X128() external view returns (uint256 feeGrowth);

    /// @notice Returns accounting data stored for an initialized or uninitialized tick.
    /// @param tick Tick index to query.
    /// @return liquidityGross Total liquidity referencing the tick.
    /// @return liquidityNet Net liquidity change when crossing the tick left to right.
    /// @return feeGrowthOutside0X128 Token0 fee growth on the opposite side of the tick.
    /// @return feeGrowthOutside1X128 Token1 fee growth on the opposite side of the tick.
    /// @return tickCumulativeOutside Tick accumulator on the opposite side of the tick.
    /// @return secondsPerLiquidityOutsideX128 Seconds-per-liquidity accumulator on the opposite side.
    /// @return secondsOutside Seconds elapsed on the opposite side of the tick.
    /// @return initialized Whether the tick has ever been initialized.
    function ticks(int24 tick)
        external
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        );

    /// @notice Returns the pool's current price, tick, and observation state.
    /// @return sqrtPriceX96 Current square-root price as a Q64.96 value.
    /// @return tick Current pool tick.
    /// @return observationIndex Index of the most recently written observation.
    /// @return observationCardinality Current number of populated observation slots.
    /// @return observationCardinalityNext Target number of observation slots.
    /// @return feeProtocol Encoded protocol-fee configuration.
    /// @return unlocked Whether the pool is currently unlocked.
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    /// @notice Returns cumulative observations at the requested lookback times.
    /// @param secondsAgos Seconds before the current block timestamp for each observation.
    /// @return tickCumulatives Cumulative tick values at each requested lookback.
    /// @return secondsPerLiquidityCumulativeX128s Cumulative seconds-per-liquidity values at each lookback.
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}

/// @notice Defines the ERC-721 position-manager operations required by the V3 adapter.
interface INonfungiblePositionManager {
    /// @notice Contains parameters for minting a new concentrated-liquidity position.
    /// @param token0 Lower-address pool token.
    /// @param token1 Higher-address pool token.
    /// @param fee Pool fee tier.
    /// @param tickLower Lower tick of the position range.
    /// @param tickUpper Upper tick of the position range.
    /// @param amount0Desired Desired token0 contribution.
    /// @param amount1Desired Desired token1 contribution.
    /// @param amount0Min Minimum token0 contribution permitted by the caller.
    /// @param amount1Min Minimum token1 contribution permitted by the caller.
    /// @param recipient Recipient and owner of the newly minted position NFT.
    /// @param deadline Last timestamp at which minting may execute.
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    /// @notice Contains parameters for adding liquidity to an existing position.
    /// @param tokenId Identifier of the position NFT.
    /// @param amount0Desired Desired token0 contribution.
    /// @param amount1Desired Desired token1 contribution.
    /// @param amount0Min Minimum token0 contribution permitted by the caller.
    /// @param amount1Min Minimum token1 contribution permitted by the caller.
    /// @param deadline Last timestamp at which the increase may execute.
    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Contains parameters for removing liquidity from an existing position.
    /// @param tokenId Identifier of the position NFT.
    /// @param liquidity Native liquidity units to remove.
    /// @param amount0Min Minimum token0 principal produced by the removal.
    /// @param amount1Min Minimum token1 principal produced by the removal.
    /// @param deadline Last timestamp at which the decrease may execute.
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Contains parameters for collecting principal and fees owed by a position.
    /// @param tokenId Identifier of the position NFT.
    /// @param recipient Account that receives collected token0 and token1.
    /// @param amount0Max Maximum token0 amount to collect.
    /// @param amount1Max Maximum token1 amount to collect.
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    /// @notice Returns the factory used by the position manager.
    /// @return factoryAddress Address of the Uniswap V3 factory.
    function factory() external view returns (address factoryAddress);

    /// @notice Returns the complete stored state of a position NFT.
    /// @param tokenId Identifier of the position NFT.
    /// @return nonce Permit nonce of the NFT.
    /// @return operator Approved operator of the NFT.
    /// @return token0 Lower-address position token.
    /// @return token1 Higher-address position token.
    /// @return fee Pool fee tier.
    /// @return tickLower Lower tick of the position range.
    /// @return tickUpper Upper tick of the position range.
    /// @return liquidity Native liquidity units held by the position.
    /// @return feeGrowthInside0LastX128 Last recorded token0 fee growth inside the range.
    /// @return feeGrowthInside1LastX128 Last recorded token1 fee growth inside the range.
    /// @return tokensOwed0 Stored token0 amount owed to the position.
    /// @return tokensOwed1 Stored token1 amount owed to the position.
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
        );

    /// @notice Mints a new concentrated-liquidity position NFT.
    /// @param params Pool, range, amount, recipient, and deadline parameters.
    /// @return tokenId Identifier of the newly minted position NFT.
    /// @return liquidity Native liquidity units minted.
    /// @return amount0 Actual token0 amount consumed.
    /// @return amount1 Actual token1 amount consumed.
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Adds liquidity to an existing position NFT.
    /// @param params Position, amount, slippage, and deadline parameters.
    /// @return liquidity Native liquidity units added.
    /// @return amount0 Actual token0 amount consumed.
    /// @return amount1 Actual token1 amount consumed.
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Removes liquidity from an existing position and records the resulting owed tokens.
    /// @param params Position, liquidity, slippage, and deadline parameters.
    /// @return amount0 Token0 principal made collectible.
    /// @return amount1 Token1 principal made collectible.
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    /// @notice Collects principal and fees owed by a position.
    /// @param params Position, recipient, and maximum-amount parameters.
    /// @return amount0 Actual token0 amount collected.
    /// @return amount1 Actual token1 amount collected.
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

    /// @notice Burns an empty position NFT.
    /// @param tokenId Identifier of the empty position NFT.
    function burn(uint256 tokenId) external payable;

    /// @notice Returns the owner of a position NFT.
    /// @param tokenId Identifier of the position NFT.
    /// @return owner Owner of the position NFT.
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

/// @notice Defines the exact-input, single-hop Uniswap V3 router operation used by the executor.
interface IUniswapV3SwapRouter {
    /// @notice Contains parameters for an exact-input, single-hop swap.
    /// @param tokenIn Address of the input token.
    /// @param tokenOut Address of the output token.
    /// @param fee Pool fee tier.
    /// @param recipient Account that receives the output token.
    /// @param deadline Last timestamp at which the swap may execute.
    /// @param amountIn Exact input-token amount.
    /// @param amountOutMinimum Minimum acceptable output-token amount.
    /// @param sqrtPriceLimitX96 Optional Q64.96 square-root-price limit, or zero for no limit.
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns the factory used by the swap router.
    /// @return factoryAddress Address of the Uniswap V3 factory.
    function factory() external view returns (address factoryAddress);

    /// @notice Executes an exact-input swap through one V3 pool.
    /// @param params Token, pool, recipient, amount, limit, and deadline parameters.
    /// @return amountOut Actual output-token amount produced by the swap.
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}
