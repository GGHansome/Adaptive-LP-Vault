// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MockV2ERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockV2Factory {
    mapping(address tokenA => mapping(address tokenB => address pair)) public getPair;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        MockV2Pair deployed = new MockV2Pair(token0, token1, address(this));
        pair = address(deployed);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
    }

    function registerPair(address tokenA, address tokenB, address pair) external {
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
    }
}

contract MockV2Pair is ERC20 {
    using SafeERC20 for IERC20;

    address private immutable _FACTORY;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;

    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32 private _blockTimestampLast;

    bool private _overrideMintLiquidity;
    uint256 private _reportedMintLiquidity;

    address private _reentryTarget;
    bytes private _reentryData;
    bool public lastReentrySucceeded;
    bytes4 public lastReentryRevertSelector;

    constructor(address token0_, address token1_, address factory_) ERC20("Mock V2 LP", "MV2LP") {
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _FACTORY = factory_;
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

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    function mint(address to) external returns (uint256 liquidity) {
        _attemptReentry();

        uint256 balance0 = IERC20(_TOKEN0).balanceOf(address(this));
        uint256 balance1 = IERC20(_TOKEN1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;
        uint256 supply = totalSupply();

        if (supply == 0) {
            liquidity = Math.sqrt(amount0 * amount1);
        } else {
            liquidity = Math.min(Math.mulDiv(amount0, supply, _reserve0), Math.mulDiv(amount1, supply, _reserve1));
        }
        require(liquidity != 0, "INSUFFICIENT_LIQUIDITY_MINTED");

        _mint(to, liquidity);
        _updateReserves(balance0, balance1);
        if (_overrideMintLiquidity) liquidity = _reportedMintLiquidity;
    }

    function setReportedMintLiquidity(uint256 liquidity) external {
        _overrideMintLiquidity = true;
        _reportedMintLiquidity = liquidity;
    }

    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        uint256 liquidity = balanceOf(address(this));
        uint256 supply = totalSupply();
        uint256 balance0 = IERC20(_TOKEN0).balanceOf(address(this));
        uint256 balance1 = IERC20(_TOKEN1).balanceOf(address(this));

        amount0 = Math.mulDiv(liquidity, balance0, supply);
        amount1 = Math.mulDiv(liquidity, balance1, supply);
        require(amount0 != 0 && amount1 != 0, "INSUFFICIENT_LIQUIDITY_BURNED");

        _burn(address(this), liquidity);
        IERC20(_TOKEN0).safeTransfer(to, amount0);
        IERC20(_TOKEN1).safeTransfer(to, amount1);
        _updateReserves(IERC20(_TOKEN0).balanceOf(address(this)), IERC20(_TOKEN1).balanceOf(address(this)));
    }

    function armReentry(address target, bytes calldata data) external {
        _reentryTarget = target;
        _reentryData = data;
    }

    function sync() external {
        _updateReserves(IERC20(_TOKEN0).balanceOf(address(this)), IERC20(_TOKEN1).balanceOf(address(this)));
    }

    function _attemptReentry() internal {
        address target = _reentryTarget;
        if (target == address(0)) return;

        bytes memory data = _reentryData;
        delete _reentryTarget;
        delete _reentryData;

        (bool success, bytes memory returnData) = target.call(data);
        lastReentrySucceeded = success;
        if (!success && returnData.length >= 4) {
            bytes4 revertSelector;
            assembly ("memory-safe") {
                revertSelector := mload(add(returnData, 0x20))
            }
            lastReentryRevertSelector = revertSelector;
        }
    }

    function _updateReserves(uint256 balance0, uint256 balance1) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "RESERVE_OVERFLOW");
        // forge-lint: disable-next-line(unsafe-typecast)
        _reserve0 = uint112(balance0);
        // forge-lint: disable-next-line(unsafe-typecast)
        _reserve1 = uint112(balance1);
        _blockTimestampLast = uint32(block.timestamp);
    }
}
