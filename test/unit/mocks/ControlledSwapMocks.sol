// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV3SwapRouter} from "../../../src/interfaces/IUniswapV3External.sol";

contract MockSwapERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockSwapFactory {
    mapping(address tokenA => mapping(address tokenB => mapping(uint24 fee => address pool))) public getPool;

    function registerPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        getPool[tokenA][tokenB][fee] = pool;
        getPool[tokenB][tokenA][fee] = pool;
    }
}

contract MockSwapPool {
    address private immutable _FACTORY;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    uint24 private immutable _FEE;

    constructor(address factory_, address token0_, address token1_, uint24 fee_) {
        _FACTORY = factory_;
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _FEE = fee_;
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
}

contract MockSwapRouter {
    using SafeERC20 for IERC20;

    address private immutable _FACTORY;

    uint256 public amountOut;
    uint256 public reportedAmountOut;
    uint256 public amountToPull;
    uint256 public amountToBurnFromRecipient;
    bool public useCustomPullAmount;
    bool public sendOutputToExecutor;

    address public lastTokenIn;
    address public lastTokenOut;
    uint24 public lastFee;
    address public lastRecipient;
    uint256 public lastDeadline;
    uint256 public lastAmountIn;
    uint256 public lastAmountOutMinimum;
    uint160 public lastSqrtPriceLimitX96;

    constructor(address factory_) {
        _FACTORY = factory_;
    }

    function factory() external view returns (address) {
        return _FACTORY;
    }

    function setResult(uint256 actualAmountOut, uint256 routerReportedAmountOut) external {
        amountOut = actualAmountOut;
        reportedAmountOut = routerReportedAmountOut;
    }

    function setPullAmount(uint256 value) external {
        amountToPull = value;
        useCustomPullAmount = true;
    }

    function setSendOutputToExecutor(bool value) external {
        sendOutputToExecutor = value;
    }

    function setAmountToBurnFromRecipient(uint256 value) external {
        amountToBurnFromRecipient = value;
    }

    function exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256)
    {
        lastTokenIn = params.tokenIn;
        lastTokenOut = params.tokenOut;
        lastFee = params.fee;
        lastRecipient = params.recipient;
        lastDeadline = params.deadline;
        lastAmountIn = params.amountIn;
        lastAmountOutMinimum = params.amountOutMinimum;
        lastSqrtPriceLimitX96 = params.sqrtPriceLimitX96;

        uint256 pullAmount = useCustomPullAmount ? amountToPull : params.amountIn;
        if (pullAmount != 0) IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), pullAmount);

        address recipient = sendOutputToExecutor ? msg.sender : params.recipient;
        if (amountToBurnFromRecipient != 0) {
            MockSwapERC20(params.tokenOut).burn(params.recipient, amountToBurnFromRecipient);
        }
        MockSwapERC20(params.tokenOut).mint(recipient, amountOut);
        return reportedAmountOut;
    }
}
