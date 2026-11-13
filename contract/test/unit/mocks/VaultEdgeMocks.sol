// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AdaptiveLPVault} from "../../../src/core/AdaptiveLPVault.sol";
import {PositionPlan, VenueType} from "../../../src/core/VaultTypes.sol";
import {PositionSnapshot} from "../../../src/adapters/AdapterTypes.sol";
import {OracleSnapshot} from "../../../src/oracle/OracleTypes.sol";
import {IUniswapV3SwapRouter} from "../../../src/interfaces/IUniswapV3External.sol";
import {SwapDirection} from "../../../src/swap/SwapTypes.sol";

/// @dev Hooks run only at explicitly selected boundaries, and propagate unexpected failures.
abstract contract EdgeHook {
    address public hookTarget;
    bytes public hookData;
    uint256 public hookCalls;

    function setHook(address target, bytes calldata data) external {
        hookTarget = target;
        hookData = data;
    }

    function _hook() internal {
        if (hookTarget == address(0)) return;
        ++hookCalls;
        (bool ok, bytes memory reason) = hookTarget.call(hookData);
        if (!ok) {
            assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
    }
}

contract EdgeToken is ERC20, EdgeHook {
    uint8 private _decimals = 18;
    address public hookFrom;
    address public hookTo;

    constructor() ERC20("Edge Token", "EDGE") {}

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setDecimals(uint8 value) external {
        _decimals = value;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTransferBoundary(address from, address to) external {
        hookFrom = from;
        hookTo = to;
    }

    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        // One shot per arm: isolate the selected transfer even if a later phase has the same endpoints.
        if (from == hookFrom && to == hookTo && amount != 0 && hookTarget != address(0)) {
            _hook();
            hookTarget = address(0);
        }
    }
}

contract EdgeFactory {
    mapping(address => mapping(address => address)) public getPair;
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    function register(address token0, address token1, uint24 fee, address pool) external {
        if (fee == 0) getPair[token0][token1] = pool;
        else getPool[token0][token1][fee] = pool;
    }
}

contract EdgePool {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;

    constructor(address factory_, address token0_, address token1_, uint24 fee_, int24 spacing_) {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
        tickSpacing = spacing_;
    }
}

/// @dev Tick-sensitive quotes make accidental re-reading observable. Prices are deterministic,
/// not an implementation of Uniswap math; the real vault/control/executor remain under test.
contract EdgeOracle {
    address public immutable canonicalPool;
    address public immutable token0;
    address public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;
    OracleSnapshot private _state;
    bool public restrictQuoteTick;
    error UnexpectedQuoteTick(int24 actual);

    constructor(address pool_, EdgeToken token0_, EdgeToken token1_) {
        canonicalPool = pool_;
        token0 = address(token0_);
        token1 = address(token1_);
        token0Decimals = token0_.decimals();
        token1Decimals = token1_.decimals();
        setState(0, 17, true);
    }

    function setState(uint256 deviation, int24 tick, bool healthy) public {
        _state.healthy = healthy;
        _state.deviationBps = deviation;
        _state.twapTick = tick;
        _state.spotTick = tick;
    }

    function currentTick() external view returns (int24) {
        return _state.twapTick;
    }

    function setRestrictQuoteTick(bool value) external {
        restrictQuoteTick = value;
    }

    function snapshot() external view returns (OracleSnapshot memory) {
        return _state;
    }

    function quoteToken0InToken1(uint256 amount, int24 tick, bool roundUp) external view returns (uint256) {
        if (restrictQuoteTick && tick != 17) revert UnexpectedQuoteTick(tick);
        uint256 price = tick == 17 ? 1 : 10;
        return Math.mulDiv(
            amount,
            (10 ** uint256(token1Decimals)) * price,
            10 ** uint256(token0Decimals),
            roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor
        );
    }

    function quoteToken1InToken0(uint256 amount, int24 tick, bool roundUp) external view returns (uint256) {
        if (restrictQuoteTick && tick != 17) revert UnexpectedQuoteTick(tick);
        uint256 price = tick == 17 ? 1 : 10;
        return Math.mulDiv(
            amount,
            10 ** uint256(token0Decimals),
            (10 ** uint256(token1Decimals)) * price,
            roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor
        );
    }
}

/// @dev Asset-moving boundary double, not an AMM/NFT simulation. Injected losses actually
/// leave the managed balances; reported amounts stay consistent with those balances.
contract EdgeAdapter is EdgeHook {
    address public immutable vault;
    address public immutable pool;
    address public immutable token0;
    address public immutable token1;
    VenueType public immutable venue;
    uint24 public immutable feeTier;
    int24 public immutable tickSpacing;
    address public constant LOSS_SINK = address(0xD057);
    PositionSnapshot private _position;
    bool public balancedPreview;
    uint256 public depositLoss0;
    uint256 public depositLoss1;
    uint256 public exitLoss0;
    uint256 public exitLoss1;
    // 1=fee sync, 2=deposit, 4=partial withdrawal, 8=full withdrawal.
    uint8 public hookMask;

    constructor(address vault_, EdgePool pool_, VenueType venue_) {
        vault = vault_;
        pool = address(pool_);
        token0 = pool_.token0();
        token1 = pool_.token1();
        feeTier = pool_.fee();
        tickSpacing = pool_.tickSpacing();
        venue = venue_;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "only vault");
        _;
    }

    function setHookMask(uint8 mask) external {
        hookMask = mask;
    }

    function setBalancedPreview(bool value) external {
        balancedPreview = value;
    }

    function setLosses(uint256 deposit0, uint256 deposit1, uint256 exit0, uint256 exit1) external {
        depositLoss0 = deposit0;
        depositLoss1 = deposit1;
        exitLoss0 = exit0;
        exitLoss1 = exit1;
    }

    function snapshot() external view returns (PositionSnapshot memory) {
        return _position;
    }

    function accrueFees(uint256 fee0, uint256 fee1) external {
        _position.claimableFee0 += fee0;
        _position.claimableFee1 += fee1;
        _position.amount0 += fee0;
        _position.amount1 += fee1;
    }

    function previewDeposit(uint256 amount0, uint256 amount1, PositionPlan calldata)
        public
        view
        returns (uint256, uint256)
    {
        if (!balancedPreview) return (amount0, amount1);
        uint256 used = Math.min(amount0, amount1);
        return (used, used);
    }

    function deposit(uint256 amount0, uint256 amount1, PositionPlan calldata plan)
        external
        onlyVault
        returns (uint256 used0, uint256 used1, uint256 liquidity)
    {
        (used0, used1) = previewDeposit(amount0, amount1, plan);
        require(IERC20(token0).transferFrom(vault, address(this), used0));
        require(IERC20(token1).transferFrom(vault, address(this), used1));
        if (depositLoss0 != 0) require(IERC20(token0).transfer(LOSS_SINK, depositLoss0));
        if (depositLoss1 != 0) require(IERC20(token1).transfer(LOSS_SINK, depositLoss1));
        _position.venue = venue;
        _position.adapter = address(this);
        _position.positionId = venue == VenueType.UNISWAP_V2 ? 0 : 1;
        _position.tickLower = plan.tickLower;
        _position.tickUpper = plan.tickUpper;
        _position.principal0 += used0 - depositLoss0;
        _position.principal1 += used1 - depositLoss1;
        _position.amount0 += used0 - depositLoss0;
        _position.amount1 += used1 - depositLoss1;
        liquidity = used0 + used1 - depositLoss0 - depositLoss1;
        _position.liquidity += liquidity;
        if (hookMask & 2 != 0) _hook();
    }

    function syncFees() external onlyVault returns (uint256 fee0, uint256 fee1) {
        fee0 = _position.claimableFee0;
        fee1 = _position.claimableFee1;
        _position.claimableFee0 = 0;
        _position.claimableFee1 = 0;
        _position.amount0 -= fee0;
        _position.amount1 -= fee1;
        require(IERC20(token0).transfer(vault, fee0));
        require(IERC20(token1).transfer(vault, fee1));
        if (hookMask & 1 != 0) _hook();
    }

    function withdraw(uint256 shares, uint256 supply) external onlyVault returns (uint256 amount0, uint256 amount1) {
        amount0 = Math.mulDiv(_position.principal0, shares, supply);
        amount1 = Math.mulDiv(_position.principal1, shares, supply);
        _position.principal0 -= amount0;
        _position.principal1 -= amount1;
        _position.amount0 -= amount0;
        _position.amount1 -= amount1;
        _position.liquidity = _position.principal0 + _position.principal1;
        require(IERC20(token0).transfer(vault, amount0));
        require(IERC20(token1).transfer(vault, amount1));
        if (hookMask & 4 != 0) _hook();
    }

    function withdrawAll() external onlyVault returns (uint256 amount0, uint256 amount1) {
        amount0 = _position.amount0 - exitLoss0;
        amount1 = _position.amount1 - exitLoss1;
        delete _position;
        if (exitLoss0 != 0) require(IERC20(token0).transfer(LOSS_SINK, exitLoss0));
        if (exitLoss1 != 0) require(IERC20(token1).transfer(LOSS_SINK, exitLoss1));
        require(IERC20(token0).transfer(vault, amount0));
        require(IERC20(token1).transfer(vault, amount1));
        if (hookMask & 8 != 0) _hook();
    }
}

contract EdgeRouter is EdgeHook {
    address public immutable factory;
    uint256 public outputBps = 10000;
    uint256 public lastMinimum;
    uint256 public swapCalls;

    constructor(address factory_) {
        factory = factory_;
    }

    function setOutputBps(uint256 value) external {
        outputBps = value;
    }

    function exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams calldata params)
        external
        returns (uint256 out)
    {
        ++swapCalls;
        lastMinimum = params.amountOutMinimum;
        require(IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn));
        _hook();
        out = Math.mulDiv(params.amountIn, outputBps, 10000);
        require(IERC20(params.tokenOut).transfer(params.recipient, out));
    }
}

contract EdgeReentryProbe {
    AdaptiveLPVault public immutable vault;
    address public immutable owner;
    uint256 public batches;
    uint256 public observedSupply;
    uint256 public observedOwnerShares;
    bytes[6] public results;

    constructor(AdaptiveLPVault vault_, address owner_) {
        vault = vault_;
        owner = owner_;
    }

    error ReceiverRejected();

    function rejectTransfer() external pure {
        revert ReceiverRejected();
    }

    function attackAll() external {
        observedSupply = vault.totalSupply();
        observedOwnerShares = vault.balanceOf(owner);
        bytes[6] memory calls;
        calls[0] = abi.encodeCall(vault.bootstrap, (1, 1, address(this)));
        calls[1] = abi.encodeCall(vault.deposit, (1, 1, 0, address(this)));
        calls[2] = abi.encodeCall(vault.redeem, (1, 0, 0, address(this), owner));
        calls[3] = abi.encodeCall(vault.rebalance, (bytes32(0), type(uint32).max));
        calls[4] =
            abi.encodeCall(vault.rebalanceWithSwap, (bytes32(0), SwapDirection.ZERO_FOR_ONE, 1, 0, type(uint32).max));
        calls[5] = abi.encodeCall(vault.emergencyExitToIdle, ());
        for (uint256 i; i < calls.length; ++i) {
            (bool ok, bytes memory reason) = address(vault).call(calls[i]);
            require(
                !ok
                    && keccak256(reason)
                        == keccak256(abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)),
                "wrong reentry outcome"
            );
            results[i] = reason;
        }
        ++batches;
    }
}
