// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlConfig} from "../core/VaultTypes.sol";
import {IControlledSwapExecutor} from "./IControlledSwapExecutor.sol";
import {IVaultControl} from "./IVaultControl.sol";

/// @notice Deploys the control and swap components dedicated to one vault.
/// @dev The calling vault becomes the immutable authorized vault of both components.
interface IVaultComponentFactory {
    /// @notice Emitted after a vault receives its dedicated control and swap components.
    event VaultComponentsDeployed(
        address indexed vault, address indexed vaultControl, address indexed swapExecutor, address swapPool
    );

    /// @notice Deploys a control plane and controlled swap executor bound to the caller.
    /// @param accessConfig Initial default-administrator configuration for the control plane.
    /// @param token0 Lower-address vault token derived from the canonical oracle.
    /// @param token1 Higher-address vault token derived from the canonical oracle.
    /// @param uniswapV2Factory Expected Uniswap V2 factory for adapter validation.
    /// @param uniswapV3Factory Expected Uniswap V3 factory for adapter and router validation.
    /// @param swapPool Canonical V3 pool validated by the vault before component deployment.
    /// @param router Approved exact-input Uniswap V3 router.
    /// @return control Newly deployed vault control plane.
    /// @return executor Newly deployed controlled swap executor.
    function deployComponents(
        AccessControlConfig calldata accessConfig,
        address token0,
        address token1,
        address uniswapV2Factory,
        address uniswapV3Factory,
        address swapPool,
        address router
    ) external returns (IVaultControl control, IControlledSwapExecutor executor);
}
