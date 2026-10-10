// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BasePriceFeedManagerTest} from "./BasePriceFeedManager.t.sol";
import {PriceFeedManagerEvents} from "../../../src/events/PriceFeedManagerEvents.sol";
import {
    PriceFeedManager__CallerNotAssetManager,
    PriceFeedManager__InvalidAsset,
    PriceFeedManager__InvalidPriceFeed,
    PriceFeedManager__InvalidMaxDelay,
    PriceFeedManager__PriceFeedAlreadySet
} from "../../../src/errors/PriceFeedManagerErrors.sol";
import {Vm} from "forge-std/Vm.sol";

contract PriceFeedManagerRegisterTest is BasePriceFeedManagerTest {
    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  registerPriceFeed — access control
    // =========================================================================

    function testRegisterPriceFeedRevertsIfCallerNotAssetManager() public {
        vm.prank(user1);
        vm.expectRevert(PriceFeedManager__CallerNotAssetManager.selector);
        priceFeedManager.registerPriceFeed(
            s_asset,
            address(s_feed8Decimals),
            s_validMaxDelay
        );
    }

    function testRegisterPriceFeedRevertsIfCallerIsIndexManagerAdminWithoutAssetManagerRole()
        public
    {
        // Revoke the role from the deployer: the check reads the IndexManager roles live.
        vm.prank(deployer);
        indexManager.revokeRole(s_assetManagerRole, deployer);

        vm.prank(deployer);
        vm.expectRevert(PriceFeedManager__CallerNotAssetManager.selector);
        priceFeedManager.registerPriceFeed(
            s_asset,
            address(s_feed8Decimals),
            s_validMaxDelay
        );
    }

    function testRegisterPriceFeedSucceedsForMultiSigAssetManager() public {
        vm.prank(address(multiSigWallet));
        priceFeedManager.registerPriceFeed(
            s_asset,
            address(s_feed8Decimals),
            s_validMaxDelay
        );

        assertTrue(priceFeedManager.hasPriceFeed(s_asset));
    }

    // =========================================================================
    //  registerPriceFeed — asset checks
    // =========================================================================

    function testRegisterPriceFeedRevertsIfAssetIsZero() public {
        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__InvalidAsset.selector);
        priceFeedManager.registerPriceFeed(
            address(0),
            address(s_feed8Decimals),
            s_validMaxDelay
        );
    }

    function testRegisterPriceFeedRevertsIfAlreadySet() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__PriceFeedAlreadySet.selector,
                s_asset
            )
        );
        priceFeedManager.registerPriceFeed(
            s_asset,
            address(s_newFeed),
            s_otherValidMaxDelay
        );
    }

    function testRegisterPriceFeedRevertsIfUsdcAlreadyRegisteredByDeployScript()
        public
    {
        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__PriceFeedAlreadySet.selector,
                address(mockUsdc)
            )
        );
        priceFeedManager.registerPriceFeed(
            address(mockUsdc),
            address(s_newFeed),
            s_validMaxDelay
        );
    }

    // =========================================================================
    //  registerPriceFeed — feed validation
    // =========================================================================

    function testRegisterPriceFeedRevertsIfFeedIsZero() public {
        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                address(0)
            )
        );
        priceFeedManager.registerPriceFeed(s_asset, address(0), s_validMaxDelay);
    }

    function testRegisterPriceFeedRevertsIfFeedHasNoCode() public {
        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                s_noCodeFeed
            )
        );
        priceFeedManager.registerPriceFeed(s_asset, s_noCodeFeed, s_validMaxDelay);
    }

    function testRegisterPriceFeedRevertsIfFeedIsNotAnAggregator() public {
        // An ERC20 has code but no latestRoundData(): the try/catch must map it to InvalidPriceFeed.
        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                address(mockWeth)
            )
        );
        priceFeedManager.registerPriceFeed(
            s_asset,
            address(mockWeth),
            s_validMaxDelay
        );
    }

    function testRegisterPriceFeedRevertsIfLatestRoundDataReverts() public {
        s_feed8Decimals.setRevertOnLatestRoundData(true);

        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                address(s_feed8Decimals)
            )
        );
        priceFeedManager.registerPriceFeed(
            s_asset,
            address(s_feed8Decimals),
            s_validMaxDelay
        );
    }

    function testRegisterPriceFeedRevertsIfAnswerIsZero() public {
        s_feed8Decimals.setAnswer(0);

        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                address(s_feed8Decimals)
            )
        );
        priceFeedManager.registerPriceFeed(
            s_asset,
            address(s_feed8Decimals),
            s_validMaxDelay
        );
    }

    function testRegisterPriceFeedRevertsIfAnswerIsNegative() public {
        s_feed8Decimals.setAnswer(-1);

        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                address(s_feed8Decimals)
            )
        );
        priceFeedManager.registerPriceFeed(
            s_asset,
            address(s_feed8Decimals),
            s_validMaxDelay
        );
    }

    function testRegisterPriceFeedRevertsIfDecimalsAboveStandard() public {
        s_feed18Decimals.setDecimals(s_decimalsAboveStandard);

        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                address(s_feed18Decimals)
            )
        );
        priceFeedManager.registerPriceFeed(
            s_asset,
            address(s_feed18Decimals),
            s_validMaxDelay
        );
    }

    function testRegisterPriceFeedRevertsIfDecimalsReverts() public {
        s_feed8Decimals.setRevertOnDecimals(true);

        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                address(s_feed8Decimals)
            )
        );
        priceFeedManager.registerPriceFeed(
            s_asset,
            address(s_feed8Decimals),
            s_validMaxDelay
        );
    }

    function testRegisterPriceFeedAcceptsDecimalsEqualToStandard() public {
        _register(s_asset, address(s_feed18Decimals), s_validMaxDelay);

        _assertConfig(s_asset, address(s_feed18Decimals), s_validMaxDelay);
    }

    // =========================================================================
    //  registerPriceFeed — maxDelay validation
    // =========================================================================

    function testRegisterPriceFeedRevertsIfMaxDelayIsZero() public {
        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__InvalidMaxDelay.selector);
        priceFeedManager.registerPriceFeed(s_asset, address(s_feed8Decimals), 0);
    }

    function testRegisterPriceFeedRevertsIfMaxDelayAboveLimit() public {
        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__InvalidMaxDelay.selector);
        priceFeedManager.registerPriceFeed(
            s_asset,
            address(s_feed8Decimals),
            s_maxDelayAboveLimit
        );
    }

    function testRegisterPriceFeedAcceptsMaxDelayAtLimit() public {
        _register(s_asset, address(s_feed8Decimals), s_maxDelayLimit);

        _assertConfig(s_asset, address(s_feed8Decimals), s_maxDelayLimit);
    }

    // =========================================================================
    //  registerPriceFeed — success
    // =========================================================================

    function testRegisterPriceFeedStoresConfig() public {
        assertFalse(priceFeedManager.hasPriceFeed(s_asset));
        _assertConfig(s_asset, address(0), 0);

        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        assertTrue(priceFeedManager.hasPriceFeed(s_asset));
        _assertConfig(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        _assertPendingCleared(s_asset);
        // Other assets are untouched
        assertFalse(priceFeedManager.hasPriceFeed(s_otherAsset));
        _assertConfig(
            address(mockWeth),
            address(mockWethPriceFeed),
            assetPriceFeedMaxDelay
        );
    }

    function testRegisterPriceFeedIsEffectiveImmediately() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        assertEq(
            priceFeedManager.getPrice(s_asset),
            uint256(PRICE_8_DECIMALS) * 10 ** (DECIMALS_STANDARD - FEED_DECIMALS_8)
        );
    }

    function testRegisterPriceFeedEmitsEvent() public {
        vm.recordLogs();
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(priceFeedManager) ||
                logs[i].topics[0] !=
                PriceFeedManagerEvents.PriceFeedRegistered.selector
            ) continue;

            eventFound = true;
            assertEq(
                address(uint160(uint256(logs[i].topics[1]))),
                s_asset,
                "event must log the asset"
            );
            assertEq(
                address(uint160(uint256(logs[i].topics[2]))),
                address(s_feed8Decimals),
                "event must log the feed"
            );
            uint32 maxDelay = abi.decode(logs[i].data, (uint32));
            assertEq(maxDelay, s_validMaxDelay, "event must log the maxDelay");
            break;
        }
        assertTrue(eventFound, "PriceFeedRegistered event was not emitted");
    }
}
