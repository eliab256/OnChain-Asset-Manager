//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
import {IndexManager} from "../src/IndexManager.sol";
import {Router} from "../src/Router.sol";
import {SwapManager} from "../src/SwapManager.sol";
import {HelperConfig, NetworkConfig} from "./HelperConfig.s.sol";
import {CodeConstants} from "../script/CodeConstants.sol";

contract DeployPeriphery is Script, CodeConstants {
    MultiSigWallet public multiSigWallet;
    IndexManager public indexManager;
    Router public router;
    HelperConfig public helperConfig;
    SwapManager public swapManager;

    function run()
        external
        returns (
            IndexManager,
            Router,
            HelperConfig,
            SwapManager,
            MultiSigWallet,
            address deployer
        )
    {
        helperConfig = new HelperConfig();
        NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        deployer = config.deployerAccount;

        bool isAnvil = block.chainid == ANVIL_CHAIN_ID;

        vm.startBroadcast(deployer);

        console.log("============== Contracts Deployment ==============");
        // 1. Deploy MultiSigWallet and fund it with some ETH to cover transaction costs for confirmations and execution
        multiSigWallet = new MultiSigWallet(
            config.multiSigOwners,
            MULTISIG_REQUIRED_CONFIRMATIONS
        );
        address(multiSigWallet).call{value: 10 ether}("");

        // 2. Deploy the SwapManager implementation (initializers disabled)
        SwapManager swapManagerImplementation = new SwapManager();

        // 3. Deploy IndexManager; its constructor deploys and initializes the SwapManager proxy
        indexManager = new IndexManager(
            config.usdcAddress,
            config.usdcPriceFeedAddress,
            config.uniswapUniversalRouter,
            address(swapManagerImplementation)
        );
        swapManager = SwapManager(indexManager.getSwapManagerAddress());

        // 4. Deploy Router with the address of the deployed IndexManager
        router = new Router(address(indexManager));

        // 5. Set the Router address in the IndexManager
        indexManager.setRouterAddress(address(router));

        // 6. Transfer ownership to MultiSigWallet
        // Grant roles to the multi-sig first
        indexManager.grantRole(
            indexManager.DEFAULT_ADMIN_ROLE(),
            address(multiSigWallet)
        );
        indexManager.grantRole(
            indexManager.ASSET_MANAGER_ROLE(),
            address(multiSigWallet)
        );
        // Revoke ASSET_MANAGER_ROLE before DEFAULT_ADMIN_ROLE (revoking requires admin)
        indexManager.revokeRole(indexManager.ASSET_MANAGER_ROLE(), deployer);
        indexManager.revokeRole(indexManager.DEFAULT_ADMIN_ROLE(), deployer);

        console.log("============== Deployment Summary ==============");

        if (!isAnvil) {
            console.log("Deployer Address:", deployer);
            console.log("MultiSigWallet Address:", address(multiSigWallet));
            console.log("IndexManager Address:", address(indexManager));
            console.log("SwapManager Proxy Address:", address(swapManager));
            console.log(
                "SwapManager Implementation Address:",
                address(swapManagerImplementation)
            );
            console.log("Router Address:", address(router));
            console.log(
                "Router sets IndexManager's router address to:",
                router.getIndexManager()
            );
            console.log(
                "IndexManager sets Router's address to:",
                indexManager.getRouterAddress()
            );
            console.log(
                "IndexManager's SwapManager proxy:",
                indexManager.getSwapManagerAddress()
            );
        }

        vm.stopBroadcast();
        return (
            indexManager,
            router,
            helperConfig,
            swapManager,
            multiSigWallet,
            deployer
        );
    }
}
