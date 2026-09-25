// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Enumerates swap directions in the vault's canonical token order.
enum SwapDirection {
    /// @notice No swap is required or permitted.
    NONE,
    /// @notice Swap token0 for token1.
    ZERO_FOR_ONE,
    /// @notice Swap token1 for token0.
    ONE_FOR_ZERO
}

/// @notice Contains immutable controlled-swap-executor bindings assembled by the creating vault.
/// @param vault Address of the creating vault and the only account allowed to call the executor.
/// @param router Address of the approved exact-input router.
/// @param swapPool Address of the canonical V3 pool used for the swap.
/// @param factory Address of the expected Uniswap V3 factory used to validate the pool and router.
struct SwapExecutorConfig {
    address vault;
    address router;
    address swapPool;
    address factory;
}

/// @notice Contains transaction-scoped swap instructions constructed by the vault.
/// @param direction Direction of the swap in canonical token order.
/// @param amountIn Exact amount of the input token to swap.
/// @param minAmountOut Keeper-provided minimum acceptable output amount.
/// @param deadline Last timestamp at which the swap may execute.
struct SwapPlan {
    SwapDirection direction;
    uint256 amountIn;
    uint256 minAmountOut;
    uint32 deadline;
}
