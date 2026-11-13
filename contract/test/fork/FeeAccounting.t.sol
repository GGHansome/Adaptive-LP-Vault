// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MainnetForkFixture, IForkV2Pair} from "./helpers/MainnetForkFixture.sol";
import {PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {AssetSnapshot, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdaptiveLPVault} from "../../src/interfaces/IAdaptiveLPVault.sol";

contract FeeAccountingForkTest is MainnetForkFixture {
    function test_lowFeeAccrualIsPricedBeforeNewSharesAndPaidOnExit() public {
        _feeLifecycle(VenueType.UNISWAP_V3_LOW_FEE, 500);
    }

    function test_highFeeAccrualIsPricedBeforeNewSharesAndPaidOnExit() public {
        _feeLifecycle(VenueType.UNISWAP_V3_HIGH_FEE, 3000);
    }

    function _feeLifecycle(VenueType venue, uint24 fee) private {
        _deployAndBootstrap(venue);
        uint256 aliceShares = _deposit(alice, alice, seed0 / 5, seed1 / 5);
        uint256 out = _tradeV3(fee, true, 10_000e6);
        _tradeV3(fee, false, out);
        PositionSnapshot memory accrued = _adapter(venue).snapshot();
        assertGt(accrued.claimableFee0, 0);
        assertGt(accrued.claimableFee1, 0);
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        uint256 bobShares = _deposit(bob, bob, seed0 / 5, seed1 / 5);
        PositionSnapshot memory afterDeposit = _adapter(venue).snapshot();
        assertEq(afterDeposit.positionId, accrued.positionId);
        assertEq(afterDeposit.claimableFee0, 0);
        assertEq(afterDeposit.claimableFee1, 0);
        // Removing fees from the denominator would incorrectly give the entrant extra shares.
        int24 tick = oracle.snapshot().twapTick;
        uint256 allNav = _nav(beforeAssets.total0, beforeAssets.total1, tick);
        uint256 principalNav =
            _nav(beforeAssets.total0 - accrued.claimableFee0, beforeAssets.total1 - accrued.claimableFee1, tick);
        assertGt(allNav, principalNav);
        assertGt(Math.mulDiv(bobShares, allNav, principalNav), bobShares);
        _redeem(alice, alice, receiver, aliceShares);
        _redeem(bob, bob, bob, bobShares);
        _deposit(alice, alice, seed0 / 10, seed1 / 10);
        assertEq(_adapter(venue).snapshot().claimableFee0, 0, "fees must not be counted twice");
        assertEq(_adapter(venue).snapshot().claimableFee1, 0);
    }

    function test_redeemSlippageRestoresRealFeesLiquidityAndShareAllowance() public {
        _deployAndBootstrap(VenueType.UNISWAP_V3_LOW_FEE);
        uint256 shares = _deposit(alice, alice, seed0 / 5, seed1 / 5);
        uint256 out = _tradeV3(500, true, 10_000e6);
        _tradeV3(500, false, out);
        assertGt(low.snapshot().claimableFee0, 0);
        vm.prank(alice);
        vault.approve(operator, shares);
        bytes32 beforeState = keccak256(
            abi.encode(
                vault.assetSnapshot(),
                low.snapshot(),
                vault.balanceOf(alice),
                vault.totalSupply(),
                token0.balanceOf(LOW_POOL),
                token1.balanceOf(LOW_POOL)
            )
        );
        vm.prank(operator);
        vm.expectPartialRevert(IAdaptiveLPVault.AssetSlippage.selector);
        vault.redeem(shares, type(uint256).max, 0, receiver, alice);
        assertEq(
            keccak256(
                abi.encode(
                    vault.assetSnapshot(),
                    low.snapshot(),
                    vault.balanceOf(alice),
                    vault.totalSupply(),
                    token0.balanceOf(LOW_POOL),
                    token1.balanceOf(LOW_POOL)
                )
            ),
            beforeState
        );
        assertEq(vault.allowance(alice, operator), shares);
        _assertAccounting();
        _redeem(operator, alice, receiver, shares);
        assertEq(vault.allowance(alice, operator), 0);
    }

    function test_v2RealTradesIncreaseReserveProductAndLpEquity() public {
        _deployAndBootstrap(VenueType.UNISWAP_V2);
        uint256 shares = _deposit(alice, alice, seed0 / 5, seed1 / 5);
        (uint112 r0, uint112 r1,) = IForkV2Pair(PAIR).getReserves();
        uint256 initialProduct = uint256(r0) * r1;
        uint256 initialNav =
            _nav(vault.assetSnapshot().total0, vault.assetSnapshot().total1, oracle.snapshot().twapTick);
        uint256 out = _tradeV2(true, 100_000e6);
        _tradeV2(false, out);
        (r0, r1,) = IForkV2Pair(PAIR).getReserves();
        assertGt(uint256(r0) * r1, initialProduct);
        assertGt(
            _nav(vault.assetSnapshot().total0, vault.assetSnapshot().total1, oracle.snapshot().twapTick), initialNav
        );
        assertEq(v2.snapshot().claimableFee0, 0);
        assertEq(v2.snapshot().claimableFee1, 0);
        _deposit(bob, bob, seed0 / 5, seed1 / 5);
        _redeem(alice, alice, alice, shares);
        _redeem(bob, bob, bob, vault.balanceOf(bob));
    }

    function _tradeV2(bool zeroForOne, uint256 amountIn) private returns (uint256 amountOut) {
        (uint112 r0, uint112 r1,) = IForkV2Pair(PAIR).getReserves();
        uint256 reserveIn = zeroForOne ? r0 : r1;
        uint256 reserveOut = zeroForOne ? r1 : r0;
        amountOut = amountIn * 997 * reserveOut / (reserveIn * 1000 + amountIn * 997);
        uint256 beforeOut = (zeroForOne ? token1 : token0).balanceOf(address(this));
        assertTrue((zeroForOne ? token0 : token1).transfer(PAIR, amountIn));
        IForkV2Pair(PAIR).swap(zeroForOne ? 0 : amountOut, zeroForOne ? amountOut : 0, address(this), "");
        assertGt(amountOut, 0);
        assertEq((zeroForOne ? token1 : token0).balanceOf(address(this)) - beforeOut, amountOut);
    }
}
