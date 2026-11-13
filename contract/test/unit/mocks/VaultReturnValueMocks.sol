// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VenueType} from "../../../src/core/VaultTypes.sol";
import {SwapDirection, SwapPlan} from "../../../src/swap/SwapTypes.sol";
import {DonationV3Adapter} from "./DonationMocks.sol";
import {MockV2ERC20} from "./UniswapV2Mocks.sol";

/// @dev Transfers real assets but deliberately reports unrelated amounts only on full exit.
contract MisreportingFullExitAdapter is DonationV3Adapter {
    uint256 public exitPayoutBps = 10_000;
    bool public leavePosition;

    constructor(address vault_, address pool_, address token0_, address token1_)
        DonationV3Adapter(vault_, pool_, token0_, token1_, VenueType.UNISWAP_V3_LOW_FEE)
    {}

    function setExitBehavior(uint256 payoutBps, bool leavePosition_) external {
        exitPayoutBps = payoutBps;
        leavePosition = leavePosition_;
    }

    function withdrawAll() external override returns (uint256, uint256) {
        require(msg.sender == vault);
        uint256 amount0 = Math.mulDiv(_position.amount0, exitPayoutBps, 10_000);
        uint256 amount1 = Math.mulDiv(_position.amount1, exitPayoutBps, 10_000);
        if (!leavePosition) delete _position;
        require(IERC20(token0).transfer(vault, amount0));
        require(IERC20(token1).transfer(vault, amount1));
        return (type(uint256).max, 0);
    }
}

/// @dev Replaces only the executor in tests to independently exercise the vault's balance checks.
contract SwapExecutorStub {
    struct Behavior {
        uint256 outputAmount;
        uint256 inputSpent;
        bool refundInput;
        bool retainOutput;
        bool leaveAllowance;
    }

    address public immutable router;
    address private immutable _vault;
    address private immutable _token0;
    address private immutable _token1;
    uint256 private immutable _outputAmount;
    uint256 private immutable _inputSpent;
    bool private immutable _refundInput;
    bool private immutable _retainOutput;
    bool private immutable _leaveAllowance;

    constructor(address vault_, address token0_, address token1_, address router_, Behavior memory behavior) {
        _vault = vault_;
        _token0 = token0_;
        _token1 = token1_;
        router = router_;
        _outputAmount = behavior.outputAmount;
        _inputSpent = behavior.inputSpent;
        _refundInput = behavior.refundInput;
        _retainOutput = behavior.retainOutput;
        _leaveAllowance = behavior.leaveAllowance;
    }

    function executeSwap(SwapPlan calldata plan) external returns (uint256) {
        require(msg.sender == _vault);
        address input = plan.direction == SwapDirection.ZERO_FOR_ONE ? _token0 : _token1;
        address output = plan.direction == SwapDirection.ZERO_FOR_ONE ? _token1 : _token0;
        require(IERC20(input).transfer(router, _inputSpent));
        if (_refundInput) require(IERC20(input).transfer(_vault, plan.amountIn - _inputSpent));
        if (_leaveAllowance) require(IERC20(input).approve(router, 1));
        MockV2ERC20(output).mint(_vault, _outputAmount);
        if (_retainOutput) MockV2ERC20(output).mint(address(this), 1);
        return _outputAmount;
    }
}
