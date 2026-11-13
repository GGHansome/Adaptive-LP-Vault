// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Unrestricted faucet token for isolated Anvil environments only. Never deploy for real assets.
contract LocalToken is ERC20 {
    uint8 private immutable _PRECISION;

    constructor(string memory name_, string memory symbol_, uint8 precision_) ERC20(name_, symbol_) {
        require(block.chainid == 31337, "LOCAL_ONLY");
        _PRECISION = precision_;
    }

    function decimals() public view override returns (uint8) {
        return _PRECISION;
    }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}
