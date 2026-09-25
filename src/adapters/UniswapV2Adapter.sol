// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PositionAdapterConfig, PositionSnapshot} from "./AdapterTypes.sol";
import {IPositionAdapter} from "../interfaces/IPositionAdapter.sol";
import {IUniswapV2Factory, IUniswapV2Pair} from "../interfaces/IUniswapV2External.sol";
import {PositionPlan, VenueType} from "../core/VaultTypes.sol";

/// @title Uniswap V2 Position Adapter
/// @notice Manages one vault's liquidity in one immutable Uniswap V2 pair.
/// @dev V2 fees are incorporated into pair reserves and therefore into LP-token reserve equity.
contract UniswapV2Adapter is IPositionAdapter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address private immutable _VAULT;
    address private immutable _POOL;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    IUniswapV2Pair private immutable _PAIR;

    /// @notice Restricts asset-mutating operations to the immutable vault.
    modifier onlyVault() {
        _checkVaultCaller();
        _;
    }

    function _checkVaultCaller() internal view {
        if (msg.sender != _VAULT) revert NotVaultCaller();
    }

    /// @notice Deploys an adapter bound to one vault and one validated Uniswap V2 pair.
    /// @param config Immutable vault, venue, pair, expected-factory, and position-manager configuration.
    constructor(PositionAdapterConfig memory config) {
        if (
            config.vault == address(0) || config.pool == address(0) || config.factory == address(0)
                || config.venue != VenueType.UNISWAP_V2 || config.positionManager != address(0)
                || config.pool.code.length == 0 || config.factory.code.length == 0
        ) {
            revert InvalidAdapterConfiguration();
        }

        IUniswapV2Pair pair = IUniswapV2Pair(config.pool);
        address pairToken0;
        address pairToken1;
        address pairFactory;

        try pair.token0() returns (address value) {
            pairToken0 = value;
        } catch {
            revert InvalidPoolBinding();
        }
        try pair.token1() returns (address value) {
            pairToken1 = value;
        } catch {
            revert InvalidPoolBinding();
        }

        if (
            pairToken0 == address(0) || pairToken1 == address(0) || pairToken0 == pairToken1 || pairToken0 >= pairToken1
        ) {
            revert InvalidTokenOrder();
        }
        if (pairToken0.code.length == 0 || pairToken1.code.length == 0) revert InvalidAssetPair();

        try pair.factory() returns (address value) {
            pairFactory = value;
        } catch {
            revert InvalidPoolBinding();
        }
        if (pairFactory != config.factory) revert InvalidPoolBinding();

        address registeredPair;
        try IUniswapV2Factory(config.factory).getPair(pairToken0, pairToken1) returns (address value) {
            registeredPair = value;
        } catch {
            revert InvalidPoolBinding();
        }
        if (registeredPair != config.pool) revert InvalidPoolBinding();

        _VAULT = config.vault;
        _POOL = config.pool;
        _TOKEN0 = pairToken0;
        _TOKEN1 = pairToken1;
        _PAIR = pair;
    }

    /// @inheritdoc IPositionAdapter
    function vault() external view override returns (address vaultAddress) {
        return _VAULT;
    }

    /// @inheritdoc IPositionAdapter
    function venue() external pure override returns (VenueType venueType) {
        return VenueType.UNISWAP_V2;
    }

    /// @inheritdoc IPositionAdapter
    function pool() external view override returns (address poolAddress) {
        return _POOL;
    }

    /// @inheritdoc IPositionAdapter
    function token0() external view override returns (address token) {
        return _TOKEN0;
    }

    /// @inheritdoc IPositionAdapter
    function token1() external view override returns (address token) {
        return _TOKEN1;
    }

    /// @inheritdoc IPositionAdapter
    function feeTier() external pure override returns (uint24 fee) {
        return 0;
    }

    /// @inheritdoc IPositionAdapter
    function tickSpacing() external pure override returns (int24 spacing) {
        return 0;
    }

    /// @inheritdoc IPositionAdapter
    function snapshot() external view override returns (PositionSnapshot memory position) {
        uint256 lpBalance = _PAIR.balanceOf(address(this));

        position.venue = VenueType.UNISWAP_V2;
        position.adapter = address(this);
        position.liquidity = lpBalance;

        if (lpBalance == 0) return position;

        (uint112 reserve0, uint112 reserve1,) = _PAIR.getReserves();
        uint256 supply = _PAIR.totalSupply();
        if (supply == 0) revert InvalidPoolBinding();

        position.principal0 = Math.mulDiv(lpBalance, uint256(reserve0), supply);
        position.principal1 = Math.mulDiv(lpBalance, uint256(reserve1), supply);
        position.amount0 = position.principal0;
        position.amount1 = position.principal1;
    }

    /// @inheritdoc IPositionAdapter
    function syncFees() external view override onlyVault returns (uint256 fee0, uint256 fee1) {
        return (0, 0);
    }

    /// @inheritdoc IPositionAdapter
    function previewDeposit(uint256 amount0Max, uint256 amount1Max, PositionPlan calldata plan)
        external
        view
        override
        returns (uint256 used0, uint256 used1)
    {
        _validatePlan(plan);
        return _previewDeposit(amount0Max, amount1Max);
    }

    /// @inheritdoc IPositionAdapter
    function deposit(uint256 amount0Max, uint256 amount1Max, PositionPlan calldata plan)
        external
        override
        onlyVault
        nonReentrant
        returns (uint256 used0, uint256 used1, uint256 liquidity)
    {
        _validatePlan(plan);
        (used0, used1) = _previewDeposit(amount0Max, amount1Max);
        if (used0 == 0 || used1 == 0) return (0, 0, 0);

        IERC20(_TOKEN0).safeTransferFrom(_VAULT, _POOL, used0);
        IERC20(_TOKEN1).safeTransferFrom(_VAULT, _POOL, used1);
        liquidity = _PAIR.mint(address(this));
    }

    /// @inheritdoc IPositionAdapter
    function withdraw(uint256 shares, uint256 totalShares)
        external
        override
        onlyVault
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (shares == 0) return (0, 0);
        if (totalShares == 0 || shares > totalShares) revert InvalidShareSupply();

        uint256 lpBalance = _PAIR.balanceOf(address(this));
        uint256 liquidityToBurn = Math.mulDiv(lpBalance, shares, totalShares);
        if (liquidityToBurn == 0) return (0, 0);

        return _burnLiquidity(liquidityToBurn);
    }

    /// @inheritdoc IPositionAdapter
    function withdrawAll() external override onlyVault nonReentrant returns (uint256 amount0, uint256 amount1) {
        uint256 lpBalance = _PAIR.balanceOf(address(this));
        if (lpBalance == 0) return (0, 0);

        (amount0, amount1) = _burnLiquidity(lpBalance);
        if (_PAIR.balanceOf(address(this)) != 0) revert PositionNotCleared();
    }

    /// @notice Validates that a plan targets this adapter.
    function _validatePlan(PositionPlan calldata plan) internal pure {
        if (plan.targetVenue != VenueType.UNISWAP_V2) {
            revert InvalidPlanVenue(VenueType.UNISWAP_V2, plan.targetVenue);
        }
    }

    /// @notice Calculates deployable token amounts using current reserve equity.
    /// @param amount0Max Maximum token0 amount available from the vault.
    /// @param amount1Max Maximum token1 amount available from the vault.
    /// @return used0 Token0 amount that can be added without exceeding either maximum.
    /// @return used1 Token1 amount that can be added without exceeding either maximum.
    function _previewDeposit(uint256 amount0Max, uint256 amount1Max)
        internal
        view
        returns (uint256 used0, uint256 used1)
    {
        if (amount0Max == 0 || amount1Max == 0) return (0, 0);

        (uint112 reserve0, uint112 reserve1,) = _PAIR.getReserves();
        uint256 ratio0 = uint256(reserve0);
        uint256 ratio1 = uint256(reserve1);
        if (ratio0 == 0 || ratio1 == 0) return (0, 0);

        if (_productLessThanOrEqual(amount0Max, ratio1, amount1Max, ratio0)) {
            used0 = amount0Max;
            used1 = Math.mulDiv(amount0Max, ratio1, ratio0);
        } else {
            used1 = amount1Max;
            used0 = Math.mulDiv(amount1Max, ratio0, ratio1);
        }
    }

    /// @notice Burns pair liquidity and measures the vault's actual token balance increases.
    /// @param liquidityToBurn Number of LP Token raw units to burn.
    /// @return amount0 Actual token0 amount received by the vault.
    /// @return amount1 Actual token1 amount received by the vault.
    function _burnLiquidity(uint256 liquidityToBurn) internal returns (uint256 amount0, uint256 amount1) {
        uint256 balance0Before = IERC20(_TOKEN0).balanceOf(_VAULT);
        uint256 balance1Before = IERC20(_TOKEN1).balanceOf(_VAULT);

        IERC20(_POOL).safeTransfer(_POOL, liquidityToBurn);
        _PAIR.burn(_VAULT);

        amount0 = IERC20(_TOKEN0).balanceOf(_VAULT) - balance0Before;
        amount1 = IERC20(_TOKEN1).balanceOf(_VAULT) - balance1Before;
    }

    /// @notice Compares two 512-bit products without overflowing uint256.
    /// @param a Left factor of the first product.
    /// @param b Right factor of the first product.
    /// @param c Left factor of the second product.
    /// @param d Right factor of the second product.
    /// @return result Whether `a * b <= c * d`.
    function _productLessThanOrEqual(uint256 a, uint256 b, uint256 c, uint256 d) internal pure returns (bool result) {
        (uint256 high0, uint256 low0) = Math.mul512(a, b);
        (uint256 high1, uint256 low1) = Math.mul512(c, d);
        return high0 < high1 || (high0 == high1 && low0 <= low1);
    }
}
