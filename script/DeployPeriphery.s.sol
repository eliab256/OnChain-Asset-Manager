//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {IndexManager} from "../src/IndexManager.sol";
import {Router} from "../src/Router.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployPeriphery is Script {

    IndexManager public indexManager;
    Router public router;
    HelperConfig public helperConfig;

    function run() external returns ( IndexManager, Router, HelperConfig) {
        vm.startBroadcast();

        vm.stopBroadcast();
    }

}