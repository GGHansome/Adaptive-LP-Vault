// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IControlledSwapExecutor} from "../interfaces/IControlledSwapExecutor.sol";
import {IUniswapV3Factory, IUniswapV3Pool, IUniswapV3SwapRouter} from "../interfaces/IUniswapV3External.sol";
import {SwapDirection, SwapExecutorConfig, SwapPlan} from "./SwapTypes.sol";

/// @title Controlled Swap Executor
/// @notice Executes exact-input, single-hop swaps for one immutable vault through one approved V3 router and pool.
/// @dev The creating vault transfers the exact input amount to this contract before calling `executeSwap`.
contract ControlledSwapExecutor is IControlledSwapExecutor, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address private immutable _VAULT;
    address private immutable _ROUTER_ADDRESS;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    address private immutable _SWAP_POOL;
    uint24 private immutable _FEE_TIER;

    IUniswapV3SwapRouter private immutable _ROUTER;

    /// @notice Restricts swap execution to the immutable creating vault.
    modifier onlyVault() {
        _checkVaultCaller();
        _;
    }

    function _checkVaultCaller() internal view {
        if (msg.sender != _VAULT) revert NotVaultCaller();
    }

    /// @notice Creates an executor bound to its creating vault, one V3 router, and one expected-factory pool.
    /// @param config Immutable executor bindings and expected V3 factory assembled by the creating vault.
    constructor(SwapExecutorConfig memory config) {
        if (config.vault == address(0) || config.vault != msg.sender) revert InvalidVaultBinding();
        if (config.swapPool == address(0) || config.swapPool.code.length == 0) revert InvalidSwapPool();
        if (config.factory == address(0) || config.factory.code.length == 0) revert InvalidSwapPool();
        if (config.router == address(0) || config.router.code.length == 0) revert RouterNotAllowed();

        IUniswapV3Pool pool = IUniswapV3Pool(config.swapPool);
        address poolToken0;
        address poolToken1;
        address poolFactory;
        uint24 poolFee;

        try pool.token0() returns (address value) {
            poolToken0 = value;
        } catch {
            revert InvalidSwapPool();
        }
        try pool.token1() returns (address value) {
            poolToken1 = value;
        } catch {
            revert InvalidSwapPool();
        }

        if (
            poolToken0 == address(0) || poolToken1 == address(0) || poolToken0 == poolToken1 || poolToken0 >= poolToken1
        ) {
            revert InvalidTokenOrder();
        }
        if (poolToken0.code.length == 0 || poolToken1.code.length == 0) revert InvalidAssetPair();

        try pool.factory() returns (address value) {
            poolFactory = value;
        } catch {
            revert InvalidSwapPool();
        }
        try pool.fee() returns (uint24 value) {
            poolFee = value;
        } catch {
            revert InvalidSwapPool();
        }
        if (poolFactory != config.factory || poolFee == 0) revert InvalidSwapPool();

        address registeredPool;
        try IUniswapV3Factory(config.factory).getPool(poolToken0, poolToken1, poolFee) returns (address value) {
            registeredPool = value;
        } catch {
            revert InvalidSwapPool();
        }
        if (registeredPool != config.swapPool) revert InvalidSwapPool();

        address routerFactory;
        try IUniswapV3SwapRouter(config.router).factory() returns (address value) {
            routerFactory = value;
        } catch {
            revert RouterNotAllowed();
        }
        if (routerFactory != config.factory) revert RouterNotAllowed();

        _VAULT = config.vault;
        _ROUTER_ADDRESS = config.router;
        _TOKEN0 = poolToken0;
        _TOKEN1 = poolToken1;
        _SWAP_POOL = config.swapPool;
        _FEE_TIER = poolFee;
        _ROUTER = IUniswapV3SwapRouter(config.router);
    }

    /// @inheritdoc IControlledSwapExecutor
    function executeSwap(SwapPlan calldata plan) external override onlyVault nonReentrant returns (uint256 amountOut) {
        if (plan.direction == SwapDirection.NONE || plan.amountIn == 0 || plan.minAmountOut == 0) {
            revert SwapNotAllowed();
        }
        if (block.timestamp > plan.deadline) revert DeadlineExpired();

        (address tokenIn, address tokenOut) =
            plan.direction == SwapDirection.ZERO_FOR_ONE ? (_TOKEN0, _TOKEN1) : (_TOKEN1, _TOKEN0);

        IERC20 inputToken = IERC20(tokenIn);
        IERC20 outputToken = IERC20(tokenOut);
        uint256 executorInputBefore = inputToken.balanceOf(address(this));
        if (executorInputBefore < plan.amountIn) {
            revert InsufficientExecutorInputBalance(tokenIn, plan.amountIn, executorInputBefore);
        }

        uint256 vaultOutputBefore = outputToken.balanceOf(_VAULT);
        uint256 executorOutputBefore = outputToken.balanceOf(address(this));

        inputToken.forceApprove(_ROUTER_ADDRESS, plan.amountIn);
        _ROUTER.exactInputSingle(
            IUniswapV3SwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: _FEE_TIER,
                recipient: _VAULT,
                deadline: uint256(plan.deadline),
                amountIn: plan.amountIn,
                amountOutMinimum: plan.minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        inputToken.forceApprove(_ROUTER_ADDRESS, 0);

        uint256 executorInputAfter = inputToken.balanceOf(address(this));
        uint256 expectedExecutorInputAfter = executorInputBefore - plan.amountIn;
        if (executorInputAfter != expectedExecutorInputAfter) {
            revert ExecutorBalanceMismatch(tokenIn, expectedExecutorInputAfter, executorInputAfter);
        }

        uint256 executorOutputAfter = outputToken.balanceOf(address(this));
        if (executorOutputAfter != executorOutputBefore) {
            revert ExecutorBalanceMismatch(tokenOut, executorOutputBefore, executorOutputAfter);
        }

        uint256 vaultOutputAfter = outputToken.balanceOf(_VAULT);
        if (vaultOutputAfter < vaultOutputBefore) {
            revert VaultOutputBalanceDecreased(tokenOut, vaultOutputBefore, vaultOutputAfter);
        }
        amountOut = vaultOutputAfter - vaultOutputBefore;
        if (amountOut < plan.minAmountOut) revert SwapSlippage(plan.minAmountOut, amountOut);

        emit SwapExecuted(_ROUTER_ADDRESS, plan.direction, plan.amountIn, amountOut, plan.minAmountOut);
    }

    /// @inheritdoc IControlledSwapExecutor
    function router() external view override returns (address routerAddress) {
        return _ROUTER_ADDRESS;
    }

    /// @inheritdoc IControlledSwapExecutor
    function vault() external view override returns (address vaultAddress) {
        return _VAULT;
    }

    /// @inheritdoc IControlledSwapExecutor
    function token0() external view override returns (address token) {
        return _TOKEN0;
    }

    /// @inheritdoc IControlledSwapExecutor
    function token1() external view override returns (address token) {
        return _TOKEN1;
    }

    /// @inheritdoc IControlledSwapExecutor
    function swapPool() external view override returns (address pool) {
        return _SWAP_POOL;
    }

    /// @inheritdoc IControlledSwapExecutor
    function feeTier() external view override returns (uint24 fee) {
        return _FEE_TIER;
    }
}
