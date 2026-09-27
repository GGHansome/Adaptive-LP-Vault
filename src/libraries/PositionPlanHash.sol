// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PositionPlan} from "../core/VaultTypes.sol";

/// @notice Computes the stable identity of a normalized vault position plan.
library PositionPlanHash {
    /// @notice Hashes every plan field except `planHash` itself using the protocol-defined ABI encoding.
    function compute(PositionPlan memory plan) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(uint8(plan.targetVenue), uint8(plan.marketRegime), plan.tickLower, plan.tickUpper, plan.version)
        );
    }
}
