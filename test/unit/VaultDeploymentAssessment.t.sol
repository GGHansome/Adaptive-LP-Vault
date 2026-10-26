// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DeploymentAssessment, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {VaultStrategyMath} from "../../src/libraries/VaultStrategyMath.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";

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

contract VaultDeploymentAssessmentTest is Test {
    DeploymentAssessmentHarness private harness;

    function setUp() public {
        harness = new DeploymentAssessmentHarness();
    }

    function test_assessmentCallsLinkedLibraryAndPreservesQueryArguments() public {
        VaultStrategyMath.AssessmentInputs memory input = _input(1000, 1000);
        _mockPreviewAndQuotes(input, 900, 1000, 1);
        vm.expectCall(
            address(VaultStrategyMath), abi.encodeWithSelector(VaultStrategyMath.assessDeployment.selector, input)
        );
        vm.expectCall(
            input.adapter,
            abi.encodeCall(IPositionAdapter.previewDeposit, (input.amount0, input.amount1, input.plan)),
            uint64(1)
        );
        vm.expectCall(
            input.oracle,
            abi.encodeCall(ICanonicalV3Oracle.quoteToken0InToken1, (1000, input.twapTick, false)),
            uint64(1)
        );
        vm.expectCall(
            input.oracle,
            abi.encodeCall(ICanonicalV3Oracle.quoteToken0InToken1, (900, input.twapTick, false)),
            uint64(1)
        );
        DeploymentAssessment memory actual = harness.assess(input);
        assertFalse(actual.requiresSwap);
        assertEq(uint8(actual.direction), uint8(SwapDirection.ZERO_FOR_ONE));
    }

    function test_idleDoesNotQueryZeroAddressDependencies() public view {
        VaultStrategyMath.AssessmentInputs memory input;
        DeploymentAssessment memory actual = harness.assess(input);
        assertFalse(actual.requiresSwap);
        assertEq(uint8(actual.direction), uint8(SwapDirection.NONE));
    }

    function test_zeroNavAndMaximumNavWorkWithinStaticCall() public {
        VaultStrategyMath.AssessmentInputs memory input = _input(0, 0);
        _mockPreviewAndQuotes(input, 0, 0, 1);
        assertTrue(harness.assess(input).requiresSwap);
        input = _input(type(uint256).max, 0);
        input.minDeployBps = 10_000;
        _mockPreviewAndQuotes(input, type(uint256).max, 0, 1);
        (bool success, bytes memory result) = address(harness).staticcall(abi.encodeCall(harness.assess, (input)));
        assertTrue(success);
        DeploymentAssessment memory actual = abi.decode(result, (DeploymentAssessment));
        assertFalse(actual.requiresSwap);
        assertEq(uint8(actual.direction), uint8(SwapDirection.NONE));
    }

    function testFuzz_matchesOriginalResultsAndReverts(
        uint128 amount0,
        uint128 amount1,
        uint128 used0,
        uint128 used1,
        uint128 dust0,
        uint128 dust1,
        uint16 divisorSeed,
        uint16 minimumSeed
    ) public {
        VaultStrategyMath.AssessmentInputs memory input = _input(amount0, amount1);
        input.dust0 = dust0;
        input.dust1 = dust1;
        input.minDeployBps = bound(uint256(minimumSeed), 1, 10_000);
        uint256 divisor = bound(uint256(divisorSeed), 1, 1000);
        _mockPreviewAndQuotes(input, used0, used1, divisor);
        (bool actualSuccess, bytes memory actual) = address(harness).staticcall(abi.encodeCall(harness.assess, (input)));
        (bool expectedSuccess, bytes memory expected) =
            address(harness).staticcall(abi.encodeCall(harness.referenceAssessment, (input, used0, used1, divisor)));
        assertEq(actualSuccess, expectedSuccess);
        assertEq(actual, expected);
    }

    function testFuzz_validPreviewsMatchOriginalCalculation(
        uint128 amount0,
        uint128 amount1,
        uint128 usedSeed,
        bool excessToken0,
        uint16 divisorSeed,
        uint16 minimumSeed
    ) public {
        VaultStrategyMath.AssessmentInputs memory input = _input(amount0, amount1);
        input.minDeployBps = bound(uint256(minimumSeed), 1, 10_000);
        uint256 used0 = excessToken0 ? bound(uint256(usedSeed), 0, amount0) : amount0;
        uint256 used1 = excessToken0 ? amount1 : bound(uint256(usedSeed), 0, amount1);
        uint256 divisor = bound(uint256(divisorSeed), 1, 1000);
        _mockPreviewAndQuotes(input, used0, used1, divisor);
        DeploymentAssessment memory actual = harness.assess(input);
        DeploymentAssessment memory expected = harness.referenceAssessment(input, used0, used1, divisor);
        assertEq(actual.requiresSwap, expected.requiresSwap);
        assertEq(uint8(actual.direction), uint8(expected.direction));
    }

    function _input(uint256 amount0, uint256 amount1)
        private
        pure
        returns (VaultStrategyMath.AssessmentInputs memory input)
    {
        input.adapter = address(0xA11);
        input.oracle = address(0xB11);
        input.plan.targetVenue = VenueType.UNISWAP_V2;
        input.amount0 = amount0;
        input.amount1 = amount1;
        input.dust0 = 1;
        input.dust1 = 1;
        input.minDeployBps = 9500;
        input.twapTick = -17;
    }

    function _mockPreviewAndQuotes(
        VaultStrategyMath.AssessmentInputs memory input,
        uint256 used0,
        uint256 used1,
        uint256 divisor
    ) private {
        vm.etch(input.adapter, hex"00");
        vm.etch(input.oracle, hex"00");
        vm.mockCall(
            input.adapter,
            abi.encodeCall(IPositionAdapter.previewDeposit, (input.amount0, input.amount1, input.plan)),
            abi.encode(used0, used1)
        );
        vm.mockCall(
            input.oracle,
            abi.encodeCall(ICanonicalV3Oracle.quoteToken0InToken1, (input.amount0, input.twapTick, false)),
            abi.encode(input.amount0 / divisor)
        );
        vm.mockCall(
            input.oracle,
            abi.encodeCall(ICanonicalV3Oracle.quoteToken0InToken1, (used0, input.twapTick, false)),
            abi.encode(used0 / divisor)
        );
    }
}
