// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LocalToken} from "./LocalToken.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/IUniswapV3External.sol";

interface ILocalV2Factory {
    function createPair(address token0, address token1) external returns (address);
}

interface ILocalV2Router {
    function addLiquidity(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 min0,
        uint256 min1,
        address recipient,
        uint256 deadline
    ) external returns (uint256, uint256, uint256);
}

interface ILocalV3Factory {
    function createPool(address token0, address token1, uint24 fee) external returns (address);
}

interface ILocalV3Pool {
    function initialize(uint160 price) external;
    function increaseObservationCardinalityNext(uint16 capacity) external;
}

/// @notice Prepares real protocol contracts and faucet assets on an isolated Anvil chain.
/// @dev Vault deployment/configuration deliberately remains in the shared production scripts.
contract PrepareLocal is Script {
    function run() external {
        require(block.chainid == 31337, "LOCAL_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        address[] memory accounts = vm.envAddress("LOCAL_ACCOUNTS", ",");
        require(accounts.length == 7 && accounts[0] == deployer, "LOCAL_ACCOUNTS");
        vm.startBroadcast(key);
        LocalToken usd = new LocalToken("Local USD test token", "tUSD", 6);
        LocalToken eth = new LocalToken("Local Ether test token", "tETH", 18);
        (LocalToken token0, LocalToken token1) = address(usd) < address(eth) ? (usd, eth) : (eth, usd);
        uint256 unit0 = 10 ** uint256(token0.decimals());
        uint256 unit1 = 10 ** uint256(token1.decimals());
        address v2Factory = _official("@uniswap/v2-core/build/UniswapV2Factory.json", abi.encode(deployer));
        address v3Factory =
            _official("@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json", "");
        // ERC20-only test paths; eth is not a real wrapped-native token, and NFT metadata is not tested.
        address router = _official(
            "@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json",
            abi.encode(v3Factory, address(eth))
        );
        address positionManager = _official(
            "@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json",
            abi.encode(v3Factory, address(eth), address(0))
        );
        address v2Router =
            _official("@uniswap/v2-periphery/build/UniswapV2Router02.json", abi.encode(v2Factory, address(eth)));
        address pair = ILocalV2Factory(v2Factory).createPair(address(token0), address(token1));
        address[3] memory pools;
        uint24[3] memory fees = [uint24(500), 3000, 10000];
        for (uint256 i; i < fees.length; ++i) {
            pools[i] = ILocalV3Factory(v3Factory).createPool(address(token0), address(token1), fees[i]);
            ILocalV3Pool(pools[i]).initialize(uint160(Math.sqrt(((uint256(1) << 192) * unit1) / unit0)));
            ILocalV3Pool(pools[i]).increaseObservationCardinalityNext(256);
        }
        for (uint256 i; i < accounts.length; ++i) {
            require(accounts[i] != address(0), "ZERO_ACCOUNT");
            token0.mint(accounts[i], 100_000_000 * unit0);
            token1.mint(accounts[i], 100_000_000 * unit1);
        }
        address[3] memory targets = [router, positionManager, v2Router];
        for (uint256 i; i < targets.length; ++i) {
            token0.approve(targets[i], type(uint256).max);
            token1.approve(targets[i], type(uint256).max);
        }
        ILocalV2Router(v2Router)
            .addLiquidity(
                address(token0),
                address(token1),
                1_000_000 * unit0,
                1_000_000 * unit1,
                0,
                0,
                deployer,
                block.timestamp + 600
            );
        for (uint256 i; i < fees.length; ++i) {
            int24 spacing = i == 0 ? int24(10) : i == 1 ? int24(60) : int24(200);
            int24 upper = (int24(887272) / spacing) * spacing;
            INonfungiblePositionManager(positionManager)
                .mint(
                    INonfungiblePositionManager.MintParams({
                        token0: address(token0),
                        token1: address(token1),
                        fee: fees[i],
                        tickLower: -upper,
                        tickUpper: upper,
                        amount0Desired: 1_000_000 * unit0,
                        amount1Desired: 1_000_000 * unit1,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: deployer,
                        deadline: block.timestamp + 600
                    })
                );
        }
        vm.stopBroadcast();
        string memory object = "local-protocol";
        vm.serializeAddress(object, "token0", address(token0));
        vm.serializeAddress(object, "token1", address(token1));
        vm.serializeUint(object, "decimals0", token0.decimals());
        vm.serializeUint(object, "decimals1", token1.decimals());
        vm.serializeAddress(object, "v2Factory", v2Factory);
        vm.serializeAddress(object, "v3Factory", v3Factory);
        vm.serializeAddress(object, "v2Router", v2Router);
        vm.serializeAddress(object, "router", router);
        vm.serializeAddress(object, "positionManager", positionManager);
        vm.serializeAddress(object, "pair", pair);
        vm.serializeAddress(object, "lowPool", pools[0]);
        vm.serializeAddress(object, "highPool", pools[1]);
        string memory json = vm.serializeAddress(object, "canonicalPool", pools[2]);
        vm.writeJson(json, vm.envString("LOCAL_PROTOCOL_FILE"));
    }

    function _official(string memory relativePath, bytes memory args) private returns (address deployed) {
        string memory path = string.concat(vm.projectRoot(), "/lib/uniswap-test-deps/node_modules/", relativePath);
        string memory text = vm.parseJsonString(vm.readFile(path), ".bytecode");
        if (bytes(text)[0] != "0" || bytes(text)[1] != "x") text = string.concat("0x", text);
        bytes memory code = bytes.concat(vm.parseBytes(text), args);
        assembly ("memory-safe") {
            deployed := create(0, add(code, 32), mload(code))
        }
        require(deployed != address(0), "PROTOCOL_DEPLOY_FAILED");
    }
}
