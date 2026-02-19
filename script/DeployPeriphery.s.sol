//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {AdminController} from "../src/AdminController.sol";
import {IndexFactory} from "../src/IndexFactory.sol";

contract DeployPeriphery is Script {
    function run() external {
        vm.startBroadcast();

        vm.stopBroadcast();
    }

}