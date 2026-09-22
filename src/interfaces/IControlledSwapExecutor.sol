// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SwapDirection, SwapPlan} from "../swap/SwapTypes.sol";

/// @notice Defines a vault-only exact-input swap executor bound to one router and canonical pool.
interface IControlledSwapExecutor {
    /// @notice Indicates that the executor token pair differs from the vault pair.
    error InvalidAssetPair();

    /// @notice Indicates that the bound swap pool is not the vault's canonical pool.
    error InvalidSwapPool();

    /// @notice Indicates that pool tokens are zero, equal, or not ordered by address.
    error InvalidTokenOrder();

    /// @notice Indicates that the swap deadline has passed.
    error DeadlineExpired();

    /// @notice Indicates that the supplied plan does not permit a swap.
    error SwapNotAllowed();

    /// @notice Indicates that execution targeted a router other than the immutable approved router.
    error RouterNotAllowed();

    /// @notice Indicates that the swap tokens do not match the canonical pair and direction.
    error TokenNotAllowed();

    /// @notice Indicates that `amountIn` exceeds the inventory-repair amount permitted by the vault.
    error SwapAmountExceeded();

    /// @notice Indicates that the actual output is below the effective minimum output.
    error SwapSlippage();

    /// @notice Indicates that `executeSwap` was called by an account other than the vault.
    error NotVaultCaller();

    /// @notice Emitted after the immutable router completes an approved swap.
    /// @param router Address of the immutable router used for execution.
    /// @param direction Executed direction in canonical token order.
    /// @param amountIn Exact input amount consumed by the router.
    /// @param amountOut Actual output amount received by the vault.
    /// @param protocolMinOut Minimum output imposed by canonical pricing and protocol slippage limits.
    event SwapExecuted(
        address indexed router, SwapDirection direction, uint256 amountIn, uint256 amountOut, uint256 protocolMinOut
    );

    /// @notice Executes one approved exact-input, single-hop swap.
    /// @dev Only the bound vault may call this function.
    /// @param plan Transaction-scoped swap plan constructed by the vault.
    /// @return amountOut Actual output-token balance increase received by the vault.
    function executeSwap(SwapPlan calldata plan) external returns (uint256 amountOut);

    /// @notice Returns the immutable approved router.
    /// @return routerAddress Address of the router.
    function router() external view returns (address routerAddress);

    /// @notice Returns the immutable vault authorized to call the executor.
    /// @return vaultAddress Address of the vault.
    function vault() external view returns (address vaultAddress);

    /// @notice Returns the lower-address token bound to the executor.
    /// @return token Address of token0.
    function token0() external view returns (address token);

    /// @notice Returns the higher-address token bound to the executor.
    /// @return token Address of token1.
    function token1() external view returns (address token);

    /// @notice Returns the immutable canonical pool used for swaps.
    /// @return pool Address of the swap pool.
    function swapPool() external view returns (address pool);

    /// @notice Returns the fee tier of the immutable swap pool.
    /// @return fee Fee tier expressed in hundredths of a basis point.
    function feeTier() external view returns (uint24 fee);
}
