// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PositionSnapshot} from "../../../src/adapters/AdapterTypes.sol";
import {PositionPlan, VenueType} from "../../../src/core/VaultTypes.sol";
import {IUniswapV3SwapRouter} from "../../../src/interfaces/IUniswapV3External.sol";

/// @dev Stateful V3 stand-in. Real V2 adapter/pair balances and real vault/executor flows stay under test.
contract DonationV3Adapter {
    address public immutable vault;
    address public immutable pool;
    address public immutable token0;
    address public immutable token1;
    VenueType public immutable venue;
    uint24 public immutable feeTier;
    int24 public immutable tickSpacing;
    PositionSnapshot internal _position;

    constructor(address vault_, address pool_, address token0_, address token1_, VenueType venue_) {
        vault = vault_;
        pool = pool_;
        token0 = token0_;
        token1 = token1_;
        venue = venue_;
        feeTier = venue_ == VenueType.UNISWAP_V3_LOW_FEE ? 500 : 3000;
        tickSpacing = venue_ == VenueType.UNISWAP_V3_LOW_FEE ? int24(10) : int24(60);
    }

    function snapshot() external view returns (PositionSnapshot memory) {
        return _position;
    }

    function syncFees() external virtual returns (uint256, uint256) {
        return (0, 0);
    }

    function previewDeposit(uint256 amount0, uint256 amount1, PositionPlan calldata)
        external
        pure
        returns (uint256, uint256)
    {
        return (amount0, amount1);
    }

    function deposit(uint256 amount0, uint256 amount1, PositionPlan calldata plan)
        external
        returns (uint256, uint256, uint256)
    {
        require(msg.sender == vault);
        require(IERC20(token0).transferFrom(vault, address(this), amount0));
        require(IERC20(token1).transferFrom(vault, address(this), amount1));
        _position.venue = venue;
        _position.adapter = address(this);
        _position.positionId = 1;
        _position.tickLower = plan.tickLower;
        _position.tickUpper = plan.tickUpper;
        _position.liquidity += amount0 + amount1;
        _position.principal0 += amount0;
        _position.principal1 += amount1;
        _position.amount0 = _position.principal0;
        _position.amount1 = _position.principal1;
        return (amount0, amount1, amount0 + amount1);
    }

    function withdraw(uint256 shares, uint256 supply) external returns (uint256 amount0, uint256 amount1) {
        require(msg.sender == vault);
        amount0 = Math.mulDiv(_position.amount0, shares, supply);
        amount1 = Math.mulDiv(_position.amount1, shares, supply);
        _position.principal0 -= amount0;
        _position.principal1 -= amount1;
        _position.amount0 -= amount0;
        _position.amount1 -= amount1;
        _position.liquidity = _position.amount0 + _position.amount1;
        require(IERC20(token0).transfer(vault, amount0));
        require(IERC20(token1).transfer(vault, amount1));
    }

    function withdrawAll() external virtual returns (uint256 amount0, uint256 amount1) {
        require(msg.sender == vault);
        amount0 = _position.amount0;
        amount1 = _position.amount1;
        delete _position;
        require(IERC20(token0).transfer(vault, amount0));
        require(IERC20(token1).transfer(vault, amount1));
    }
}

contract DonationRouter {
    address public immutable factory;
    uint256 public outputBps = 10_000;
    uint256 public outputReduction;

    constructor(address factory_) {
        factory = factory_;
    }

    function setOutputBps(uint256 bps) external {
        outputBps = bps;
    }

    function setOutputReduction(uint256 amount) external {
        outputReduction = amount;
    }

    function exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut)
    {
        require(IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn));
        amountOut = Math.mulDiv(params.amountIn, outputBps, 10_000) - outputReduction;
        require(IERC20(params.tokenOut).transfer(params.recipient, amountOut));
    }
}
