//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {AdminController} from "../src/AdminController.sol";
import {IndexFactory} from "../src/IndexFactory.sol";
import {Router} from "../src/Router.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployPeriphery is Script {
    AdminController public adminController;
    IndexFactory public indexFactory;
    Router public router;
    HelperConfig public helperConfig;

    function run() external returns (AdminController, IndexFactory, Router, HelperConfig) {
        vm.startBroadcast();

        vm.stopBroadcast();
    }

}