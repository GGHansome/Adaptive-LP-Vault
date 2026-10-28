// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AdaptiveLPVault} from "../../src/core/AdaptiveLPVault.sol";
import {VaultComponentFactory} from "../../src/core/VaultComponentFactory.sol";
import {VaultControl} from "../../src/control/VaultControl.sol";
import {UniswapV2Adapter} from "../../src/adapters/UniswapV2Adapter.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
import {PositionAdapterConfig, PositionSnapshot} from "../../src/adapters/AdapterTypes.sol";
import {CanonicalV3Oracle} from "../../src/oracle/CanonicalV3Oracle.sol";
import {OracleConfig, OracleSnapshot} from "../../src/oracle/OracleTypes.sol";
import {ICanonicalV3Oracle} from "../../src/interfaces/ICanonicalV3Oracle.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {
    INonfungiblePositionManager,
    IUniswapV3Pool,
    IUniswapV3SwapRouter
} from "../../src/interfaces/IUniswapV3External.sol";
import {
    AccessControlConfig,
    AssetSnapshot,
    PositionPlan,
    StrategyConfig,
    VaultConfig,
    VenueType
} from "../../src/core/VaultTypes.sol";

interface IIntegrationV2Factory {
    function createPair(address, address) external returns (address);
}

interface IIntegrationV2Pair {
    function mint(address) external returns (uint256);
    function swap(uint256, uint256, address, bytes calldata) external;
    function getReserves() external view returns (uint112, uint112, uint32);
}

interface IIntegrationV3Factory {
    function createPool(address, address, uint24) external returns (address);
}

interface IIntegrationV3Pool {
    function initialize(uint160) external;
    function increaseObservationCardinalityNext(uint16) external;
}

/// @dev Test token for local Uniswap deployments and invariant handler funding.
contract LocalTestToken is ERC20 {
    uint8 private _DECIMALS;

    constructor(uint8 decimals_) ERC20("Local test token", "LTT") {
        _DECIMALS = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }

    function setDecimals(uint8 value) external {
        _DECIMALS = value;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Shared local Uniswap environment for integration and invariant tests.
/// Deploys official, pinned Uniswap bytecode; no pool/router/position-manager doubles.
/// Strategy scenarios override ONLY oracle.snapshot to select deterministic regimes.
/// Quotes still use the production oracle. Tests not calling _market use real observations.
abstract contract LocalUniswapFixture is Test {
    uint256 internal LOCKED;
    uint256 internal constant DUST = 10;
    uint32 internal constant COOLDOWN = 60;
    uint160 internal constant Q96 = 79228162514264337593543950336;

    address internal admin;
    address internal manager;
    address internal guardian;
    address internal keeper;
    address internal alice;
    address internal bob;
    address internal operator;
    address internal receiver;
    LocalTestToken internal token0;
    LocalTestToken internal token1;
    address internal v2Factory;
    address internal v3Factory;
    address internal pair;
    address internal lowPool;
    address internal highPool;
    address internal canonicalPool;
    INonfungiblePositionManager internal positionManager;
    IUniswapV3SwapRouter internal router;
    CanonicalV3Oracle internal oracle;
    AdaptiveLPVault internal vault;
    VaultControl internal control;
    UniswapV2Adapter internal v2;
    UniswapV3Adapter internal low;
    UniswapV3Adapter internal high;
    uint256 internal seed;

    function _tokenDecimals() internal pure virtual returns (uint8, uint8) {
        return (18, 18);
    }

    function setUp() public virtual {
        vm.warp(10_000);
        admin = makeAddr("integration admin");
        manager = makeAddr("integration manager");
        guardian = makeAddr("integration guardian");
        keeper = makeAddr("integration keeper");
        alice = makeAddr("integration alice");
        bob = makeAddr("integration bob");
        operator = makeAddr("integration operator");
        receiver = makeAddr("integration receiver");
        (uint8 d0, uint8 d1) = _tokenDecimals();
        LocalTestToken a = new LocalTestToken(d0);
        LocalTestToken b = new LocalTestToken(d1);
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);
        token0.setDecimals(d0);
        token1.setDecimals(d1);
        // The pools intentionally start at RAW price 1, including mixed-decimal suites.
        seed = 1000 * 10 ** uint256(Math.min(d0, d1));
        // Lock the same economic fraction for every precision configuration, retaining
        // representable underlying assets even when token1 uses only six decimals.
        LOCKED = Math.mulDiv(seed, 1e18, 10 ** uint256(d1)) / 1000;

        v2Factory = _artifact("@uniswap/v2-core/build/UniswapV2Factory.json", abi.encode(address(this)));
        v3Factory = _artifact("@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json", "");
        // Native ETH wrapping and NFT tokenURI are outside these ERC20 business flows.
        address weth = address(new LocalTestToken(18));
        positionManager = INonfungiblePositionManager(
            _artifact(
                "@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json",
                abi.encode(v3Factory, weth, address(0))
            )
        );
        router = IUniswapV3SwapRouter(
            _artifact(
                "@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json", abi.encode(v3Factory, weth)
            )
        );
        pair = IIntegrationV2Factory(v2Factory).createPair(address(token0), address(token1));
        lowPool = _createPool(500);
        highPool = _createPool(3000);
        canonicalPool = _createPool(10000);

        _fund(address(this), seed * 100_000);
        token0.approve(address(positionManager), type(uint256).max);
        token1.approve(address(positionManager), type(uint256).max);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.transfer(pair, seed * 1000);
        token1.transfer(pair, seed * 1000);
        IIntegrationV2Pair(pair).mint(address(this));
        _seedV3(500, -887220, 887220);
        _seedV3(3000, -887220, 887220);
        _seedV3(10000, -887200, 887200);
        vm.warp(vm.getBlockTimestamp() + 1801);
        oracle = new CanonicalV3Oracle(OracleConfig(canonicalPool, v3Factory, 1800, 300));
        assertTrue(oracle.snapshot().healthy, "real oracle must have sufficient history");
        vault = new AdaptiveLPVault(
            "Integration Vault",
            "IV",
            VaultConfig(
                DUST,
                DUST,
                address(oracle),
                address(new VaultComponentFactory()),
                address(router),
                v2Factory,
                v3Factory,
                LOCKED,
                1
            ),
            AccessControlConfig(1 days, admin),
            StrategyConfig(COOLDOWN, 100, 50, 300, 200, 500, 400, 10, 10, 100, 500, 200, 100)
        );
        control = VaultControl(address(vault.vaultControl()));
        vm.startPrank(admin);
        control.grantRole(control.MANAGER_ROLE(), manager);
        control.grantRole(control.GUARDIAN_ROLE(), guardian);
        control.grantRole(control.KEEPER_ROLE(), keeper);
        vm.stopPrank();
        v2 = new UniswapV2Adapter(
            PositionAdapterConfig(address(vault), VenueType.UNISWAP_V2, pair, v2Factory, address(0))
        );
        low = new UniswapV3Adapter(
            PositionAdapterConfig(
                address(vault), VenueType.UNISWAP_V3_LOW_FEE, lowPool, v3Factory, address(positionManager)
            )
        );
        high = new UniswapV3Adapter(
            PositionAdapterConfig(
                address(vault), VenueType.UNISWAP_V3_HIGH_FEE, highPool, v3Factory, address(positionManager)
            )
        );
        vm.startPrank(manager);
        control.configureAdapter(VenueType.UNISWAP_V2, address(v2));
        control.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(low));
        control.configureAdapter(VenueType.UNISWAP_V3_HIGH_FEE, address(high));
        vm.stopPrank();
        _fund(manager, seed * 100);
        _fund(alice, seed * 100);
        _fund(bob, seed * 100);
        _approveVault(manager);
        _approveVault(alice);
        _approveVault(bob);
    }

    function _artifact(string memory relativePath, bytes memory args) private returns (address deployed) {
        string memory path = string.concat(vm.projectRoot(), "/lib/uniswap-test-deps/node_modules/", relativePath);
        // V2 publishes both top-level and nested EVM bytecode, which vm.getCode cannot deserialize.
        string memory hexCode = vm.parseJsonString(vm.readFile(path), ".bytecode");
        bytes memory text = bytes(hexCode);
        if (text[0] != "0" || text[1] != "x") hexCode = string.concat("0x", hexCode);
        bytes memory creationCode = abi.encodePacked(vm.parseBytes(hexCode), args);
        assembly ("memory-safe") {
            deployed := create(0, add(creationCode, 32), mload(creationCode))
        }
        require(deployed != address(0), "official Uniswap artifact deployment failed");
    }

    function _createPool(uint24 fee) private returns (address pool) {
        pool = IIntegrationV3Factory(v3Factory).createPool(address(token0), address(token1), fee);
        IIntegrationV3Pool(pool).initialize(Q96);
        IIntegrationV3Pool(pool).increaseObservationCardinalityNext(16);
    }

    function _seedV3(uint24 fee, int24 lower, int24 upper) private {
        positionManager.mint(
            INonfungiblePositionManager.MintParams(
                address(token0),
                address(token1),
                fee,
                lower,
                upper,
                seed * 1000,
                seed * 1000,
                0,
                0,
                address(this),
                vm.getBlockTimestamp()
            )
        );
    }

    function _fund(address account, uint256 amount) internal {
        token0.mint(account, amount);
        token1.mint(account, amount);
    }

    function _approveVault(address account) internal {
        vm.startPrank(account);
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function _market(uint256 deviation) internal {
        vm.clearMockedCalls();
        OracleSnapshot memory snapshot = oracle.snapshot();
        assertTrue(snapshot.healthy);
        snapshot.deviationBps = deviation;
        vm.mockCall(address(oracle), abi.encodeCall(ICanonicalV3Oracle.snapshot, ()), abi.encode(snapshot));
    }

    function _bootstrap(VenueType venue) internal {
        if (venue == VenueType.UNISWAP_V3_HIGH_FEE) _market(150);
        if (venue == VenueType.UNISWAP_V2) _market(350);
        if (venue == VenueType.IDLE) _market(600);
        vm.prank(manager);
        vault.bootstrap(seed, seed, manager);
        assertEq(uint8(vault.activeVenue()), uint8(venue));
        _assertAccounting();
    }

    function _adapter(VenueType venue) internal view returns (IPositionAdapter) {
        if (venue == VenueType.UNISWAP_V2) return IPositionAdapter(address(v2));
        if (venue == VenueType.UNISWAP_V3_LOW_FEE) return IPositionAdapter(address(low));
        return IPositionAdapter(address(high));
    }

    function _assertAccounting() internal view {
        AssetSnapshot memory assets = vault.assetSnapshot();
        assertEq(assets.idle0, token0.balanceOf(address(vault)));
        assertEq(assets.idle1, token1.balanceOf(address(vault)));
        assertEq(assets.total0, assets.idle0 + assets.position0);
        assertEq(assets.total1, assets.idle1 + assets.position1);
        assertEq(assets.totalShares, vault.totalSupply());
        assertEq(vault.balanceOf(address(vault)), LOCKED);
        VenueType active = vault.activeVenue();
        if (active != VenueType.UNISWAP_V2) assertEq(IERC20(pair).balanceOf(address(v2)), 0);
        if (active != VenueType.UNISWAP_V3_LOW_FEE) assertEq(low.positionId(), 0);
        if (active != VenueType.UNISWAP_V3_HIGH_FEE) assertEq(high.positionId(), 0);
        if (active != VenueType.IDLE) {
            PositionSnapshot memory position = _adapter(active).snapshot();
            assertGt(position.liquidity, 0);
            assertEq(assets.position0, position.amount0);
            assertEq(assets.position1, position.amount1);
            if (active != VenueType.UNISWAP_V2) {
                PositionPlan memory plan = vault.lastExecutedPlan();
                assertEq(position.tickLower, plan.tickLower);
                assertEq(position.tickUpper, plan.tickUpper);
                assertEq(positionManager.ownerOf(position.positionId), address(_adapter(active)));
            }
        }
        address[3] memory adapters = [address(v2), address(low), address(high)];
        for (uint256 i; i < adapters.length; ++i) {
            assertEq(token0.allowance(address(vault), adapters[i]), 0);
            assertEq(token1.allowance(address(vault), adapters[i]), 0);
            assertEq(token0.balanceOf(adapters[i]), 0);
            assertEq(token1.balanceOf(adapters[i]), 0);
        }
        assertEq(token0.allowance(address(low), address(positionManager)), 0);
        assertEq(token1.allowance(address(low), address(positionManager)), 0);
        assertEq(token0.allowance(address(high), address(positionManager)), 0);
        assertEq(token1.allowance(address(high), address(positionManager)), 0);
        assertEq(token0.allowance(address(vault.swapExecutor()), address(router)), 0);
        assertEq(token1.allowance(address(vault.swapExecutor()), address(router)), 0);
        assertEq(token0.balanceOf(address(vault.swapExecutor())), 0);
        assertEq(token1.balanceOf(address(vault.swapExecutor())), 0);
    }
}
