//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Index} from "../src/Index.sol";
import {IndexFactory} from "../src/IndexFactory.sol";

contract DeployNewIndex is Script {
    function run() external {
        vm.startBroadcast();

        vm.stopBroadcast();
    }

}