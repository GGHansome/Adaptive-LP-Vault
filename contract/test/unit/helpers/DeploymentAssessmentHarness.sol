// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DeploymentAssessment, VenueType} from "../../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../../src/interfaces/IAdaptiveLPVault.sol";
import {VaultStrategyMath} from "../../../src/libraries/VaultStrategyMath.sol";
import {SwapDirection} from "../../../src/swap/SwapTypes.sol";

contract DeploymentAssessmentHarness {
    function assess(VaultStrategyMath.AssessmentInputs memory input)
        external
        view
        returns (DeploymentAssessment memory)
    {
        return VaultStrategyMath.assessDeployment(input);
    }

    /// @dev Frozen pre-extraction algorithm with deterministic floor-rounded oracle quotes.
    function referenceAssessment(
        VaultStrategyMath.AssessmentInputs memory input,
        uint256 used0,
        uint256 used1,
        uint256 divisor
    ) external pure returns (DeploymentAssessment memory assessment) {
        if (input.plan.targetVenue == VenueType.IDLE) {
            return DeploymentAssessment(false, SwapDirection.NONE);
        }
        if (used0 > input.amount0 || used1 > input.amount1) revert IAdaptiveLPVault.AdapterBalanceMismatch();
        uint256 unused0 = input.amount0 - used0;
        uint256 unused1 = input.amount1 - used1;
        bool excess0 = unused0 > input.dust0;
        bool excess1 = unused1 > input.dust1;
        if (excess0 && excess1) revert IAdaptiveLPVault.InvalidDeploymentPreview();
        uint256 nav = input.amount1 + input.amount0 / divisor;
        uint256 deployed = used1 + used0 / divisor;
        uint256 bps = nav == 0 ? 0 : Math.mulDiv(deployed, 10_000, nav);
        assessment.requiresSwap = nav == 0 || bps < input.minDeployBps;
        assessment.direction =
            excess0 ? SwapDirection.ZERO_FOR_ONE : excess1 ? SwapDirection.ONE_FOR_ZERO : SwapDirection.NONE;
    }
}
