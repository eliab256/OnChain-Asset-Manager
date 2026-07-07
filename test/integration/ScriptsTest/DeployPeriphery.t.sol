// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DeployPeriphery} from "../../../script/DeployPeriphery.s.sol";
import {HelperConfig, AssetConfig} from "../../../script/HelperConfig.s.sol";
import {MultiSigWallet} from "../../../src/contracts/periphery/MultiSigWallet.sol";
import {Router} from "../../../src/contracts/periphery/Router.sol";
import {IndexManager} from "../../../src/contracts/periphery/IndexManager.sol";
import {Index} from "../../../src/contracts/core/Index.sol";
import {SwapManager} from "../../../src/contracts/periphery/SwapManager.sol";
import {CodeConstants} from "../../../script/CodeConstants.sol";

contract DeployPeripheryTest is Test, CodeConstants {
    MultiSigWallet public multiSigWallet;
    IndexManager public mainnetIndexManager;
    Router public mainnetRouter;
    SwapManager public mainnetSwapManager;
    HelperConfig public isolatedHelperConfig;
    address public mainnetDeployer;

    modifier selectFork(string memory rpcAlias) {
        vm.createSelectFork(vm.rpcUrl(rpcAlias));
        _;
    }
    
    function setUp() public {
        
    }

    function testDeployPeripheryOnMainnet() public selectFork("mainnet") {
        DeployPeriphery mainnetDeployerPeriphery = new DeployPeriphery();
        (
            mainnetIndexManager,
            mainnetRouter,
            isolatedHelperConfig,
            mainnetSwapManager,
            multiSigWallet,
            mainnetDeployer
        ) = mainnetDeployerPeriphery.run();

        assertEq(mainnetIndexManager.getUsdc(), isolatedHelperConfig.getActiveNetworkConfig().usdcAddress);
        assertEq(mainnetIndexManager.getUsdcPriceFeed(), isolatedHelperConfig.getActiveNetworkConfig().usdcPriceFeedAddress);
        assertEq(mainnetIndexManager.getUniswapUniversalRouter(), isolatedHelperConfig.getActiveNetworkConfig().uniswapUniversalRouter);
        assertEq(mainnetIndexManager.getRouterAddress(), address(mainnetRouter));
        assertEq(mainnetIndexManager.getSwapManagerAddress(), address(mainnetSwapManager));
    }


}
