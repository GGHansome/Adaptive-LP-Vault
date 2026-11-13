// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PositionPlan} from "../../../src/core/VaultTypes.sol";
import {VaultStrategyMath} from "../../../src/libraries/VaultStrategyMath.sol";

/// @notice Exercises the same external-library call used by the vault, without its storage or dependencies.
contract VaultStrategyMathHarness {
    function getPlan(VaultStrategyMath.PlanInputs memory input) external pure returns (PositionPlan memory) {
        return VaultStrategyMath.getPlan(input);
    }
}
