// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AdaptiveLPVault} from "../../../src/core/AdaptiveLPVault.sol";
import {VaultComponentFactory} from "../../../src/core/VaultComponentFactory.sol";
import {VaultControl} from "../../../src/control/VaultControl.sol";
import {UniswapV2Adapter} from "../../../src/adapters/UniswapV2Adapter.sol";
import {UniswapV3Adapter} from "../../../src/adapters/UniswapV3Adapter.sol";
import {PositionAdapterConfig, PositionSnapshot} from "../../../src/adapters/AdapterTypes.sol";
import {CanonicalV3Oracle} from "../../../src/oracle/CanonicalV3Oracle.sol";
import {OracleConfig, OracleSnapshot} from "../../../src/oracle/OracleTypes.sol";
import {IPositionAdapter} from "../../../src/interfaces/IPositionAdapter.sol";
import {INonfungiblePositionManager, IUniswapV3SwapRouter} from "../../../src/interfaces/IUniswapV3External.sol";
import {
    AccessControlConfig,
    AssetSnapshot,
    DeploymentAssessment,
    PositionPlan,
    StrategyConfig,
    VaultConfig,
    VenueType
} from "../../../src/core/VaultTypes.sol";

interface IForkWETH is IERC20 {
    function deposit() external payable;
}

interface IForkV2Pair is IERC20 {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function factory() external view returns (address);
    function getReserves() external view returns (uint112, uint112, uint32);
    function swap(uint256, uint256, address, bytes calldata) external;
}

interface IForkV2Factory {
    function getPair(address, address) external view returns (address);
}

/// @dev No protocol mocks, storage writes, synthetic ERC20 balances, or deployment scripts.
/// The fixed historical deviation selects HIGH/V2 with deliberately small TEST thresholds.
abstract contract MainnetForkFixture is Test {
    uint256 internal constant BASELINE_BLOCK = 21_000_000;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address internal constant LOW_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address internal constant HIGH_POOL = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;
    address internal constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant USDC_HOLDER = 0x28C6c06298d514Db089934071355E5743bf21d60;
    uint256 internal constant LOCKED = 1e12;
    // Raw-unit bounds: V2 double ratio-flooring can lose a few USDC micro-units' WETH
    // equivalent (~3.8e8 wei each at this block), in addition to LP/liquidity rounding.
    uint256 internal constant DUST0 = 10;
    uint256 internal constant DUST1 = 2_000_000_000;
    uint32 internal constant COOLDOWN = 60;

    IERC20 internal token0 = IERC20(USDC);
    IERC20 internal token1 = IERC20(WETH);
    IUniswapV3SwapRouter internal router = IUniswapV3SwapRouter(ROUTER);
    INonfungiblePositionManager internal positionManager = INonfungiblePositionManager(POSITION_MANAGER);
    CanonicalV3Oracle internal oracle;
    AdaptiveLPVault internal vault;
    VaultControl internal control;
    UniswapV2Adapter internal v2;
    UniswapV3Adapter internal low;
    UniswapV3Adapter internal high;
    address internal admin;
    address internal manager;
    address internal guardian;
    address internal keeper;
    address internal alice;
    address internal bob;
    address internal operator;
    address internal receiver;
    uint256 internal seed0;
    uint256 internal seed1;

    function setUp() public virtual {
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        require(bytes(rpc).length != 0, "MAINNET_RPC_URL must be an archive RPC");
        vm.createSelectFork(rpc, vm.envOr("MAINNET_FORK_BLOCK", BASELINE_BLOCK));
        assertEq(block.chainid, 1, "Ethereum mainnet required");
        admin = makeAddr("fork admin");
        manager = makeAddr("fork manager");
        guardian = makeAddr("fork guardian");
        keeper = makeAddr("fork keeper");
        alice = makeAddr("fork alice");
        bob = makeAddr("fork bob");
        operator = makeAddr("fork operator");
        receiver = makeAddr("fork receiver");
        oracle = new CanonicalV3Oracle(OracleConfig(LOW_POOL, V3_FACTORY, 1800, 300));
        assertTrue(oracle.snapshot().healthy, "baseline needs real observation history");
    }

    function _deployAndBootstrap(VenueType venue) internal {
        _deployAndBootstrap(venue, 50);
    }

    function _deployAndBootstrap(VenueType venue, uint24 narrowSteps) internal {
        StrategyConfig memory strategy =
            StrategyConfig(COOLDOWN, 100, 50, 300, 200, 1000, 800, narrowSteps, 50, 2500, 500, 100, 50);
        if (venue == VenueType.UNISWAP_V3_HIGH_FEE) {
            strategy.enterMediumBps = 1;
            strategy.exitMediumBps = 0;
        } else if (venue == VenueType.UNISWAP_V2) {
            strategy.enterMediumBps = 1;
            strategy.exitMediumBps = 0;
            strategy.enterHighBps = 2;
            strategy.exitHighBps = 1;
        }
        // HIGH/V2 intentionally use the existing short/long TWAP difference, not mocked observations.
        uint256 deviation = oracle.snapshot().deviationBps;
        if (venue != VenueType.UNISWAP_V3_LOW_FEE) assertGe(deviation, 2, "historical regime assumption changed");
        assertLt(deviation, 100, "baseline must be a quiet market");
        vault = new AdaptiveLPVault(
            "Mainnet Fork Vault",
            "MFV",
            VaultConfig(
                DUST0,
                DUST1,
                address(oracle),
                address(new VaultComponentFactory()),
                ROUTER,
                V2_FACTORY,
                V3_FACTORY,
                LOCKED,
                1
            ),
            AccessControlConfig(1 days, admin),
            strategy
        );
        control = VaultControl(address(vault.vaultControl()));
        vm.startPrank(admin);
        control.grantRole(control.MANAGER_ROLE(), manager);
        control.grantRole(control.GUARDIAN_ROLE(), guardian);
        control.grantRole(control.KEEPER_ROLE(), keeper);
        vm.stopPrank();
        v2 = new UniswapV2Adapter(
            PositionAdapterConfig(address(vault), VenueType.UNISWAP_V2, PAIR, V2_FACTORY, address(0))
        );
        low = new UniswapV3Adapter(
            PositionAdapterConfig(address(vault), VenueType.UNISWAP_V3_LOW_FEE, LOW_POOL, V3_FACTORY, POSITION_MANAGER)
        );
        high = new UniswapV3Adapter(
            PositionAdapterConfig(
                address(vault), VenueType.UNISWAP_V3_HIGH_FEE, HIGH_POOL, V3_FACTORY, POSITION_MANAGER
            )
        );
        vm.startPrank(manager);
        control.configureAdapter(VenueType.UNISWAP_V2, address(v2));
        control.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, address(low));
        control.configureAdapter(VenueType.UNISWAP_V3_HIGH_FEE, address(high));
        vm.stopPrank();

        _fund(address(this), 5_000_000e6, 1000 ether);
        _fund(manager, 100_000e6, 100 ether);
        _fund(alice, 100_000e6, 100 ether);
        _fund(bob, 100_000e6, 100 ether);
        token0.approve(ROUTER, type(uint256).max);
        token1.approve(ROUTER, type(uint256).max);
        _approveVault(manager);
        _approveVault(alice);
        _approveVault(bob);

        // Match the real adapter's raw-unit ratio rather than assuming equal dollar/raw amounts.
        PositionPlan memory plan;
        plan.targetVenue = venue;
        if (venue != VenueType.UNISWAP_V2) {
            int24 spacing = venue == VenueType.UNISWAP_V3_LOW_FEE ? int24(10) : int24(60);
            int24 tick = oracle.snapshot().twapTick;
            int24 center = tick / spacing * spacing;
            if (tick < 0 && tick % spacing != 0) center -= spacing;
            if ((tick - center) * 2 > spacing) center += spacing;
            int24 halfWidth = int24(venue == VenueType.UNISWAP_V3_LOW_FEE ? narrowSteps : uint24(50)) * spacing;
            plan.tickLower = center - halfWidth;
            plan.tickUpper = center + halfWidth;
        }
        (seed0, seed1) = _adapter(venue).previewDeposit(10_000e6, 10 ether, plan);
        assertGt(seed0, 0);
        assertGt(seed1, 0);
        uint256 expectedSupply = _nav(seed0, seed1, oracle.snapshot().twapTick);
        vm.prank(manager);
        vault.bootstrap(seed0, seed1, manager);
        assertEq(uint8(vault.activeVenue()), uint8(venue));
        assertEq(vault.totalSupply(), expectedSupply, "WETH-denominated NAV equals 18-decimal shares");
        assertEq(vault.balanceOf(manager), expectedSupply - LOCKED);
        _assertAccounting();
    }

    function _fund(address account, uint256 amount0, uint256 amount1) internal {
        uint256 before0 = token0.balanceOf(account);
        vm.prank(USDC_HOLDER);
        assertTrue(token0.transfer(account, amount0));
        assertEq(token0.balanceOf(account) - before0, amount0);
        // Only native ETH is assigned; the real WETH contract mints through deposit().
        uint256 before1 = token1.balanceOf(account);
        vm.deal(account, account.balance + amount1);
        vm.prank(account);
        IForkWETH(WETH).deposit{value: amount1}();
        assertEq(token1.balanceOf(account) - before1, amount1);
    }

    function _approveVault(address account) internal {
        vm.startPrank(account);
        assertTrue(token0.approve(address(vault), type(uint256).max));
        assertTrue(token1.approve(address(vault), type(uint256).max));
        vm.stopPrank();
    }

    function _adapter(VenueType venue) internal view returns (IPositionAdapter) {
        if (venue == VenueType.UNISWAP_V2) return IPositionAdapter(address(v2));
        if (venue == VenueType.UNISWAP_V3_LOW_FEE) return IPositionAdapter(address(low));
        require(venue == VenueType.UNISWAP_V3_HIGH_FEE, "no IDLE adapter");
        return IPositionAdapter(address(high));
    }

    function _nav(uint256 amount0, uint256 amount1, int24 tick) internal view returns (uint256) {
        return amount1 + oracle.quoteToken0InToken1(amount0, tick, false);
    }

    function _deposit(address payer, address beneficiary, uint256 max0, uint256 max1)
        internal
        returns (uint256 shares)
    {
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        int24 tick = oracle.snapshot().twapTick;
        uint256 before0 = token0.balanceOf(payer);
        uint256 before1 = token1.balanceOf(payer);
        uint256 beforeShares = vault.balanceOf(beneficiary);
        uint256 used0;
        uint256 used1;
        vm.prank(payer);
        (used0, used1, shares) = vault.deposit(max0, max1, 1, beneficiary);
        assertGt(shares, 0);
        assertLe(used0, max0);
        assertLe(used1, max1);
        assertEq(before0 - token0.balanceOf(payer), used0);
        assertEq(before1 - token1.balanceOf(payer), used1);
        assertEq(vault.balanceOf(beneficiary) - beforeShares, shares);
        assertEq(vault.totalSupply() - beforeAssets.totalShares, shares);
        assertEq(
            shares,
            Math.mulDiv(
                _nav(used0, used1, tick), beforeAssets.totalShares, _nav(beforeAssets.total0, beforeAssets.total1, tick)
            )
        );
        AssetSnapshot memory afterAssets = vault.assetSnapshot();
        assertApproxEqAbs(afterAssets.total0, beforeAssets.total0 + used0, DUST0);
        assertApproxEqAbs(afterAssets.total1, beforeAssets.total1 + used1, DUST1);
        _assertAccounting();
    }

    function _redeem(address caller, address owner, address recipient, uint256 shares) internal {
        AssetSnapshot memory beforeAssets = vault.assetSnapshot();
        uint256 before0 = token0.balanceOf(recipient);
        uint256 before1 = token1.balanceOf(recipient);
        uint256 ownerShares = vault.balanceOf(owner);
        vm.prank(caller);
        (uint256 out0, uint256 out1) = vault.redeem(shares, 0, 0, recipient, owner);
        assertEq(token0.balanceOf(recipient) - before0, out0);
        assertEq(token1.balanceOf(recipient) - before1, out1);
        assertEq(ownerShares - vault.balanceOf(owner), shares);
        assertEq(beforeAssets.totalShares - vault.totalSupply(), shares);
        assertApproxEqAbs(out0, Math.mulDiv(beforeAssets.total0, shares, beforeAssets.totalShares), DUST0);
        assertApproxEqAbs(out1, Math.mulDiv(beforeAssets.total1, shares, beforeAssets.totalShares), DUST1);
        AssetSnapshot memory afterAssets = vault.assetSnapshot();
        assertApproxEqAbs(afterAssets.total0 + out0, beforeAssets.total0, DUST0);
        assertApproxEqAbs(afterAssets.total1 + out1, beforeAssets.total1, DUST1);
        _assertAccounting();
    }

    function _tradeV3(uint24 fee, bool zeroForOne, uint256 amountIn) internal returns (uint256 amountOut) {
        IERC20 input = zeroForOne ? token0 : token1;
        IERC20 output = zeroForOne ? token1 : token0;
        uint256 beforeIn = input.balanceOf(address(this));
        uint256 beforeOut = output.balanceOf(address(this));
        amountOut = router.exactInputSingle(
            IUniswapV3SwapRouter.ExactInputSingleParams(
                address(input), address(output), fee, address(this), vm.getBlockTimestamp(), amountIn, 1, 0
            )
        );
        assertGt(amountOut, 0);
        assertEq(beforeIn - input.balanceOf(address(this)), amountIn);
        assertEq(output.balanceOf(address(this)) - beforeOut, amountOut);
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
        if (active != VenueType.UNISWAP_V2) assertEq(IERC20(PAIR).balanceOf(address(v2)), 0);
        if (active != VenueType.UNISWAP_V3_LOW_FEE) assertEq(low.positionId(), 0);
        if (active != VenueType.UNISWAP_V3_HIGH_FEE) assertEq(high.positionId(), 0);
        if (active != VenueType.IDLE) {
            PositionSnapshot memory position = _adapter(active).snapshot();
            assertGt(position.liquidity, 0);
            assertEq(assets.position0, position.amount0);
            assertEq(assets.position1, position.amount1);
            if (active != VenueType.UNISWAP_V2) {
                assertEq(positionManager.ownerOf(position.positionId), address(_adapter(active)));
                PositionPlan memory plan = vault.lastExecutedPlan();
                assertEq(position.tickLower, plan.tickLower);
                assertEq(position.tickUpper, plan.tickUpper);
            }
        } else {
            assertEq(assets.position0, 0);
            assertEq(assets.position1, 0);
        }
        address[3] memory adapters = [address(v2), address(low), address(high)];
        for (uint256 i; i < adapters.length; ++i) {
            assertEq(token0.balanceOf(adapters[i]), 0);
            assertEq(token1.balanceOf(adapters[i]), 0);
            assertEq(token0.allowance(address(vault), adapters[i]), 0);
            assertEq(token1.allowance(address(vault), adapters[i]), 0);
        }
        assertEq(token0.allowance(address(low), POSITION_MANAGER), 0);
        assertEq(token1.allowance(address(low), POSITION_MANAGER), 0);
        assertEq(token0.allowance(address(high), POSITION_MANAGER), 0);
        assertEq(token1.allowance(address(high), POSITION_MANAGER), 0);
        assertEq(token0.balanceOf(address(vault.swapExecutor())), 0);
        assertEq(token1.balanceOf(address(vault.swapExecutor())), 0);
        assertEq(token0.allowance(address(vault.swapExecutor()), ROUTER), 0);
        assertEq(token1.allowance(address(vault.swapExecutor()), ROUTER), 0);
    }
}
