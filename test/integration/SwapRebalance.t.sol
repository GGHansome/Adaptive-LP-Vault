// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IntegrationTestFixture} from "./helpers/IntegrationTestFixture.sol";
import {IIntegrationV2Pair} from "../helpers/LocalUniswapFixture.sol";
import {VenueType, AssetSnapshot, PositionPlan, DeploymentAssessment} from "../../src/core/VaultTypes.sol";
import {SwapDirection} from "../../src/swap/SwapTypes.sol";
import {IUniswapV3SwapRouter, IUniswapV3Pool} from "../../src/interfaces/IUniswapV3External.sol";

contract SwapRebalanceIntegrationTest is IntegrationTestFixture {
    function test_swapToken0ToToken1AndMigrateIntoV3() public {
        _successfulSwap(false, true);
    }

    function test_swapToken1ToToken0AndMigrateIntoV3() public {
        _successfulSwap(false, false);
    }

    function test_swapToken0ToToken1AndMigrateIntoV2() public {
        _successfulSwap(true, true);
    }

    function test_swapToken1ToToken0AndMigrateIntoV2() public {
        _successfulSwap(true, false);
    }

    function _successfulSwap(bool intoV2, bool zeroForOne) private {
        (PositionPlan memory plan, SwapDirection direction) = _prepareSwap(intoV2, zeroForOne);
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        uint256 amountIn = seed / 10;
        uint256 poolInputBefore = (zeroForOne ? token0 : token1).balanceOf(canonicalPool);
        uint256 poolOutputBefore = (zeroForOne ? token1 : token0).balanceOf(canonicalPool);
        // Protocol minimum is 98%; Keeper raises it to 98.5%. The real pool charges 1%.
        vm.prank(keeper);
        vault.rebalanceWithSwap(
            plan.planHash, direction, amountIn, amountIn * 985 / 1000, uint32(vm.getBlockTimestamp())
        );
        uint256 actualOutput = poolOutputBefore - (zeroForOne ? token1 : token0).balanceOf(canonicalPool);
        assertEq((zeroForOne ? token0 : token1).balanceOf(canonicalPool) - poolInputBefore, amountIn);
        AssetSnapshot memory afterAssets = vault.assetSnapshot();
        assertApproxEqAbs(
            afterAssets.total0, zeroForOne ? beforeAssets.total0 - amountIn : beforeAssets.total0 + actualOutput, DUST
        );
        assertApproxEqAbs(
            afterAssets.total1, zeroForOne ? beforeAssets.total1 + actualOutput : beforeAssets.total1 - amountIn, DUST
        );
        assertEq(afterAssets.totalShares, beforeAssets.totalShares);
        assertGe(afterAssets.total0 + afterAssets.total1, (beforeAssets.total0 + beforeAssets.total1) * 9900 / 10000);
        assertEq(vault.planVersion(), plan.version);
        assertEq(keccak256(abi.encode(vault.lastExecutedPlan())), keccak256(abi.encode(plan)));
        _assertAccounting();
        _deposit(alice, alice, seed / 10, seed / 10);
        _redeem(alice, alice, alice, vault.balanceOf(alice));
    }

    function test_routerSlippageRevertsOldPositionAndEveryBalance() public {
        _slippageFailure(true);
    }

    function test_reverseRouterSlippageRevertsOldPositionAndEveryBalance() public {
        _slippageFailure(false);
    }

    function _slippageFailure(bool zeroForOne) private {
        (PositionPlan memory plan, SwapDirection direction) = _prepareSwap(false, zeroForOne);
        bytes32 state = _stateHash();
        vm.prank(keeper);
        vm.expectRevert(bytes("Too little received"));
        vault.rebalanceWithSwap(plan.planHash, direction, seed / 10, seed / 10, uint32(vm.getBlockTimestamp()));
        assertEq(_stateHash(), state);
        _assertAccounting();
        vm.prank(keeper);
        vault.rebalanceWithSwap(plan.planHash, direction, seed / 10, 0, uint32(vm.getBlockTimestamp()));
        _assertAccounting();
    }

    function test_targetMintFailureRollsBackAnExecutedRealSwapAndAllowsRetry() public {
        (PositionPlan memory plan, SwapDirection direction) = _prepareSwap(false, true);
        bytes32 state = _stateHash();
        // Inject a failure only at the target pool mint boundary, after real old-NFT exit
        // and real router execution. Production Vault/Adapter/Executor code remains unchanged.
        vm.mockCallRevert(
            highPool,
            abi.encodeWithSelector(bytes4(keccak256("mint(address,int24,int24,uint128,bytes)"))),
            abi.encodeWithSignature("Error(string)", "injected target mint failure")
        );
        vm.expectCall(address(router), abi.encodeWithSelector(IUniswapV3SwapRouter.exactInputSingle.selector));
        vm.prank(keeper);
        vm.expectRevert(bytes("injected target mint failure"));
        vault.rebalanceWithSwap(plan.planHash, direction, seed / 10, 0, uint32(vm.getBlockTimestamp()));
        assertEq(_stateHash(), state);
        _market(150); // Also removes the injected pool fault.
        vm.prank(keeper);
        vault.rebalanceWithSwap(plan.planHash, direction, seed / 10, 0, uint32(vm.getBlockTimestamp()));
        _assertAccounting();
    }

    function test_publicCallerCannotExecuteKeeperSwapButCanRedeemAfterFailure() public {
        (PositionPlan memory plan, SwapDirection direction) = _prepareSwap(false, true);
        bytes32 state = _stateHash();
        bytes32 managerRole = control.MANAGER_ROLE();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, managerRole)
        );
        vault.rebalanceWithSwap(plan.planHash, direction, seed / 10, 0, uint32(vm.getBlockTimestamp()));
        assertEq(_stateHash(), state);
        _redeem(manager, manager, receiver, vault.balanceOf(manager) / 10);
    }

    function _prepareSwap(bool intoV2, bool zeroForOne)
        private
        returns (PositionPlan memory plan, SwapDirection direction)
    {
        _bootstrap(intoV2 ? VenueType.UNISWAP_V3_HIGH_FEE : VenueType.UNISWAP_V3_LOW_FEE);
        (zeroForOne ? token0 : token1).transfer(address(vault), seed / 5);
        _market(intoV2 ? 350 : 150);
        vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        DeploymentAssessment memory assessment;
        (plan, assessment) = vault.previewRebalance();
        assertTrue(assessment.requiresSwap);
        assertEq(uint8(plan.targetVenue), uint8(intoV2 ? VenueType.UNISWAP_V2 : VenueType.UNISWAP_V3_HIGH_FEE));
        direction = zeroForOne ? SwapDirection.ZERO_FOR_ONE : SwapDirection.ONE_FOR_ZERO;
        assertEq(uint8(assessment.direction), uint8(direction));
    }

    function _stateHash() private view returns (bytes32) {
        bytes32 balances;
        address[10] memory accounts = [
            address(vault),
            address(low),
            address(high),
            address(v2),
            pair,
            lowPool,
            highPool,
            canonicalPool,
            address(router),
            address(vault.swapExecutor())
        ];
        for (uint256 i; i < accounts.length; ++i) {
            balances = keccak256(abi.encode(balances, token0.balanceOf(accounts[i]), token1.balanceOf(accounts[i])));
        }
        (uint160 price, int24 tick,,,,,) = IUniswapV3Pool(canonicalPool).slot0();
        (uint112 r0, uint112 r1, uint32 timestamp) = IIntegrationV2Pair(pair).getReserves();
        return keccak256(
            abi.encode(
                balances,
                vault.assetSnapshot(),
                low.snapshot(),
                high.snapshot(),
                v2.snapshot(),
                vault.lastExecutedPlan(),
                vault.planVersion(),
                vault.lastPositionChangeAt(),
                vault.balanceOf(manager),
                vault.totalSupply(),
                IERC20(pair).balanceOf(address(v2)),
                IERC20(pair).totalSupply(),
                r0,
                r1,
                timestamp,
                price,
                tick,
                IUniswapV3Pool(canonicalPool).feeGrowthGlobal0X128(),
                IUniswapV3Pool(canonicalPool).feeGrowthGlobal1X128(),
                token0.allowance(address(vault.swapExecutor()), address(router)),
                token1.allowance(address(vault.swapExecutor()), address(router))
            )
        );
    }
}
