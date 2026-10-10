// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {AdapterRegistry} from "../../src/core/AdapterRegistry.sol";
import {VaultControl} from "../../src/core/VaultControl.sol";
import {VaultPause} from "../../src/core/VaultPause.sol";
import {VaultRoles} from "../../src/core/VaultRoles.sol";
import {AccessControlConfig, AdapterConfig, PauseFlag, PauseState, VenueType} from "../../src/core/VaultTypes.sol";
import {IAdapterRegistry} from "../../src/interfaces/IAdapterRegistry.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {IVaultPause} from "../../src/interfaces/IVaultPause.sol";
import {IVaultControl} from "../../src/interfaces/IVaultControl.sol";
import {IVaultRoles} from "../../src/interfaces/IVaultRoles.sol";

contract MockCoreToken {}

contract MockCoreVaultLifecycle {
    bool public initialized;

    function setInitialized(bool initialized_) external {
        initialized = initialized_;
    }
}

contract MockCoreFactory {
    mapping(address tokenA => mapping(address tokenB => address pair)) public getPair;
    mapping(address tokenA => mapping(address tokenB => mapping(uint24 fee => address pool))) public getPool;

    function registerPair(address token0, address token1, address pair) external {
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
    }

    function registerPool(address token0, address token1, uint24 fee, address pool) external {
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool;
    }
}

contract MockCoreV2Pool {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    constructor(address factory_, address token0_, address token1_) {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
    }
}

contract MockCoreV3Pool {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;

    constructor(address factory_, address token0_, address token1_, uint24 fee_, int24 tickSpacing_) {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
        tickSpacing = tickSpacing_;
    }
}

contract MockCoreAdapter {
    address public immutable vault;
    VenueType public immutable venue;
    address public immutable pool;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable feeTier;
    int24 public tickSpacing;

    constructor(
        address vault_,
        VenueType venue_,
        address pool_,
        address token0_,
        address token1_,
        uint24 feeTier_,
        int24 tickSpacing_
    ) {
        vault = vault_;
        venue = venue_;
        pool = pool_;
        token0 = token0_;
        token1 = token1_;
        feeTier = feeTier_;
        tickSpacing = tickSpacing_;
    }

    function setTickSpacing(int24 newTickSpacing) external {
        tickSpacing = newTickSpacing;
    }
}

contract VaultRolesHarness is VaultRoles {
    constructor(AccessControlConfig memory config) VaultRoles(config) {}
}

contract VaultPauseHarness is VaultPause {
    bool private _initialized;

    constructor(AccessControlConfig memory config) VaultRoles(config) {}

    function setInitialized(bool initialized_) external {
        _initialized = initialized_;
    }

    function requireNotPaused(PauseFlag flag) external view {
        _requireNotPaused(flag);
    }

    function pauseAll(address caller) external returns (bool changed) {
        return _pauseAll(caller);
    }

    function _vaultInitialized() internal view override returns (bool) {
        return _initialized;
    }
}

contract AdapterRegistryHarness is AdapterRegistry {
    bool private _initialized;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    address private immutable _V2_FACTORY;
    address private immutable _V3_FACTORY;

    constructor(
        AccessControlConfig memory config,
        address token0_,
        address token1_,
        address v2Factory_,
        address v3Factory_
    ) VaultRoles(config) {
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _V2_FACTORY = v2Factory_;
        _V3_FACTORY = v3Factory_;
    }

    function setInitialized(bool initialized_) external {
        _initialized = initialized_;
    }

    function validateConfiguredAdapters() external view {
        _validateConfiguredAdapters();
    }

    function requireEnterEnabled(VenueType venue) external view returns (address) {
        return _requireEnterEnabled(venue);
    }

    function adapterTickSpacing(VenueType venue) external view returns (int24) {
        return _adapterTickSpacing(venue);
    }

    function _vaultInitialized() internal view override returns (bool) {
        return _initialized;
    }

    function _registryVault() internal view override returns (address) {
        return address(this);
    }

    function _registryToken0() internal view override returns (address) {
        return _TOKEN0;
    }

    function _registryToken1() internal view override returns (address) {
        return _TOKEN1;
    }

    function _registryV2Factory() internal view override returns (address) {
        return _V2_FACTORY;
    }

    function _registryV3Factory() internal view override returns (address) {
        return _V3_FACTORY;
    }
}

contract CombinedCoreHarness is VaultPause, AdapterRegistry {
    bool private _initialized;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    address private immutable _V2_FACTORY;
    address private immutable _V3_FACTORY;

    constructor(
        AccessControlConfig memory config,
        address token0_,
        address token1_,
        address v2Factory_,
        address v3Factory_
    ) VaultRoles(config) {
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _V2_FACTORY = v2Factory_;
        _V3_FACTORY = v3Factory_;
    }

    function setInitialized(bool initialized_) external {
        _initialized = initialized_;
    }

    function _vaultInitialized() internal view override(VaultPause, AdapterRegistry) returns (bool) {
        return _initialized;
    }

    function _registryVault() internal view override returns (address) {
        return address(this);
    }

    function _registryToken0() internal view override returns (address) {
        return _TOKEN0;
    }

    function _registryToken1() internal view override returns (address) {
        return _TOKEN1;
    }

    function _registryV2Factory() internal view override returns (address) {
        return _V2_FACTORY;
    }

    function _registryV3Factory() internal view override returns (address) {
        return _V3_FACTORY;
    }
}

contract CoreModulesTest is Test {
    address private constant MANAGER = address(0xA11CE);
    address private constant GUARDIAN = address(0xB0B);
    address private constant OUTSIDER = address(0xCAFE);

    AccessControlConfig private accessConfig;
    MockCoreToken private tokenA;
    MockCoreToken private tokenB;
    MockCoreFactory private v2Factory;
    MockCoreFactory private v3Factory;
    address private token0;
    address private token1;

    function setUp() external {
        accessConfig = AccessControlConfig({initialDefaultAdminDelay: 2 days, initialDefaultAdmin: address(this)});
        tokenA = new MockCoreToken();
        tokenB = new MockCoreToken();
        v2Factory = new MockCoreFactory();
        v3Factory = new MockCoreFactory();
        (token0, token1) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));
    }

    function test_modulesComposeIntoOneVaultInheritanceGraph() external {
        CombinedCoreHarness combined =
            new CombinedCoreHarness(accessConfig, token0, token1, address(v2Factory), address(v3Factory));
        combined.grantRole(combined.MANAGER_ROLE(), MANAGER);
        combined.setInitialized(true);

        vm.prank(MANAGER);
        combined.setPauseState(
            PauseState({depositPaused: true, plainRebalancePaused: false, swapRebalancePaused: true})
        );

        assertTrue(combined.pauseState().depositPaused);
        assertEq(combined.getAdapter(VenueType.IDLE), address(0));
        assertEq(combined.defaultAdmin(), address(this));
    }

    function test_rolesUseFixedIdentifiersWithoutImplicitBusinessPermissions() external {
        VaultRolesHarness roles = new VaultRolesHarness(accessConfig);

        assertEq(roles.defaultAdmin(), address(this));
        assertEq(roles.defaultAdminDelay(), 2 days);
        assertEq(roles.DEFAULT_ADMIN_ROLE(), bytes32(0));
        assertEq(roles.MANAGER_ROLE(), keccak256("MANAGER_ROLE"));
        assertEq(roles.KEEPER_ROLE(), keccak256("KEEPER_ROLE"));
        assertEq(roles.GUARDIAN_ROLE(), keccak256("GUARDIAN_ROLE"));
        assertFalse(roles.hasRole(roles.MANAGER_ROLE(), address(this)));
        assertFalse(roles.hasRole(roles.KEEPER_ROLE(), address(this)));
        assertFalse(roles.hasRole(roles.GUARDIAN_ROLE(), address(this)));
        assertEq(roles.getRoleAdmin(roles.MANAGER_ROLE()), roles.DEFAULT_ADMIN_ROLE());
        assertTrue(roles.supportsInterface(type(IVaultRoles).interfaceId));
    }

    function test_pauseChecksRoleBeforeLifecycleAndGuardianCannotRelax() external {
        VaultPauseHarness pause = new VaultPauseHarness(accessConfig);
        pause.grantRole(pause.MANAGER_ROLE(), MANAGER);
        pause.grantRole(pause.GUARDIAN_ROLE(), GUARDIAN);
        PauseState memory allPaused =
            PauseState({depositPaused: true, plainRebalancePaused: true, swapRebalancePaused: true});

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, OUTSIDER, pause.MANAGER_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        pause.setPauseState(allPaused);

        vm.expectRevert(IAdapterRegistry.NotInitialized.selector);
        vm.prank(MANAGER);
        pause.setPauseState(allPaused);

        pause.setInitialized(true);
        vm.prank(GUARDIAN);
        pause.setPauseState(allPaused);
        assertTrue(pause.pauseState().depositPaused);

        vm.expectRevert(IVaultPause.GuardianCannotUnpause.selector);
        vm.prank(GUARDIAN);
        pause.setPauseState(PauseState({depositPaused: false, plainRebalancePaused: true, swapRebalancePaused: true}));

        vm.prank(MANAGER);
        pause.setPauseState(PauseState({depositPaused: false, plainRebalancePaused: true, swapRebalancePaused: false}));
        PauseState memory state = pause.pauseState();
        assertFalse(state.depositPaused);
        assertTrue(state.plainRebalancePaused);
        assertFalse(state.swapRebalancePaused);
    }

    function test_pauseInternalGuardsAndEmergencyPauseAreIndependent() external {
        VaultPauseHarness pause = new VaultPauseHarness(accessConfig);
        pause.setInitialized(true);

        assertTrue(pause.pauseAll(GUARDIAN));
        assertFalse(pause.pauseAll(GUARDIAN));

        vm.expectRevert(abi.encodeWithSelector(IVaultPause.Paused.selector, PauseFlag.DEPOSIT));
        pause.requireNotPaused(PauseFlag.DEPOSIT);
        vm.expectRevert(abi.encodeWithSelector(IVaultPause.Paused.selector, PauseFlag.PLAIN_REBALANCE));
        pause.requireNotPaused(PauseFlag.PLAIN_REBALANCE);
        vm.expectRevert(abi.encodeWithSelector(IVaultPause.Paused.selector, PauseFlag.SWAP_REBALANCE));
        pause.requireNotPaused(PauseFlag.SWAP_REBALANCE);
    }

    function test_controlBindsVaultAndEnforcesVaultOnlyOperationalChecks() external {
        MockCoreVaultLifecycle lifecycle = new MockCoreVaultLifecycle();
        VaultControl control =
            new VaultControl(address(lifecycle), accessConfig, token0, token1, address(v2Factory), address(v3Factory));
        control.grantRole(control.MANAGER_ROLE(), MANAGER);
        control.grantRole(control.GUARDIAN_ROLE(), GUARDIAN);

        assertEq(control.vault(), address(lifecycle));
        assertEq(control.token0(), token0);
        assertEq(control.token1(), token1);
        assertTrue(control.supportsInterface(type(IVaultControl).interfaceId));

        (MockCoreAdapter v2, MockCoreAdapter low, MockCoreAdapter high) = _deployAdaptersForVault(address(lifecycle));
        vm.startPrank(MANAGER);
        control.configureAdapter(VenueType.UNISWAP_V2, address(v2));
        control.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(low));
        control.configureAdapter(VenueType.UNISWAP_V3_HIGH_FEE, address(high));
        vm.stopPrank();

        vm.expectRevert(IVaultControl.NotVaultCaller.selector);
        control.validateConfiguredAdapters();

        vm.prank(address(lifecycle));
        control.validateConfiguredAdapters();
        vm.prank(address(lifecycle));
        (int24 lowSpacing, int24 highSpacing) = control.adapterTickSpacings();
        assertEq(lowSpacing, 10);
        assertEq(highSpacing, 60);

        lifecycle.setInitialized(true);
        vm.prank(MANAGER);
        control.setPauseState(
            PauseState({depositPaused: true, plainRebalancePaused: false, swapRebalancePaused: false})
        );
        vm.expectRevert(abi.encodeWithSelector(IVaultPause.Paused.selector, PauseFlag.DEPOSIT));
        vm.prank(address(lifecycle));
        control.requireDepositEnabled(VenueType.UNISWAP_V3_LOW_FEE);
    }

    function test_registryConfiguresAndFreezesValidatedBindings() external {
        AdapterRegistryHarness registry = _newRegistry();
        (MockCoreAdapter v2, MockCoreAdapter low, MockCoreAdapter high) = _deployAdapters(registry);

        vm.startPrank(MANAGER);
        registry.configureAdapter(VenueType.UNISWAP_V2, address(v2));
        registry.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(low));
        registry.configureAdapter(VenueType.UNISWAP_V3_HIGH_FEE, address(high));
        vm.stopPrank();

        AdapterConfig memory lowConfig = registry.getConfig(VenueType.UNISWAP_V3_LOW_FEE);
        assertEq(lowConfig.adapter, address(low));
        assertEq(lowConfig.tickSpacing, 10);
        assertTrue(lowConfig.enabled);
        assertEq(registry.getAdapter(VenueType.IDLE), address(0));
        assertFalse(registry.isEnterEnabled(VenueType.IDLE));
        assertEq(registry.adapterTickSpacing(VenueType.UNISWAP_V3_HIGH_FEE), 60);
        registry.validateConfiguredAdapters();

        registry.setInitialized(true);
        vm.expectRevert(IAdapterRegistry.AlreadyInitialized.selector);
        vm.prank(MANAGER);
        registry.configureAdapter(VenueType.UNISWAP_V2, address(v2));
    }

    function test_registryRoleAndLifecycleOrderingAndGuardianStatusLimits() external {
        AdapterRegistryHarness registry = _newRegistry();
        (MockCoreAdapter v2,,) = _deployAdapters(registry);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, OUTSIDER, registry.MANAGER_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        registry.setAdapterEnabled(VenueType.UNISWAP_V2, false);

        vm.expectRevert(IAdapterRegistry.NotInitialized.selector);
        vm.prank(MANAGER);
        registry.setAdapterEnabled(VenueType.UNISWAP_V2, false);

        vm.prank(MANAGER);
        registry.configureAdapter(VenueType.UNISWAP_V2, address(v2));
        registry.setInitialized(true);

        vm.prank(GUARDIAN);
        registry.setAdapterEnabled(VenueType.UNISWAP_V2, false);
        assertFalse(registry.isEnterEnabled(VenueType.UNISWAP_V2));
        vm.expectRevert(IAdapterRegistry.AdapterDisabled.selector);
        registry.requireEnterEnabled(VenueType.UNISWAP_V2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, GUARDIAN, registry.MANAGER_ROLE()
            )
        );
        vm.prank(GUARDIAN);
        registry.setAdapterEnabled(VenueType.UNISWAP_V2, true);

        vm.prank(MANAGER);
        registry.setAdapterEnabled(VenueType.UNISWAP_V2, true);
        assertTrue(registry.isEnterEnabled(VenueType.UNISWAP_V2));
    }

    function test_registryRejectsReversedAdapterTokenOrder() external {
        AdapterRegistryHarness registry = _newRegistry();
        MockCoreV2Pool pool = new MockCoreV2Pool(address(v2Factory), token0, token1);
        v2Factory.registerPair(token0, token1, address(pool));
        MockCoreAdapter adapter =
            new MockCoreAdapter(address(registry), VenueType.UNISWAP_V2, address(pool), token1, token0, 0, 0);

        vm.expectRevert(IAdapterRegistry.InvalidAssetPair.selector);
        vm.prank(MANAGER);
        registry.configureAdapter(VenueType.UNISWAP_V2, address(adapter));
    }

    function test_registryRejectsSelfCertifiedPairFromUnexpectedFactory() external {
        AdapterRegistryHarness registry = _newRegistry();
        MockCoreFactory unexpectedFactory = new MockCoreFactory();
        MockCoreV2Pool pool = new MockCoreV2Pool(address(unexpectedFactory), token0, token1);
        unexpectedFactory.registerPair(token0, token1, address(pool));
        MockCoreAdapter adapter =
            new MockCoreAdapter(address(registry), VenueType.UNISWAP_V2, address(pool), token0, token1, 0, 0);

        vm.expectRevert(IPositionAdapter.InvalidPoolBinding.selector);
        vm.prank(MANAGER);
        registry.configureAdapter(VenueType.UNISWAP_V2, address(adapter));
    }

    function test_registryRevalidationDetectsChangedSpacingCache() external {
        AdapterRegistryHarness registry = _newRegistry();
        (MockCoreAdapter v2, MockCoreAdapter low, MockCoreAdapter high) = _deployAdapters(registry);

        vm.startPrank(MANAGER);
        registry.configureAdapter(VenueType.UNISWAP_V2, address(v2));
        registry.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(low));
        registry.configureAdapter(VenueType.UNISWAP_V3_HIGH_FEE, address(high));
        vm.stopPrank();

        low.setTickSpacing(60);
        vm.expectRevert(IAdapterRegistry.InvalidTickSpacing.selector);
        registry.validateConfiguredAdapters();
    }

    function _newRegistry() private returns (AdapterRegistryHarness registry) {
        registry = new AdapterRegistryHarness(accessConfig, token0, token1, address(v2Factory), address(v3Factory));
        registry.grantRole(registry.MANAGER_ROLE(), MANAGER);
        registry.grantRole(registry.GUARDIAN_ROLE(), GUARDIAN);
    }

    function _deployAdapters(AdapterRegistryHarness registry)
        private
        returns (MockCoreAdapter v2, MockCoreAdapter low, MockCoreAdapter high)
    {
        return _deployAdaptersForVault(address(registry));
    }

    function _deployAdaptersForVault(address vault_)
        private
        returns (MockCoreAdapter v2, MockCoreAdapter low, MockCoreAdapter high)
    {
        MockCoreV2Pool v2Pool = new MockCoreV2Pool(address(v2Factory), token0, token1);
        MockCoreV3Pool lowPool = new MockCoreV3Pool(address(v3Factory), token0, token1, 500, 10);
        MockCoreV3Pool highPool = new MockCoreV3Pool(address(v3Factory), token0, token1, 3000, 60);
        v2Factory.registerPair(token0, token1, address(v2Pool));
        v3Factory.registerPool(token0, token1, 500, address(lowPool));
        v3Factory.registerPool(token0, token1, 3000, address(highPool));

        v2 = new MockCoreAdapter(vault_, VenueType.UNISWAP_V2, address(v2Pool), token0, token1, 0, 0);
        low = new MockCoreAdapter(vault_, VenueType.UNISWAP_V3_LOW_FEE, address(lowPool), token0, token1, 500, 10);
        high = new MockCoreAdapter(vault_, VenueType.UNISWAP_V3_HIGH_FEE, address(highPool), token0, token1, 3000, 60);
    }
}
