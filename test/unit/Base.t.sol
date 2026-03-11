// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployPeriphery} from "../../script/DeployPeriphery.s.sol";
import {DeployAndInitNewIndex} from "../../script/DeployAndInitNewIndex.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Router} from "../../src/Router.sol";
import {IndexManager} from "../../src/IndexManager.sol";
import {Index} from "../../src/Index.sol";
import {MockUSDC} from "../mocks/USDCMock.sol";
import {AssetTokenMock} from "../mocks/AssetTokenMock.sol";
import {
    MockV3Aggregator
} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {IndexAsset, AssetAvailable} from "../../src/types.sol";

contract BaseTest is Test {
    DeployPeriphery public deployerPeriphery;
    HelperConfig public helperConfig;
    Router public router;
    IndexManager public indexManager;
    DeployAndInitNewIndex public deployAndInitNewIndex;
    Index public index;

    // Mocks
    MockUSDC public mockUsdc;
    AssetTokenMock public mockWeth;
    AssetTokenMock public mockWbtc;
    AssetTokenMock public mockLink;

    MockV3Aggregator public mockWethPriceFeed;
    MockV3Aggregator public mockUsdcPriceFeed;
    MockV3Aggregator public mockWbtcPriceFeed;
    MockV3Aggregator public mockLinkPriceFeed;

    //Test partecipants
    address public deployer;
    address public feeCollector;
    address public rebalancer;
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    //token Amounts
    uint256 public constant INITIAL_WETH_BALANCE = 100_000;
    uint256 public constant INITIAL_WBTC_BALANCE = 100_000;
    uint256 public constant INITIAL_LINK_BALANCE = 100_000_000;
    uint256 public constant INITIAL_USDC_BALANCE = 10_000_000_000;

    //constants
    uint128 public PERCENTAGE_FEE_PRECISION = 10000; // 4 decimals precision for percentage values
    uint128 public WEIGHT_PRECISION = 10000; // 4 decimals precision for weights to allow more granular weights

    function setUp() public {
        deployerPeriphery = new DeployPeriphery();
        deployAndInitNewIndex = new DeployAndInitNewIndex();

        (indexManager, router, /*helperConfig*/, deployer) = deployerPeriphery
            .run();

        // (mockWeth, mockUsdc, mockWbtc, mockLink) = helperConfig
        //     .getAssetTokenMocks();
        // (
        //     mockWethPriceFeed,
        //     mockUsdcPriceFeed,
        //     mockWbtcPriceFeed,
        //     mockLinkPriceFeed
        // ) = helperConfig.getPriceFeedMocks();

        // feeCollector = helperConfig.getFeeCollector();
        // rebalancer = helperConfig.getRebalancer();

        vm.label(deployer, "assetManager");
        vm.label(feeCollector, "feeCollector");
        vm.label(rebalancer, "rebalancer");
        vm.label(user1, "user1");
        vm.label(user2, "user2");
        vm.label(user3, "user3");

        mockWeth.mint(deployer, INITIAL_WETH_BALANCE * 10 ** mockWeth.decimals());
        mockWbtc.mint(deployer, INITIAL_WBTC_BALANCE * 10 ** mockWbtc.decimals());
        mockLink.mint(deployer, INITIAL_LINK_BALANCE * 10 ** mockLink.decimals());
        mockUsdc.mint(deployer, INITIAL_USDC_BALANCE * 10 ** mockUsdc.decimals());

    }

    function testDeployNewIndex() public {
              
        assert(address(mockUsdc) != address(0));

    }

    
}
