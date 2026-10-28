// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VaultInvariantFixture} from "./helpers/VaultInvariantFixture.sol";
import {VaultReference} from "./helpers/VaultReference.sol";
import {VenueType, AssetSnapshot} from "../../src/core/VaultTypes.sol";
import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";

contract AccountingInvariantsTest is VaultInvariantFixture {
    /// @dev INV-01/05/06/11: issuance/burning is tracked independently of share balances.
    function invariant_shareSupplyAndPermanentLock() public view {
        uint256 accounted = vault.balanceOf(address(vault));
        for (uint256 i; i < 5; ++i) {
            accounted += vault.balanceOf(handler.actor(i));
        }
        assertEq(vault.totalSupply(), accounted);
        assertEq(vault.totalSupply(), handler.initialSupply() + handler.minted() - handler.burned());
        assertGe(vault.balanceOf(address(vault)), LOCKED);
        assertGe(vault.totalSupply(), LOCKED);
        assertTrue(vault.initialized());
    }

    /// @dev INV-04: compare BOTH vault and adapter accounting to raw AMM/NFT storage.
    function invariant_assetsAndFeesMatchIndependentProtocolAccounting() public view {
        (uint256 expected0, uint256 expected1) = handler.referenceAssets(false);
        (uint256 actual0, uint256 actual1) = vault.totalAssets();
        assertEq(actual0, expected0);
        assertEq(actual1, expected1);
        AssetSnapshot memory assets = vault.assetSnapshot();
        assertEq(assets.total0, expected0);
        assertEq(assets.total1, expected1);
        assertEq(assets.idle0, token0.balanceOf(address(vault)));
        assertEq(assets.idle1, token1.balanceOf(address(vault)));
        assertEq(assets.totalShares, vault.totalSupply());
        assertEq(assets.position0, expected0 - assets.idle0);
        assertEq(assets.position1, expected1 - assets.idle1);
        for (uint256 i = 1; i <= 3; ++i) {
            VaultReference.Position memory ref = handler.referencePosition(VenueType(i));
            PositionSnapshot memory position = IPositionAdapter(handler.adapter(VenueType(i))).snapshot();
            assertEq(position.principal0, ref.principal0);
            assertEq(position.principal1, ref.principal1);
            assertEq(position.claimableFee0, ref.fee0);
            assertEq(position.claimableFee1, ref.fee1);
            assertEq(position.amount0, ref.principal0 + ref.fee0);
            assertEq(position.amount1, ref.principal1 + ref.fee1);
            assertEq(position.liquidity, ref.units);
        }
    }

    /// @dev INV-01/04/09/11: includes non-active, unrecognized V2 LP equity in the physical
    /// ledger, but excludes it above from user pricing until activation. Only native AMM
    /// floor/recombination dust is tolerated; user inputs/outputs and swaps are exact.
    function invariant_cumulativeTokenCashFlowsAreConserved() public view {
        _assertGhostAccounting();
    }
}
