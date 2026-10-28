// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {VaultComponentFactory} from "../../src/core/VaultComponentFactory.sol";
import {AccessControlConfig} from "../../src/core/VaultTypes.sol";
import {ControlledSwapExecutor} from "../../src/swap/ControlledSwapExecutor.sol";
import {IControlledSwapExecutor} from "../../src/interfaces/IControlledSwapExecutor.sol";
import {IVaultControl} from "../../src/interfaces/IVaultControl.sol";
import {IUniswapV3SwapRouter} from "../../src/interfaces/IUniswapV3External.sol";
import {SwapDirection, SwapExecutorConfig, SwapPlan} from "../../src/swap/SwapTypes.sol";

import {MockSwapERC20, MockSwapFactory, MockSwapPool, MockSwapRouter} from "./mocks/ControlledSwapMocks.sol";

contract ControlledSwapExecutorTest is Test {
    event SwapExecuted(
        address indexed router, SwapDirection direction, uint256 amountIn, uint256 amountOut, uint256 protocolMinOut
    );

    uint24 private constant FEE = 3_000;
    uint256 private constant AMOUNT_IN = 10 ether;
    uint256 private constant AMOUNT_OUT = 19 ether;
    uint256 private constant MIN_AMOUNT_OUT = 18 ether;

    MockSwapERC20 private tokenA;
    MockSwapERC20 private tokenB;
    MockSwapERC20 private token0;
    MockSwapERC20 private token1;
    MockSwapFactory private factory;
    MockSwapPool private pool;
    MockSwapRouter private router;
    ControlledSwapExecutor private executor;

    function setUp() external {
        tokenA = new MockSwapERC20("Token A", "TKA");
        tokenB = new MockSwapERC20("Token B", "TKB");
        (token0, token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        factory = new MockSwapFactory();
        pool = new MockSwapPool(address(factory), address(token0), address(token1), FEE);
        factory.registerPool(address(token0), address(token1), FEE, address(pool));
        router = new MockSwapRouter(address(factory));
        router.setResult(AMOUNT_OUT, 1);

        executor = _deploy(address(this), address(router), address(pool));
    }

    function test_constructorStoresValidatedImmutableBindings() external view {
        assertEq(executor.vault(), address(this));
        assertEq(executor.router(), address(router));
        assertEq(executor.swapPool(), address(pool));
        assertEq(executor.token0(), address(token0));
        assertEq(executor.token1(), address(token1));
        assertEq(executor.feeTier(), FEE);
    }

    function test_componentFactoryDeploysComponentsBoundToCallingVault() external {
        VaultComponentFactory componentFactory = new VaultComponentFactory();
        (IVaultControl control, IControlledSwapExecutor factoryExecutor) = componentFactory.deployComponents(
            AccessControlConfig({initialDefaultAdminDelay: 2 days, initialDefaultAdmin: address(this)}),
            address(token0),
            address(token1),
            address(factory),
            address(factory),
            address(pool),
            address(router)
        );

        assertEq(control.vault(), address(this));
        assertEq(control.token0(), address(token0));
        assertEq(control.token1(), address(token1));
        assertEq(factoryExecutor.vault(), address(this));
        assertEq(factoryExecutor.swapPool(), address(pool));
        assertEq(factoryExecutor.router(), address(router));
    }

    function test_constructorAllowsFactoryToBindAnotherVault() external {
        ControlledSwapExecutor factoryDeployed = _deploy(address(0xBEEF), address(router), address(pool));
        assertEq(factoryDeployed.vault(), address(0xBEEF));
    }

    function test_constructorRejectsZeroVault() external {
        vm.expectRevert(IControlledSwapExecutor.InvalidVaultBinding.selector);
        _deploy(address(0), address(router), address(pool));
    }

    function test_constructorRejectsRouterWithoutCode() external {
        vm.expectRevert(IControlledSwapExecutor.RouterNotAllowed.selector);
        _deploy(address(this), address(0xBEEF), address(pool));
    }

    function test_constructorRejectsPoolWithoutCode() external {
        vm.expectRevert(IControlledSwapExecutor.InvalidSwapPool.selector);
        _deploy(address(this), address(router), address(0xBEEF));
    }

    function test_constructorRejectsExpectedFactoryWithoutCode() external {
        vm.expectRevert(IControlledSwapExecutor.InvalidSwapPool.selector);
        _deployWithFactory(address(this), address(router), address(pool), address(0xBEEF));
    }

    function test_constructorRejectsInvalidTokenOrder() external {
        MockSwapPool reversed = new MockSwapPool(address(factory), address(token1), address(token0), FEE);
        factory.registerPool(address(token0), address(token1), FEE, address(reversed));

        vm.expectRevert(IControlledSwapExecutor.InvalidTokenOrder.selector);
        _deploy(address(this), address(router), address(reversed));
    }

    function test_constructorRejectsUnregisteredPool() external {
        MockSwapPool unregistered = new MockSwapPool(address(factory), address(token0), address(token1), FEE);

        vm.expectRevert(IControlledSwapExecutor.InvalidSwapPool.selector);
        _deploy(address(this), address(router), address(unregistered));
    }

    function test_constructorRejectsSelfCertifiedPoolFromUnexpectedFactory() external {
        MockSwapFactory unexpectedFactory = new MockSwapFactory();
        MockSwapPool unexpectedPool =
            new MockSwapPool(address(unexpectedFactory), address(token0), address(token1), FEE);
        unexpectedFactory.registerPool(address(token0), address(token1), FEE, address(unexpectedPool));
        MockSwapRouter unexpectedRouter = new MockSwapRouter(address(unexpectedFactory));

        vm.expectRevert(IControlledSwapExecutor.InvalidSwapPool.selector);
        _deploy(address(this), address(unexpectedRouter), address(unexpectedPool));
    }

    function test_constructorRejectsRouterFromAnotherFactory() external {
        MockSwapFactory otherFactory = new MockSwapFactory();
        MockSwapRouter otherRouter = new MockSwapRouter(address(otherFactory));

        vm.expectRevert(IControlledSwapExecutor.RouterNotAllowed.selector);
        _deploy(address(this), address(otherRouter), address(pool));
    }

    function test_executeSwapRejectsNonVaultCaller() external {
        vm.prank(address(0xBEEF));
        vm.expectRevert(IControlledSwapExecutor.NotVaultCaller.selector);
        executor.executeSwap(_plan(SwapDirection.ZERO_FOR_ONE, AMOUNT_IN, MIN_AMOUNT_OUT, _futureDeadline()));
    }

    function test_executeSwapRejectsNoneDirection() external {
        vm.expectRevert(IControlledSwapExecutor.SwapNotAllowed.selector);
        executor.executeSwap(_plan(SwapDirection.NONE, AMOUNT_IN, MIN_AMOUNT_OUT, _futureDeadline()));
    }

    function test_executeSwapRejectsZeroInput() external {
        vm.expectRevert(IControlledSwapExecutor.SwapNotAllowed.selector);
        executor.executeSwap(_plan(SwapDirection.ZERO_FOR_ONE, 0, MIN_AMOUNT_OUT, _futureDeadline()));
    }

    function test_executeSwapRejectsZeroMinimumOutput() external {
        vm.expectRevert(IControlledSwapExecutor.SwapNotAllowed.selector);
        executor.executeSwap(_plan(SwapDirection.ZERO_FOR_ONE, AMOUNT_IN, 0, _futureDeadline()));
    }

    function test_executeSwapRejectsExpiredDeadline() external {
        vm.warp(10);
        vm.expectRevert(IControlledSwapExecutor.DeadlineExpired.selector);
        executor.executeSwap(_plan(SwapDirection.ZERO_FOR_ONE, AMOUNT_IN, MIN_AMOUNT_OUT, 9));
    }

    function test_executeSwapRejectsInputAboveExecutorBalance() external {
        token0.mint(address(executor), AMOUNT_IN - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IControlledSwapExecutor.InsufficientExecutorInputBalance.selector,
                address(token0),
                AMOUNT_IN,
                AMOUNT_IN - 1
            )
        );
        executor.executeSwap(_plan(SwapDirection.ZERO_FOR_ONE, AMOUNT_IN, MIN_AMOUNT_OUT, _futureDeadline()));
    }

    function test_executeSwapZeroForOneUsesFixedRouteAndActualVaultBalanceDelta() external {
        uint256 executorBaseline = 3 ether;
        token0.mint(address(executor), executorBaseline + AMOUNT_IN);
        token1.mint(address(this), 7 ether);

        vm.expectEmit(true, false, false, true, address(executor));
        emit SwapExecuted(address(router), SwapDirection.ZERO_FOR_ONE, AMOUNT_IN, AMOUNT_OUT, MIN_AMOUNT_OUT);

        uint32 deadline = _futureDeadline();
        uint256 returnedAmount =
            executor.executeSwap(_plan(SwapDirection.ZERO_FOR_ONE, AMOUNT_IN, MIN_AMOUNT_OUT, deadline));

        assertEq(returnedAmount, AMOUNT_OUT);
        assertEq(token0.balanceOf(address(executor)), executorBaseline);
        assertEq(token1.balanceOf(address(executor)), 0);
        assertEq(token1.balanceOf(address(this)), 7 ether + AMOUNT_OUT);
        assertEq(token0.allowance(address(executor), address(router)), 0);

        assertEq(router.lastTokenIn(), address(token0));
        assertEq(router.lastTokenOut(), address(token1));
        assertEq(router.lastFee(), FEE);
        assertEq(router.lastRecipient(), address(this));
        assertEq(router.lastDeadline(), deadline);
        assertEq(router.lastAmountIn(), AMOUNT_IN);
        assertEq(router.lastAmountOutMinimum(), MIN_AMOUNT_OUT);
        assertEq(router.lastSqrtPriceLimitX96(), 0);
    }

    function test_executeSwapOneForZeroUsesCanonicalReverseDirection() external {
        token1.mint(address(executor), AMOUNT_IN);

        uint256 returnedAmount =
            executor.executeSwap(_plan(SwapDirection.ONE_FOR_ZERO, AMOUNT_IN, MIN_AMOUNT_OUT, _futureDeadline()));

        assertEq(returnedAmount, AMOUNT_OUT);
        assertEq(router.lastTokenIn(), address(token1));
        assertEq(router.lastTokenOut(), address(token0));
        assertEq(router.lastRecipient(), address(this));
        assertEq(token1.balanceOf(address(executor)), 0);
        assertEq(token0.balanceOf(address(this)), AMOUNT_OUT);
        assertEq(token1.allowance(address(executor), address(router)), 0);
    }

    function test_executeSwapIgnoresUntrustedRouterReturnValue() external {
        token0.mint(address(executor), AMOUNT_IN);
        router.setResult(AMOUNT_OUT, type(uint256).max);

        uint256 returnedAmount =
            executor.executeSwap(_plan(SwapDirection.ZERO_FOR_ONE, AMOUNT_IN, MIN_AMOUNT_OUT, _futureDeadline()));

        assertEq(returnedAmount, AMOUNT_OUT);
    }

    function test_executeSwapRejectsActualOutputBelowMinimum() external {
        token0.mint(address(executor), AMOUNT_IN);
        router.setResult(MIN_AMOUNT_OUT - 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IControlledSwapExecutor.SwapSlippage.selector, MIN_AMOUNT_OUT, MIN_AMOUNT_OUT - 1)
        );
        executor.executeSwap(_plan(SwapDirection.ZERO_FOR_ONE, AMOUNT_IN, MIN_AMOUNT_OUT, _futureDeadline()));

        assertEq(token0.balanceOf(address(executor)), AMOUNT_IN);
        assertEq(token1.balanceOf(address(this)), 0);
        assertEq(token0.allowance(address(executor), address(router)), 0);
    }

    function test_executeSwapRejectsVaultOutputBalanceDecrease() external {
        token0.mint(address(executor), AMOUNT_IN);
        token1.mint(address(this), 2 ether);
        router.setResult(0, 0);
        router.setAmountToBurnFromRecipient(1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IControlledSwapExecutor.VaultOutputBalanceDecreased.selector, address(token1), 2 ether, 1 ether
            )
        );
        executor.executeSwap(_plan(SwapDirection.ZERO_FOR_ONE, AMOUNT_IN, MIN_AMOUNT_OUT, _futureDeadline()));

        assertEq(token0.balanceOf(address(executor)), AMOUNT_IN);
        assertEq(token1.balanceOf(address(this)), 2 ether);
        assertEq(token0.allowance(address(executor), address(router)), 0);
    }

    function test_executeSwapRejectsRouterThatConsumesLessThanExactInput() external {
        token0.mint(address(executor), AMOUNT_IN);
        router.setPullAmount(AMOUNT_IN - 1);

        vm.expectRevert(
            abi.encodeWithSelector(IControlledSwapExecutor.ExecutorBalanceMismatch.selector, address(token0), 0, 1)
        );
        executor.executeSwap(_plan(SwapDirection.ZERO_FOR_ONE, AMOUNT_IN, MIN_AMOUNT_OUT, _futureDeadline()));

        assertEq(token0.balanceOf(address(executor)), AMOUNT_IN);
        assertEq(token0.allowance(address(executor), address(router)), 0);
    }

    function test_executeSwapRejectsOutputSentAnywhereButVault() external {
        token0.mint(address(executor), AMOUNT_IN);
        router.setSendOutputToExecutor(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IControlledSwapExecutor.ExecutorBalanceMismatch.selector, address(token1), 0, AMOUNT_OUT
            )
        );
        executor.executeSwap(_plan(SwapDirection.ZERO_FOR_ONE, AMOUNT_IN, MIN_AMOUNT_OUT, _futureDeadline()));

        assertEq(token0.balanceOf(address(executor)), AMOUNT_IN);
        assertEq(token1.balanceOf(address(executor)), 0);
        assertEq(token0.allowance(address(executor), address(router)), 0);
    }

    function _deploy(address vault_, address router_, address pool_) private returns (ControlledSwapExecutor deployed) {
        return _deployWithFactory(vault_, router_, pool_, address(factory));
    }

    function _deployWithFactory(address vault_, address router_, address pool_, address expectedFactory)
        private
        returns (ControlledSwapExecutor deployed)
    {
        deployed = new ControlledSwapExecutor(
            SwapExecutorConfig({vault: vault_, router: router_, swapPool: pool_, factory: expectedFactory})
        );
    }

    function _plan(SwapDirection direction, uint256 amountIn, uint256 minAmountOut, uint32 deadline)
        private
        pure
        returns (SwapPlan memory)
    {
        return SwapPlan({direction: direction, amountIn: amountIn, minAmountOut: minAmountOut, deadline: deadline});
    }

    function _futureDeadline() private view returns (uint32) {
        return uint32(block.timestamp + 1 hours);
    }
}
