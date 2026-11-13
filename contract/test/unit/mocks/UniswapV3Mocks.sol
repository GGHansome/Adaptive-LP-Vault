// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {INonfungiblePositionManager} from "../../../src/interfaces/IUniswapV3External.sol";

contract MockV3ERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockV3Factory {
    mapping(address tokenA => mapping(address tokenB => mapping(uint24 fee => address pool))) public getPool;

    function registerPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        getPool[tokenA][tokenB][fee] = pool;
        getPool[tokenB][tokenA][fee] = pool;
    }
}

contract MockV3Pool {
    uint160 private constant Q96 = 0x1000000000000000000000000;

    address private immutable _FACTORY;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    uint24 private immutable _FEE;
    int24 private immutable _TICK_SPACING;

    constructor(address factory_, address token0_, address token1_, uint24 fee_, int24 tickSpacing_) {
        _FACTORY = factory_;
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _FEE = fee_;
        _TICK_SPACING = tickSpacing_;
    }

    function factory() external view returns (address) {
        return _FACTORY;
    }

    function token0() external view returns (address) {
        return _TOKEN0;
    }

    function token1() external view returns (address) {
        return _TOKEN1;
    }

    function fee() external view returns (uint24) {
        return _FEE;
    }

    function tickSpacing() external view returns (int24) {
        return _TICK_SPACING;
    }

    function slot0() external pure returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (Q96, 0, 0, 0, 0, 0, true);
    }

    function feeGrowthGlobal0X128() external pure returns (uint256) {
        return 0;
    }

    function feeGrowthGlobal1X128() external pure returns (uint256) {
        return 0;
    }

    function ticks(int24) external pure returns (uint128, int128, uint256, uint256, int56, uint160, uint32, bool) {
        return (0, 0, 0, 0, 0, 0, 0, false);
    }
}

contract MockV3PositionManager {
    struct MockPosition {
        address owner;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    address private immutable _FACTORY;
    uint256 private _nextTokenId = 1;
    mapping(uint256 tokenId => MockPosition position) private _positions;

    bool public returnWrongOwner;
    bool public leaveFeesOnCollect;
    bool public leaveAssetsOnExit;

    constructor(address factory_) {
        _FACTORY = factory_;
    }

    function factory() external view returns (address) {
        return _FACTORY;
    }

    function setReturnWrongOwner(bool value) external {
        returnWrongOwner = value;
    }

    function setLeaveFeesOnCollect(bool value) external {
        leaveFeesOnCollect = value;
    }

    function setLeaveAssetsOnExit(bool value) external {
        leaveAssetsOnExit = value;
    }

    function setTokensOwed(uint256 tokenId, uint128 amount0, uint128 amount1) external {
        _positions[tokenId].tokensOwed0 = amount0;
        _positions[tokenId].tokensOwed1 = amount1;
    }

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
        )
    {
        MockPosition memory position = _positions[tokenId];
        return (
            0,
            address(0),
            position.token0,
            position.token1,
            position.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            0,
            0,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    function mint(INonfungiblePositionManager.MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        tokenId = _nextTokenId++;
        liquidity = 1;
        _positions[tokenId] = MockPosition({
            owner: params.recipient,
            token0: params.token0,
            token1: params.token1,
            fee: params.fee,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
        return (tokenId, liquidity, 0, 0);
    }

    function increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        return (1, 0, 0);
    }

    function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        MockPosition storage position = _positions[params.tokenId];
        position.liquidity -= params.liquidity;
        if (leaveAssetsOnExit) position.tokensOwed0 = 1;
        return (0, 0);
    }

    function collect(INonfungiblePositionManager.CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        if (!leaveFeesOnCollect && !leaveAssetsOnExit) {
            _positions[params.tokenId].tokensOwed0 = 0;
            _positions[params.tokenId].tokensOwed1 = 0;
        }
        return (0, 0);
    }

    function burn(uint256 tokenId) external payable {
        MockPosition memory position = _positions[tokenId];
        require(position.liquidity == 0 && position.tokensOwed0 == 0 && position.tokensOwed1 == 0, "Not cleared");
        delete _positions[tokenId];
    }

    function ownerOf(uint256 tokenId) external view returns (address owner) {
        if (returnWrongOwner) return address(0xBEEF);
        return _positions[tokenId].owner;
    }
}
