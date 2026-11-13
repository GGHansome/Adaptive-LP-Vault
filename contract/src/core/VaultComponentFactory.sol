// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VaultControl} from "../control/VaultControl.sol";
import {AccessControlConfig} from "./VaultTypes.sol";
import {IControlledSwapExecutor} from "../interfaces/IControlledSwapExecutor.sol";
import {IVaultComponentFactory} from "../interfaces/IVaultComponentFactory.sol";
import {IVaultControl} from "../interfaces/IVaultControl.sol";
import {ControlledSwapExecutor} from "../swap/ControlledSwapExecutor.sol";
import {SwapExecutorConfig} from "../swap/SwapTypes.sol";

/// @title Vault Component Factory
/// @notice Creates the dedicated control plane and swap executor used by each adaptive LP vault.
/// @dev Keeping component creation code here prevents it from being embedded in every vault's initcode.
contract VaultComponentFactory is IVaultComponentFactory {
    /// @inheritdoc IVaultComponentFactory
    function deployComponents(
        AccessControlConfig calldata accessConfig,
        address token0,
        address token1,
        address uniswapV2Factory,
        address uniswapV3Factory,
        address swapPool,
        address router
    ) external override returns (IVaultControl control, IControlledSwapExecutor executor) {
        control = IVaultControl(
            address(new VaultControl(msg.sender, accessConfig, token0, token1, uniswapV2Factory, uniswapV3Factory))
        );
        executor = IControlledSwapExecutor(
            address(
                new ControlledSwapExecutor(
                    SwapExecutorConfig({
                        vault: msg.sender, router: router, swapPool: swapPool, factory: uniswapV3Factory
                    })
                )
            )
        );

        emit VaultComponentsDeployed(msg.sender, address(control), address(executor), swapPool);
    }
}
