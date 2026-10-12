// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BasePriceFeedManagerTest} from "./BasePriceFeedManager.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {PriceFeedManagerEvents} from "../../../src/events/PriceFeedManagerEvents.sol";

/**
 * @dev Event-only tests for proposePriceFeedUpdate: overwriting an executable or
 *      expired pending update emits PriceFeedUpdateCancelled before PriceFeedUpdateProposed.
 */
contract PriceFeedManagerUpdateEventsTest is BasePriceFeedManagerTest {
    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev Returns how many PriceFeedManager logs match `_sig` and the position of the first one.
    function _findLogs(
        Vm.Log[] memory _logs,
        bytes32 _sig
    ) internal view returns (uint256 count, uint256 firstIndex) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (
                _logs[i].emitter != address(priceFeedManager) ||
                _logs[i].topics[0] != _sig
            ) continue;
            if (count == 0) firstIndex = i;
            count++;
        }
    }

    function _topicToAddress(bytes32 _topic) internal pure returns (address) {
        return address(uint160(uint256(_topic)));
    }

    /// @dev Overwrites the pending (s_newFeed, s_validMaxDelay) proposal of s_asset with
    ///      (s_feed18Decimals, s_otherValidMaxDelay) and checks Cancelled is emitted first.
    function _assertOverwriteEmitsCancelledFirst() internal {
        s_feed18Decimals.setAnswer(PRICE_18_DECIMALS);

        vm.recordLogs();
        uint256 secondExecutableAt = _propose(
            s_asset,
            address(s_feed18Decimals),
            s_otherValidMaxDelay
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 cancelledCount, uint256 cancelledIndex) = _findLogs(
            logs,
            PriceFeedManagerEvents.PriceFeedUpdateCancelled.selector
        );
        (uint256 proposedCount, uint256 proposedIndex) = _findLogs(
            logs,
            PriceFeedManagerEvents.PriceFeedUpdateProposed.selector
        );

        assertEq(cancelledCount, 1, "PriceFeedUpdateCancelled must be emitted once");
        assertEq(proposedCount, 1, "PriceFeedUpdateProposed must be emitted once");
        assertLt(
            cancelledIndex,
            proposedIndex,
            "PriceFeedUpdateCancelled must be emitted before PriceFeedUpdateProposed"
        );

        Vm.Log memory cancelled = logs[cancelledIndex];
        assertEq(_topicToAddress(cancelled.topics[1]), s_asset, "cancelled asset");
        assertEq(
            _topicToAddress(cancelled.topics[2]),
            address(s_newFeed),
            "cancelled feed must be the overwritten one"
        );
        assertEq(
            abi.decode(cancelled.data, (uint32)),
            s_validMaxDelay,
            "cancelled maxDelay must be the overwritten one"
        );

        Vm.Log memory proposed = logs[proposedIndex];
        assertEq(_topicToAddress(proposed.topics[1]), s_asset, "proposed asset");
        assertEq(
            _topicToAddress(proposed.topics[2]),
            address(s_feed18Decimals),
            "proposed feed"
        );
        (uint32 maxDelay, uint256 executableAt) = abi.decode(
            proposed.data,
            (uint32, uint256)
        );
        assertEq(maxDelay, s_otherValidMaxDelay, "proposed maxDelay");
        assertEq(executableAt, secondExecutableAt, "proposed executableAt");
    }

    // =========================================================================
    //  proposePriceFeedUpdate — PriceFeedUpdateCancelled on overwrite
    // =========================================================================

    function testProposePriceFeedUpdateFirstProposalDoesNotEmitCancelled()
        public
    {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        vm.recordLogs();
        _propose(s_asset, address(s_newFeed), s_validMaxDelay);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 cancelledCount, ) = _findLogs(
            logs,
            PriceFeedManagerEvents.PriceFeedUpdateCancelled.selector
        );
        (uint256 proposedCount, ) = _findLogs(
            logs,
            PriceFeedManagerEvents.PriceFeedUpdateProposed.selector
        );
        assertEq(cancelledCount, 0, "first proposal must not emit Cancelled");
        assertEq(proposedCount, 1, "PriceFeedUpdateProposed must be emitted");
    }

    function testProposePriceFeedUpdateOverwritingExecutableEmitsCancelledFirst()
        public
    {
        uint256 firstExecutableAt = _registerAndProposeNewFeed();
        vm.warp(firstExecutableAt);

        _assertOverwriteEmitsCancelledFirst();
    }

    function testProposePriceFeedUpdateOverwritingExpiredEmitsCancelledFirst()
        public
    {
        uint256 firstExecutableAt = _registerAndProposeNewFeed();
        vm.warp(firstExecutableAt + PRICE_FEED_UPDATE_EXECUTION_WINDOW + 1);

        _assertOverwriteEmitsCancelledFirst();
    }

    function testProposePriceFeedUpdateAfterExplicitCancelDoesNotEmitCancelled()
        public
    {
        _registerAndProposeNewFeed();
        _cancel(s_asset);

        vm.recordLogs();
        _propose(s_asset, address(s_feed18Decimals), s_otherValidMaxDelay);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 cancelledCount, ) = _findLogs(
            logs,
            PriceFeedManagerEvents.PriceFeedUpdateCancelled.selector
        );
        assertEq(
            cancelledCount,
            0,
            "a cleared proposal must not be cancelled again"
        );
    }
}
