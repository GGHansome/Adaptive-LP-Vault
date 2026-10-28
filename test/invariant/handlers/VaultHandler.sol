// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LocalTestToken} from "../../helpers/LocalUniswapFixture.sol";
import {AdaptiveLPVault} from "../../../src/core/AdaptiveLPVault.sol";
import {VaultControl} from "../../../src/control/VaultControl.sol";
import {UniswapV3Adapter} from "../../../src/adapters/UniswapV3Adapter.sol";
import {IPositionAdapter} from "../../../src/interfaces/IPositionAdapter.sol";
import {IAdaptiveLPVault} from "../../../src/interfaces/IAdaptiveLPVault.sol";
import {IAdapterRegistry} from "../../../src/interfaces/IAdapterRegistry.sol";
import {IVaultPause} from "../../../src/interfaces/IVaultPause.sol";
import {ICanonicalV3Oracle} from "../../../src/interfaces/ICanonicalV3Oracle.sol";
import {IUniswapV2Pair} from "../../../src/interfaces/IUniswapV2External.sol";
import {IUniswapV3Pool, INonfungiblePositionManager} from "../../../src/interfaces/IUniswapV3External.sol";
import {
    AssetSnapshot,
    PositionPlan,
    DeploymentAssessment,
    PauseState,
    PauseFlag,
    VenueType,
    MarketRegime
} from "../../../src/core/VaultTypes.sol";
import {OracleSnapshot} from "../../../src/oracle/OracleTypes.sol";
import {SwapDirection} from "../../../src/swap/SwapTypes.sol";
import {VaultReference} from "../helpers/VaultReference.sol";

interface IFeeV2Pair {
    function sync() external;
}

interface IFlashFeePool {
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

/// @dev All mutating selectors are explicitly targeted by the fixture. Valid actions call directly:
/// unexpected reverts fail the campaign (fail_on_revert=true). Expected failures are checked by
/// selector AND a state digest; no catch-all can hide assertions. Skips are counted separately.
contract VaultHandler is Test {
    struct Environment {
        AdaptiveLPVault vault;
        LocalTestToken token0;
        LocalTestToken token1;
        address pair;
        UniswapV3Adapter low;
        UniswapV3Adapter high;
        address admin;
        address manager;
        address guardian;
        address keeper;
        address[5] actors;
        uint256 seed;
    }

    Environment internal e;
    VaultControl public immutable control;
    address public immutable v2;
    address public immutable campaign;
    uint256 public immutable initialSupply;
    uint256 public immutable seed;
    uint256 public minted;
    uint256 public burned;
    int256 public expected0;
    int256 public expected1;
    uint256 public roundingBudget;
    uint64 public expectedVersion;
    bytes32 public expectedHistory;
    uint32 public expectedChangeAt;
    bool public oracleHealthy = true;
    uint256 public marketDeviation;
    uint256 public mutations;
    uint256 public visitedVenues;
    uint256 public swaps0;
    uint256 public swaps1;
    mapping(bytes4 => uint256) public attempts;
    mapping(bytes4 => uint256) public successes;
    mapping(bytes4 => uint256) public skips;
    uint256 public checkedFailures;
    address private flashPool;
    uint256 private flash0;
    uint256 private flash1;

    constructor(Environment memory env) {
        e = env;
        campaign = msg.sender;
        control = VaultControl(address(env.vault.vaultControl()));
        v2 = control.getAdapter(VenueType.UNISWAP_V2);
        seed = env.seed;
        initialSupply = env.vault.totalSupply();
        // Bootstrap inputs are known, not copied from totalAssets(). Real AMM minting can
        // leave at most a few raw units unrepresented in the marked LP principal.
        expected0 = int256(env.seed);
        expected1 = int256(env.seed);
        roundingBudget = 4;
        expectedVersion = env.vault.planVersion();
        expectedHistory = keccak256(abi.encode(env.vault.lastExecutedPlan()));
        expectedChangeAt = env.vault.lastPositionChangeAt();
        visitedVenues = 1 << uint8(env.vault.activeVenue());
        for (uint256 i; i < env.actors.length; ++i) {
            vm.startPrank(env.actors[i]);
            env.token0.approve(address(env.vault), type(uint256).max);
            env.token1.approve(address(env.vault), type(uint256).max);
            vm.stopPrank();
        }
        _market(0, true);
    }

    modifier counted() {
        ++attempts[msg.sig];
        _;
    }

    modifier stableHistory() {
        _;
        assertHistory();
    }

    function actor(uint256 index) public view returns (address) {
        return e.actors[index % 5];
    }

    function adapter(VenueType venue) public view returns (address) {
        return control.getAdapter(venue);
    }

    function referencePosition(VenueType venue) public view returns (VaultReference.Position memory p) {
        if (venue == VenueType.UNISWAP_V2) return VaultReference.v2(e.pair, v2);
        if (venue == VenueType.UNISWAP_V3_LOW_FEE) return VaultReference.v3(e.low);
        if (venue == VenueType.UNISWAP_V3_HIGH_FEE) return VaultReference.v3(e.high);
    }

    function referenceAssets(bool includeUnrecognized) public view returns (uint256 a0, uint256 a1) {
        a0 = e.token0.balanceOf(address(e.vault));
        a1 = e.token1.balanceOf(address(e.vault));
        for (uint256 i = 1; i <= 3; ++i) {
            if (!includeUnrecognized && VenueType(i) != e.vault.activeVenue()) continue;
            VaultReference.Position memory p = referencePosition(VenueType(i));
            a0 += p.principal0 + p.fee0;
            a1 += p.principal1 + p.fee1;
        }
    }

    function deposit(uint256 payerSeed, uint256 receiverSeed, uint256 amount0Seed, uint256 amount1Seed)
        external
        counted
        stableHistory
    {
        VenueType venue = e.vault.activeVenue();
        if (!oracleHealthy || control.pauseState().depositPaused || !control.isEnterEnabled(venue)) return _skip();
        VaultReference.Position memory p = referencePosition(venue);
        if (p.principal0 == 0 || p.principal1 == 0) return _skip();
        (uint256 total0, uint256 total1) = referenceAssets(false);
        uint256 idle0 = e.token0.balanceOf(address(e.vault)) + p.fee0;
        uint256 idle1 = e.token1.balanceOf(address(e.vault)) + p.fee1;
        if (Math.mulDiv(idle0 + idle1, 10000, total0 + total1) > e.vault.maxHealthyIdleBps()) return _skip();
        uint256 max0 = bound(amount0Seed, seed / 1000, seed / 2);
        uint256 max1 = bound(amount1Seed, seed / 1000, seed / 2);
        uint256 used0 = max0;
        uint256 used1 = Math.mulDiv(max0, p.principal1, p.principal0);
        if (used1 > max1) {
            used1 = max1;
            used0 = Math.mulDiv(max1, p.principal0, p.principal1);
        }
        uint256 supply = e.vault.totalSupply();
        uint256 shares = Math.mulDiv(used0 + used1, supply, total0 + total1);
        if (shares == 0 || used0 == 0 || used1 == 0) return _skip();
        address payer = actor(payerSeed);
        address recipient = actor(receiverSeed);
        _fund(payer, max0, max1);
        uint256 b0 = e.token0.balanceOf(payer);
        uint256 b1 = e.token1.balanceOf(payer);
        uint256 previous = e.vault.balanceOf(recipient);
        vm.prank(payer);
        (uint256 actual0, uint256 actual1, uint256 actualShares) = e.vault.deposit(max0, max1, shares, recipient);
        assertEq(actual0, used0, "principal ratio token0");
        assertEq(actual1, used1, "principal ratio token1");
        assertEq(actualShares, shares, "pre-deposit NAV pricing / INV-05");
        assertEq(b0 - e.token0.balanceOf(payer), used0);
        assertEq(b1 - e.token1.balanceOf(payer), used1);
        assertEq(e.vault.balanceOf(recipient), previous + shares);
        assertEq(e.vault.totalSupply(), supply + shares);
        minted += shares;
        expected0 += int256(used0);
        expected1 += int256(used1);
        _checkFeesCleared(venue);
        _healthyDeployment();
        _success(4);
    }

    function redeem(uint256 ownerSeed, uint256 receiverSeed, uint256 fraction, uint256 mode)
        external
        counted
        stableHistory
    {
        address owner = actor(ownerSeed);
        uint256 balance = e.vault.balanceOf(owner);
        if (balance == 0) return _skip();
        uint256 shares = bound(fraction, 1, balance);
        address caller = owner;
        uint256 allowanceBefore;
        if (mode % 3 != 0) {
            caller = actor(ownerSeed % 5 + 1);
            allowanceBefore = mode % 3 == 1 ? shares : type(uint256).max;
            vm.prank(owner);
            e.vault.approve(caller, allowanceBefore);
        }
        _redeem(caller, owner, actor(receiverSeed), shares);
        if (caller != owner) {
            assertEq(e.vault.allowance(owner, caller), allowanceBefore == type(uint256).max ? allowanceBefore : 0);
        }
        ++successes[msg.sig];
    }

    function transferShares(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool delegated)
        external
        counted
        stableHistory
    {
        address from = actor(fromSeed);
        address to = toSeed % 6 == 5 ? address(e.vault) : actor(toSeed);
        uint256 balance = e.vault.balanceOf(from);
        if (balance == 0) return _skip();
        uint256 amount = bound(amountSeed, 0, balance);
        uint256 beforeTo = e.vault.balanceOf(to);
        uint256 supply = e.vault.totalSupply();
        if (delegated) {
            address spender = actor(fromSeed % 5 + 1);
            vm.prank(from);
            e.vault.approve(spender, amount);
            vm.prank(spender);
            e.vault.transferFrom(from, to, amount);
            assertEq(e.vault.allowance(from, spender), 0);
        } else {
            vm.prank(from);
            e.vault.transfer(to, amount);
        }
        assertEq(e.vault.balanceOf(from), from == to ? balance : balance - amount);
        assertEq(e.vault.balanceOf(to), from == to ? beforeTo : beforeTo + amount);
        assertEq(e.vault.totalSupply(), supply);
        ++successes[msg.sig];
    }

    function approveShares(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external counted stableHistory {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        vm.prank(owner);
        e.vault.approve(spender, amount);
        assertEq(e.vault.allowance(owner, spender), amount);
        ++successes[msg.sig];
    }

    function donateTokens(uint256 a0, uint256 a1) external counted stableHistory {
        a0 = bound(a0, 0, seed / 10);
        a1 = bound(a1, 0, seed / 10);
        _donate(a0, a1);
        ++successes[msg.sig];
    }

    function donateLp(uint256 amountSeed) external counted stableHistory {
        uint256 balance = IERC20(e.pair).balanceOf(address(this));
        if (balance == 0) return _skip();
        uint256 amount = bound(amountSeed, 1, Math.min(balance, seed / 10));
        (uint256 a0, uint256 a1) = referenceAssets(false);
        VaultReference.Position memory beforeP = referencePosition(VenueType.UNISWAP_V2);
        IERC20(e.pair).transfer(v2, amount);
        VaultReference.Position memory afterP = referencePosition(VenueType.UNISWAP_V2);
        expected0 += int256(afterP.principal0 - beforeP.principal0);
        expected1 += int256(afterP.principal1 - beforeP.principal1);
        if (e.vault.activeVenue() != VenueType.UNISWAP_V2) {
            (uint256 b0, uint256 b1) = e.vault.totalAssets();
            assertEq(b0, a0, "unrecognized V2 donation token0");
            assertEq(b1, a1, "unrecognized V2 donation token1");
        }
        ++successes[msg.sig];
    }

    function accrueFees(uint256 amount0Seed, uint256 amount1Seed) external counted stableHistory {
        VenueType venue = e.vault.activeVenue();
        if (venue == VenueType.IDLE) return _skip();
        VaultReference.Position memory beforeP = referencePosition(venue);
        uint256 a0 = bound(amount0Seed, 1, seed / 100);
        uint256 a1 = bound(amount1Seed, 1, seed / 100);
        _fund(address(this), a0, a1);
        if (venue == VenueType.UNISWAP_V2) {
            e.token0.transfer(e.pair, a0);
            e.token1.transfer(e.pair, a1);
            IFeeV2Pair(e.pair).sync();
        } else {
            flashPool = IPositionAdapter(adapter(venue)).pool();
            flash0 = a0;
            flash1 = a1;
            IFlashFeePool(flashPool).flash(address(this), 0, 0, "");
            flashPool = address(0);
        }
        VaultReference.Position memory afterP = referencePosition(venue);
        expected0 += int256(afterP.principal0 + afterP.fee0) - int256(beforeP.principal0 + beforeP.fee0);
        expected1 += int256(afterP.principal1 + afterP.fee1) - int256(beforeP.principal1 + beforeP.fee1);
        ++successes[msg.sig];
    }

    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata) external {
        require(msg.sender == flashPool && flashPool != address(0), "untrusted flash callback");
        assertEq(fee0, 0);
        assertEq(fee1, 0);
        e.token0.transfer(msg.sender, flash0);
        e.token1.transfer(msg.sender, flash1);
    }

    function setMarket(uint256 deviationSeed, bool healthy) external counted stableHistory {
        _market(bound(deviationSeed, 0, 650), healthy);
        ++successes[msg.sig];
    }

    function advanceTime(uint256 secondsSeed) external counted stableHistory {
        vm.warp(vm.getBlockTimestamp() + bound(secondsSeed, 0, 180));
        ++successes[msg.sig];
    }

    function setControls(uint256 pauseBits, uint256 venueSeed, bool enabled, bool byGuardian)
        external
        counted
        stableHistory
    {
        PauseState memory state = PauseState(pauseBits & 1 != 0, pauseBits & 2 != 0, pauseBits & 4 != 0);
        if (byGuardian) {
            PauseState memory old = control.pauseState();
            state.depositPaused = old.depositPaused || state.depositPaused;
            state.plainRebalancePaused = old.plainRebalancePaused || state.plainRebalancePaused;
            state.swapRebalancePaused = old.swapRebalancePaused || state.swapRebalancePaused;
            enabled = false;
        }
        vm.startPrank(byGuardian ? e.guardian : e.manager);
        control.setPauseState(state);
        control.setAdapterEnabled(VenueType(1 + venueSeed % 3), enabled);
        vm.stopPrank();
        assertEq(keccak256(abi.encode(control.pauseState())), keccak256(abi.encode(state)));
        ++successes[msg.sig];
    }

    function rebalance(uint256 deviationSeed) external counted {
        if (!oracleHealthy || control.pauseState().plainRebalancePaused || !_cooldownReady()) return _skip();
        _market(bound(deviationSeed, 0, 650), true);
        VenueType target = _targetRegimeVenue();
        if (target != VenueType.IDLE && !control.isEnterEnabled(target)) return _skip();
        (PositionPlan memory plan, DeploymentAssessment memory assessment) = e.vault.previewRebalance();
        _assertPlan(plan);
        assertEq(uint8(plan.targetVenue), uint8(target), "independent hysteresis transition / INV-13");
        if (plan.targetVenue == e.vault.activeVenue() || assessment.requiresSwap) return _skip();
        vm.prank(actor(deviationSeed));
        e.vault.rebalance(plan.planHash, uint32(vm.getBlockTimestamp()));
        _committed(plan);
        if (plan.targetVenue != VenueType.IDLE) _healthyDeployment();
        _success(8);
    }

    /// @dev Selects a neighboring non-IDLE regime, then supplies a single-sided donation
    /// large enough to REQUIRE a swap. It never bypasses pause/health/cooldown/disabled gates.
    function rebalanceWithSwap(bool zeroForOne, uint256 skewSeed) external counted {
        if (!oracleHealthy || control.pauseState().swapRebalancePaused || !_cooldownReady()) return _skip();
        uint256 regime = uint8(e.vault.lastExecutedPlan().marketRegime);
        _market(regime == 0 || regime == 2 ? 150 : 350, true);
        VenueType target = _targetRegimeVenue();
        if (!control.isEnterEnabled(target) || target == e.vault.activeVenue()) return _skip();
        (uint256 a0, uint256 a1) = referenceAssets(false);
        uint256 extra = bound(skewSeed, seed / 5, seed / 2);
        // Establish a known direction even after arbitrary older donations and fees.
        if (zeroForOne) _donate((a1 > a0 ? a1 - a0 : 0) + extra, 0);
        else _donate(0, (a0 > a1 ? a0 - a1 : 0) + extra);
        (PositionPlan memory plan, DeploymentAssessment memory assessment) = e.vault.previewRebalance();
        assertEq(uint8(plan.targetVenue), uint8(target), "independent swap target / INV-13");
        if (!assessment.requiresSwap) return _skip(); // large NAV can make bounded skew immaterial
        SwapDirection direction = zeroForOne ? SwapDirection.ZERO_FOR_ONE : SwapDirection.ONE_FOR_ZERO;
        assertEq(uint8(assessment.direction), uint8(direction));
        (a0, a1) = referenceAssets(false);
        uint256 amountIn = (zeroForOne ? a0 - a1 : a1 - a0) / 2;
        uint256 navBefore = a0 + a1;
        uint256 inBefore = (zeroForOne ? e.token0 : e.token1).balanceOf(address(e.vault.swapExecutor()));
        uint256 outBefore = (zeroForOne ? e.token1 : e.token0).balanceOf(address(e.vault.swapExecutor()));
        address pool = e.vault.swapExecutor().swapPool();
        uint256 poolIn = (zeroForOne ? e.token0 : e.token1).balanceOf(pool);
        uint256 poolOut = (zeroForOne ? e.token1 : e.token0).balanceOf(pool);
        vm.prank(e.keeper);
        e.vault.rebalanceWithSwap(plan.planHash, direction, amountIn, 0, uint32(vm.getBlockTimestamp()));
        uint256 amountOut = poolOut - (zeroForOne ? e.token1 : e.token0).balanceOf(pool);
        assertEq((zeroForOne ? e.token0 : e.token1).balanceOf(pool) - poolIn, amountIn);
        uint256 minimum = Math.mulDiv(amountIn, 10000 - e.vault.maxSwapSlippageBps(), 10000, Math.Rounding.Ceil);
        assertGe(amountOut, minimum, "protocol minimum output / INV-09");
        if (zeroForOne) {
            expected0 -= int256(amountIn);
            expected1 += int256(amountOut);
            ++swaps0;
        } else {
            expected1 -= int256(amountIn);
            expected0 += int256(amountOut);
            ++swaps1;
        }
        assertEq((zeroForOne ? e.token0 : e.token1).balanceOf(address(e.vault.swapExecutor())), inBefore);
        assertEq((zeroForOne ? e.token1 : e.token0).balanceOf(address(e.vault.swapExecutor())), outBefore);
        (a0, a1) = referenceAssets(false);
        assertGe(a0 + a1, Math.mulDiv(navBefore, 10000 - e.vault.maxMigrationLossBps(), 10000, Math.Rounding.Ceil));
        _committed(plan);
        _healthyDeployment();
        _success(8);
    }

    function emergencyExit(bool byGuardian) external counted {
        VenueType previous = e.vault.activeVenue();
        vm.prank(byGuardian ? e.guardian : e.manager);
        e.vault.emergencyExitToIdle();
        if (previous != VenueType.IDLE) ++expectedVersion;
        assertEq(uint8(e.vault.activeVenue()), uint8(VenueType.IDLE));
        assertHistory(); // history/timestamp preserved; version only invalidates stale plans
        PauseState memory pauses = control.pauseState();
        assertTrue(pauses.depositPaused && pauses.plainRebalancePaused && pauses.swapRebalancePaused);
        visitedVenues |= 1;
        _success(previous == VenueType.IDLE ? 0 : 4);
    }

    function exerciseFailure(uint256 kindSeed, uint256 ownerSeed) external counted stableHistory {
        uint256 kind = kindSeed % 7;
        address owner = actor(ownerSeed);
        uint256 shares = e.vault.balanceOf(owner);
        if (kind <= 1) {
            if (shares == 0) return _skip();
            if (kind == 0) {
                _failure(
                    address(e.vault),
                    owner,
                    abi.encodeCall(e.vault.redeem, (shares, type(uint256).max, 0, actor(ownerSeed % 5 + 1), owner)),
                    IAdaptiveLPVault.AssetSlippage.selector
                );
            } else {
                address spender = actor(ownerSeed % 5 + 1);
                vm.prank(owner);
                e.vault.approve(spender, 0);
                _failure(
                    address(e.vault),
                    spender,
                    abi.encodeCall(e.vault.redeem, (shares, 0, 0, owner, owner)),
                    bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)"))
                );
            }
        } else if (kind == 2) {
            if (control.pauseState().plainRebalancePaused) return _skip();
            _failure(
                address(e.vault),
                owner,
                abi.encodeCall(e.vault.rebalance, (bytes32(0), uint32(vm.getBlockTimestamp() - 1))),
                IAdaptiveLPVault.DeadlineExpired.selector
            );
        } else if (kind == 3) {
            if (!oracleHealthy || control.pauseState().plainRebalancePaused || !_cooldownReady()) return _skip();
            VenueType target = _targetRegimeVenue();
            if (target != VenueType.IDLE && !control.isEnterEnabled(target)) return _skip();
            _failure(
                address(e.vault),
                owner,
                abi.encodeCall(e.vault.rebalance, (bytes32(0), uint32(vm.getBlockTimestamp()))),
                IAdaptiveLPVault.InvalidPlanHash.selector
            );
        } else if (kind == 4) {
            if (control.pauseState().depositPaused || !control.isEnterEnabled(e.vault.activeVenue())) return _skip();
            if (oracleHealthy) return _skip();
            _failure(
                address(e.vault),
                owner,
                abi.encodeCall(e.vault.deposit, (seed, seed, 0, owner)),
                IAdaptiveLPVault.OracleUnhealthy.selector
            );
        } else if (kind == 5) {
            if (control.pauseState().plainRebalancePaused || _cooldownReady()) return _skip();
            _failure(
                address(e.vault),
                owner,
                abi.encodeCall(e.vault.rebalance, (bytes32(0), uint32(vm.getBlockTimestamp()))),
                IAdaptiveLPVault.CooldownActive.selector
            );
        } else {
            if (
                e.vault.activeVenue() == VenueType.IDLE || control.isEnterEnabled(e.vault.activeVenue())
                    || control.pauseState().depositPaused
            ) return _skip();
            _failure(
                address(e.vault),
                owner,
                abi.encodeCall(e.vault.deposit, (seed, seed, 0, owner)),
                IAdapterRegistry.AdapterDisabled.selector
            );
        }
        ++successes[msg.sig];
    }

    function unauthorized(uint256 kindSeed, bool useAdmin) external counted stableHistory {
        address caller = useAdmin ? e.admin : actor(4);
        bytes4 accessError = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
        uint256 kind = kindSeed % 6;
        if (kind == 0) {
            _failure(address(e.vault), caller, abi.encodeCall(e.vault.emergencyExitToIdle, ()), accessError);
        }
        if (kind == 1) {
            _failure(
                address(e.vault),
                caller,
                abi.encodeCall(
                    e.vault.rebalanceWithSwap,
                    (bytes32(0), SwapDirection.ZERO_FOR_ONE, 1, 0, uint32(vm.getBlockTimestamp()))
                ),
                accessError
            );
        }
        if (kind == 2) {
            _failure(
                address(control),
                caller,
                abi.encodeCall(control.setPauseState, (PauseState(false, false, false))),
                accessError
            );
        }
        if (kind == 3) {
            _failure(
                address(control),
                caller,
                abi.encodeCall(control.setAdapterEnabled, (VenueType.UNISWAP_V2, true)),
                accessError
            );
        }
        if (kind == 4) {
            _failure(address(e.vault), caller, abi.encodeCall(e.vault.bootstrap, (1, 1, caller)), accessError);
        }
        if (kind == 5) {
            bytes32 keeperRole = control.KEEPER_ROLE();
            vm.prank(e.admin);
            control.revokeRole(keeperRole, e.keeper);
            _failure(
                address(e.vault),
                e.keeper,
                abi.encodeCall(
                    e.vault.rebalanceWithSwap,
                    (bytes32(0), SwapDirection.ZERO_FOR_ONE, 1, 0, uint32(vm.getBlockTimestamp()))
                ),
                accessError
            );
            vm.prank(e.admin);
            control.grantRole(keeperRole, e.keeper);
        }
        ++successes[msg.sig];
    }

    /// @dev Probe all three entry gates without repairing state. A successful gate probe uses
    /// an intentionally invalid plan hash, so neither rebalance can actually move assets.
    function probeGates(uint256 actorSeed) external counted stableHistory {
        address caller = actor(actorSeed);
        PauseState memory pauses = control.pauseState();
        if (pauses.depositPaused) {
            _failure(
                address(e.vault),
                caller,
                abi.encodeCall(e.vault.deposit, (1, 1, 0, caller)),
                IVaultPause.Paused.selector
            );
        } else if (!control.isEnterEnabled(e.vault.activeVenue())) {
            _failure(
                address(e.vault),
                caller,
                abi.encodeCall(e.vault.deposit, (1, 1, 0, caller)),
                IAdapterRegistry.AdapterDisabled.selector
            );
        } else if (!oracleHealthy) {
            _failure(
                address(e.vault),
                caller,
                abi.encodeCall(e.vault.deposit, (1, 1, 0, caller)),
                IAdaptiveLPVault.OracleUnhealthy.selector
            );
        }
        bytes4 plainError = _rebalanceGateError(pauses.plainRebalancePaused);
        bytes4 swapError = _rebalanceGateError(pauses.swapRebalancePaused);
        _failure(
            address(e.vault),
            caller,
            abi.encodeCall(e.vault.rebalance, (bytes32(0), uint32(vm.getBlockTimestamp()))),
            plainError
        );
        _failure(
            address(e.vault),
            e.keeper,
            abi.encodeCall(
                e.vault.rebalanceWithSwap,
                (bytes32(0), SwapDirection.ZERO_FOR_ONE, 1, 0, uint32(vm.getBlockTimestamp()))
            ),
            swapError
        );
        ++successes[msg.sig];
    }

    function _rebalanceGateError(bool paused) internal view returns (bytes4) {
        if (paused) return IVaultPause.Paused.selector;
        if (!_cooldownReady()) return IAdaptiveLPVault.CooldownActive.selector;
        if (!oracleHealthy) return IAdaptiveLPVault.OracleUnhealthy.selector;
        VenueType target = _targetRegimeVenue();
        if (target != VenueType.IDLE && !control.isEnterEnabled(target)) {
            return IAdapterRegistry.AdapterDisabled.selector;
        }
        return IAdaptiveLPVault.InvalidPlanHash.selector;
    }

    function guardianCannotRelax(uint256 venueSeed) external counted stableHistory {
        VenueType venue = VenueType(1 + venueSeed % 3);
        _failure(
            address(control),
            e.guardian,
            abi.encodeCall(control.setAdapterEnabled, (venue, true)),
            bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"))
        );
        PauseState memory state = control.pauseState();
        if (state.depositPaused || state.plainRebalancePaused || state.swapRebalancePaused) {
            _failure(
                address(control),
                e.guardian,
                abi.encodeCall(control.setPauseState, (PauseState(false, false, false))),
                IVaultPause.GuardianCannotUnpause.selector
            );
        }
        ++successes[msg.sig];
    }

    /// @dev End-of-sequence liveness check: no oracle, entry pause, or enabled-adapter repair.
    /// Only privileged exit and users' own share redemption are needed to release their assets.
    function finish() external {
        require(msg.sender == campaign, "campaign only");
        VenueType previous = e.vault.activeVenue();
        vm.prank(e.guardian);
        e.vault.emergencyExitToIdle();
        if (previous != VenueType.IDLE) ++expectedVersion;
        roundingBudget += 4;
        for (uint256 i; i < 5; ++i) {
            address owner = actor(i);
            uint256 shares = e.vault.balanceOf(owner);
            if (shares != 0) _redeem(owner, owner, owner, shares);
        }
        assertEq(e.vault.totalSupply(), e.vault.balanceOf(address(e.vault)));
        assertGe(e.vault.totalSupply(), e.vault.minimumLockedShares());
        assertHistory();
    }

    function assertHistory() public view {
        assertEq(e.vault.planVersion(), expectedVersion, "structural changes increment exactly once / INV-14");
        assertEq(
            keccak256(abi.encode(e.vault.lastExecutedPlan())),
            expectedHistory,
            "history changes only on commit / INV-13"
        );
        assertEq(e.vault.lastPositionChangeAt(), expectedChangeAt, "cooldown history / INV-10");
    }

    function _redeem(address caller, address owner, address recipient, uint256 shares) internal {
        uint256 supply = e.vault.totalSupply();
        VenueType venue = e.vault.activeVenue();
        VaultReference.Position memory p = referencePosition(venue);
        uint256 out0 = Math.mulDiv(e.token0.balanceOf(address(e.vault)) + p.fee0, shares, supply);
        uint256 out1 = Math.mulDiv(e.token1.balanceOf(address(e.vault)) + p.fee1, shares, supply);
        uint256 units = Math.mulDiv(p.units, shares, supply);
        if (venue == VenueType.UNISWAP_V2 && units != 0) {
            // Real Pair burn divides its BALANCES by pre-burn LP supply, after native LP flooring.
            out0 += Math.mulDiv(e.token0.balanceOf(e.pair), units, IERC20(e.pair).totalSupply());
            out1 += Math.mulDiv(e.token1.balanceOf(e.pair), units, IERC20(e.pair).totalSupply());
        } else if (venue != VenueType.IDLE && units != 0) {
            (uint160 price,,,,,,) = IUniswapV3Pool(IPositionAdapter(adapter(venue)).pool()).slot0();
            (uint256 a0, uint256 a1) = VaultReference.amounts(price, p.lower, p.upper, units);
            out0 += a0;
            out1 += a1;
        }
        uint256 b0 = e.token0.balanceOf(recipient);
        uint256 b1 = e.token1.balanceOf(recipient);
        uint256 balance = e.vault.balanceOf(owner);
        uint256 selfAllowance = e.vault.allowance(owner, owner);
        vm.prank(caller);
        (uint256 actual0, uint256 actual1) = e.vault.redeem(shares, out0, out1, recipient, owner);
        assertEq(actual0, out0, "pre-burn supply and native units token0 / INV-06");
        assertEq(actual1, out1, "pre-burn supply and native units token1 / INV-06");
        assertEq(e.token0.balanceOf(recipient) - b0, out0);
        assertEq(e.token1.balanceOf(recipient) - b1, out1);
        assertEq(e.vault.balanceOf(owner), balance - shares);
        assertEq(e.vault.totalSupply(), supply - shares);
        if (caller == owner) assertEq(e.vault.allowance(owner, owner), selfAllowance);
        burned += shares;
        expected0 -= int256(out0);
        expected1 -= int256(out1);
        // Recombining separately floored principal before/after a burn can differ by one raw unit.
        roundingBudget += 2;
        _checkFeesCleared(venue);
        assertHistory();
    }

    function _committed(PositionPlan memory plan) internal {
        _assertPlan(plan);
        ++expectedVersion;
        assertEq(plan.version, expectedVersion);
        expectedHistory = keccak256(abi.encode(plan));
        expectedChangeAt = uint32(vm.getBlockTimestamp());
        assertHistory();
        assertEq(uint8(e.vault.activeVenue()), uint8(plan.targetVenue));
        visitedVenues |= 1 << uint8(plan.targetVenue);
        _checkFeesCleared(plan.targetVenue);
    }

    function _assertPlan(PositionPlan memory p) internal view {
        assertEq(p.planHash, keccak256(abi.encode(p.targetVenue, p.marketRegime, p.tickLower, p.tickUpper, p.version)));
        VenueType expected = p.marketRegime == MarketRegime.LOW_DEVIATION
            ? VenueType.UNISWAP_V3_LOW_FEE
            : p.marketRegime == MarketRegime.MEDIUM_DEVIATION
                ? VenueType.UNISWAP_V3_HIGH_FEE
                : p.marketRegime == MarketRegime.HIGH_DEVIATION ? VenueType.UNISWAP_V2 : VenueType.IDLE;
        assertEq(uint8(p.targetVenue), uint8(expected));
        if (p.targetVenue == VenueType.IDLE || p.targetVenue == VenueType.UNISWAP_V2) {
            assertEq(p.tickLower, 0);
            assertEq(p.tickUpper, 0);
        } else {
            int24 spacing = IPositionAdapter(adapter(p.targetVenue)).tickSpacing();
            assertEq(p.tickLower % spacing, 0);
            assertEq(p.tickUpper % spacing, 0);
            assertLt(p.tickLower, p.tickUpper);
            assertGe(p.tickLower, -887272);
            assertLe(p.tickUpper, 887272);
        }
    }

    function _targetRegimeVenue() internal view returns (VenueType) {
        uint256 regime = uint8(e.vault.lastExecutedPlan().marketRegime);
        // Explicit reference transition table: inclusive hysteresis, at most one step.
        if (regime == 0 && marketDeviation >= 100) {
            regime = 1;
        } else if (regime == 1) {
            if (marketDeviation <= 50) regime = 0;
            else if (marketDeviation >= 300) regime = 2;
        } else if (regime == 2) {
            if (marketDeviation <= 200) regime = 1;
            else if (marketDeviation >= 500) regime = 3;
        } else if (regime == 3 && marketDeviation <= 400) {
            regime = 2;
        }
        if (regime == 0) return VenueType.UNISWAP_V3_LOW_FEE;
        if (regime == 1) return VenueType.UNISWAP_V3_HIGH_FEE;
        if (regime == 2) return VenueType.UNISWAP_V2;
        return VenueType.IDLE;
    }

    function _market(uint256 deviation, bool healthy) internal {
        marketDeviation = deviation;
        oracleHealthy = healthy;
        OracleSnapshot memory s;
        s.healthy = healthy;
        s.deviationBps = deviation;
        s.observedAt = uint32(vm.getBlockTimestamp());
        // Only observation is controlled; all quotes, AMMs, adapters, and router are real.
        vm.mockCall(address(e.vault.canonicalOracle()), abi.encodeCall(ICanonicalV3Oracle.snapshot, ()), abi.encode(s));
    }

    function _donate(uint256 a0, uint256 a1) internal {
        _fund(address(this), a0, a1);
        e.token0.transfer(address(e.vault), a0);
        e.token1.transfer(address(e.vault), a1);
        expected0 += int256(a0);
        expected1 += int256(a1);
    }

    function _fund(address to, uint256 a0, uint256 a1) internal {
        e.token0.mint(to, a0);
        e.token1.mint(to, a1);
    }

    function _healthyDeployment() internal view {
        (uint256 a0, uint256 a1) = referenceAssets(false);
        uint256 idle = e.token0.balanceOf(address(e.vault)) + e.token1.balanceOf(address(e.vault));
        uint256 nav = a0 + a1;
        assertGt(nav, 0);
        assertGe(Math.mulDiv(nav - idle, 10000, nav), e.vault.minDeployBps());
        assertLe(Math.mulDiv(idle, 10000, nav), e.vault.maxHealthyIdleBps());
    }

    function _checkFeesCleared(VenueType venue) internal view {
        VaultReference.Position memory p = referencePosition(venue);
        assertEq(p.fee0, 0, "fees cleared token0 / INV-04");
        assertEq(p.fee1, 0, "fees cleared token1 / INV-04");
    }

    function _cooldownReady() internal view returns (bool) {
        return vm.getBlockTimestamp() >= uint256(e.vault.lastPositionChangeAt()) + e.vault.minRebalanceCooldown();
    }

    function _success(uint256 budget) internal {
        ++successes[msg.sig];
        ++mutations;
        roundingBudget += budget;
        assertEq(e.vault.totalSupply(), initialSupply + minted - burned);
    }

    function _skip() internal {
        ++skips[msg.sig];
    }

    function _failure(address target, address caller, bytes memory data, bytes4 selector) internal {
        bytes32 beforeState = stateDigest();
        vm.prank(caller);
        (bool ok, bytes memory reason) = target.call(data);
        assertFalse(ok, "expected rejection / unauthorized success");
        assertGe(reason.length, 4, "missing revert selector");
        assertEq(bytes4(reason), selector, "unexpected failure reason");
        assertEq(stateDigest(), beforeState, "failed operation changed state / INV-10");
        ++checkedFailures;
    }

    function stateDigest() public view returns (bytes32 digest) {
        digest = keccak256(
            abi.encode(
                e.vault.assetSnapshot(),
                e.vault.lastExecutedPlan(),
                e.vault.planVersion(),
                e.vault.lastPositionChangeAt(),
                e.vault.activeVenue(),
                e.vault.initialized(),
                control.pauseState()
            )
        );
        address manager = e.low.positionManager();
        for (uint256 i = 1; i <= 3; ++i) {
            address a = adapter(VenueType(i));
            digest = keccak256(
                abi.encode(
                    digest,
                    control.getConfig(VenueType(i)),
                    IPositionAdapter(a).snapshot(),
                    e.token0.allowance(address(e.vault), a),
                    e.token1.allowance(address(e.vault), a),
                    e.token0.allowance(a, manager),
                    e.token1.allowance(a, manager)
                )
            );
        }
        address[13] memory accounts = [
            address(e.vault),
            v2,
            address(e.low),
            address(e.high),
            e.pair,
            e.low.pool(),
            e.high.pool(),
            e.vault.swapExecutor().swapPool(),
            address(e.vault.swapExecutor()),
            e.vault.swapExecutor().router(),
            manager,
            address(this),
            campaign
        ];
        for (uint256 i; i < accounts.length; ++i) {
            digest = keccak256(abi.encode(digest, e.token0.balanceOf(accounts[i]), e.token1.balanceOf(accounts[i])));
        }
        for (uint256 i; i < 5; ++i) {
            address a = actor(i);
            digest = keccak256(
                abi.encode(
                    digest,
                    e.vault.balanceOf(a),
                    e.token0.balanceOf(a),
                    e.token1.balanceOf(a),
                    e.token0.allowance(a, address(e.vault)),
                    e.token1.allowance(a, address(e.vault))
                )
            );
            for (uint256 j; j < 5; ++j) {
                digest = keccak256(abi.encode(digest, e.vault.allowance(a, actor(j))));
            }
        }
        digest = keccak256(
            abi.encode(
                digest,
                e.vault.totalSupply(),
                e.vault.balanceOf(address(e.vault)),
                IERC20(e.pair).totalSupply(),
                IERC20(e.pair).balanceOf(v2),
                e.token0.allowance(address(e.vault.swapExecutor()), e.vault.swapExecutor().router()),
                e.token1.allowance(address(e.vault.swapExecutor()), e.vault.swapExecutor().router())
            )
        );
    }
}
