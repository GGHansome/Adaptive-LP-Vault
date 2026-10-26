// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {AccessControlConfig, StrategyConfig, VaultConfig, VenueType} from "../src/core/VaultTypes.sol";
import {AdaptiveLPVault} from "../src/core/AdaptiveLPVault.sol";
import {VaultComponentFactory} from "../src/core/VaultComponentFactory.sol";
import {UniswapV2Adapter} from "../src/adapters/UniswapV2Adapter.sol";
import {PositionAdapterConfig} from "../src/adapters/AdapterTypes.sol";
import {UniswapV3Adapter} from "../src/adapters/UniswapV3Adapter.sol";
import {CanonicalV3Oracle} from "../src/oracle/CanonicalV3Oracle.sol";
import {OracleConfig} from "../src/oracle/OracleTypes.sol";
import {IAdaptiveLPVault} from "../src/interfaces/IAdaptiveLPVault.sol";
import {IControlledSwapExecutor} from "../src/interfaces/IControlledSwapExecutor.sol";
import {IVaultControl} from "../src/interfaces/IVaultControl.sol";
import {IPositionAdapter} from "../src/interfaces/IPositionAdapter.sol";
import {VaultStrategyMath} from "../src/libraries/VaultStrategyMath.sol";

/// @title Adaptive LP Vault deployment script
/// @notice Deploys the linked strategy library, shared factory, oracle, vault, and three adapters.
/// @dev Adapter registration, role grants, and bootstrap are deliberately separate phases.
contract DeployAdaptiveLPVault is Script {
    error MissingLibraryPlaceholder();
    error DeploymentFailed();

    function run() external returns (address vaultAddress) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address canonicalPool = vm.envAddress("CANONICAL_POOL");
        address v2Factory = vm.envAddress("UNISWAP_V2_FACTORY");
        address v3Factory = vm.envAddress("UNISWAP_V3_FACTORY");
        address router = vm.envAddress("ROUTER");
        address lowFeePool = vm.envAddress("LOW_FEE_POOL");
        address highFeePool = vm.envAddress("HIGH_FEE_POOL");
        address positionManager = vm.envAddress("POSITION_MANAGER");

        vm.startBroadcast(deployerPrivateKey);
        if (deployer == address(0)) revert DeploymentFailed();

        address strategyMath = vm.deployCode("VaultStrategyMath.sol:VaultStrategyMath");
        VaultComponentFactory componentFactory = new VaultComponentFactory();
        CanonicalV3Oracle oracle = new CanonicalV3Oracle(
            OracleConfig({
                canonicalPool: canonicalPool,
                factory: v3Factory,
                twapWindowSeconds: uint32(vm.envUint("TWAP_WINDOW_SECONDS")),
                shortTwapWindowSeconds: uint32(vm.envUint("SHORT_TWAP_WINDOW_SECONDS"))
            })
        );

        VaultConfig memory vaultConfig = VaultConfig({
            dustTolerance0: vm.envUint("DUST_TOLERANCE0"),
            dustTolerance1: vm.envUint("DUST_TOLERANCE1"),
            canonicalOracle: address(oracle),
            componentFactory: address(componentFactory),
            router: router,
            uniswapV2Factory: v2Factory,
            uniswapV3Factory: v3Factory,
            minimumLockedShares: vm.envUint("MINIMUM_LOCKED_SHARES"),
            minimumInitialNav: vm.envUint("MINIMUM_INITIAL_NAV")
        });
        AccessControlConfig memory accessConfig = AccessControlConfig({
            initialDefaultAdminDelay: uint48(vm.envUint("DEFAULT_ADMIN_DELAY")),
            initialDefaultAdmin: vm.envAddress("DEFAULT_ADMIN")
        });
        StrategyConfig memory strategyConfig = StrategyConfig({
            minRebalanceCooldown: uint32(vm.envUint("MIN_REBALANCE_COOLDOWN")),
            enterMediumBps: uint24(vm.envUint("ENTER_MEDIUM_BPS")),
            exitMediumBps: uint24(vm.envUint("EXIT_MEDIUM_BPS")),
            enterHighBps: uint24(vm.envUint("ENTER_HIGH_BPS")),
            exitHighBps: uint24(vm.envUint("EXIT_HIGH_BPS")),
            enterExtremeBps: uint24(vm.envUint("ENTER_EXTREME_BPS")),
            exitExtremeBps: uint24(vm.envUint("EXIT_EXTREME_BPS")),
            narrowRangeHalfWidthSteps: uint24(vm.envUint("NARROW_RANGE_HALF_WIDTH_STEPS")),
            wideRangeHalfWidthSteps: uint24(vm.envUint("WIDE_RANGE_HALF_WIDTH_STEPS")),
            minRecenterBps: uint16(vm.envUint("MIN_RECENTER_BPS")),
            maxHealthyIdleBps: uint16(vm.envUint("MAX_HEALTHY_IDLE_BPS")),
            maxSwapSlippageBps: uint16(vm.envUint("MAX_SWAP_SLIPPAGE_BPS")),
            maxMigrationLossBps: uint16(vm.envUint("MAX_MIGRATION_LOSS_BPS"))
        });

        bytes memory creationCode =
            _linkStrategyLibrary(vm.getCode("AdaptiveLPVault.sol:AdaptiveLPVault"), strategyMath);
        bytes memory constructorArgs = abi.encode(
            vm.envString("VAULT_NAME"), vm.envString("VAULT_SYMBOL"), vaultConfig, accessConfig, strategyConfig
        );
        creationCode = bytes.concat(creationCode, constructorArgs);
        assembly ("memory-safe") {
            vaultAddress := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        if (vaultAddress == address(0)) revert DeploymentFailed();

        AdaptiveLPVault vault = AdaptiveLPVault(vaultAddress);
        address token0 = vault.token0();
        address token1 = vault.token1();

        UniswapV2Adapter v2Adapter = new UniswapV2Adapter(
            PositionAdapterConfig({
                vault: vaultAddress,
                venue: VenueType.UNISWAP_V2,
                pool: vm.envAddress("V2_POOL"),
                factory: v2Factory,
                positionManager: address(0)
            })
        );
        UniswapV3Adapter lowAdapter = new UniswapV3Adapter(
            PositionAdapterConfig({
                vault: vaultAddress,
                venue: VenueType.UNISWAP_V3_LOW_FEE,
                pool: lowFeePool,
                factory: v3Factory,
                positionManager: positionManager
            })
        );
        UniswapV3Adapter highAdapter = new UniswapV3Adapter(
            PositionAdapterConfig({
                vault: vaultAddress,
                venue: VenueType.UNISWAP_V3_HIGH_FEE,
                pool: highFeePool,
                factory: v3Factory,
                positionManager: positionManager
            })
        );

        _assertAddress("token0", token0, IPositionAdapter(address(v2Adapter)).token0());
        _assertAddress("token1", token1, IPositionAdapter(address(v2Adapter)).token1());
        _assertAddress("oracle pool", canonicalPool, oracle.canonicalPool());
        _assertAddress("component factory", address(componentFactory), vaultConfig.componentFactory);
        _assertAddress("vault control", vaultAddress, IVaultControl(address(vault.vaultControl())).vault());
        _assertAddress("executor vault", vaultAddress, IControlledSwapExecutor(address(vault.swapExecutor())).vault());

        string memory path =
            vm.envOr("DEPLOYMENT_FILE", string.concat("deployments/", vm.toString(block.chainid), ".json"));
        vm.createDir("deployments", true);
        vm.writeJson(
            _manifest(
                deployer,
                strategyMath,
                address(componentFactory),
                address(oracle),
                vaultAddress,
                address(vault.vaultControl()),
                address(vault.swapExecutor()),
                address(v2Adapter),
                address(lowAdapter),
                address(highAdapter),
                token0,
                token1,
                canonicalPool,
                v2Factory,
                v3Factory,
                router,
                vm.envAddress("V2_POOL"),
                lowFeePool,
                highFeePool,
                positionManager
            ),
            path
        );

        console2.log("VaultStrategyMath", strategyMath);
        console2.log("VaultComponentFactory", address(componentFactory));
        console2.log("CanonicalV3Oracle", address(oracle));
        console2.log("AdaptiveLPVault", vaultAddress);
        console2.log("VaultControl", address(vault.vaultControl()));
        console2.log("ControlledSwapExecutor", address(vault.swapExecutor()));
        console2.log("UniswapV2Adapter", address(v2Adapter));
        console2.log("UniswapV3LowFeeAdapter", address(lowAdapter));
        console2.log("UniswapV3HighFeeAdapter", address(highAdapter));
        console2.log("Deployment manifest", path);
        vm.stopBroadcast();
    }

    function _linkStrategyLibrary(bytes memory code, address libraryAddress) internal pure returns (bytes memory) {
        uint160 value = uint160(libraryAddress);
        bool linked;
        for (uint256 i; i + 40 <= code.length; ++i) {
            if (code[i] != bytes1("_") || code[i + 1] != bytes1("_") || code[i + 2] != bytes1("$")) continue;
            linked = true;
            for (uint256 j; j < 40; ++j) {
                uint8 nibble = uint8(value >> (4 * (39 - j)));
                code[i + j] = nibble < 10 ? bytes1(uint8(48 + nibble)) : bytes1(uint8(87 + nibble));
            }
            i += 39;
        }
        if (!linked) revert MissingLibraryPlaceholder();
        return code;
    }

    function _manifest(
        address deployer,
        address strategyMath,
        address componentFactory,
        address oracle,
        address vault,
        address control,
        address executor,
        address v2Adapter,
        address lowAdapter,
        address highAdapter,
        address token0,
        address token1,
        address canonicalPool,
        address v2Factory,
        address v3Factory,
        address router,
        address v2Pool,
        address lowPool,
        address highPool,
        address positionManager
    ) internal view returns (string memory) {
        return string.concat(
            '{"chainId":',
            vm.toString(block.chainid),
            ',"deployer":"',
            vm.toString(deployer),
            '","strategyMath":"',
            vm.toString(strategyMath),
            '","componentFactory":"',
            vm.toString(componentFactory),
            '","oracle":"',
            vm.toString(oracle),
            '","vault":"',
            vm.toString(vault),
            '","control":"',
            vm.toString(control),
            '","executor":"',
            vm.toString(executor),
            '","v2Adapter":"',
            vm.toString(v2Adapter),
            '","lowAdapter":"',
            vm.toString(lowAdapter),
            '","highAdapter":"',
            vm.toString(highAdapter),
            '","token0":"',
            vm.toString(token0),
            '","token1":"',
            vm.toString(token1),
            '","canonicalPool":"',
            vm.toString(canonicalPool),
            '","v2Factory":"',
            vm.toString(v2Factory),
            '","v3Factory":"',
            vm.toString(v3Factory),
            '","router":"',
            vm.toString(router),
            '","v2Pool":"',
            vm.toString(v2Pool),
            '","lowPool":"',
            vm.toString(lowPool),
            '","highPool":"',
            vm.toString(highPool),
            '","positionManager":"',
            vm.toString(positionManager),
            '"}'
        );
    }

    function _assertAddress(string memory label, address expected, address actual) internal pure {
        if (expected != actual) {
            console2.log(label, expected);
            console2.log("actual", actual);
            revert DeploymentFailed();
        }
    }
}
