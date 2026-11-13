// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockOracleToken {
    uint8 private immutable _DECIMALS;

    constructor(uint8 decimals_) {
        _DECIMALS = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _DECIMALS;
    }
}

contract MockTokenWithoutMetadata {}

contract MockOracleV3Factory {
    mapping(address tokenA => mapping(address tokenB => mapping(uint24 fee => address pool))) public getPool;

    function register(address token0, address token1, uint24 fee, address pool) external {
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool;
    }
}

contract MockOracleV3Pool {
    address private immutable _FACTORY;
    address private immutable _TOKEN0;
    address private immutable _TOKEN1;
    uint24 private immutable _FEE;
    int24 private immutable _TICK_SPACING;

    uint128 public liquidity = 1 ether;
    uint160 public sqrtPriceX96 = uint160(1 << 96);
    int24 public currentTick;
    bool public unlocked = true;

    int56[3] private _tickCumulatives;
    bool public revertSlot0;
    bool public revertObserve;
    bool public malformedObservations;

    constructor(address factory_, address token0_, address token1_) {
        _FACTORY = factory_;
        _TOKEN0 = token0_;
        _TOKEN1 = token1_;
        _FEE = 3_000;
        _TICK_SPACING = 60;
    }

    function factory() external view returns (address) {
        return _FACTORY;
    }

    function token0() external view returns (address) {
        return _TOKEN0;
    }

    function token1() external view returns (address) {
        return _TOKEN1;
    }

    function fee() external view returns (uint24) {
        return _FEE;
    }

    function tickSpacing() external view returns (int24) {
        return _TICK_SPACING;
    }

    function setSlot0(int24 tick, uint160 sqrtPrice, bool unlocked_) external {
        currentTick = tick;
        sqrtPriceX96 = sqrtPrice;
        unlocked = unlocked_;
    }

    function setLiquidity(uint128 value) external {
        liquidity = value;
    }

    function setObservations(int56 longAgo, int56 shortAgo, int56 current) external {
        _tickCumulatives = [longAgo, shortAgo, current];
    }

    function setFailures(bool slot0Failure, bool observeFailure, bool malformed) external {
        revertSlot0 = slot0Failure;
        revertObserve = observeFailure;
        malformedObservations = malformed;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        if (revertSlot0) revert("SLOT0_FAILURE");
        return (sqrtPriceX96, currentTick, 0, 3, 3, 0, unlocked);
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        if (revertObserve) revert("OBSERVE_FAILURE");
        require(secondsAgos.length == 3 && secondsAgos[0] == 100 && secondsAgos[1] == 10 && secondsAgos[2] == 0);

        uint256 length = malformedObservations ? 2 : 3;
        tickCumulatives = new int56[](length);
        secondsPerLiquidityCumulativeX128s = new uint160[](length);
        for (uint256 i; i < length; ++i) {
            tickCumulatives[i] = _tickCumulatives[i];
            // The loop is bounded by the three-element mock observation array.
            // forge-lint: disable-next-line(unsafe-typecast)
            secondsPerLiquidityCumulativeX128s[i] = uint160(i + 1);
        }
    }
}

contract MockOracleV3PoolWithFailingLiquidity {
    MockOracleV3Pool private immutable _POOL;

    constructor(MockOracleV3Pool pool_) {
        _POOL = pool_;
    }

    function factory() external view returns (address) {
        return _POOL.factory();
    }

    function token0() external view returns (address) {
        return _POOL.token0();
    }

    function token1() external view returns (address) {
        return _POOL.token1();
    }

    function fee() external view returns (uint24) {
        return _POOL.fee();
    }

    function tickSpacing() external view returns (int24) {
        return _POOL.tickSpacing();
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return _POOL.slot0();
    }

    function liquidity() external pure returns (uint128) {
        revert("LIQUIDITY_FAILURE");
    }

    function observe(uint32[] calldata secondsAgos) external view returns (int56[] memory, uint160[] memory) {
        return _POOL.observe(secondsAgos);
    }
}
