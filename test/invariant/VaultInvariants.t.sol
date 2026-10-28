// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VaultInvariantFixture} from "./helpers/VaultInvariantFixture.sol";
import {VaultReference} from "./helpers/VaultReference.sol";
import {VenueType, PositionPlan, MarketRegime} from "../../src/core/VaultTypes.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {IUniswapV2Factory} from "../../src/interfaces/IUniswapV2External.sol";
import {IUniswapV3Factory} from "../../src/interfaces/IUniswapV3External.sol";

contract VaultInvariantsTest is VaultInvariantFixture {
    /// @dev INV-02/03/17: non-active V2 LP donations are explicitly permitted.
    function invariant_singleActivePositionAndNormalizedPlan() public view {
        VenueType active = vault.activeVenue();
        PositionPlan memory plan = vault.lastExecutedPlan();
        assertEq(
            plan.planHash,
            keccak256(abi.encode(plan.targetVenue, plan.marketRegime, plan.tickLower, plan.tickUpper, plan.version))
        );
        assertLe(plan.version, vault.planVersion()); // emergency invalidates version, preserves history
        VenueType planned = plan.marketRegime == MarketRegime.LOW_DEVIATION
            ? VenueType.UNISWAP_V3_LOW_FEE
            : plan.marketRegime == MarketRegime.MEDIUM_DEVIATION
                ? VenueType.UNISWAP_V3_HIGH_FEE
                : plan.marketRegime == MarketRegime.HIGH_DEVIATION ? VenueType.UNISWAP_V2 : VenueType.IDLE;
        assertEq(uint8(plan.targetVenue), uint8(planned));
        for (uint256 i = 1; i <= 3; ++i) {
            VenueType venue = VenueType(i);
            VaultReference.Position memory p = handler.referencePosition(venue);
            if (venue != active) {
                if (venue != VenueType.UNISWAP_V2) {
                    assertEq(p.id, 0);
                    assertEq(p.units, 0);
                    assertEq(p.principal0 + p.principal1 + p.fee0 + p.fee1, 0);
                }
                continue;
            }
            assertGt(p.units, 0);
            if (venue != VenueType.UNISWAP_V2) {
                assertGt(p.id, 0);
                assertEq(positionManager.ownerOf(p.id), handler.adapter(venue));
                assertEq(p.lower, plan.tickLower);
                assertEq(p.upper, plan.tickUpper);
                int24 spacing = IPositionAdapter(handler.adapter(venue)).tickSpacing();
                assertEq(p.lower % spacing, 0);
                assertEq(p.upper % spacing, 0);
                assertLt(p.lower, p.upper);
            }
        }
        if (plan.targetVenue == VenueType.IDLE || plan.targetVenue == VenueType.UNISWAP_V2) {
            assertEq(plan.tickLower, 0);
            assertEq(plan.tickUpper, 0);
        }
        if (active == VenueType.IDLE) {
            (uint256 a0, uint256 a1) = vault.totalAssets();
            assertEq(a0, token0.balanceOf(address(vault)));
            assertEq(a1, token1.balanceOf(address(vault)));
        } else {
            assertEq(uint8(active), uint8(plan.targetVenue));
        }
    }

    /// @dev INV-10/13/14: checks independent expected history after every random action.
    function invariant_versionAndHistoricalPlanFollowOnlySuccessfulTransitions() public view {
        handler.assertHistory();
    }

    /// @dev INV-09: balances sent directly to these addresses are not part of this campaign;
    /// all valid calls must restore the zero baselines and clear temporary approvals.
    function invariant_noResidualCustodyOrTemporaryAllowances() public view {
        address[3] memory adapters = [address(v2), address(low), address(high)];
        for (uint256 i; i < 3; ++i) {
            assertEq(token0.allowance(address(vault), adapters[i]), 0);
            assertEq(token1.allowance(address(vault), adapters[i]), 0);
            assertEq(token0.balanceOf(adapters[i]), 0);
            assertEq(token1.balanceOf(adapters[i]), 0);
            assertEq(token0.allowance(adapters[i], address(positionManager)), 0);
            assertEq(token1.allowance(adapters[i], address(positionManager)), 0);
        }
        address executor = address(vault.swapExecutor());
        assertEq(token0.balanceOf(executor), 0);
        assertEq(token1.balanceOf(executor), 0);
        assertEq(token0.allowance(executor, address(router)), 0);
        assertEq(token1.allowance(executor, address(router)), 0);
        assertEq(token0.balanceOf(address(control)), 0);
        assertEq(token1.balanceOf(address(control)), 0);
    }

    /// @dev INV-15/16/19: runtime changes cannot replace fixed bindings or confer business
    /// privileges on the root administrator. Delayed admin transfer has dedicated unit tests.
    function invariant_bindingsAndAuthorityRemainSeparated() public view {
        assertLt(uint160(address(token0)), uint160(address(token1)));
        assertEq(vault.token0(), address(token0));
        assertEq(vault.token1(), address(token1));
        assertEq(control.vault(), address(vault));
        assertEq(vault.swapExecutor().vault(), address(vault));
        assertEq(vault.swapExecutor().swapPool(), oracle.canonicalPool());
        assertEq(vault.swapExecutor().router(), address(router));
        assertEq(control.defaultAdmin(), admin);
        assertTrue(control.hasRole(control.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(control.hasRole(control.MANAGER_ROLE(), admin));
        assertFalse(control.hasRole(control.KEEPER_ROLE(), admin));
        assertFalse(control.hasRole(control.GUARDIAN_ROLE(), admin));
        assertEq(control.getAdapter(VenueType.UNISWAP_V2), address(v2));
        assertEq(control.getAdapter(VenueType.UNISWAP_V3_LOW_FEE), address(low));
        assertEq(control.getAdapter(VenueType.UNISWAP_V3_HIGH_FEE), address(high));
        assertEq(control.getConfig(VenueType.UNISWAP_V3_LOW_FEE).tickSpacing, 10);
        assertEq(control.getConfig(VenueType.UNISWAP_V3_HIGH_FEE).tickSpacing, 60);
        assertEq(IUniswapV2Factory(v2Factory).getPair(address(token0), address(token1)), pair);
        assertEq(IUniswapV3Factory(v3Factory).getPool(address(token0), address(token1), 10000), canonicalPool);
        for (uint256 i; i < 5; ++i) {
            assertFalse(control.hasRole(control.DEFAULT_ADMIN_ROLE(), handler.actor(i)));
        }
        for (uint256 i = 1; i <= 3; ++i) {
            IPositionAdapter a = IPositionAdapter(handler.adapter(VenueType(i)));
            assertEq(a.vault(), address(vault));
            assertEq(a.token0(), address(token0));
            assertEq(a.token1(), address(token1));
            if (i != 1) {
                assertEq(IUniswapV3Factory(v3Factory).getPool(address(token0), address(token1), a.feeTier()), a.pool());
            }
        }
    }
}
