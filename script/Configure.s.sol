// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IAdapterRegistry} from "../src/interfaces/IAdapterRegistry.sol";
import {IVaultControl} from "../src/interfaces/IVaultControl.sol";
import {IVaultRoles} from "../src/interfaces/IVaultRoles.sol";
import {VenueType} from "../src/core/VaultTypes.sol";

/// @title Adaptive LP Vault configuration script
/// @notice Grants business roles as Default Admin and registers adapters as Manager.
contract ConfigureAdaptiveLPVault is Script {
    error InvalidConfiguration();

    function run() external {
        string memory path =
            vm.envOr("DEPLOYMENT_FILE", string.concat("deployments/", vm.toString(block.chainid), ".json"));
        string memory manifest = vm.readFile(path);
        address vault = vm.parseJsonAddress(manifest, ".vault");
        address controlAddress = vm.parseJsonAddress(manifest, ".control");
        address v2Adapter = vm.parseJsonAddress(manifest, ".v2Adapter");
        address lowAdapter = vm.parseJsonAddress(manifest, ".lowAdapter");
        address highAdapter = vm.parseJsonAddress(manifest, ".highAdapter");
        address admin = vm.envAddress("DEFAULT_ADMIN");
        address manager = vm.envAddress("MANAGER");
        address guardian = vm.envAddress("GUARDIAN");
        address keeper = vm.envAddress("KEEPER");
        if (IVaultControl(controlAddress).vault() != vault) revert InvalidConfiguration();
        if (vm.addr(vm.envUint("ADMIN_PRIVATE_KEY")) != admin) revert InvalidConfiguration();
        if (vm.addr(vm.envUint("MANAGER_PRIVATE_KEY")) != manager) revert InvalidConfiguration();

        IVaultRoles roles = IVaultRoles(controlAddress);
        bytes32 defaultAdminRole = roles.DEFAULT_ADMIN_ROLE();
        if (!roles.hasRole(defaultAdminRole, admin)) revert InvalidConfiguration();

        vm.startBroadcast(vm.envUint("ADMIN_PRIVATE_KEY"));
        if (!roles.hasRole(roles.MANAGER_ROLE(), manager)) {
            roles.grantRole(roles.MANAGER_ROLE(), manager);
        }
        if (!roles.hasRole(roles.GUARDIAN_ROLE(), guardian)) {
            roles.grantRole(roles.GUARDIAN_ROLE(), guardian);
        }
        if (!roles.hasRole(roles.KEEPER_ROLE(), keeper)) {
            roles.grantRole(roles.KEEPER_ROLE(), keeper);
        }
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("MANAGER_PRIVATE_KEY"));
        IAdapterRegistry registry = IAdapterRegistry(controlAddress);
        registry.configureAdapter(VenueType.UNISWAP_V2, v2Adapter);
        registry.configureAdapter(VenueType.UNISWAP_V3_LOW_FEE, lowAdapter);
        registry.configureAdapter(VenueType.UNISWAP_V3_HIGH_FEE, highAdapter);

        if (registry.getAdapter(VenueType.UNISWAP_V2) != v2Adapter) revert InvalidConfiguration();
        if (registry.getAdapter(VenueType.UNISWAP_V3_LOW_FEE) != lowAdapter) revert InvalidConfiguration();
        if (registry.getAdapter(VenueType.UNISWAP_V3_HIGH_FEE) != highAdapter) revert InvalidConfiguration();

        console2.log("Configured vault", vault);
        console2.log("VaultControl", controlAddress);
        console2.log("Manager", manager);
        console2.log("Guardian", guardian);
        console2.log("Keeper", keeper);
        vm.stopBroadcast();
    }
}
