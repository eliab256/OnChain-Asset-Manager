// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DeployPeriphery} from "../../../script/DeployPeriphery.s.sol";
import {HelperConfig, AssetConfig} from "../../../script/HelperConfig.s.sol";
import {MultiSigWallet} from "../../../src/MultiSigWallet.sol";
import {Router} from "../../../src/Router.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {Index} from "../../../src/Index.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {PriceFeedManager} from "../../../src/PriceFeedManager.sol";
import {FeedConfig} from "../../../src/types.sol";
import {CodeConstants} from "../../../script/CodeConstants.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

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

        // SwapManager is the ERC1967 proxy owned by the IndexManager
        assertEq(
            mainnetSwapManager.owner(),
            address(mainnetIndexManager),
            "IndexManager must own the SwapManager proxy"
        );
        address implementation = address(
            uint160(
                uint256(
                    vm.load(
                        address(mainnetSwapManager),
                        ERC1967Utils.IMPLEMENTATION_SLOT
                    )
                )
            )
        );
        assertTrue(implementation != address(0), "implementation slot must be set");
        assertTrue(
            implementation != address(mainnetSwapManager),
            "implementation must differ from the proxy"
        );
        assertTrue(implementation.code.length > 0, "implementation must have code");
        assertEq(
            mainnetSwapManager.getImplementation(),
            implementation,
            "getImplementation must match the ERC-1967 slot"
        );
    }

    function testDeployPeripheryDeploysPriceFeedManagerOnMainnet()
        public
        selectFork("mainnet")
    {
        DeployPeriphery mainnetDeployerPeriphery = new DeployPeriphery();
        (
            mainnetIndexManager,
            mainnetRouter,
            isolatedHelperConfig,
            mainnetSwapManager,
            multiSigWallet,
            mainnetDeployer
        ) = mainnetDeployerPeriphery.run();
        PriceFeedManager priceFeedManager = mainnetDeployerPeriphery
            .priceFeedManager();

        assertEq(
            address(priceFeedManager),
            mainnetIndexManager.getPriceFeedManagerAddress(),
            "script must expose the IndexManager PriceFeedManager proxy"
        );
        assertEq(
            priceFeedManager.owner(),
            address(mainnetIndexManager),
            "IndexManager must own the PriceFeedManager proxy"
        );

        address implementation = address(
            uint160(
                uint256(
                    vm.load(
                        address(priceFeedManager),
                        ERC1967Utils.IMPLEMENTATION_SLOT
                    )
                )
            )
        );
        assertTrue(implementation != address(0), "implementation slot must be set");
        assertTrue(
            implementation != address(priceFeedManager),
            "implementation must differ from the proxy"
        );
        assertTrue(implementation.code.length > 0, "implementation must have code");
        assertEq(
            priceFeedManager.getImplementation(),
            implementation,
            "getImplementation must match the ERC-1967 slot"
        );

        // USDC/USD feed registered by the script with USDC_USD_PRICEFEED_MAX_DELAY.
        FeedConfig memory usdcConfig = priceFeedManager.getPriceFeedConfig(
            USDC_MAINNET
        );
        assertEq(usdcConfig.feed, USDC_USD_PRICEFEED_MAINNET);
        assertEq(usdcConfig.maxDelay, USDC_USD_PRICEFEED_MAX_DELAY);
        assertTrue(priceFeedManager.hasPriceFeed(USDC_MAINNET));
        assertGt(priceFeedManager.getPrice(USDC_MAINNET), 0);

        // Asset feeds are registered later, by DeployAndInitNewIndex.
        assertFalse(priceFeedManager.hasPriceFeed(WETH_MAINNET));

        // The deployer no longer holds ASSET_MANAGER_ROLE: it cannot register feeds.
        assertFalse(
            mainnetIndexManager.hasRole(
                mainnetIndexManager.ASSET_MANAGER_ROLE(),
                mainnetDeployer
            )
        );
        assertTrue(
            mainnetIndexManager.hasRole(
                mainnetIndexManager.ASSET_MANAGER_ROLE(),
                address(multiSigWallet)
            )
        );
    }


}
