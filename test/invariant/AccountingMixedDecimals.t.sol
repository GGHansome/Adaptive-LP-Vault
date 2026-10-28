// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccountingInvariantsTest} from "./AccountingInvariants.t.sol";

/// @dev Same stateful ledger with raw-unit prices held at one and heterogeneous token
/// metadata. In particular share decimals must not be confused with token0 decimals.
contract AccountingMixedDecimalsInvariantsTest is AccountingInvariantsTest {
    function _tokenDecimals() internal pure override returns (uint8, uint8) {
        return (6, 18);
    }
}
