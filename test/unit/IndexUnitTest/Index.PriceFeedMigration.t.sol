// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Index} from "../../../src/Index.sol";
import {AssetAvailable} from "../../../src/types.sol";
import {RunParams} from "../../../script/DeployAndInitNewIndex.s.sol";
import {
    MockV3Aggregator
} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {
    PriceFeedManager__PriceIsStale
} from "../../../src/errors/PriceFeedManagerErrors.sol";

/**
 * @dev Scenario tests for the shared PriceFeedManager:
 *      - M-02: a deprecated / stale feed blocks every index using the asset, and a single
 *        timelocked feed update in the PriceFeedManager restores all of them.
 *      - L-03: the per-feed maxDelay (heartbeat + margin) accepts answers older than the heartbeat.
 */
contract IndexPriceFeedMigrationTest is BaseTest {
    // =========================================================================
    //  Contracts and addresses
    // =========================================================================

    Index internal s_secondIndex;
    MockV3Aggregator internal s_asset0Feed;
    MockV3Aggregator internal s_replacementFeed;

    // =========================================================================
    //  Constants
    // =========================================================================

    uint256 internal constant MINT_USDC_AMOUNT = 1_000e6;
    uint8 internal constant REPLACEMENT_FEED_DECIMALS = 8;
    /// L-03: age of an answer published just after a 1h heartbeat, still within the 15 min margin
    uint256 internal constant ANSWER_AGE_WITHIN_MARGIN = 1 hours + 5 minutes;

    // =========================================================================
    //  Values derived from the contracts
    // =========================================================================

    address internal s_asset0;
    int256 internal s_asset0Price;
    /// Timestamp at which the asset0 feed stops updating
    uint256 internal s_frozenAt;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();

        s_asset0 = initializedToken0;
        bool asset0IsWeth = s_asset0 == address(mockWeth);
        s_asset0Feed = asset0IsWeth ? mockWethPriceFeed : mockWbtcPriceFeed;
        s_asset0Price = asset0IsWeth ? WETH_INITIAL_PRICE : WBTC_INITIAL_PRICE;

        // Second initialized index sharing asset0 with initializedIndex (asset0 / COMP).
        s_secondIndex = deployAndInitNewIndex.run(
            helperConfig,
            address(indexManager),
            address(multiSigWallet),
            RunParams({
                assetA: asset0IsWeth ? AssetAvailable.WETH : AssetAvailable.WBTC,
                assetB: AssetAvailable.COMP,
                weightA: weight50,
                weightB: weight50,
                feePercentage: validFeePercentage,
                initialAssetADeposit: asset0IsWeth
                    ? 10 * 10 ** mockWeth.decimals()
                    : 1 * 10 ** mockWbtc.decimals(),
                initialAssetBDeposit: 0
            })
        );

        s_replacementFeed = new MockV3Aggregator(
            REPLACEMENT_FEED_DECIMALS,
            s_asset0Price
        );

        vm.label(address(s_secondIndex), "SecondIndex");
        vm.label(address(s_replacementFeed), "ReplacementFeed");
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev Freezes the asset0 feed at the current timestamp and warps past its maxDelay,
    ///      keeping every other feed fresh.
    function _makeAsset0FeedStale() internal {
        s_frozenAt = block.timestamp;
        vm.warp(block.timestamp + assetPriceFeedMaxDelay + 1);
        _refreshFeedsKeepingAsset0Stale();
    }

    /// @dev Refreshes every Base feed and the replacement feed, then rewinds the asset0 feed
    ///      to its frozen answer, as a deprecated feed that stopped updating would look.
    function _refreshFeedsKeepingAsset0Stale() internal {
        _refreshPriceFeeds();
        s_replacementFeed.updateAnswer(s_asset0Price);
        s_asset0Feed.updateRoundData(
            uint80(s_asset0Feed.latestRound() + 1),
            s_asset0Price,
            s_frozenAt,
            s_frozenAt
        );
    }

    /// @dev Proposes the replacement feed for asset0, warps past the delay and executes it.
    function _migrateAsset0Feed() internal {
        vm.prank(deployer);
        uint256 executableAt = priceFeedManager.proposePriceFeedUpdate(
            s_asset0,
            address(s_replacementFeed),
            assetPriceFeedMaxDelay
        );
        vm.warp(executableAt);
        _refreshFeedsKeepingAsset0Stale();

        vm.prank(deployer);
        priceFeedManager.executePriceFeedUpdate(s_asset0);
    }

    function _buyViaRouter(Index _index, address _buyer) internal {
        vm.startPrank(_buyer);
        mockUsdc.approve(address(_index), MINT_USDC_AMOUNT);
        router.buyExactUsdcAmountOfShares(
            address(_index),
            MINT_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        vm.stopPrank();
    }

    function _sellViaRouter(
        Index _index,
        address _seller,
        uint256 _shares
    ) internal {
        vm.prank(_seller);
        router.sellExactAmountOfSharesForUsdc(
            address(_index),
            _shares,
            VALID_TOLERANCE
        );
    }

    /// @dev Buys then sells shares of `_index` and asserts both legs moved balances.
    function _assertMintAndRedeemWork(Index _index, address _user) internal {
        uint256 sharesBefore = _index.balanceOf(_user);
        _buyViaRouter(_index, _user);
        uint256 sharesBought = _index.balanceOf(_user) - sharesBefore;
        assertGt(sharesBought, 0, "mint must work");

        uint256 usdcBefore = mockUsdc.balanceOf(_user);
        _sellViaRouter(_index, _user, sharesBought);
        assertEq(_index.balanceOf(_user), sharesBefore, "shares must be burned");
        assertGt(mockUsdc.balanceOf(_user), usdcBefore, "redeem must pay USDC");
    }

    // =========================================================================
    //  M-02 — stale feed blocks the indexes
    // =========================================================================

    function testMintRevertsWhenAsset0FeedIsStale() public {
        _makeAsset0FeedStale();

        vm.startPrank(user1);
        mockUsdc.approve(address(initializedIndex), MINT_USDC_AMOUNT);
        vm.expectRevert(PriceFeedManager__PriceIsStale.selector);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            MINT_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        vm.stopPrank();
    }

    function testRedeemRevertsWhenAsset0FeedIsStale() public {
        _buyViaRouter(initializedIndex, user1);
        uint256 shares = initializedIndex.balanceOf(user1);
        _makeAsset0FeedStale();

        vm.prank(user1);
        vm.expectRevert(PriceFeedManager__PriceIsStale.selector);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            shares,
            VALID_TOLERANCE
        );
    }

    function testMintOnSecondIndexRevertsWhenSharedFeedIsStale() public {
        _makeAsset0FeedStale();

        vm.startPrank(user1);
        mockUsdc.approve(address(s_secondIndex), MINT_USDC_AMOUNT);
        vm.expectRevert(PriceFeedManager__PriceIsStale.selector);
        router.buyExactUsdcAmountOfShares(
            address(s_secondIndex),
            MINT_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        vm.stopPrank();
    }

    function testMintStillRevertsWhileFeedUpdateIsInDelay() public {
        _makeAsset0FeedStale();
        vm.prank(deployer);
        uint256 executableAt = priceFeedManager.proposePriceFeedUpdate(
            s_asset0,
            address(s_replacementFeed),
            assetPriceFeedMaxDelay
        );
        vm.warp(executableAt - 1);
        _refreshFeedsKeepingAsset0Stale();

        vm.startPrank(user1);
        mockUsdc.approve(address(initializedIndex), MINT_USDC_AMOUNT);
        vm.expectRevert(PriceFeedManager__PriceIsStale.selector);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            MINT_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        vm.stopPrank();
    }

    // =========================================================================
    //  M-02 — one feed update restores every index
    // =========================================================================

    function testFeedMigrationRestoresMintAndRedeem() public {
        _buyViaRouter(initializedIndex, user1);
        uint256 sharesHeld = initializedIndex.balanceOf(user1);
        _makeAsset0FeedStale();

        _migrateAsset0Feed();

        assertEq(
            initializedIndex.getLatestPrice(s_asset0),
            uint256(s_asset0Price) * 1e10,
            "asset0 must be priced by the replacement feed"
        );
        _assertMintAndRedeemWork(initializedIndex, user1);

        // Shares minted before the outage can be redeemed after the migration.
        uint256 usdcBefore = mockUsdc.balanceOf(user1);
        _sellViaRouter(initializedIndex, user1, sharesHeld);
        assertEq(initializedIndex.balanceOf(user1), 0);
        assertGt(mockUsdc.balanceOf(user1), usdcBefore);
    }

    function testSingleFeedUpdateRestoresEveryIndexSharingTheAsset() public {
        _makeAsset0FeedStale();

        _migrateAsset0Feed();

        _assertMintAndRedeemWork(initializedIndex, user1);
        _assertMintAndRedeemWork(s_secondIndex, user2);
    }

    function testIndexFeedGettersFollowFeedMigration() public {
        assertEq(initializedIndex.getAsset0PriceFeed(), address(s_asset0Feed));
        _makeAsset0FeedStale();

        _migrateAsset0Feed();

        assertEq(initializedIndex.getAsset0PriceFeed(), address(s_replacementFeed));
        address secondIndexFeed = s_secondIndex.getAsset0() == s_asset0
            ? s_secondIndex.getAsset0PriceFeed()
            : s_secondIndex.getAsset1PriceFeed();
        assertEq(secondIndexFeed, address(s_replacementFeed));
    }

    // =========================================================================
    //  L-03 — heartbeat + margin
    // =========================================================================

    function testAsset0FeedRegisteredWithHeartbeatPlusMargin() public view {
        assertEq(
            priceFeedManager.getPriceFeedConfig(s_asset0).maxDelay,
            1 hours + 15 minutes
        );
    }

    function testGetLatestPriceAcceptsAnswerOlderThanHeartbeatWithinMargin()
        public
    {
        vm.warp(block.timestamp + ANSWER_AGE_WITHIN_MARGIN);

        assertEq(
            initializedIndex.getLatestPrice(s_asset0),
            uint256(s_asset0Price) * 1e10
        );
    }

    function testMintSucceedsWithAnswersOlderThanHeartbeatWithinMargin()
        public
    {
        // Every feed was last updated in setUp: all answers are 1h05m old.
        vm.warp(block.timestamp + ANSWER_AGE_WITHIN_MARGIN);

        _assertMintAndRedeemWork(initializedIndex, user1);
    }

    function testGetLatestPriceRevertsOneSecondPastHeartbeatPlusMargin() public {
        vm.warp(block.timestamp + assetPriceFeedMaxDelay + 1);

        vm.expectRevert(PriceFeedManager__PriceIsStale.selector);
        initializedIndex.getLatestPrice(s_asset0);
    }
}
