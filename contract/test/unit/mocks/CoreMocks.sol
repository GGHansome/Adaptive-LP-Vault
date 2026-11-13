// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VenueType} from "../../../src/core/VaultTypes.sol";

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
