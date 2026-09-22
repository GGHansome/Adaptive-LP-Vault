// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Defines the Uniswap V2 factory reads required to validate a pair binding.
interface IUniswapV2Factory {
    /// @notice Returns the pair registered for two tokens, independent of argument order.
    /// @param tokenA First token in the lookup.
    /// @param tokenB Second token in the lookup.
    /// @return pair Address of the registered pair, or zero when no pair exists.
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/// @notice Defines the Uniswap V2 pair operations required by the V2 adapter.
interface IUniswapV2Pair {
    /// @notice Returns the factory that created the pair.
    /// @return factoryAddress Address of the pair factory.
    function factory() external view returns (address factoryAddress);

    /// @notice Returns the lower-address pair token.
    /// @return token Address of token0.
    function token0() external view returns (address token);

    /// @notice Returns the higher-address pair token.
    /// @return token Address of token1.
    function token1() external view returns (address token);

    /// @notice Returns the latest stored reserves and reserve-update timestamp.
    /// @return reserve0 Stored token0 reserve.
    /// @return reserve1 Stored token1 reserve.
    /// @return blockTimestampLast Timestamp of the latest reserve update, modulo 2^32.
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    /// @notice Returns the total supply of pair liquidity tokens.
    /// @return supply Total liquidity-token supply.
    function totalSupply() external view returns (uint256 supply);

    /// @notice Returns the liquidity-token balance held by an account.
    /// @param owner Account whose balance is queried.
    /// @return balance Liquidity-token balance of `owner`.
    function balanceOf(address owner) external view returns (uint256 balance);

    /// @notice Transfers pair liquidity tokens to another account.
    /// @param to Recipient of the liquidity tokens.
    /// @param value Number of liquidity tokens to transfer.
    /// @return success Whether the transfer succeeded.
    function transfer(address to, uint256 value) external returns (bool success);

    /// @notice Mints liquidity tokens for assets already transferred to the pair.
    /// @param to Recipient of the minted liquidity tokens.
    /// @return liquidity Number of liquidity tokens minted.
    function mint(address to) external returns (uint256 liquidity);

    /// @notice Burns liquidity tokens held by the pair and transfers both assets to a recipient.
    /// @param to Recipient of the withdrawn token0 and token1.
    /// @return amount0 Token0 amount withdrawn.
    /// @return amount1 Token1 amount withdrawn.
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}
