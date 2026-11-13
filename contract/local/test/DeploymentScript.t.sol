// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployAdaptiveLPVault} from "../../script/Deploy.s.sol";
import {VaultStrategyMath} from "../../src/libraries/VaultStrategyMath.sol";
import {PositionPlan, VenueType} from "../../src/core/VaultTypes.sol";
import {PreviewLocalBootstrap} from "../script/PreviewLocalBootstrap.s.sol";

contract BootstrapPreviewHarness is PreviewLocalBootstrap {
    function plan(address planner, VaultStrategyMath.PlanInputs memory input) external returns (PositionPlan memory) {
        return _getPlan(planner, input);
    }
}

contract DeploymentLinkHarness is DeployAdaptiveLPVault {
    function link(bytes memory text, address libraryAddress) external pure returns (bytes memory) {
        return _linkStrategyLibrary(text, libraryAddress);
    }
}

contract DeploymentScriptTest is Test {
    DeploymentLinkHarness private harness;

    function setUp() public {
        harness = new DeploymentLinkHarness();
    }

    function test_linksHexadecimalTextBeforeDecoding() public view {
        address libraryAddress = address(0x1234567890123456789012345678901234567890);
        bytes memory linked = harness.link(bytes("0x60__$aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa$__00"), libraryAddress);
        assertEq(vm.parseBytes(string(linked)), abi.encodePacked(hex"60", libraryAddress, hex"00"));
    }

    function test_linksAllReferences() public view {
        address libraryAddress = address(0x1234567890123456789012345678901234567890);
        bytes memory linked = harness.link(
            bytes("0x__$aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa$____$aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa$__"), libraryAddress
        );
        assertEq(vm.parseBytes(string(linked)), abi.encodePacked(libraryAddress, libraryAddress));
    }

    function test_previewUsesDeployedLibrarySelectorAndCallingConvention() public {
        address planner = vm.deployCode("VaultStrategyMath.sol:VaultStrategyMath");
        VaultStrategyMath.PlanInputs memory input;
        input.oracle.twapTick = 276324;
        input.oracle.spotTick = 276324;
        input.lowSpacing = 10;
        input.highSpacing = 60;
        input.strategy = uint256(30) | (uint256(15) << 24) | (uint256(100) << 48) | (uint256(70) << 72)
            | (uint256(300) << 96) | (uint256(200) << 120) | (uint256(100) << 144) | (uint256(50) << 168)
            | (uint256(1000) << 192);
        BootstrapPreviewHarness preview = new BootstrapPreviewHarness();
        PositionPlan memory plan = preview.plan(planner, input);
        assertEq(uint256(plan.targetVenue), uint256(VenueType.UNISWAP_V3_LOW_FEE));
        assertEq(plan.version, 1);
        assertEq(int256(plan.tickUpper) - int256(plan.tickLower), 2000);
    }

    function test_rejectsArtifactWithoutLibraryReference() public {
        vm.expectRevert(DeployAdaptiveLPVault.MissingLibraryPlaceholder.selector);
        harness.link(bytes("0x6000"), address(1));
    }
}
