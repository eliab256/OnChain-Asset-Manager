// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployPeriphery} from "../../script/DeployPeriphery.s.sol";
import {
    DeployAndInitNewIndex,
    RunParams
} from "../../script/DeployAndInitNewIndex.s.sol";
import {HelperConfig, AssetConfig} from "../../script/HelperConfig.s.sol";
import {Router} from "../../src/Router.sol";
import {IndexManager} from "../../src/IndexManager.sol";
import {Index} from "../../src/Index.sol";
import {SwapManager} from "../../src/SwapManager.sol";
import {MockUSDC} from "../mocks/USDCMock.sol";
import {AssetTokenMock} from "../mocks/AssetTokenMock.sol";
import {
    MockV3Aggregator
} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {UniversalRouterMock} from "../mocks/UniversalRouterMock.sol";
import {IndexAsset, AssetAvailable} from "../../src/types.sol";
import {CodeConstants} from "../../src/CodeConstants.sol";

abstract contract BaseTest is Test, CodeConstants {
    DeployPeriphery public deployerPeriphery;
    HelperConfig public helperConfig;
    Router public router;
    IndexManager public indexManager;
    DeployAndInitNewIndex public deployAndInitNewIndex;

    Index public initializedIndex;
    address public initializedToken0;
    address public initializedToken1;

    Index public nonInitializedIndex;
    address public nonInitializedToken0;
    address public nonInitializedToken1;

    SwapManager public swapManager;

    // Mocks
    MockUSDC public mockUsdc;
    AssetTokenMock public mockWeth;
    AssetTokenMock public mockWbtc;
    AssetTokenMock public mockLink;

    MockV3Aggregator public mockWethPriceFeed;
    MockV3Aggregator public mockUsdcPriceFeed;
    MockV3Aggregator public mockWbtcPriceFeed;
    MockV3Aggregator public mockLinkPriceFeed;

    UniversalRouterMock public mockUniRouter;

    //Test partecipants
    address public deployer;
    address public feeCollector;
    address public rebalancer;
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    //token Amounts
    uint256 public constant INITIAL_WETH_BALANCE = 1_000_000;
    uint256 public constant INITIAL_WBTC_BALANCE = 100_000;
    uint256 public constant INITIAL_LINK_BALANCE = 100_000_000;
    uint256 public constant INITIAL_USDC_BALANCE = 10_000_000_000;

    //constants
    uint128 public weight30 = (30 * WEIGHT_PRECISION); // 30%
    uint128 public weight60 = (60 * WEIGHT_PRECISION); // 60%
    uint128 public weight50 = (50 * WEIGHT_PRECISION); // 50%
    uint128 public weight40 = (40 * WEIGHT_PRECISION); // 40%
    uint32 public validFeePercentage = 1 * PERCENTAGE_FEE_PRECISION; // 1%
    uint32 public invalidFeePercentage = (1 * PERCENTAGE_FEE_PRECISION) / 1000; // 0.001% - above the max fee percentage allowed of 10%

    int256 public constant WETH_INITIAL_PRICE = 2000 * 10 ** 8; // $2000 with 8 decimals
    int256 public constant WBTC_INITIAL_PRICE = 30000 * 10 ** 8; // $30000 with 8 decimals
    int256 public constant LINK_INITIAL_PRICE = 7 * 10 ** 8; // $7 with 8 decimals
    //int256 public constant USDC_INITIAL_PRICE = 9979999;
    int256 public constant USDC_INITIAL_PRICE = 1 * 10 ** 8; // $1 with 8 decimals, to be consistent with other price feeds

    /// Valid tolerance: 0,5% expressed with 4-decimal precision.
    uint256 constant VALID_TOLERANCE = (5 * PERCENTAGE_FEE_PRECISION) / 10; // 0,5%

    function setUp() public virtual {
        deployerPeriphery = new DeployPeriphery();
        deployAndInitNewIndex = new DeployAndInitNewIndex();

        (
            indexManager,
            router,
            helperConfig,
            swapManager,
            deployer
        ) = deployerPeriphery.run();

        (mockWeth, mockUsdc, mockWbtc, mockLink) = helperConfig
            .getAssetTokenMocks();
        (
            mockWethPriceFeed,
            mockUsdcPriceFeed,
            mockWbtcPriceFeed,
            mockLinkPriceFeed
        ) = helperConfig.getPriceFeedMocks();

        mockUniRouter = helperConfig.getUniswapUniversalRouter();

        feeCollector = helperConfig.getFeeCollector();
        rebalancer = helperConfig.getRebalancer();

        vm.label(deployer, "assetManager");
        vm.label(feeCollector, "feeCollector");
        vm.label(rebalancer, "rebalancer");
        vm.label(user1, "user1");
        vm.label(user2, "user2");
        vm.label(user3, "user3");

        mockWeth.mint(
            deployer,
            INITIAL_WETH_BALANCE * 10 ** mockWeth.decimals()
        );
        mockWbtc.mint(
            deployer,
            INITIAL_WBTC_BALANCE * 10 ** mockWbtc.decimals()
        );
        mockLink.mint(
            deployer,
            INITIAL_LINK_BALANCE * 10 ** mockLink.decimals()
        );
        mockUsdc.mint(
            deployer,
            INITIAL_USDC_BALANCE * 10 ** mockUsdc.decimals()
        );

        mockWethPriceFeed.updateAnswer(WETH_INITIAL_PRICE);
        mockUsdcPriceFeed.updateAnswer(USDC_INITIAL_PRICE);
        mockLinkPriceFeed.updateAnswer(LINK_INITIAL_PRICE);
        mockWbtcPriceFeed.updateAnswer(WBTC_INITIAL_PRICE);

        initializedIndex = deployAndInitNewIndex.run(
            helperConfig,
            address(indexManager),
            RunParams({
                assetA: AssetAvailable.WETH,
                assetB: AssetAvailable.WBTC,
                weightA: weight60, // 60%
                weightB: weight40, // 40%
                feePercentage: validFeePercentage, // 1%
                initialAssetADeposit: 10 * 10 ** mockWeth.decimals(),
                initialAssetBDeposit: 0
            })
        );

        initializedToken0 = initializedIndex.getAsset0();
        initializedToken1 = initializedIndex.getAsset1();

        //deploy a non initialized index
        AssetConfig memory asset0Config = helperConfig.getActiveAssetConfig(
            AssetAvailable.WBTC
        );
        AssetConfig memory asset1Config = helperConfig.getActiveAssetConfig(
            AssetAvailable.LINK
        );

        IndexAsset memory indexAsset0 = IndexAsset({
            asset: asset0Config.token,
            weightPercentage: weight40,
            priceFeed: asset0Config.priceFeed
        });

        IndexAsset memory indexAsset1 = IndexAsset({
            asset: asset1Config.token,
            weightPercentage: weight60,
            priceFeed: asset1Config.priceFeed
        });
        vm.prank(deployer);
        (
            address nonInitializedIndexAddress,
            address notinitToken0,
            address notinitToken1
        ) = indexManager.createIndex(
                validFeePercentage,
                indexAsset0,
                indexAsset1
            );
        nonInitializedIndex = Index(nonInitializedIndexAddress);
        nonInitializedToken0 = notinitToken0;
        nonInitializedToken1 = notinitToken1;

        vm.label(address(router), "Router");
        vm.label(address(indexManager), "IndexManager");
        vm.label(address(swapManager), "SwapManager");
        vm.label(address(initializedIndex), "InitializedIndex");
        vm.label(address(nonInitializedIndex), "NonInitializedIndex");
    }

    /**
     * @dev Refreshes all mock price feeds to block.timestamp.
     *      Required after vm.warp() because Index.getLatestPrice reverts with
     *      Index__PriceIsStale when updatedAt > MAX_DELAY (1 hour) in the past.
     */
    function _refreshPriceFeeds() internal {
        mockWethPriceFeed.updateAnswer(WETH_INITIAL_PRICE);
        mockUsdcPriceFeed.updateAnswer(USDC_INITIAL_PRICE);
        mockLinkPriceFeed.updateAnswer(LINK_INITIAL_PRICE);
        mockWbtcPriceFeed.updateAnswer(WBTC_INITIAL_PRICE);
    }
}
