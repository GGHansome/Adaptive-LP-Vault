// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LocalUniswapFixture} from "../../helpers/LocalUniswapFixture.sol";
import {VaultHandler} from "../handlers/VaultHandler.sol";
import {VenueType} from "../../../src/core/VaultTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract VaultInvariantFixture is LocalUniswapFixture {
    VaultHandler internal handler;

    function setUp() public virtual override {
        super.setUp();
        _bootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        handler = new VaultHandler(
            VaultHandler.Environment({
                vault: vault,
                token0: token0,
                token1: token1,
                pair: pair,
                low: low,
                high: high,
                admin: admin,
                manager: manager,
                guardian: guardian,
                keeper: keeper,
                actors: [manager, alice, bob, receiver, operator],
                seed: seed
            })
        );
        // Handler donates existing LP, never fabricates LP balances or pool reserves.
        IERC20(pair).transfer(address(handler), seed * 10);
        bytes4[] memory selectors = new bytes4[](18);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.redeem.selector;
        selectors[2] = handler.transferShares.selector;
        selectors[3] = handler.approveShares.selector;
        selectors[4] = handler.donateTokens.selector;
        selectors[5] = handler.donateLp.selector;
        selectors[6] = handler.accrueFees.selector;
        selectors[7] = handler.setMarket.selector;
        selectors[8] = handler.advanceTime.selector;
        selectors[9] = handler.setControls.selector;
        selectors[10] = handler.rebalance.selector;
        selectors[11] = handler.rebalanceWithSwap.selector;
        selectors[12] = handler.emergencyExit.selector;
        selectors[13] = handler.exerciseFailure.selector;
        selectors[14] = handler.unauthorized.selector;
        selectors[15] = handler.guardianCannotRelax.selector;
        // Additional weighting for time advancement keeps cooldown success paths reachable.
        selectors[16] = handler.advanceTime.selector;
        selectors[17] = handler.probeGates.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector(address(handler), selectors));
        // Keep the fixture address out of fuzz senders: it alone may invoke finish().
        excludeSender(address(this));
    }

    function _assertGhostAccounting() internal view {
        (uint256 a0, uint256 a1) = handler.referenceAssets(true);
        int256 delta0 = int256(a0) - handler.expected0();
        int256 delta1 = int256(a1) - handler.expected1();
        uint256 budget = handler.roundingBudget();
        assertLe(uint256(delta0 < 0 ? -delta0 : delta0), budget, "token0 cumulative cash flow");
        assertLe(uint256(delta1 < 0 ? -delta1 : delta1), budget, "token1 cumulative cash flow");
    }

    /// @dev Runs after EVERY generated sequence, not once after the entire campaign.
    function afterInvariant() public {
        handler.finish();
        _assertGhostAccounting();
        assertEq(uint8(vault.activeVenue()), uint8(VenueType.IDLE));
        assertEq(vault.totalSupply(), vault.balanceOf(address(vault)));
        assertGe(vault.totalSupply(), LOCKED);
        assertTrue(vault.initialized());
        assertEq(low.positionId(), 0);
        assertEq(high.positionId(), 0);
    }
}
