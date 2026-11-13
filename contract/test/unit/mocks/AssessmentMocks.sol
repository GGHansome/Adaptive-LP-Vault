// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OracleSnapshot} from "../../../src/oracle/OracleTypes.sol";

contract AssessmentToken is ERC20 {
    constructor() ERC20("Assessment Token", "AT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Provides a deterministic rounded valuation while keeping the real vault orchestration under test.
contract AssessmentOracle {
    address public immutable canonicalPool;
    address public immutable token0;
    address public immutable token1;
    uint8 public constant token0Decimals = 18;
    uint8 public constant token1Decimals = 18;
    uint256 public quoteDivisor = 1;
    OracleSnapshot private _snapshot;

    constructor(address pool, address token0_, address token1_) {
        canonicalPool = pool;
        token0 = token0_;
        token1 = token1_;
        setDeviation(1000);
    }

    function setDeviation(uint256 deviation) public {
        _snapshot.healthy = true;
        _snapshot.deviationBps = deviation;
        _snapshot.twapTick = 17;
    }

    function setQuoteDivisor(uint256 divisor) external {
        quoteDivisor = divisor;
    }

    function snapshot() external view returns (OracleSnapshot memory) {
        return _snapshot;
    }

    function quoteToken0InToken1(uint256 amount, int24, bool roundUp) external view returns (uint256) {
        return amount / quoteDivisor + (roundUp && amount % quoteDivisor != 0 ? 1 : 0);
    }
}
