// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VaultEdgeFixture} from "./helpers/VaultEdgeFixtures.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";
import {VenueType} from "../../src/core/VaultTypes.sol";

contract AdaptiveLPVaultBootstrapBoundsTest is VaultEdgeFixture {
    function test_bootstrapMinimumNavOneBelowBoundaryRevertsAcrossPrecisions() public {
        for (uint256 config; config < 4; ++config) {
            uint8 decimals0 = config & 1 == 0 ? 6 : 18;
            uint8 decimals1 = config & 2 == 0 ? 6 : 18;
            uint256 unit0 = 10 ** uint256(decimals0);
            uint256 unit1 = 10 ** uint256(decimals1);
            _deploy(decimals0, decimals1, 2 * unit1, LOCKED);
            oracle.setState(1000, 17, true);
            token0.approve(address(vault), 3 * unit0);
            token1.approve(address(vault), 3 * unit1);
            bytes32 beforeState = _stateDigest();
            vm.expectRevert(IAdaptiveLPVault.MinimumNavNotMet.selector);
            vault.bootstrap(unit0, unit1 - 1, address(this));
            assertEq(_stateDigest(), beforeState);
            assertEq(vault.totalSupply(), 0);
            assertEq(vault.planVersion(), 0);
            assertFalse(vault.initialized());
        }
    }

    function test_bootstrapMinimumNavExactBoundaryMintsExpectedSharesAcrossPrecisions() public {
        for (uint256 config; config < 4; ++config) {
            uint8 decimals0 = config & 1 == 0 ? 6 : 18;
            uint8 decimals1 = config & 2 == 0 ? 6 : 18;
            uint256 unit0 = 10 ** uint256(decimals0);
            uint256 unit1 = 10 ** uint256(decimals1);
            _deploy(decimals0, decimals1, 2 * unit1, LOCKED);
            oracle.setState(1000, 17, true);
            address receiver = makeAddr("bootstrap receiver");
            uint256 user0 = token0.balanceOf(address(this));
            uint256 user1 = token1.balanceOf(address(this));
            vm.expectEmit(true, true, true, true, address(vault));
            emit IAdaptiveLPVault.VaultBootstrapped(address(this), unit0, unit1, 2 ether, LOCKED, VenueType.IDLE);
            vault.bootstrap(unit0, unit1, receiver);
            assertTrue(vault.initialized());
            assertEq(vault.decimals(), 18);
            assertEq(vault.token0Decimals(), decimals0);
            assertEq(vault.token1Decimals(), decimals1);
            assertEq(vault.totalSupply(), 2 ether);
            assertEq(vault.balanceOf(receiver), 1 ether);
            assertEq(vault.balanceOf(address(vault)), LOCKED);
            assertEq(vault.balanceOf(address(this)), 0);
            assertEq(user0 - token0.balanceOf(address(this)), unit0);
            assertEq(user1 - token1.balanceOf(address(this)), unit1);
            assertEq(token0.balanceOf(address(vault)), unit0);
            assertEq(token1.balanceOf(address(vault)), unit1);
            assertEq(vault.planVersion(), 1);
            assertEq(vault.lastExecutedPlan().version, 1);
            assertEq(vault.lastPositionChangeAt(), vm.getBlockTimestamp());
        }
    }

    function test_bootstrapGrossSharesEqualLockedRevertsAcrossPrecisions() public {
        for (uint256 config; config < 4; ++config) {
            uint8 decimals0 = config & 1 == 0 ? 6 : 18;
            uint8 decimals1 = config & 2 == 0 ? 6 : 18;
            _deploy(decimals0, decimals1, 1, 2 ether);
            oracle.setState(1000, 17, true);
            bytes32 beforeState = _stateDigest();
            vm.expectRevert(abi.encodeWithSelector(IAdaptiveLPVault.InitialSharesTooLow.selector, 2 ether, 2 ether));
            vault.bootstrap(10 ** uint256(decimals0), 10 ** uint256(decimals1), address(this));
            assertEq(_stateDigest(), beforeState);
            assertFalse(vault.initialized());
        }
    }

    function test_bootstrapGrossSharesOneAboveLockedSucceedsAcrossPrecisions() public {
        for (uint256 config; config < 4; ++config) {
            uint8 decimals0 = config & 1 == 0 ? 6 : 18;
            uint8 decimals1 = config & 2 == 0 ? 6 : 18;
            _deploy(decimals0, decimals1, 1, 2 ether - 1);
            oracle.setState(1000, 17, true);
            _bootstrap(10 ** uint256(decimals0), 10 ** uint256(decimals1));
            assertEq(vault.totalSupply(), 2 ether);
            assertEq(vault.balanceOf(address(vault)), 2 ether - 1);
            assertEq(vault.balanceOf(address(this)), 1);
            assertTrue(vault.initialized());
            assertEq(vault.planVersion(), 1);
        }
    }

    function testFuzz_bootstrapScalesFractionalRawAmounts(uint96 raw0, uint96 raw1, bool six0, bool six1) public {
        uint8 decimals0 = six0 ? 6 : 18;
        uint8 decimals1 = six1 ? 6 : 18;
        uint256 unit0 = 10 ** uint256(decimals0);
        uint256 unit1 = 10 ** uint256(decimals1);
        uint256 amount0 = bound(raw0, 1, 10000 * unit0);
        uint256 amount1 = bound(raw1, 2, 10000 * unit1);
        _deploy(decimals0, decimals1, 1, 1);
        oracle.setState(1000, 17, true);
        // All intermediates fit uint256 in this bounded independent raw-unit reference.
        uint256 nav = amount0 * unit1 / unit0 + amount1;
        uint256 expectedShares = nav * 1e18 / unit1;
        _bootstrap(amount0, amount1);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.balanceOf(address(this)), expectedShares - 1);
        assertEq(vault.balanceOf(address(vault)), 1);
        (uint256 total0, uint256 total1) = vault.totalAssets();
        assertEq(total0, amount0);
        assertEq(total1, amount1);
    }
}
