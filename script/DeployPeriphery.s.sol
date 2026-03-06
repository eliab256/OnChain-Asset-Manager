//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IndexManager} from "../src/IndexManager.sol";
import {Router} from "../src/Router.sol";
import {HelperConfig, NetworkConfig} from "./HelperConfig.s.sol";
import {CodeConstants} from "../script/CodeConstants.sol";

contract DeployPeriphery is Script, CodeConstants {
    IndexManager public indexManager;
    Router public router;
    HelperConfig public helperConfig;

    function run()
        external
        returns (IndexManager, Router, HelperConfig, address deployer)
    {
        helperConfig = new HelperConfig();
        NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        deployer = config.deployerAccount;

        bool isAnvil = block.chainid == ANVIL_CHAIN_ID;

        vm.startBroadcast(deployer);
        console.log(
            "======================= Contracts Deployment ================="
        );
        // 1. Deploy IndexManager
        indexManager = new IndexManager(config.usdcAddress);

        // 2. Deploy Router with the address of the deployed IndexManager
        router = new Router(address(indexManager));

        // 3. Set the Router address in the IndexManager
        indexManager.setRouterAddress(address(router));

        console.log(
            "======================= Deployment Summary ================="
        );
        if (!isAnvil) {
            console.log("Deployer Address:", deployer);
            console.log("IndexManager Address:", address(indexManager));
            console.log("Router Address:", address(router));
            console.log(
                "Router sets IndexManager's router address to:",
                router.getIndexManager()
            );
            console.log(
                "IndexManager sets Router's address to:",
                indexManager.getRouterAddress()
            );
        }

        vm.stopBroadcast();
        return (indexManager, router, helperConfig, deployer);
    }
}
