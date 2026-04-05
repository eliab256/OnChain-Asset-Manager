// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployPeriphery} from "../../../script/DeployPeriphery.s.sol";
import {
    DeployAndInitNewIndex,
    RunParams
} from "../../../script/DeployAndInitNewIndex.s.sol";
import {
    HelperConfig,
    AssetConfig,
    NetworkConfig
} from "../../../script/HelperConfig.s.sol";
import {AssetAvailable} from "../../../src/types.sol";
import {Router} from "../../../src/Router.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {Index} from "../../../src/Index.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract IntegrationBase is Test {
    DeployPeriphery deployScript;
    DeployAndInitNewIndex indexDeployer;
    HelperConfig helperConfig;

    IndexManager indexManager;
    SwapManager swapManager;
    Router router;

    /**
     * @notice Ierc20 interface for weth is ok because we only interact with it for transfers and
     * balance checks, not for any specific WETH functions.
     */
    IERC20 usdc;
    IERC20 weth;
    IERC20 link;
    IERC20 wbtc;
    IERC20 comp;

    AggregatorV3Interface usdcPriceFeed;
    AggregatorV3Interface wethPriceFeed;
    AggregatorV3Interface linkPriceFeed;
    AggregatorV3Interface wbtcPriceFeed;
    AggregatorV3Interface compPriceFeed;

    Index wbtcWethIndex;
    Index wbtcLinkIndex;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address deployer;

    function setUp() public virtual {
        vm.createSelectFork("mainnet");

        deployScript = new DeployPeriphery();
        helperConfig = new HelperConfig();

        // Deploy the periphery contracts and get the deployed addresses
        (
            indexManager,
            router,
            helperConfig,
            swapManager,
            deployer
        ) = deployScript.run();

        // Setting up token and price feed interfaces
        NetworkConfig memory networkConfig = helperConfig
            .getActiveNetworkConfig();

        usdc = IERC20(networkConfig.usdcAddress);
        weth = IERC20(
            helperConfig.getActiveAssetConfig(AssetAvailable.WETH).token
        );
        link = IERC20(
            helperConfig.getActiveAssetConfig(AssetAvailable.LINK).token
        );
        wbtc = IERC20(
            helperConfig.getActiveAssetConfig(AssetAvailable.WBTC).token
        );
        comp = IERC20(
            helperConfig.getActiveAssetConfig(AssetAvailable.COMP).token
        );

        usdcPriceFeed = AggregatorV3Interface(
            networkConfig.usdcPriceFeedAddress
        );
        wethPriceFeed = AggregatorV3Interface(
            helperConfig.getActiveAssetConfig(AssetAvailable.WETH).priceFeed
        );
        linkPriceFeed = AggregatorV3Interface(
            helperConfig.getActiveAssetConfig(AssetAvailable.LINK).priceFeed
        );
        wbtcPriceFeed = AggregatorV3Interface(
            helperConfig.getActiveAssetConfig(AssetAvailable.WBTC).priceFeed
        );
        compPriceFeed = AggregatorV3Interface(
            helperConfig.getActiveAssetConfig(AssetAvailable.COMP).priceFeed
        );

        deal(address(wbtc), deployer, 100e6); // 100 WBTC
        deal(address(weth), deployer, 100e18); // 100 WETH
        deal(address(link), deployer, 100e18); // 100 LINK
        deal(address(comp), deployer, 100e18); // 100 COMP
        deal(address(usdc), deployer, 100e6); // 100 USDC

        // Deploy Wbtc/Weth index
        indexDeployer = new DeployAndInitNewIndex();

        RunParams memory wbtcWethParams = RunParams({
            assetA: AssetAvailable.WBTC,
            assetB: AssetAvailable.WETH,
            weightA: 600000, // 60% weight for WBTC
            weightB: 400000, // 40% weight for WETH
            feePercentage: 20000, // 2% fee
            initialAssetADeposit: 10e6, // 10 WBTC
            initialAssetBDeposit: 0
        });

        wbtcWethIndex = indexDeployer.run(
            helperConfig,
            address(indexManager),
            wbtcWethParams
        );
    }
}
