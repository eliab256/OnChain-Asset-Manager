// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {BaseTest} from "../Base.t.sol";
import {DeployPeriphery} from "../../../script/DeployPeriphery.s.sol";
import {HelperConfig, AssetConfig} from "../../../script/HelperConfig.s.sol";
import {Router} from "../../../src/Router.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {Index} from "../../../src/Index.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {CodeConstants} from "../../../script/CodeConstants.sol";

contract DeployPeripheryTest is BaseTest, CodeConstants {
    IndexManager public mainnetIndexManager;
    Router public mainnetRouter;
    SwapManager public mainnetSwapManager;
    HelperConfig public isolatedHelperConfig;
    address public mainnetDeployer;

    modifier selectFork(string memory rpcAlias) {
        vm.createSelectFork(vm.rpcUrl(rpcAlias));
        _;
    }
    
    function setUp() public override {
        super.setUp();
    }

    function testDeployPeripheryOnMainnet() public selectFork("mainnet") {
        DeployPeriphery mainnetDeployerPeriphery = new DeployPeriphery();
        (
            mainnetIndexManager,
            mainnetRouter,
            isolatedHelperConfig,
            mainnetSwapManager,
            mainnetDeployer
        ) = mainnetDeployerPeriphery.run();

        assertEq(mainnetIndexManager.getUsdc(), isolatedHelperConfig.getActiveNetworkConfig().usdcAddress);
        assertEq(mainnetIndexManager.getUsdcPriceFeed(), isolatedHelperConfig.getActiveNetworkConfig().usdcPriceFeedAddress);
        assertEq(mainnetIndexManager.getUniswapUniversalRouter(), isolatedHelperConfig.getActiveNetworkConfig().uniswapUniversalRouter);
        assertEq(mainnetIndexManager.getRouterAddress(), address(mainnetRouter));
        assertEq(mainnetIndexManager.getSwapManagerAddress(), address(mainnetSwapManager));
    }


}
