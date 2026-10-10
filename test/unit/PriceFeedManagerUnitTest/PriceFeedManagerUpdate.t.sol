// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BasePriceFeedManagerTest} from "./BasePriceFeedManager.t.sol";
import {PendingFeed} from "../../../src/types.sol";
import {PriceFeedManagerEvents} from "../../../src/events/PriceFeedManagerEvents.sol";
import {
    PriceFeedManager__CallerNotAssetManager,
    PriceFeedManager__InvalidPriceFeed,
    PriceFeedManager__InvalidMaxDelay,
    PriceFeedManager__PriceFeedNotSet,
    PriceFeedManager__SamePriceFeedConfig,
    PriceFeedManager__PriceFeedUpdatePending,
    PriceFeedManager__NoPendingPriceFeedUpdate,
    PriceFeedManager__PriceFeedUpdateExpired
} from "../../../src/errors/PriceFeedManagerErrors.sol";
import {Vm} from "forge-std/Vm.sol";

contract PriceFeedManagerUpdateTest is BasePriceFeedManagerTest {
    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  proposePriceFeedUpdate — reverts
    // =========================================================================

    function testProposePriceFeedUpdateRevertsIfCallerNotAssetManager() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        vm.prank(user1);
        vm.expectRevert(PriceFeedManager__CallerNotAssetManager.selector);
        priceFeedManager.proposePriceFeedUpdate(
            s_asset,
            address(s_newFeed),
            s_validMaxDelay
        );
    }

    function testProposePriceFeedUpdateRevertsIfFeedNotSet() public {
        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__PriceFeedNotSet.selector,
                s_asset
            )
        );
        priceFeedManager.proposePriceFeedUpdate(
            s_asset,
            address(s_newFeed),
            s_validMaxDelay
        );
    }

    function testProposePriceFeedUpdateRevertsIfSameConfig() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__SamePriceFeedConfig.selector);
        priceFeedManager.proposePriceFeedUpdate(
            s_asset,
            address(s_feed8Decimals),
            s_validMaxDelay
        );
    }

    function testProposePriceFeedUpdateRevertsIfPendingWithinDelay() public {
        uint256 executableAt = _registerAndProposeNewFeed();
        vm.warp(executableAt - 1);

        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__PriceFeedUpdatePending.selector);
        priceFeedManager.proposePriceFeedUpdate(
            s_asset,
            address(s_feed18Decimals),
            s_validMaxDelay
        );
    }

    function testProposePriceFeedUpdateRevertsIfNewFeedHasNoCode() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                s_noCodeFeed
            )
        );
        priceFeedManager.proposePriceFeedUpdate(
            s_asset,
            s_noCodeFeed,
            s_validMaxDelay
        );
    }

    function testProposePriceFeedUpdateRevertsIfNewFeedAnswerIsZero() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        s_newFeed.setAnswer(0);

        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                address(s_newFeed)
            )
        );
        priceFeedManager.proposePriceFeedUpdate(
            s_asset,
            address(s_newFeed),
            s_validMaxDelay
        );
    }

    function testProposePriceFeedUpdateRevertsIfMaxDelayIsZero() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__InvalidMaxDelay.selector);
        priceFeedManager.proposePriceFeedUpdate(s_asset, address(s_newFeed), 0);
    }

    function testProposePriceFeedUpdateRevertsIfMaxDelayAboveLimit() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__InvalidMaxDelay.selector);
        priceFeedManager.proposePriceFeedUpdate(
            s_asset,
            address(s_newFeed),
            s_maxDelayAboveLimit
        );
    }

    // =========================================================================
    //  proposePriceFeedUpdate — success
    // =========================================================================

    function testProposePriceFeedUpdateStoresPendingUpdate() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        _assertPendingCleared(s_asset);
        uint256 expectedExecutableAt = block.timestamp + PRICE_FEED_UPDATE_DELAY;

        uint256 executableAt = _propose(
            s_asset,
            address(s_newFeed),
            s_otherValidMaxDelay
        );

        assertEq(executableAt, expectedExecutableAt, "returned executableAt");
        PendingFeed memory pending = priceFeedManager.getPendingPriceFeedUpdate(
            s_asset
        );
        assertEq(pending.feed, address(s_newFeed), "pending feed");
        assertEq(pending.maxDelay, s_otherValidMaxDelay, "pending maxDelay");
        assertEq(pending.executableAt, expectedExecutableAt, "pending executableAt");
        // The active configuration is untouched until execution
        _assertConfig(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        assertEq(
            priceFeedManager.getPrice(s_asset),
            uint256(PRICE_8_DECIMALS) * 1e10
        );
    }

    function testProposePriceFeedUpdateAcceptsMaxDelayOnlyChange() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        _propose(s_asset, address(s_feed8Decimals), s_otherValidMaxDelay);

        PendingFeed memory pending = priceFeedManager.getPendingPriceFeedUpdate(
            s_asset
        );
        assertEq(pending.feed, address(s_feed8Decimals));
        assertEq(pending.maxDelay, s_otherValidMaxDelay);
    }

    function testProposePriceFeedUpdateAcceptsFeedOnlyChange() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        _propose(s_asset, address(s_newFeed), s_validMaxDelay);

        PendingFeed memory pending = priceFeedManager.getPendingPriceFeedUpdate(
            s_asset
        );
        assertEq(pending.feed, address(s_newFeed));
        assertEq(pending.maxDelay, s_validMaxDelay);
    }

    function testProposePriceFeedUpdateOverwritesExecutableProposal() public {
        uint256 firstExecutableAt = _registerAndProposeNewFeed();
        vm.warp(firstExecutableAt);

        uint256 secondExecutableAt = _propose(
            s_asset,
            address(s_feed18Decimals),
            s_otherValidMaxDelay
        );

        PendingFeed memory pending = priceFeedManager.getPendingPriceFeedUpdate(
            s_asset
        );
        assertEq(pending.feed, address(s_feed18Decimals));
        assertEq(pending.maxDelay, s_otherValidMaxDelay);
        assertEq(pending.executableAt, secondExecutableAt);
        assertEq(secondExecutableAt, block.timestamp + PRICE_FEED_UPDATE_DELAY);
    }

    function testProposePriceFeedUpdateOverwritesExpiredProposal() public {
        uint256 firstExecutableAt = _registerAndProposeNewFeed();
        vm.warp(firstExecutableAt + PRICE_FEED_UPDATE_EXECUTION_WINDOW + 1);
        s_feed18Decimals.setAnswer(PRICE_18_DECIMALS);

        uint256 secondExecutableAt = _propose(
            s_asset,
            address(s_feed18Decimals),
            s_validMaxDelay
        );

        PendingFeed memory pending = priceFeedManager.getPendingPriceFeedUpdate(
            s_asset
        );
        assertEq(pending.feed, address(s_feed18Decimals));
        assertEq(pending.executableAt, secondExecutableAt);
    }

    function testProposePriceFeedUpdateDoesNotAffectOtherAssets() public {
        _registerAndProposeNewFeed();

        _assertPendingCleared(address(mockWeth));
        _assertConfig(
            address(mockWeth),
            address(mockWethPriceFeed),
            assetPriceFeedMaxDelay
        );
    }

    function testProposePriceFeedUpdateEmitsEvent() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        uint256 expectedExecutableAt = block.timestamp + PRICE_FEED_UPDATE_DELAY;

        vm.recordLogs();
        _propose(s_asset, address(s_newFeed), s_otherValidMaxDelay);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(priceFeedManager) ||
                logs[i].topics[0] !=
                PriceFeedManagerEvents.PriceFeedUpdateProposed.selector
            ) continue;

            eventFound = true;
            assertEq(
                address(uint160(uint256(logs[i].topics[1]))),
                s_asset,
                "event must log the asset"
            );
            assertEq(
                address(uint160(uint256(logs[i].topics[2]))),
                address(s_newFeed),
                "event must log the proposed feed"
            );
            (uint32 maxDelay, uint256 executableAt) = abi.decode(
                logs[i].data,
                (uint32, uint256)
            );
            assertEq(maxDelay, s_otherValidMaxDelay, "event must log the maxDelay");
            assertEq(executableAt, expectedExecutableAt, "event must log executableAt");
            break;
        }
        assertTrue(eventFound, "PriceFeedUpdateProposed event was not emitted");
    }

    // =========================================================================
    //  executePriceFeedUpdate — reverts
    // =========================================================================

    function testExecutePriceFeedUpdateRevertsIfCallerNotAssetManager() public {
        uint256 executableAt = _registerAndProposeNewFeed();
        vm.warp(executableAt);

        vm.prank(user1);
        vm.expectRevert(PriceFeedManager__CallerNotAssetManager.selector);
        priceFeedManager.executePriceFeedUpdate(s_asset);
    }

    function testExecutePriceFeedUpdateRevertsIfNoPendingUpdate() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__NoPendingPriceFeedUpdate.selector);
        priceFeedManager.executePriceFeedUpdate(s_asset);
    }

    function testExecutePriceFeedUpdateRevertsBeforeDelay() public {
        uint256 executableAt = _registerAndProposeNewFeed();
        vm.warp(executableAt - 1);

        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__NoPendingPriceFeedUpdate.selector);
        priceFeedManager.executePriceFeedUpdate(s_asset);
    }

    function testExecutePriceFeedUpdateRevertsAfterExecutionWindow() public {
        uint256 executableAt = _registerAndProposeNewFeed();
        vm.warp(executableAt + PRICE_FEED_UPDATE_EXECUTION_WINDOW + 1);

        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__PriceFeedUpdateExpired.selector);
        priceFeedManager.executePriceFeedUpdate(s_asset);
    }

    function testExecutePriceFeedUpdateRevertsIfProposedFeedBrokeDuringDelay()
        public
    {
        uint256 executableAt = _registerAndProposeNewFeed();
        vm.warp(executableAt);
        s_newFeed.setAnswer(0);

        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                address(s_newFeed)
            )
        );
        priceFeedManager.executePriceFeedUpdate(s_asset);
    }

    function testExecutePriceFeedUpdateRevertsIfProposedFeedDeprecatedDuringDelay()
        public
    {
        uint256 executableAt = _registerAndProposeNewFeed();
        vm.warp(executableAt);
        s_newFeed.setRevertOnLatestRoundData(true);

        vm.prank(s_assetManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__InvalidPriceFeed.selector,
                address(s_newFeed)
            )
        );
        priceFeedManager.executePriceFeedUpdate(s_asset);
    }

    function testExecutePriceFeedUpdateRevertsAfterCancel() public {
        uint256 executableAt = _registerAndProposeNewFeed();
        _cancel(s_asset);
        vm.warp(executableAt);

        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__NoPendingPriceFeedUpdate.selector);
        priceFeedManager.executePriceFeedUpdate(s_asset);
    }

    // =========================================================================
    //  executePriceFeedUpdate — success
    // =========================================================================

    function testExecutePriceFeedUpdateSucceedsAtExecutableAt() public {
        uint256 executableAt = _registerAndProposeNewFeed();
        vm.warp(executableAt);

        _execute(s_asset);

        _assertConfig(s_asset, address(s_newFeed), s_validMaxDelay);
    }

    function testExecutePriceFeedUpdateSucceedsAtEndOfExecutionWindow() public {
        uint256 executableAt = _registerAndProposeNewFeed();
        vm.warp(executableAt + PRICE_FEED_UPDATE_EXECUTION_WINDOW);

        _execute(s_asset);

        _assertConfig(s_asset, address(s_newFeed), s_validMaxDelay);
    }

    function testExecutePriceFeedUpdateAppliesConfigAndClearsPending() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        uint256 executableAt = _propose(
            s_asset,
            address(s_newFeed),
            s_otherValidMaxDelay
        );
        vm.warp(executableAt);
        s_newFeed.setAnswer(NEW_FEED_PRICE);

        _execute(s_asset);

        _assertConfig(s_asset, address(s_newFeed), s_otherValidMaxDelay);
        _assertPendingCleared(s_asset);
        assertTrue(priceFeedManager.hasPriceFeed(s_asset));
        assertEq(
            priceFeedManager.getPrice(s_asset),
            uint256(NEW_FEED_PRICE) * 1e10,
            "getPrice must read the new feed"
        );
    }

    function testExecutePriceFeedUpdateAppliesMaxDelayOnlyChange() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        uint256 executableAt = _propose(
            s_asset,
            address(s_feed8Decimals),
            s_otherValidMaxDelay
        );
        vm.warp(executableAt);

        _execute(s_asset);

        _assertConfig(s_asset, address(s_feed8Decimals), s_otherValidMaxDelay);
    }

    function testExecutePriceFeedUpdateEmitsEvent() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        uint256 executableAt = _propose(
            s_asset,
            address(s_newFeed),
            s_otherValidMaxDelay
        );
        vm.warp(executableAt);

        vm.recordLogs();
        _execute(s_asset);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(priceFeedManager) ||
                logs[i].topics[0] !=
                PriceFeedManagerEvents.PriceFeedUpdated.selector
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
                "event must log the old feed"
            );
            assertEq(
                address(uint160(uint256(logs[i].topics[3]))),
                address(s_newFeed),
                "event must log the new feed"
            );
            uint32 maxDelay = abi.decode(logs[i].data, (uint32));
            assertEq(maxDelay, s_otherValidMaxDelay, "event must log the maxDelay");
            break;
        }
        assertTrue(eventFound, "PriceFeedUpdated event was not emitted");
    }

    // =========================================================================
    //  cancelPriceFeedUpdate
    // =========================================================================

    function testCancelPriceFeedUpdateRevertsIfCallerNotAssetManager() public {
        _registerAndProposeNewFeed();

        vm.prank(user1);
        vm.expectRevert(PriceFeedManager__CallerNotAssetManager.selector);
        priceFeedManager.cancelPriceFeedUpdate(s_asset);
    }

    function testCancelPriceFeedUpdateRevertsIfNoPendingUpdate() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        vm.prank(s_assetManager);
        vm.expectRevert(PriceFeedManager__NoPendingPriceFeedUpdate.selector);
        priceFeedManager.cancelPriceFeedUpdate(s_asset);
    }

    function testCancelPriceFeedUpdateWithinDelayClearsPending() public {
        _registerAndProposeNewFeed();

        _cancel(s_asset);

        _assertPendingCleared(s_asset);
        _assertConfig(s_asset, address(s_feed8Decimals), s_validMaxDelay);
    }

    function testCancelPriceFeedUpdateWhenExecutableClearsPending() public {
        uint256 executableAt = _registerAndProposeNewFeed();
        vm.warp(executableAt);

        _cancel(s_asset);

        _assertPendingCleared(s_asset);
        _assertConfig(s_asset, address(s_feed8Decimals), s_validMaxDelay);
    }

    function testCancelPriceFeedUpdateWhenExpiredClearsPending() public {
        uint256 executableAt = _registerAndProposeNewFeed();
        vm.warp(executableAt + PRICE_FEED_UPDATE_EXECUTION_WINDOW + 1);

        _cancel(s_asset);

        _assertPendingCleared(s_asset);
        _assertConfig(s_asset, address(s_feed8Decimals), s_validMaxDelay);
    }

    function testCancelPriceFeedUpdateAllowsImmediateNewProposal() public {
        _registerAndProposeNewFeed();
        _cancel(s_asset);

        uint256 executableAt = _propose(
            s_asset,
            address(s_feed18Decimals),
            s_validMaxDelay
        );

        PendingFeed memory pending = priceFeedManager.getPendingPriceFeedUpdate(
            s_asset
        );
        assertEq(pending.feed, address(s_feed18Decimals));
        assertEq(executableAt, block.timestamp + PRICE_FEED_UPDATE_DELAY);
    }

    function testCancelPriceFeedUpdateEmitsEvent() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        _propose(s_asset, address(s_newFeed), s_otherValidMaxDelay);

        vm.recordLogs();
        _cancel(s_asset);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(priceFeedManager) ||
                logs[i].topics[0] !=
                PriceFeedManagerEvents.PriceFeedUpdateCancelled.selector
            ) continue;

            eventFound = true;
            assertEq(
                address(uint160(uint256(logs[i].topics[1]))),
                s_asset,
                "event must log the asset"
            );
            assertEq(
                address(uint160(uint256(logs[i].topics[2]))),
                address(s_newFeed),
                "event must log the cancelled feed"
            );
            uint32 maxDelay = abi.decode(logs[i].data, (uint32));
            assertEq(
                maxDelay,
                s_otherValidMaxDelay,
                "event must log the cancelled maxDelay"
            );
            break;
        }
        assertTrue(eventFound, "PriceFeedUpdateCancelled event was not emitted");
    }
}
