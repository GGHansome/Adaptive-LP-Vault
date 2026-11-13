// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {AdaptiveLPVault} from "../../src/core/AdaptiveLPVault.sol";
import {PositionPlan, MarketRegime, VenueType} from "../../src/core/VaultTypes.sol";
import {IVaultControl} from "../../src/interfaces/IVaultControl.sol";
import {IPositionAdapter} from "../../src/interfaces/IPositionAdapter.sol";
import {VaultStrategyMath} from "../../src/libraries/VaultStrategyMath.sol";
import {OracleSnapshot} from "../../src/oracle/OracleTypes.sol";

/// @notice Read-only bootstrap sizing using the deployed strategy library and real adapter preview.
/// @dev Writes public quantities only. Approvals and bootstrap remain in Bootstrap.s.sol.
contract PreviewLocalBootstrap is Script {
    function run() external {
        require(block.chainid == 31337, "LOCAL_ONLY");
        string memory manifest = vm.readFile(vm.envString("DEPLOYMENT_FILE"));
        AdaptiveLPVault vault = AdaptiveLPVault(vm.parseJsonAddress(manifest, ".vault"));
        require(!vault.initialized(), "ALREADY_INITIALIZED");
        OracleSnapshot memory oracle = vault.canonicalOracle().snapshot();
        require(oracle.healthy, "ORACLE_UNHEALTHY");
        IVaultControl control = vault.vaultControl();
        // The batched adapterTickSpacings() read is vault-only. A deployment preview
        // uses the public, validated registry entries without impersonating the vault.
        int24 lowSpacing = control.getConfig(VenueType.UNISWAP_V3_LOW_FEE).tickSpacing;
        int24 highSpacing = control.getConfig(VenueType.UNISWAP_V3_HIGH_FEE).tickSpacing;
        require(lowSpacing > 0 && highSpacing > 0, "MISSING_V3_ADAPTERS");
        uint256 strategy = uint256(vault.enterMediumBps()) | (uint256(vault.exitMediumBps()) << 24)
            | (uint256(vault.enterHighBps()) << 48) | (uint256(vault.exitHighBps()) << 72)
            | (uint256(vault.enterExtremeBps()) << 96) | (uint256(vault.exitExtremeBps()) << 120)
            | (uint256(vault.narrowRangeHalfWidthSteps()) << 144) | (uint256(vault.wideRangeHalfWidthSteps()) << 168)
            | (uint256(vault.minRecenterBps()) << 192);
        VaultStrategyMath.PlanInputs memory input = VaultStrategyMath.PlanInputs({
            oracle: VaultStrategyMath.PlanOracleInputs(oracle.deviationBps, oracle.twapTick, oracle.spotTick),
            currentPosition: VaultStrategyMath.PlanPositionInputs(0, 0, 0),
            strategy: strategy,
            lastExecutedRegime: MarketRegime.LOW_DEVIATION,
            activeVenue: VenueType.IDLE,
            lowSpacing: lowSpacing,
            highSpacing: highSpacing,
            planVersion: 0
        });
        PositionPlan memory plan = _getPlan(vm.parseJsonAddress(manifest, ".strategyMath"), input);
        require(plan.targetVenue == VenueType.UNISWAP_V3_LOW_FEE, "LOCAL_EXPECTS_LOW_DEVIATION");
        (uint256 amount0, uint256 amount1) = IPositionAdapter(control.getAdapter(plan.targetVenue))
            .previewDeposit(
                1000 * 10 ** uint256(vault.token0Decimals()), 1000 * 10 ** uint256(vault.token1Decimals()), plan
            );
        require(amount0 > 0 && amount1 > 0, "ZERO_BOOTSTRAP");
        string memory object = "local-bootstrap";
        // Strings preserve raw-unit precision when the orchestrator parses JSON.
        vm.serializeString(object, "amount0", vm.toString(amount0));
        string memory json = vm.serializeString(object, "amount1", vm.toString(amount1));
        vm.writeJson(json, vm.envString("LOCAL_BOOTSTRAP_FILE"));
    }

    function _getPlan(address planner, VaultStrategyMath.PlanInputs memory input)
        internal
        returns (PositionPlan memory)
    {
        // External Solidity library selectors include the qualified struct type, unlike
        // an ordinary contract interface. Use the library selector and calling convention.
        // getPlan is pure; this delegatecall executes only in the non-broadcast preview.
        (bool success, bytes memory result) =
            planner.delegatecall(abi.encodeWithSelector(VaultStrategyMath.getPlan.selector, input));
        require(success, "PLAN_PREVIEW_FAILED");
        return abi.decode(result, (PositionPlan));
    }
}
