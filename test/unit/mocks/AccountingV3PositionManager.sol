// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {INonfungiblePositionManager} from "../../../src/interfaces/IUniswapV3External.sol";

/// @dev Deterministic manager boundary double, not an AMM simulation. Moves real ERC20s,
/// tracks native liquidity and owed fees, and deliberately reports untrusted exit amounts.
contract AccountingV3PositionManager {
    struct Position {
        address owner;
        address token0;
        address token1;
        uint24 fee;
        int24 lower;
        int24 upper;
        uint128 liquidity;
        uint256 growth0;
        uint256 growth1;
        uint128 owed0;
        uint128 owed1;
    }

    address public immutable factory;
    mapping(uint256 => Position) public records;
    uint256 public nextId = 1;
    uint128 public addedLiquidity = 10001;
    uint256 public useBps = 5000;
    uint256 public reportExtra0;
    uint256 public reportExtra1;
    uint256 public growth0;
    uint256 public growth1;
    uint128 public lastRemoved;
    uint256 public decreaseCalls;
    uint256 public collectCalls;
    uint256 public burnCalls;
    address public callback;
    bytes public callbackData;
    bool public callbackSucceeded;
    bytes public callbackResult;

    constructor(address factory_) {
        factory = factory_;
    }

    function configureUsage(uint256 bps, uint256 extra0, uint256 extra1) external {
        useBps = bps;
        reportExtra0 = extra0;
        reportExtra1 = extra1;
    }

    function setAccounting(uint256 id, uint128 liquidity, uint256 last0, uint256 last1, uint128 owed0, uint128 owed1)
        external
    {
        Position storage p = records[id];
        p.liquidity = liquidity;
        p.growth0 = last0;
        p.growth1 = last1;
        p.owed0 = owed0;
        p.owed1 = owed1;
    }

    function setGrowth(uint256 value0, uint256 value1) external {
        growth0 = value0;
        growth1 = value1;
    }

    function setCallback(address target, bytes calldata data) external {
        callback = target;
        callbackData = data;
    }

    function positions(uint256 id)
        external
        view
        returns (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128)
    {
        Position memory p = records[id];
        return (
            0,
            address(0),
            p.token0,
            p.token1,
            p.fee,
            p.lower,
            p.upper,
            p.liquidity,
            p.growth0,
            p.growth1,
            p.owed0,
            p.owed1
        );
    }

    function ownerOf(uint256 id) external view returns (address) {
        return records[id].owner;
    }

    function mint(INonfungiblePositionManager.MintParams calldata params)
        external
        payable
        returns (uint256 id, uint128 liquidity, uint256 used0, uint256 used1)
    {
        id = nextId++;
        liquidity = addedLiquidity;
        records[id] = Position(
            params.recipient,
            params.token0,
            params.token1,
            params.fee,
            params.tickLower,
            params.tickUpper,
            liquidity,
            growth0,
            growth1,
            0,
            0
        );
        (used0, used1) = _consume(params.token0, params.token1, params.amount0Desired, params.amount1Desired);
        _callback();
    }

    function increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, uint256 used0, uint256 used1)
    {
        Position storage p = records[params.tokenId];
        p.liquidity += addedLiquidity;
        liquidity = addedLiquidity;
        (used0, used1) = _consume(p.token0, p.token1, params.amount0Desired, params.amount1Desired);
        _callback();
    }

    function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256, uint256)
    {
        ++decreaseCalls;
        lastRemoved = params.liquidity;
        Position storage p = records[params.tokenId];
        _crystallize(p);
        p.liquidity -= params.liquidity;
        // Explicit deterministic payout vector, independent of adapter return-value logic.
        p.owed0 += params.liquidity * 2;
        p.owed1 += params.liquidity * 3;
        _callback();
        return (777, 888);
    }

    function collect(INonfungiblePositionManager.CollectParams calldata params)
        external
        payable
        returns (uint256, uint256)
    {
        ++collectCalls;
        Position storage p = records[params.tokenId];
        _crystallize(p);
        uint128 amount0 = p.owed0;
        uint128 amount1 = p.owed1;
        p.owed0 = 0;
        p.owed1 = 0;
        require(IERC20(p.token0).transfer(params.recipient, amount0));
        require(IERC20(p.token1).transfer(params.recipient, amount1));
        _callback();
        return (999, 1111);
    }

    function burn(uint256 id) external payable {
        Position memory p = records[id];
        require(p.liquidity == 0 && p.owed0 == 0 && p.owed1 == 0, "not empty");
        ++burnCalls;
        delete records[id];
    }

    function _consume(address token0, address token1, uint256 desired0, uint256 desired1)
        private
        returns (uint256 used0, uint256 used1)
    {
        used0 = Math.mulDiv(desired0, useBps, 10000);
        used1 = Math.mulDiv(desired1, useBps, 10000);
        require(IERC20(token0).transferFrom(msg.sender, address(this), used0));
        require(IERC20(token1).transferFrom(msg.sender, address(this), used1));
        used0 += reportExtra0;
        used1 += reportExtra1;
    }

    function _crystallize(Position storage p) private {
        uint256 delta0;
        uint256 delta1;
        unchecked {
            delta0 = growth0 - p.growth0;
            delta1 = growth1 - p.growth1;
        }
        p.owed0 += uint128(Math.mulDiv(delta0, p.liquidity, 1 << 128));
        p.owed1 += uint128(Math.mulDiv(delta1, p.liquidity, 1 << 128));
        p.growth0 = growth0;
        p.growth1 = growth1;
    }

    function _callback() private {
        if (callback != address(0)) {
            (callbackSucceeded, callbackResult) = callback.call(callbackData);
        }
    }
}
