// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {AggregatorConfigurableMock} from "../../mocks/AggregatorConfigurableMock.sol";
import {FeedConfig, PendingFeed} from "../../../src/types.sol";

/**
 * @dev Shared state and helpers for the PriceFeedManager unit tests.
 *      Uses the PriceFeedManager proxy deployed by DeployPeriphery (owner = IndexManager);
 *      `deployer` holds ASSET_MANAGER_ROLE on the IndexManager (granted back in BaseTest).
 */
abstract contract BasePriceFeedManagerTest is BaseTest {
    // =========================================================================
    //  Contracts and addresses
    // =========================================================================

    AggregatorConfigurableMock internal s_feed8Decimals;
    AggregatorConfigurableMock internal s_feed18Decimals;
    AggregatorConfigurableMock internal s_newFeed;

    /// Asset with no feed registered (registerPriceFeed does not require code at the asset)
    address internal s_asset = makeAddr("pfmAsset");
    address internal s_otherAsset = makeAddr("pfmOtherAsset");
    address internal s_noCodeFeed = makeAddr("noCodeFeed");
    address internal s_assetManager;

    // =========================================================================
    //  Constants
    // =========================================================================

    uint8 internal constant FEED_DECIMALS_8 = 8;
    uint8 internal constant FEED_DECIMALS_18 = 18;
    int256 internal constant PRICE_8_DECIMALS = 2_000 * 10 ** 8; // $2000
    int256 internal constant PRICE_18_DECIMALS = 3_000 * 10 ** 18; // $3000
    int256 internal constant NEW_FEED_PRICE = 2_100 * 10 ** 8; // $2100

    /// ERC-7201 namespace id declared in the PriceFeedManager NatSpec
    string internal constant STORAGE_NAMESPACE =
        "onchainassetmanager.storage.PriceFeedManager";

    /// Number of low sequential slots checked to be empty (no non-namespaced storage)
    uint256 internal constant LOW_SLOTS_CHECKED = 10;

    // =========================================================================
    //  Values derived from the contracts
    // =========================================================================

    uint32 internal s_validMaxDelay;
    uint32 internal s_otherValidMaxDelay;
    uint32 internal s_maxDelayLimit;
    uint32 internal s_maxDelayAboveLimit;
    uint8 internal s_decimalsAboveStandard;
    bytes32 internal s_assetManagerRole;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public virtual override {
        super.setUp();

        s_feed8Decimals = new AggregatorConfigurableMock(
            FEED_DECIMALS_8,
            PRICE_8_DECIMALS
        );
        s_feed18Decimals = new AggregatorConfigurableMock(
            FEED_DECIMALS_18,
            PRICE_18_DECIMALS
        );
        s_newFeed = new AggregatorConfigurableMock(
            FEED_DECIMALS_8,
            NEW_FEED_PRICE
        );

        s_assetManager = deployer;
        s_validMaxDelay = assetPriceFeedMaxDelay;
        s_otherValidMaxDelay = usdcPriceFeedMaxDelay;
        s_maxDelayLimit = MAX_FEED_DELAY_LIMIT;
        s_maxDelayAboveLimit = MAX_FEED_DELAY_LIMIT + 1;
        s_decimalsAboveStandard = uint8(DECIMALS_STANDARD + 1);
        s_assetManagerRole = indexManager.ASSET_MANAGER_ROLE();

        vm.label(address(priceFeedManager), "PriceFeedManager");
        vm.label(address(s_feed8Decimals), "Feed8Decimals");
        vm.label(address(s_feed18Decimals), "Feed18Decimals");
        vm.label(address(s_newFeed), "NewFeed");
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _register(
        address _asset,
        address _feed,
        uint32 _maxDelay
    ) internal {
        vm.prank(s_assetManager);
        priceFeedManager.registerPriceFeed(_asset, _feed, _maxDelay);
    }

    function _propose(
        address _asset,
        address _feed,
        uint32 _maxDelay
    ) internal returns (uint256 executableAt) {
        vm.prank(s_assetManager);
        executableAt = priceFeedManager.proposePriceFeedUpdate(
            _asset,
            _feed,
            _maxDelay
        );
    }

    function _execute(address _asset) internal {
        vm.prank(s_assetManager);
        priceFeedManager.executePriceFeedUpdate(_asset);
    }

    function _cancel(address _asset) internal {
        vm.prank(s_assetManager);
        priceFeedManager.cancelPriceFeedUpdate(_asset);
    }

    /// @dev Registers s_feed8Decimals for s_asset and proposes s_newFeed as its replacement.
    function _registerAndProposeNewFeed()
        internal
        returns (uint256 executableAt)
    {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        executableAt = _propose(s_asset, address(s_newFeed), s_validMaxDelay);
    }

    /// @dev Sets `_feed` round data so that its latest answer is `_age` seconds old.
    function _setAnswerAge(
        AggregatorConfigurableMock _feed,
        int256 _answer,
        uint256 _age
    ) internal {
        _feed.setRoundData(1, _answer, block.timestamp - _age, 1);
    }

    function _assertPendingCleared(address _asset) internal view {
        PendingFeed memory pending = priceFeedManager
            .getPendingPriceFeedUpdate(_asset);
        assertEq(pending.feed, address(0), "pending feed must be cleared");
        assertEq(pending.maxDelay, 0, "pending maxDelay must be cleared");
        assertEq(pending.executableAt, 0, "pending executableAt must be cleared");
    }

    function _assertConfig(
        address _asset,
        address _feed,
        uint32 _maxDelay
    ) internal view {
        FeedConfig memory config = priceFeedManager.getPriceFeedConfig(_asset);
        assertEq(config.feed, _feed, "active feed");
        assertEq(config.maxDelay, _maxDelay, "active maxDelay");
    }
}
