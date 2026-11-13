// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PositionAdapterConfig, PositionSnapshot} from "./AdapterTypes.sol";
import {PositionPlan, VenueType} from "../core/VaultTypes.sol";
import {IPositionAdapter} from "../interfaces/IPositionAdapter.sol";
import {IUniswapV3Factory, INonfungiblePositionManager, IUniswapV3Pool} from "../interfaces/IUniswapV3External.sol";
import {PriceMath} from "../libraries/PriceMath.sol";

/// @title Uniswap V3 Position Adapter
/// @notice Manages one vault's liquidity in one immutable Uniswap V3 pool and NFT position.
contract UniswapV3Adapter is IPositionAdapter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant Q96 = 0x1000000000000000000000000;
    uint256 private constant Q128 = 0x100000000000000000000000000000000;
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = 887272;

    address private immutable _VAULT;
    VenueType private immutable _VENUE;
    address private immutable _POOL_ADDRESS;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    address private immutable _POSITION_MANAGER_ADDRESS;
    uint24 private immutable _FEE_TIER;
    int24 private immutable _TICK_SPACING;

    IUniswapV3Pool private immutable _POOL;
    INonfungiblePositionManager private immutable _POSITION_MANAGER;

    uint256 private _positionId;

    struct PositionData {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    /// @notice Restricts asset-mutating operations to the immutable vault.
    modifier onlyVault() {
        _checkVaultCaller();
        _;
    }

    function _checkVaultCaller() internal view {
        if (msg.sender != _VAULT) revert NotVaultCaller();
    }

    /// @notice Verifies that an operation left an adapter token balance at its recorded baseline.
    function _validateBalanceRestored(address token, uint256 expected) internal view {
        uint256 actual = IERC20(token).balanceOf(address(this));
        if (actual != expected) revert AdapterBalanceMismatch(token, expected, actual);
    }

    /// @notice Deploys an adapter bound to one vault, V3 pool, and position manager.
    /// @param config Immutable vault, venue, pool, expected-factory, and position-manager configuration.
    constructor(PositionAdapterConfig memory config) {
        if (
            config.vault == address(0) || config.pool == address(0) || config.factory == address(0)
                || config.positionManager == address(0) || !_isV3Venue(config.venue) || config.pool.code.length == 0
                || config.factory.code.length == 0 || config.positionManager.code.length == 0
        ) {
            revert InvalidAdapterConfiguration();
        }

        IUniswapV3Pool pool_ = IUniswapV3Pool(config.pool);
        INonfungiblePositionManager positionManager_ = INonfungiblePositionManager(config.positionManager);

        address poolToken0;
        address poolToken1;
        address poolFactory;
        address managerFactory;
        uint24 poolFee;
        int24 poolTickSpacing;

        try pool_.token0() returns (address value) {
            poolToken0 = value;
        } catch {
            revert InvalidPoolBinding();
        }
        try pool_.token1() returns (address value) {
            poolToken1 = value;
        } catch {
            revert InvalidPoolBinding();
        }

        if (
            poolToken0 == address(0) || poolToken1 == address(0) || poolToken0 == poolToken1 || poolToken0 >= poolToken1
        ) {
            revert InvalidTokenOrder();
        }
        if (poolToken0.code.length == 0 || poolToken1.code.length == 0) revert InvalidAssetPair();

        try pool_.factory() returns (address value) {
            poolFactory = value;
        } catch {
            revert InvalidPoolBinding();
        }
        try pool_.fee() returns (uint24 value) {
            poolFee = value;
        } catch {
            revert InvalidPoolBinding();
        }
        try pool_.tickSpacing() returns (int24 value) {
            poolTickSpacing = value;
        } catch {
            revert InvalidTickSpacing();
        }
        try positionManager_.factory() returns (address value) {
            managerFactory = value;
        } catch {
            revert InvalidPoolBinding();
        }

        if (poolFactory != config.factory || managerFactory != config.factory || poolFee == 0) {
            revert InvalidPoolBinding();
        }
        if (poolTickSpacing <= 0) revert InvalidTickSpacing();

        address registeredPool;
        try IUniswapV3Factory(config.factory).getPool(poolToken0, poolToken1, poolFee) returns (address value) {
            registeredPool = value;
        } catch {
            revert InvalidPoolBinding();
        }
        if (registeredPool != config.pool) revert InvalidPoolBinding();

        _VAULT = config.vault;
        _VENUE = config.venue;
        _POOL_ADDRESS = config.pool;
        _TOKEN0 = poolToken0;
        _TOKEN1 = poolToken1;
        _POSITION_MANAGER_ADDRESS = config.positionManager;
        _FEE_TIER = poolFee;
        _TICK_SPACING = poolTickSpacing;
        _POOL = pool_;
        _POSITION_MANAGER = positionManager_;
    }

    /// @inheritdoc IPositionAdapter
    function vault() external view override returns (address vaultAddress) {
        return _VAULT;
    }

    /// @inheritdoc IPositionAdapter
    function venue() external view override returns (VenueType venueType) {
        return _VENUE;
    }

    /// @inheritdoc IPositionAdapter
    function pool() external view override returns (address poolAddress) {
        return _POOL_ADDRESS;
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
    function feeTier() external view override returns (uint24 fee) {
        return _FEE_TIER;
    }

    /// @inheritdoc IPositionAdapter
    function tickSpacing() external view override returns (int24 spacing) {
        return _TICK_SPACING;
    }

    /// @notice Returns the immutable NonfungiblePositionManager binding.
    function positionManager() external view returns (address manager) {
        return _POSITION_MANAGER_ADDRESS;
    }

    /// @notice Returns the currently managed NFT token ID, or zero when no NFT exists.
    function positionId() external view returns (uint256 tokenId) {
        return _positionId;
    }

    /// @inheritdoc IPositionAdapter
    function snapshot() external view override returns (PositionSnapshot memory position) {
        return _snapshot();
    }

    /// @inheritdoc IPositionAdapter
    function syncFees() external override onlyVault nonReentrant returns (uint256 fee0, uint256 fee1) {
        uint256 tokenId = _positionId;
        if (tokenId == 0) return (0, 0);

        uint256 balance0Before = IERC20(_TOKEN0).balanceOf(_VAULT);
        uint256 balance1Before = IERC20(_TOKEN1).balanceOf(_VAULT);

        _collectAll(tokenId);

        fee0 = IERC20(_TOKEN0).balanceOf(_VAULT) - balance0Before;
        fee1 = IERC20(_TOKEN1).balanceOf(_VAULT) - balance1Before;

        PositionSnapshot memory afterSnapshot = _snapshot();
        if (afterSnapshot.claimableFee0 != 0 || afterSnapshot.claimableFee1 != 0) {
            revert FeeCollectionIncomplete();
        }
    }

    /// @inheritdoc IPositionAdapter
    function previewDeposit(uint256 amount0Max, uint256 amount1Max, PositionPlan calldata plan)
        external
        view
        override
        returns (uint256 used0, uint256 used1)
    {
        return _previewDeposit(amount0Max, amount1Max, plan);
    }

    /// @inheritdoc IPositionAdapter
    function deposit(uint256 amount0Max, uint256 amount1Max, PositionPlan calldata plan)
        external
        override
        onlyVault
        nonReentrant
        returns (uint256 used0, uint256 used1, uint256 liquidity)
    {
        (uint256 desired0, uint256 desired1) = _previewDeposit(amount0Max, amount1Max, plan);
        if (desired0 == 0 && desired1 == 0) return (0, 0, 0);

        uint256 tokenId = _positionId;
        if (tokenId != 0) {
            PositionData memory current = _readPosition(tokenId);
            if (current.liquidity != 0) {
                if (current.tickLower != plan.tickLower || current.tickUpper != plan.tickUpper) {
                    revert ActivePositionExists();
                }
            } else {
                if (current.tokensOwed0 != 0 || current.tokensOwed1 != 0) revert ActivePositionExists();
                _POSITION_MANAGER.burn(tokenId);
                _positionId = 0;
                tokenId = 0;
            }
        }

        uint256 balance0Before = IERC20(_TOKEN0).balanceOf(address(this));
        uint256 balance1Before = IERC20(_TOKEN1).balanceOf(address(this));

        if (desired0 != 0) {
            IERC20(_TOKEN0).safeTransferFrom(_VAULT, address(this), desired0);
            IERC20(_TOKEN0).forceApprove(_POSITION_MANAGER_ADDRESS, desired0);
        }
        if (desired1 != 0) {
            IERC20(_TOKEN1).safeTransferFrom(_VAULT, address(this), desired1);
            IERC20(_TOKEN1).forceApprove(_POSITION_MANAGER_ADDRESS, desired1);
        }

        if (tokenId == 0) {
            uint128 liquidityCreated;
            (tokenId, liquidityCreated, used0, used1) = _POSITION_MANAGER.mint(
                INonfungiblePositionManager.MintParams({
                    token0: _TOKEN0,
                    token1: _TOKEN1,
                    fee: _FEE_TIER,
                    tickLower: plan.tickLower,
                    tickUpper: plan.tickUpper,
                    amount0Desired: desired0,
                    amount1Desired: desired1,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp
                })
            );
            liquidity = liquidityCreated;
            _positionId = tokenId;
            _validateManagedPosition(tokenId, plan.tickLower, plan.tickUpper);
        } else {
            uint128 liquidityAdded;
            (liquidityAdded, used0, used1) = _POSITION_MANAGER.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: desired0,
                    amount1Desired: desired1,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );
            liquidity = liquidityAdded;
        }

        if (desired0 != 0) IERC20(_TOKEN0).forceApprove(_POSITION_MANAGER_ADDRESS, 0);
        if (desired1 != 0) IERC20(_TOKEN1).forceApprove(_POSITION_MANAGER_ADDRESS, 0);

        if (used0 > desired0) revert UsedAmountExceedsDesired(_TOKEN0, desired0, used0);
        if (used1 > desired1) revert UsedAmountExceedsDesired(_TOKEN1, desired1, used1);
        if (desired0 > used0) IERC20(_TOKEN0).safeTransfer(_VAULT, desired0 - used0);
        if (desired1 > used1) IERC20(_TOKEN1).safeTransfer(_VAULT, desired1 - used1);

        _validateBalanceRestored(_TOKEN0, balance0Before);
        _validateBalanceRestored(_TOKEN1, balance1Before);
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

        uint256 tokenId = _positionId;
        if (tokenId == 0) return (0, 0);

        PositionData memory current = _readPosition(tokenId);
        uint256 liquidityToRemove = Math.mulDiv(uint256(current.liquidity), shares, totalShares);
        if (liquidityToRemove == 0) return (0, 0);

        // The pro-rata result cannot exceed the uint128 source liquidity because shares <= totalShares.
        // forge-lint: disable-next-line(unsafe-typecast)
        return _decreaseAndCollect(tokenId, uint128(liquidityToRemove));
    }

    /// @inheritdoc IPositionAdapter
    function withdrawAll() external override onlyVault nonReentrant returns (uint256 amount0, uint256 amount1) {
        uint256 tokenId = _positionId;
        if (tokenId == 0) return (0, 0);

        PositionData memory current = _readPosition(tokenId);
        (amount0, amount1) = _decreaseAndCollect(tokenId, current.liquidity);

        _POSITION_MANAGER.burn(tokenId);
        _positionId = 0;
    }

    /// @notice Returns the normalized current V3 position and all accrued fees.
    function _snapshot() internal view returns (PositionSnapshot memory position) {
        position.venue = _VENUE;
        position.adapter = address(this);

        uint256 tokenId = _positionId;
        if (tokenId == 0) return position;

        PositionData memory current = _readPosition(tokenId);
        position.positionId = tokenId;
        position.tickLower = current.tickLower;
        position.tickUpper = current.tickUpper;
        position.liquidity = current.liquidity;

        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = _POOL.slot0();
        (position.principal0, position.principal1) =
            _amountsForLiquidity(sqrtPriceX96, current.tickLower, current.tickUpper, current.liquidity, false);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            _feeGrowthInside(current.tickLower, current.tickUpper, currentTick);

        uint256 feeGrowthDelta0;
        uint256 feeGrowthDelta1;
        unchecked {
            feeGrowthDelta0 = feeGrowthInside0X128 - current.feeGrowthInside0LastX128;
            feeGrowthDelta1 = feeGrowthInside1X128 - current.feeGrowthInside1LastX128;
        }

        position.claimableFee0 =
            uint256(current.tokensOwed0) + Math.mulDiv(feeGrowthDelta0, uint256(current.liquidity), Q128);
        position.claimableFee1 =
            uint256(current.tokensOwed1) + Math.mulDiv(feeGrowthDelta1, uint256(current.liquidity), Q128);
        position.amount0 = position.principal0 + position.claimableFee0;
        position.amount1 = position.principal1 + position.claimableFee1;
    }

    /// @notice Calculates exact token amounts consumed by V3 liquidity math at the current pool price.
    function _previewDeposit(uint256 amount0Max, uint256 amount1Max, PositionPlan calldata plan)
        internal
        view
        returns (uint256 used0, uint256 used1)
    {
        _validatePlan(plan);
        if (amount0Max == 0 && amount1Max == 0) return (0, 0);

        (uint160 sqrtPriceX96,,,,,,) = _POOL.slot0();
        uint160 sqrtLowerX96 = PriceMath.sqrtRatioAtTick(plan.tickLower);
        uint160 sqrtUpperX96 = PriceMath.sqrtRatioAtTick(plan.tickUpper);
        uint128 liquidity = _liquidityForAmounts(sqrtPriceX96, sqrtLowerX96, sqrtUpperX96, amount0Max, amount1Max);
        if (liquidity == 0) return (0, 0);

        (used0, used1) = _amountsForLiquidityAtPrices(sqrtPriceX96, sqrtLowerX96, sqrtUpperX96, liquidity, true);
    }

    /// @notice Collects all owed tokens after optionally removing nonzero liquidity.
    function _decreaseAndCollect(uint256 tokenId, uint128 liquidityToRemove)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 balance0Before = IERC20(_TOKEN0).balanceOf(_VAULT);
        uint256 balance1Before = IERC20(_TOKEN1).balanceOf(_VAULT);

        if (liquidityToRemove != 0) _decreaseLiquidity(tokenId, liquidityToRemove);
        _collectAll(tokenId);

        amount0 = IERC20(_TOKEN0).balanceOf(_VAULT) - balance0Before;
        amount1 = IERC20(_TOKEN1).balanceOf(_VAULT) - balance1Before;
    }

    /// @notice Removes a specified number of native V3 liquidity units.
    function _decreaseLiquidity(uint256 tokenId, uint128 liquidityToRemove) internal {
        _POSITION_MANAGER.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId, liquidity: liquidityToRemove, amount0Min: 0, amount1Min: 0, deadline: block.timestamp
            })
        );
    }

    /// @notice Pokes current fee growth and collects all manager-recorded amounts to the vault.
    /// @dev The canonical position manager performs the zero-liquidity pool burn inside `collect`.
    function _collectAll(uint256 tokenId) internal {
        _POSITION_MANAGER.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId, recipient: _VAULT, amount0Max: type(uint128).max, amount1Max: type(uint128).max
            })
        );
    }

    /// @notice Reads and validates the manager's accounting record for the current NFT.
    function _readPosition(uint256 tokenId) internal view returns (PositionData memory current) {
        (
            ,,
            current.token0,
            current.token1,
            current.fee,
            current.tickLower,
            current.tickUpper,
            current.liquidity,
            current.feeGrowthInside0LastX128,
            current.feeGrowthInside1LastX128,
            current.tokensOwed0,
            current.tokensOwed1
        ) = _POSITION_MANAGER.positions(tokenId);

        if (current.token0 != _TOKEN0 || current.token1 != _TOKEN1 || current.fee != _FEE_TIER) {
            revert InvalidManagedPosition();
        }
        _validateRange(current.tickLower, current.tickUpper);
    }

    /// @notice Validates a newly minted NFT's ownership and immutable pool/range fields.
    function _validateManagedPosition(uint256 tokenId, int24 expectedLower, int24 expectedUpper) internal view {
        if (tokenId == 0 || _POSITION_MANAGER.ownerOf(tokenId) != address(this)) revert InvalidManagedPosition();
        PositionData memory current = _readPosition(tokenId);
        if (current.tickLower != expectedLower || current.tickUpper != expectedUpper || current.liquidity == 0) {
            revert InvalidManagedPosition();
        }
    }

    /// @notice Validates that a plan targets this adapter and contains a usable aligned V3 range.
    function _validatePlan(PositionPlan calldata plan) internal view {
        if (plan.targetVenue != _VENUE) revert InvalidPlanVenue(_VENUE, plan.targetVenue);
        _validateRange(plan.tickLower, plan.tickUpper);
    }

    /// @notice Validates V3 tick bounds, ordering, and pool-spacing alignment.
    function _validateRange(int24 tickLower, int24 tickUpper) internal view {
        if (
            tickLower < MIN_TICK || tickUpper > MAX_TICK || tickLower >= tickUpper || tickLower % _TICK_SPACING != 0
                || tickUpper % _TICK_SPACING != 0
        ) {
            revert InvalidTickRange();
        }
    }

    /// @notice Computes current fee growth inside a position range.
    function _feeGrowthInside(int24 tickLower, int24 tickUpper, int24 currentTick)
        internal
        view
        returns (uint256 inside0X128, uint256 inside1X128)
    {
        uint256 global0X128 = _POOL.feeGrowthGlobal0X128();
        uint256 global1X128 = _POOL.feeGrowthGlobal1X128();
        (,, uint256 lowerOutside0X128, uint256 lowerOutside1X128,,,,) = _POOL.ticks(tickLower);
        (,, uint256 upperOutside0X128, uint256 upperOutside1X128,,,,) = _POOL.ticks(tickUpper);

        uint256 below0X128;
        uint256 below1X128;
        uint256 above0X128;
        uint256 above1X128;
        unchecked {
            if (currentTick >= tickLower) {
                below0X128 = lowerOutside0X128;
                below1X128 = lowerOutside1X128;
            } else {
                below0X128 = global0X128 - lowerOutside0X128;
                below1X128 = global1X128 - lowerOutside1X128;
            }

            if (currentTick < tickUpper) {
                above0X128 = upperOutside0X128;
                above1X128 = upperOutside1X128;
            } else {
                above0X128 = global0X128 - upperOutside0X128;
                above1X128 = global1X128 - upperOutside1X128;
            }

            inside0X128 = global0X128 - below0X128 - above0X128;
            inside1X128 = global1X128 - below1X128 - above1X128;
        }
    }

    /// @notice Computes liquidity obtainable from bounded token amounts at the current price.
    function _liquidityForAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        uint256 liquidity256;

        if (sqrtPriceX96 <= sqrtLowerX96) {
            liquidity256 = _liquidityForAmount0(sqrtLowerX96, sqrtUpperX96, amount0);
        } else if (sqrtPriceX96 < sqrtUpperX96) {
            uint256 liquidity0 = _liquidityForAmount0(sqrtPriceX96, sqrtUpperX96, amount0);
            uint256 liquidity1 = _liquidityForAmount1(sqrtLowerX96, sqrtPriceX96, amount1);
            liquidity256 = Math.min(liquidity0, liquidity1);
        } else {
            liquidity256 = _liquidityForAmount1(sqrtLowerX96, sqrtUpperX96, amount1);
        }

        if (liquidity256 > type(uint128).max) revert LiquidityOverflow();
        // The explicit upper-bound check makes this narrowing conversion safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        liquidity = uint128(liquidity256);
    }

    /// @notice Computes token amounts represented by liquidity, optionally rounding inputs upward.
    function _amountsForLiquidity(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        return _amountsForLiquidityAtPrices(
            sqrtPriceX96, PriceMath.sqrtRatioAtTick(tickLower), PriceMath.sqrtRatioAtTick(tickUpper), liquidity, roundUp
        );
    }

    /// @dev Reuses validated range prices; preserves input-up/principal-down rounding.
    function _amountsForLiquidityAtPrices(
        uint160 sqrtPriceX96,
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtPriceX96 <= sqrtLowerX96) {
            amount0 = _amount0ForLiquidity(sqrtLowerX96, sqrtUpperX96, liquidity, roundUp);
        } else if (sqrtPriceX96 < sqrtUpperX96) {
            amount0 = _amount0ForLiquidity(sqrtPriceX96, sqrtUpperX96, liquidity, roundUp);
            amount1 = _amount1ForLiquidity(sqrtLowerX96, sqrtPriceX96, liquidity, roundUp);
        } else {
            amount1 = _amount1ForLiquidity(sqrtLowerX96, sqrtUpperX96, liquidity, roundUp);
        }
    }

    function _liquidityForAmount0(uint160 sqrtA, uint160 sqrtB, uint256 amount0) internal pure returns (uint256) {
        if (amount0 == 0) return 0;
        uint256 intermediate = Math.mulDiv(uint256(sqrtA), uint256(sqrtB), Q96);
        return Math.mulDiv(amount0, intermediate, uint256(sqrtB) - uint256(sqrtA));
    }

    function _liquidityForAmount1(uint160 sqrtA, uint160 sqrtB, uint256 amount1) internal pure returns (uint256) {
        if (amount1 == 0) return 0;
        return Math.mulDiv(amount1, Q96, uint256(sqrtB) - uint256(sqrtA));
    }

    function _amount0ForLiquidity(uint160 sqrtA, uint160 sqrtB, uint128 liquidity, bool roundUp)
        internal
        pure
        returns (uint256 amount0)
    {
        uint256 numerator = uint256(liquidity) << 96;
        uint256 difference = uint256(sqrtB) - uint256(sqrtA);
        if (roundUp) {
            uint256 first = Math.mulDiv(numerator, difference, uint256(sqrtB), Math.Rounding.Ceil);
            amount0 = Math.ceilDiv(first, uint256(sqrtA));
        } else {
            amount0 = Math.mulDiv(numerator, difference, uint256(sqrtB)) / uint256(sqrtA);
        }
    }

    function _amount1ForLiquidity(uint160 sqrtA, uint160 sqrtB, uint128 liquidity, bool roundUp)
        internal
        pure
        returns (uint256 amount1)
    {
        Math.Rounding rounding = roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor;
        amount1 = Math.mulDiv(uint256(liquidity), uint256(sqrtB) - uint256(sqrtA), Q96, rounding);
    }

    function _isV3Venue(VenueType venueType) internal pure returns (bool) {
        return venueType == VenueType.UNISWAP_V3_LOW_FEE || venueType == VenueType.UNISWAP_V3_HIGH_FEE;
    }
}
