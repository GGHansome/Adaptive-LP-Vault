// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultControl} from "../../../src/control/VaultControl.sol";
import {VenueType} from "../../../src/core/VaultTypes.sol";
import {DonationV3Adapter} from "./DonationMocks.sol";

/// @dev Disables the target during exit to verify that cached addresses never replace the entry-status gate.
contract ExitDisablingAdapter is DonationV3Adapter {
    VaultControl private immutable _control;

    constructor(address vault_, address pool_, address token0_, address token1_, VaultControl control_)
        DonationV3Adapter(vault_, pool_, token0_, token1_, VenueType.UNISWAP_V3_LOW_FEE)
    {
        _control = control_;
    }

    function withdrawAll() external override returns (uint256 amount0, uint256 amount1) {
        require(msg.sender == vault);
        amount0 = _position.amount0;
        amount1 = _position.amount1;
        delete _position;
        require(IERC20(token0).transfer(vault, amount0));
        require(IERC20(token1).transfer(vault, amount1));
        _control.setAdapterEnabled(VenueType.UNISWAP_V3_HIGH_FEE, false);
    }
}

/// @dev Adds real fee transfers to the stateful V3 stand-in; no pool math is modeled here.
contract FeeDonationV3Adapter is DonationV3Adapter {
    constructor(address vault_, address pool_, address token0_, address token1_, VenueType venue_)
        DonationV3Adapter(vault_, pool_, token0_, token1_, venue_)
    {}

    function accrueFees(uint256 fee0, uint256 fee1) external {
        _position.claimableFee0 += fee0;
        _position.claimableFee1 += fee1;
        _position.amount0 += fee0;
        _position.amount1 += fee1;
    }

    function syncFees() external override returns (uint256 fee0, uint256 fee1) {
        require(msg.sender == vault);
        fee0 = _position.claimableFee0;
        fee1 = _position.claimableFee1;
        _position.claimableFee0 = 0;
        _position.claimableFee1 = 0;
        _position.amount0 = _position.principal0;
        _position.amount1 = _position.principal1;
        if (fee0 != 0) require(IERC20(token0).transfer(vault, fee0));
        if (fee1 != 0) require(IERC20(token1).transfer(vault, fee1));
    }
}
