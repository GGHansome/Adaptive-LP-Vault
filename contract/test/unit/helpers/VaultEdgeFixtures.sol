// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AdaptiveLPVault} from "../../../src/core/AdaptiveLPVault.sol";
import {VaultComponentFactory} from "../../../src/core/VaultComponentFactory.sol";
import {VaultControl} from "../../../src/control/VaultControl.sol";
import {
    AccessControlConfig,
    PositionPlan,
    StrategyConfig,
    VaultConfig,
    VenueType
} from "../../../src/core/VaultTypes.sol";
import {
    EdgeToken,
    EdgeFactory,
    EdgePool,
    EdgeOracle,
    EdgeAdapter,
    EdgeRouter,
    EdgeReentryProbe
} from "../mocks/VaultEdgeMocks.sol";

abstract contract VaultEdgeFixture is Test {
    AdaptiveLPVault internal vault;
    VaultControl internal control;
    EdgeToken internal token0;
    EdgeToken internal token1;
    EdgeOracle internal oracle;
    EdgeAdapter internal low;
    EdgeAdapter internal high;
    EdgeAdapter internal v2;
    EdgeRouter internal router;
    EdgeReentryProbe internal probe;
    uint256 internal constant SEED = 1000 ether;
    uint256 internal constant LOCKED = 1 ether;

    function _deploy(uint8 decimals0, uint8 decimals1, uint256 minimumNav, uint256 locked) internal {
        EdgeToken a = new EdgeToken();
        EdgeToken b = new EdgeToken();
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);
        token0.setDecimals(decimals0);
        token1.setDecimals(decimals1);
        EdgeFactory factory = new EdgeFactory();
        EdgePool lowPool = new EdgePool(address(factory), address(token0), address(token1), 500, 10);
        EdgePool highPool = new EdgePool(address(factory), address(token0), address(token1), 3000, 60);
        EdgePool v2Pool = new EdgePool(address(factory), address(token0), address(token1), 0, 0);
        factory.register(address(token0), address(token1), 500, address(lowPool));
        factory.register(address(token0), address(token1), 3000, address(highPool));
        factory.register(address(token0), address(token1), 0, address(v2Pool));
        oracle = new EdgeOracle(address(lowPool), token0, token1);
        router = new EdgeRouter(address(factory));
        VaultConfig memory config = VaultConfig(
            1,
            1,
            address(oracle),
            address(new VaultComponentFactory()),
            address(router),
            address(factory),
            address(factory),
            locked,
            minimumNav
        );
        StrategyConfig memory strategy = StrategyConfig(0, 100, 50, 300, 200, 500, 400, 10, 10, 100, 500, 100, 10);
        vault = new AdaptiveLPVault("Edge Vault", "EV", config, AccessControlConfig(0, address(this)), strategy);
        control = VaultControl(address(vault.vaultControl()));
        control.grantRole(control.MANAGER_ROLE(), address(this));
        low = new EdgeAdapter(address(vault), lowPool, VenueType.UNISWAP_V3_LOW_FEE);
        high = new EdgeAdapter(address(vault), highPool, VenueType.UNISWAP_V3_HIGH_FEE);
        v2 = new EdgeAdapter(address(vault), v2Pool, VenueType.UNISWAP_V2);
        control.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(low));
        control.configureAdapter(VenueType.UNISWAP_V3_HIGH_FEE, address(high));
        control.configureAdapter(VenueType.UNISWAP_V2, address(v2));
        token0.mint(address(this), 10000000 * (10 ** uint256(decimals0)));
        token1.mint(address(this), 10000000 * (10 ** uint256(decimals1)));
        token0.mint(address(router), 100000 * (10 ** uint256(decimals0)));
        token1.mint(address(router), 100000 * (10 ** uint256(decimals1)));
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        probe = new EdgeReentryProbe(vault, address(this));
        control.grantRole(control.MANAGER_ROLE(), address(probe));
        control.grantRole(control.KEEPER_ROLE(), address(probe));
        control.grantRole(control.GUARDIAN_ROLE(), address(probe));
        vault.approve(address(probe), type(uint256).max);
    }

    function _bootstrap(uint256 amount0, uint256 amount1) internal {
        vault.bootstrap(amount0, amount1, address(this));
    }

    function _plan(uint256 deviation) internal returns (PositionPlan memory plan) {
        oracle.setState(deviation, 17, true);
        (plan,) = vault.previewRebalance();
    }

    function _assertProbe(uint256 batches) internal view {
        assertEq(probe.batches(), batches);
        for (uint256 i; i < 6; ++i) {
            assertEq(probe.results(i), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        }
    }

    function _stateDigest() internal view returns (bytes32) {
        address[8] memory actors = [
            address(this),
            address(vault),
            address(low),
            address(high),
            address(v2),
            address(router),
            address(vault.swapExecutor()),
            address(probe)
        ];
        bytes32 balances;
        for (uint256 i; i < actors.length; ++i) {
            balances = keccak256(
                abi.encode(
                    balances,
                    token0.balanceOf(actors[i]),
                    token1.balanceOf(actors[i]),
                    vault.balanceOf(actors[i]),
                    token0.allowance(address(vault), actors[i]),
                    token1.allowance(address(vault), actors[i])
                )
            );
        }
        return keccak256(
            abi.encode(
                balances,
                vault.initialized(),
                vault.activeVenue(),
                vault.planVersion(),
                vault.lastPositionChangeAt(),
                vault.lastExecutedPlan(),
                vault.assetSnapshot(),
                low.snapshot(),
                high.snapshot(),
                v2.snapshot(),
                control.pauseState(),
                token0.allowance(address(this), address(vault)),
                token1.allowance(address(this), address(vault)),
                vault.allowance(address(this), address(probe)),
                token0.allowance(address(vault.swapExecutor()), address(router)),
                token1.allowance(address(vault.swapExecutor()), address(router)),
                token0.balanceOf(low.LOSS_SINK()),
                token1.balanceOf(low.LOSS_SINK()),
                oracle.snapshot(),
                router.swapCalls(),
                router.lastMinimum(),
                low.hookCalls(),
                high.hookCalls(),
                probe.batches()
            )
        );
    }
}
