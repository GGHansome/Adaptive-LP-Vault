// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssessmentOracle} from "../mocks/AssessmentMocks.sol";
import {MockV2ERC20, MockV2Factory, MockV2Pair} from "../mocks/UniswapV2Mocks.sol";
import {DonationV3Adapter, DonationRouter} from "../mocks/DonationMocks.sol";
import {UniswapV2Adapter} from "../../../src/adapters/UniswapV2Adapter.sol";
import {PositionAdapterConfig} from "../../../src/adapters/AdapterTypes.sol";
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

/// @dev Shared setup only: new suites do not inherit and rerun donation test functions.
abstract contract AdaptiveLPVaultFixture is Test {
    uint256 internal constant SEED = 1000 ether;
    uint256 internal constant LOCKED = 1 ether;
    AdaptiveLPVault internal vault;
    VaultControl internal control;
    AssessmentOracle internal oracle;
    MockV2ERC20 internal token0;
    MockV2ERC20 internal token1;
    MockV2Pair internal pair;
    UniswapV2Adapter internal v2;
    DonationV3Adapter internal low;
    DonationV3Adapter internal high;
    DonationRouter internal router;

    function setUp() public virtual {
        MockV2ERC20 a = new MockV2ERC20("Donation A", "DA");
        MockV2ERC20 b = new MockV2ERC20("Donation B", "DB");
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);
        MockV2Factory v2Factory = new MockV2Factory();
        pair = MockV2Pair(v2Factory.createPair(address(token0), address(token1)));
        token0.mint(address(this), 2_000_000 ether);
        token1.mint(address(this), 2_000_000 ether);
        token0.transfer(address(pair), 1_000_000 ether);
        token1.transfer(address(pair), 1_000_000 ether);
        pair.mint(address(this));

        address v3Factory = makeAddr("donation v3 factory");
        vm.etch(v3Factory, hex"00");
        address lowPool = _pool("donation low pool", v3Factory, 500, 10);
        address highPool = _pool("donation high pool", v3Factory, 3000, 60);
        router = new DonationRouter(v3Factory);
        token0.mint(address(router), 100_000 ether);
        token1.mint(address(router), 100_000 ether);
        oracle = new AssessmentOracle(lowPool, address(token0), address(token1));
        VaultConfig memory config = VaultConfig({
            dustTolerance0: 1,
            dustTolerance1: 1,
            canonicalOracle: address(oracle),
            componentFactory: address(new VaultComponentFactory()),
            router: address(router),
            uniswapV2Factory: address(v2Factory),
            uniswapV3Factory: v3Factory,
            minimumLockedShares: LOCKED,
            minimumInitialNav: 1
        });
        StrategyConfig memory strategy = StrategyConfig({
            minRebalanceCooldown: _rebalanceCooldown(),
            enterMediumBps: 100,
            exitMediumBps: 50,
            enterHighBps: 300,
            exitHighBps: 200,
            enterExtremeBps: 500,
            exitExtremeBps: 400,
            narrowRangeHalfWidthSteps: 10,
            wideRangeHalfWidthSteps: 10,
            minRecenterBps: 100,
            maxHealthyIdleBps: 500,
            maxSwapSlippageBps: 100,
            maxMigrationLossBps: 10
        });
        vault = new AdaptiveLPVault("Donation Vault", "DV", config, AccessControlConfig(0, address(this)), strategy);
        control = VaultControl(address(vault.vaultControl()));
        control.grantRole(control.MANAGER_ROLE(), address(this));
        v2 = new UniswapV2Adapter(
            PositionAdapterConfig({
                vault: address(vault),
                venue: VenueType.UNISWAP_V2,
                pool: address(pair),
                factory: address(v2Factory),
                positionManager: address(0)
            })
        );
        low = new DonationV3Adapter(
            address(vault), lowPool, address(token0), address(token1), VenueType.UNISWAP_V3_LOW_FEE
        );
        high = new DonationV3Adapter(
            address(vault), highPool, address(token0), address(token1), VenueType.UNISWAP_V3_HIGH_FEE
        );
        control.configureAdapter(VenueType.UNISWAP_V2, address(v2));
        control.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(low));
        control.configureAdapter(VenueType.UNISWAP_V3_HIGH_FEE, address(high));
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
    }

    function _rebalanceCooldown() internal pure virtual returns (uint32) {
        return 0;
    }

    function _bootstrap(uint256 deviation, uint256 amount0, uint256 amount1) internal {
        oracle.setDeviation(deviation);
        vault.bootstrap(amount0, amount1, address(this));
    }

    function _plan(uint256 deviation) internal returns (PositionPlan memory plan) {
        oracle.setDeviation(deviation);
        (plan,) = vault.previewRebalance();
    }

    function _pool(string memory name, address factory, uint24 fee, int24 spacing) private returns (address pool) {
        pool = makeAddr(name);
        vm.etch(pool, hex"00");
        vm.mockCall(pool, abi.encodeWithSignature("token0()"), abi.encode(address(token0)));
        vm.mockCall(pool, abi.encodeWithSignature("token1()"), abi.encode(address(token1)));
        vm.mockCall(pool, abi.encodeWithSignature("factory()"), abi.encode(factory));
        vm.mockCall(pool, abi.encodeWithSignature("fee()"), abi.encode(fee));
        vm.mockCall(pool, abi.encodeWithSignature("tickSpacing()"), abi.encode(spacing));
        vm.mockCall(
            factory,
            abi.encodeWithSignature("getPool(address,address,uint24)", address(token0), address(token1), fee),
            abi.encode(pool)
        );
    }
}
