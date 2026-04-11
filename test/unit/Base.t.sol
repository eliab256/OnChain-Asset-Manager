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
import {MultiSigWallet} from "../../src/MultiSigWallet.sol";
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
import {ContractCodeConstants} from "../../src/ContractCodeConstants.sol";

abstract contract BaseTest is Test, ContractCodeConstants {
    MultiSigWallet public multiSigWallet;
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
    AssetTokenMock public mockComp;

    MockV3Aggregator public mockWethPriceFeed;
    MockV3Aggregator public mockUsdcPriceFeed;
    MockV3Aggregator public mockWbtcPriceFeed;
    MockV3Aggregator public mockLinkPriceFeed;
    MockV3Aggregator public mockCompPriceFeed;

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
    uint256 public constant INITIAL_COMP_BALANCE = 10_000_000;
    uint256 public constant INITIAL_USDC_BALANCE = 10_000_000_000;

    //constants
    uint128 public weight30 = (30 * WEIGHT_PRECISION); // 30%
    uint128 public weight60 = (60 * WEIGHT_PRECISION); // 60%
    uint128 public weight50 = (50 * WEIGHT_PRECISION); // 50%
    uint128 public weight40 = (40 * WEIGHT_PRECISION); // 40%
    uint128 public weight70 = (70 * WEIGHT_PRECISION); // 70%
    uint128 public invalidWeight = (999 * WEIGHT_PRECISION) / 10; // 99,9%
    uint32 public validFeePercentage = 1 * PERCENTAGE_FEE_PRECISION; // 1%
    uint32 public invalidFeePercentage = (1 * PERCENTAGE_FEE_PRECISION) / 1000; // 0.001% - above the max fee percentage allowed of 10%

    int256 public constant WETH_INITIAL_PRICE = 2000 * 10 ** 8; // $2000 with 8 decimals
    int256 public constant WBTC_INITIAL_PRICE = 30000 * 10 ** 8; // $30000 with 8 decimals
    int256 public constant LINK_INITIAL_PRICE = 7 * 10 ** 8; // $7 with 8 decimals
    int256 public constant COMP_INITIAL_PRICE = 50 * 10 ** 8; // $50 with 8 decimals
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
            multiSigWallet,
            deployer
        ) = deployerPeriphery.run();

        (mockWeth, mockUsdc, mockWbtc, mockLink, mockComp) = helperConfig
            .getAssetTokenMocks();
        (
            mockWethPriceFeed,
            mockUsdcPriceFeed,
            mockWbtcPriceFeed,
            mockLinkPriceFeed,
            mockCompPriceFeed
        ) = helperConfig.getPriceFeedMocks();

        mockUniRouter = helperConfig.getUniswapUniversalRouter();

        feeCollector = helperConfig.getFeeCollector();
        rebalancer = helperConfig.getRebalancer();

        // After deployment, DEFAULT_ADMIN_ROLE and ASSET_MANAGER_ROLE belong to
        // the MultiSigWallet.  For convenience in unit tests we grant them back
        // to the deployer so that every existing vm.prank(deployer) keeps working.
        vm.startPrank(address(multiSigWallet));
        indexManager.grantRole(indexManager.DEFAULT_ADMIN_ROLE(), deployer);
        indexManager.grantRole(indexManager.ASSET_MANAGER_ROLE(), deployer);
        vm.stopPrank();

        // mint tokens to deployer
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
        mockComp.mint(
            deployer,
            INITIAL_COMP_BALANCE * 10 ** mockComp.decimals()
        );
        mockUsdc.mint(
            deployer,
            INITIAL_USDC_BALANCE * 10 ** mockUsdc.decimals()
        );

        // mint tokens to users
        mockWeth.mint(
            user1,
            (INITIAL_WETH_BALANCE * 10 ** mockWeth.decimals()) / 100
        );
        mockWbtc.mint(
            user1,
            (INITIAL_WBTC_BALANCE * 10 ** mockWbtc.decimals()) / 100
        );
        mockLink.mint(
            user1,
            (INITIAL_LINK_BALANCE * 10 ** mockLink.decimals()) / 100
        );
        mockComp.mint(
            user1,
            (INITIAL_COMP_BALANCE * 10 ** mockComp.decimals()) / 100
        );
        mockUsdc.mint(
            user1,
            (INITIAL_USDC_BALANCE * 10 ** mockUsdc.decimals()) / 100
        );

        mockWeth.mint(
            user2,
            (INITIAL_WETH_BALANCE * 10 ** mockWeth.decimals()) / 100
        );
        mockWbtc.mint(
            user2,
            (INITIAL_WBTC_BALANCE * 10 ** mockWbtc.decimals()) / 100
        );
        mockLink.mint(
            user2,
            (INITIAL_LINK_BALANCE * 10 ** mockLink.decimals()) / 100
        );
        mockComp.mint(
            user2,
            (INITIAL_COMP_BALANCE * 10 ** mockComp.decimals()) / 100
        );
        mockUsdc.mint(
            user2,
            (INITIAL_USDC_BALANCE * 10 ** mockUsdc.decimals()) / 100
        );
        mockWethPriceFeed.updateAnswer(WETH_INITIAL_PRICE);
        mockUsdcPriceFeed.updateAnswer(USDC_INITIAL_PRICE);
        mockLinkPriceFeed.updateAnswer(LINK_INITIAL_PRICE);
        mockWbtcPriceFeed.updateAnswer(WBTC_INITIAL_PRICE);
        mockCompPriceFeed.updateAnswer(COMP_INITIAL_PRICE);

        initializedIndex = deployAndInitNewIndex.run(
            helperConfig,
            address(indexManager),
            address(multiSigWallet),
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

        // Configure mock router exchange rates
        mockUniRouter.setExchangeRate(
            address(mockUsdc),
            address(mockWeth),
            mockUniRouter.computeRate(uint256(WETH_INITIAL_PRICE) / 1e2, 1e18) // WETH_INITIAL_PRICE has 8 dec, USDC has 6 dec → divide by 1e2
        );
        mockUniRouter.setExchangeRate(
            address(mockUsdc),
            address(mockWbtc),
            mockUniRouter.computeRate(uint256(WBTC_INITIAL_PRICE) / 1e2, 1e8) // WBTC_INITIAL_PRICE has 8 dec, USDC has 6 dec → divide by 1e2
        );
        mockUniRouter.setExchangeRate(
            address(mockUsdc),
            address(mockLink),
            mockUniRouter.computeRate(uint256(LINK_INITIAL_PRICE) / 1e2, 1e18) // LINK_INITIAL_PRICE has 8 dec, USDC has 6 dec → divide by 1e2
        );
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockUsdc),
            mockUniRouter.computeRate(1e18, uint256(WETH_INITIAL_PRICE) / 1e2) // 1 WETH → 2000 USDC (6 dec)
        );
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockUsdc),
            mockUniRouter.computeRate(1e8, uint256(WBTC_INITIAL_PRICE) / 1e2) // 1 WBTC → 30000 USDC (6 dec)
        );
        mockUniRouter.setExchangeRate(
            address(mockLink),
            address(mockUsdc),
            mockUniRouter.computeRate(1e18, uint256(LINK_INITIAL_PRICE) / 1e2) // 1 LINK → 7 USDC (6 dec)
        );
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockWbtc),
            mockUniRouter.computeRate(15e18, 1e8) // No direct constant for 15 WETH, keep as is
        );
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockWeth),
            mockUniRouter.computeRate(1e8, 15e18) // No direct constant for 15 WETH, keep as is
        );
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockLink),
            mockUniRouter.computeRate(
                1e18,
                ((uint256(WETH_INITIAL_PRICE) * 1e18) /
                    uint256(LINK_INITIAL_PRICE)) // 1 WETH → (2000/7) LINK
            )
        );
        mockUniRouter.setExchangeRate(
            address(mockLink),
            address(mockWeth),
            mockUniRouter.computeRate(
                ((uint256(WETH_INITIAL_PRICE) * 1e18) /
                    uint256(LINK_INITIAL_PRICE)), // (2000/7) LINK → 1 WETH
                1e18
            )
        );
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockLink),
            mockUniRouter.computeRate(
                1e8,
                ((uint256(WBTC_INITIAL_PRICE) * 1e18) /
                    uint256(LINK_INITIAL_PRICE))
            )
        );
        mockUniRouter.setExchangeRate(
            address(mockLink),
            address(mockWbtc),
            mockUniRouter.computeRate(
                ((uint256(WBTC_INITIAL_PRICE) * 1e18) /
                    uint256(LINK_INITIAL_PRICE)),
                1e8
            )
        );

        // ── USDC ↔ COMP ──
        mockUniRouter.setExchangeRate(
            address(mockUsdc),
            address(mockComp),
            mockUniRouter.computeRate(uint256(COMP_INITIAL_PRICE) / 1e2, 1e18) // COMP_INITIAL_PRICE has 8 dec, USDC has 6 dec → divide by 1e2
        );
        mockUniRouter.setExchangeRate(
            address(mockComp),
            address(mockUsdc),
            mockUniRouter.computeRate(1e18, uint256(COMP_INITIAL_PRICE) / 1e2) // 1 COMP → 50 USDC (6 dec)
        );

        // ── WETH ↔ COMP ──
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockComp),
            mockUniRouter.computeRate(
                1e18, // 1 WETH (18 dec)
                (uint256(WETH_INITIAL_PRICE) * 1e18) /
                    uint256(COMP_INITIAL_PRICE) // COMP amount (18 dec) per 1 WETH
            )
        );
        mockUniRouter.setExchangeRate(
            address(mockComp),
            address(mockWeth),
            mockUniRouter.computeRate(
                (uint256(WETH_INITIAL_PRICE) * 1e18) /
                    uint256(COMP_INITIAL_PRICE), // COMP amount (18 dec) per 1 WETH
                1e18 // 1 WETH (18 dec)
            )
        );

        // ── WBTC ↔ COMP ──
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockComp),
            mockUniRouter.computeRate(
                1e8, // 1 WBTC (8 dec)
                (uint256(WBTC_INITIAL_PRICE) * 1e18) /
                    uint256(COMP_INITIAL_PRICE) // COMP amount (18 dec) per 1 WBTC
            )
        );
        mockUniRouter.setExchangeRate(
            address(mockComp),
            address(mockWbtc),
            mockUniRouter.computeRate(
                (uint256(WBTC_INITIAL_PRICE) * 1e18) /
                    uint256(COMP_INITIAL_PRICE), // COMP amount (18 dec) per 1 WBTC
                1e8 // 1 WBTC (8 dec)
            )
        );

        // ── LINK ↔ COMP ──
        mockUniRouter.setExchangeRate(
            address(mockLink),
            address(mockComp),
            mockUniRouter.computeRate(
                1e18, // 1 LINK (18 dec)
                (uint256(LINK_INITIAL_PRICE) * 1e18) /
                    uint256(COMP_INITIAL_PRICE) // COMP amount (18 dec) per 1 LINK
            )
        );
        mockUniRouter.setExchangeRate(
            address(mockComp),
            address(mockLink),
            mockUniRouter.computeRate(
                (uint256(LINK_INITIAL_PRICE) * 1e18) /
                    uint256(COMP_INITIAL_PRICE), // COMP amount (18 dec) per 1 LINK
                1e18 // 1 LINK (18 dec)
            )
        );

        // Fund mock router with tokens for swaps
        deal(
            address(mockWeth),
            address(mockUniRouter),
            INITIAL_WETH_BALANCE * 10 ** mockWeth.decimals()
        );
        deal(
            address(mockWbtc),
            address(mockUniRouter),
            INITIAL_WBTC_BALANCE * 10 ** mockWbtc.decimals()
        );
        deal(
            address(mockLink),
            address(mockUniRouter),
            INITIAL_LINK_BALANCE * 10 ** mockLink.decimals()
        );
        deal(
            address(mockComp),
            address(mockUniRouter),
            INITIAL_COMP_BALANCE * 10 ** mockComp.decimals()
        );
        deal(
            address(mockUsdc),
            address(mockUniRouter),
            INITIAL_USDC_BALANCE * 10 ** mockUsdc.decimals()
        );
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
        mockCompPriceFeed.updateAnswer(COMP_INITIAL_PRICE);
    }

    function _updatePriceFeedsWithNewPrices(
        int256 newWethPrice,
        int256 newUsdcPrice,
        int256 newWbtcPrice,
        int256 newLinkPrice
    ) internal {
        if (newWethPrice > 0) {
            mockWethPriceFeed.updateAnswer(newWethPrice);
        }
        if (newUsdcPrice > 0) {
            mockUsdcPriceFeed.updateAnswer(newUsdcPrice);
        }
        if (newWbtcPrice > 0) {
            mockWbtcPriceFeed.updateAnswer(newWbtcPrice);
        }
        if (newLinkPrice > 0) {
            mockLinkPriceFeed.updateAnswer(newLinkPrice);
        }
    }

    /**
     * @dev Refreshes all mock router exchange rates based on the current prices
     *      from the mock price feeds. Call this after _updatePriceFeedsWithNewPrices
     *      or after any manual price feed update to keep the router in sync.
     */
    function _refreshExchangeRates() internal {
        uint256 wethPrice = uint256(mockWethPriceFeed.latestAnswer()); // 8 decimals
        uint256 wbtcPrice = uint256(mockWbtcPriceFeed.latestAnswer()); // 8 decimals
        uint256 linkPrice = uint256(mockLinkPriceFeed.latestAnswer()); // 8 decimals
        uint256 compPrice = uint256(mockCompPriceFeed.latestAnswer()); // 8 decimals

        // ── USDC ↔ token pairs ──
        // Chainlink prices have 8 dec, USDC has 6 dec → divide by 1e2
        mockUniRouter.setExchangeRate(
            address(mockUsdc),
            address(mockWeth),
            mockUniRouter.computeRate(wethPrice / 1e2, 1e18)
        );
        mockUniRouter.setExchangeRate(
            address(mockUsdc),
            address(mockWbtc),
            mockUniRouter.computeRate(wbtcPrice / 1e2, 1e8)
        );
        mockUniRouter.setExchangeRate(
            address(mockUsdc),
            address(mockLink),
            mockUniRouter.computeRate(linkPrice / 1e2, 1e18)
        );
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockUsdc),
            mockUniRouter.computeRate(1e18, wethPrice / 1e2)
        );
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockUsdc),
            mockUniRouter.computeRate(1e8, wbtcPrice / 1e2)
        );
        mockUniRouter.setExchangeRate(
            address(mockLink),
            address(mockUsdc),
            mockUniRouter.computeRate(1e18, linkPrice / 1e2)
        );

        // ── WETH ↔ WBTC ──
        // wbtcPrice / wethPrice = how many WETH per 1 WBTC
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockWbtc),
            mockUniRouter.computeRate(
                (wbtcPrice * 1e18) / wethPrice, // WETH amount (18 dec) per 1 WBTC
                1e8 // 1 WBTC (8 dec)
            )
        );
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockWeth),
            mockUniRouter.computeRate(
                1e8, // 1 WBTC (8 dec)
                (wbtcPrice * 1e18) / wethPrice // WETH amount (18 dec) per 1 WBTC
            )
        );

        // ── WETH ↔ LINK ──
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockLink),
            mockUniRouter.computeRate(
                1e18, // 1 WETH (18 dec)
                (wethPrice * 1e18) / linkPrice // LINK amount (18 dec) per 1 WETH
            )
        );
        mockUniRouter.setExchangeRate(
            address(mockLink),
            address(mockWeth),
            mockUniRouter.computeRate(
                (wethPrice * 1e18) / linkPrice, // LINK amount (18 dec) per 1 WETH
                1e18 // 1 WETH (18 dec)
            )
        );

        // ── WBTC ↔ LINK ──
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockLink),
            mockUniRouter.computeRate(
                1e8, // 1 WBTC (8 dec)
                (wbtcPrice * 1e18) / linkPrice // LINK amount (18 dec) per 1 WBTC
            )
        );
        mockUniRouter.setExchangeRate(
            address(mockLink),
            address(mockWbtc),
            mockUniRouter.computeRate(
                (wbtcPrice * 1e18) / linkPrice, // LINK amount (18 dec) per 1 WBTC
                1e8 // 1 WBTC (8 dec)
            )
        );

        // ── USDC ↔ COMP ──
        mockUniRouter.setExchangeRate(
            address(mockUsdc),
            address(mockComp),
            mockUniRouter.computeRate(compPrice / 1e2, 1e18)
        );
        mockUniRouter.setExchangeRate(
            address(mockComp),
            address(mockUsdc),
            mockUniRouter.computeRate(1e18, compPrice / 1e2)
        );

        // ── WETH ↔ COMP ──
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockComp),
            mockUniRouter.computeRate(1e18, (wethPrice * 1e18) / compPrice)
        );
        mockUniRouter.setExchangeRate(
            address(mockComp),
            address(mockWeth),
            mockUniRouter.computeRate((wethPrice * 1e18) / compPrice, 1e18)
        );

        // ── WBTC ↔ COMP ──
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockComp),
            mockUniRouter.computeRate(1e8, (wbtcPrice * 1e18) / compPrice)
        );
        mockUniRouter.setExchangeRate(
            address(mockComp),
            address(mockWbtc),
            mockUniRouter.computeRate((wbtcPrice * 1e18) / compPrice, 1e8)
        );

        // ── LINK ↔ COMP ──
        mockUniRouter.setExchangeRate(
            address(mockLink),
            address(mockComp),
            mockUniRouter.computeRate(1e18, (linkPrice * 1e18) / compPrice)
        );
        mockUniRouter.setExchangeRate(
            address(mockComp),
            address(mockLink),
            mockUniRouter.computeRate((linkPrice * 1e18) / compPrice, 1e18)
        );
    }

    // =========================================================================
    //  Helpers — price manipulation
    // =========================================================================

    /// @dev Makes asset0 of `initializedIndex` severely overweight by pumping
    ///      its price 5×. Also refreshes router exchange rates.
    function _makeAsset0Overweight() internal {
        address token0 = initializedIndex.getAsset0();

        if (token0 == address(mockWeth)) {
            mockWethPriceFeed.updateAnswer(WETH_INITIAL_PRICE * 5);
        } else {
            mockWbtcPriceFeed.updateAnswer(WBTC_INITIAL_PRICE * 5);
        }

        _refreshExchangeRates();
    }

    /// @dev Makes asset1 of `initializedIndex` severely overweight by pumping
    ///      its price 5×. Also refreshes router exchange rates.
    function _makeAsset1Overweight() internal {
        address token1 = initializedIndex.getAsset1();

        if (token1 == address(mockWeth)) {
            mockWethPriceFeed.updateAnswer(WETH_INITIAL_PRICE * 5);
        } else {
            mockWbtcPriceFeed.updateAnswer(WBTC_INITIAL_PRICE * 5);
        }

        _refreshExchangeRates();
    }

    // =========================================================================
    //  Helpers — mint / redeem via router
    // =========================================================================

    /// @dev Mints shares for `_minter` on the initialized index through the router.
    function _mintSharesViaRouter(address _minter, uint256 _amount) internal {
        vm.startPrank(_minter);
        mockUsdc.approve(address(initializedIndex), _amount);
        vm.stopPrank();

        vm.prank(address(router));
        initializedIndex.mintShares(_minter, _amount, VALID_TOLERANCE);
    }

    /// @dev Redeems shares for `_redeemer` on the initialized index through the router.
    function _redeemSharesViaRouter(
        address _redeemer,
        uint256 _shares
    ) internal {
        vm.prank(address(router));
        initializedIndex.redeem(_redeemer, _shares, VALID_TOLERANCE);
    }
}
