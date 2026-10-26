// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAdaptiveLPVault} from "../src/interfaces/IAdaptiveLPVault.sol";
import {IVaultControl} from "../src/interfaces/IVaultControl.sol";
import {IVaultRoles} from "../src/interfaces/IVaultRoles.sol";

/// @title Adaptive LP Vault bootstrap script
/// @notice Approves both seed assets and executes the one-time Manager bootstrap.
contract BootstrapAdaptiveLPVault is Script {
    error InvalidConfiguration();

    function run() external {
        string memory path =
            vm.envOr("DEPLOYMENT_FILE", string.concat("deployments/", vm.toString(block.chainid), ".json"));
        string memory manifest = vm.readFile(path);
        address vaultAddress = vm.parseJsonAddress(manifest, ".vault");
        address controlAddress = vm.parseJsonAddress(manifest, ".control");
        address token0 = vm.parseJsonAddress(manifest, ".token0");
        address token1 = vm.parseJsonAddress(manifest, ".token1");
        address bootstrapSender = vm.envAddress("BOOTSTRAP_SENDER");
        address receiver = vm.envAddress("BOOTSTRAP_RECEIVER");
        uint256 amount0 = vm.envUint("BOOTSTRAP_AMOUNT0");
        uint256 amount1 = vm.envUint("BOOTSTRAP_AMOUNT1");
        uint256 managerPrivateKey = vm.envUint("MANAGER_PRIVATE_KEY");
        if (vm.addr(managerPrivateKey) != bootstrapSender || receiver == address(0) || amount0 == 0 || amount1 == 0) {
            revert InvalidConfiguration();
        }

        IVaultRoles roles = IVaultRoles(controlAddress);
        if (!roles.hasRole(roles.MANAGER_ROLE(), bootstrapSender)) revert InvalidConfiguration();
        if (IVaultControl(controlAddress).vault() != vaultAddress) revert InvalidConfiguration();

        vm.startBroadcast(managerPrivateKey);
        IERC20(token0).approve(vaultAddress, 0);
        IERC20(token1).approve(vaultAddress, 0);
        IERC20(token0).approve(vaultAddress, amount0);
        IERC20(token1).approve(vaultAddress, amount1);
        IAdaptiveLPVault(vaultAddress).bootstrap(amount0, amount1, receiver);

        if (!IAdaptiveLPVault(vaultAddress).initialized()) revert InvalidConfiguration();
        console2.log("Bootstrapped vault", vaultAddress);
        console2.log("Bootstrap sender", bootstrapSender);
        console2.log("Receiver", receiver);
        console2.log("Amount0", amount0);
        console2.log("Amount1", amount1);
        console2.log("Plan version", IAdaptiveLPVault(vaultAddress).lastExecutedPlan().version);
        vm.stopBroadcast();
    }
}
