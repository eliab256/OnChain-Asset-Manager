//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "../../../src/errors/IndexErrors.sol";
import "../../../src/events/IndexEvents.sol";

contract IndexRebalanceAndWeightsTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  proposeWeightUpdate
    // =========================================================================

    function testProposeWeightUpdateRevertsIfNotManager() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                keccak256("INDEX_MANAGER_ROLE")
            )
        );
        initializedIndex.proposeUpdateWeights(weight70);
    }

    function testProposeUpdateWeightsRevertsIfWeightSameAsCurrent() public {
        (uint128 actualWeight0, ) = initializedIndex.getAssetsWeights();
        vm.prank(address(indexManager));
        vm.expectRevert(Index__InvalidWeight.selector);
        initializedIndex.proposeUpdateWeights(actualWeight0);
    }

    function testProposeUpdateWeightsRevertsIfWeightSameAsMax() public {
        vm.prank(address(indexManager));
        vm.expectRevert(Index__InvalidWeight.selector);
        initializedIndex.proposeUpdateWeights(MAX_WEIGHT);
    }

    function testProposeUpdateWeightsRevertsIfWeightSameAsMin() public {
        vm.prank(address(indexManager));
        vm.expectRevert(Index__InvalidWeight.selector);
        initializedIndex.proposeUpdateWeights(MIN_WEIGHT);
    }

    function testProposeUpdateWeightRevertsIfThereIsAlreadyAProposal() public {
        vm.prank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);
        vm.warp(block.timestamp + 1 hours); // move forward in time to be past the first proposal timestamp

        (, , uint256 implementationTimestamp) = initializedIndex
            .getAssetsPendingWeights();
        assert(implementationTimestamp > block.timestamp);

        vm.prank(address(indexManager));
        vm.expectRevert(Index__PendingWeightUpdate.selector);
        initializedIndex.proposeUpdateWeights(weight30);
    }

    function testProposeUpdateWeightsWorksAfterPreviousProposalIsExecuted()
        public
    {
        vm.startPrank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1 hours); // move forward in time to be past the first proposal timestamp

        initializedIndex.executeWeightUpdate();

        (uint128 actualWeight0, ) = initializedIndex.getAssetsWeights();
        assertEq(actualWeight0, weight70);

        // Now we can propose a new weight update
        initializedIndex.proposeUpdateWeights(weight30);
        vm.stopPrank();

        (
            uint128 pendingWeight0,
            ,
            uint256 implementationTimestamp
        ) = initializedIndex.getAssetsPendingWeights();
        assertEq(pendingWeight0, weight30);
        assert(implementationTimestamp > block.timestamp);
    }

    function testProposeWeightUpdateUpdateStorage() public {
        vm.prank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);
        uint256 implementationTimestamp = block.timestamp + WEIGHT_UPDATE_DELAY;

        (
            uint128 pendingWeight0,
            uint128 pendingWeight1,
            uint256 actualImplementationTimestamp
        ) = initializedIndex.getAssetsPendingWeights();
        assertEq(pendingWeight0, weight70);
        assertEq(pendingWeight1, weight30);
        assertEq(implementationTimestamp, actualImplementationTimestamp);
    }

    function testProposeUpdateWeightsEmitsEvent() public {
        vm.prank(address(indexManager));
        vm.expectEmit(true, true, true, true);
        emit WeightsUpdateProposed(
            weight70,
            weight30,
            block.timestamp + WEIGHT_UPDATE_DELAY
        );
        initializedIndex.proposeUpdateWeights(weight70);
    }

    // =========================================================================
    //  executeWeightUpdate
    // =========================================================================

    function testExecuteWeightUpdateRevertsIfNotManager() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                keccak256("INDEX_MANAGER_ROLE")
            )
        );
        initializedIndex.executeWeightUpdate();
    }

    function testExecuteWeightUpdateRevertsIfThereAreNotProposedWeights()
        public
    {
        vm.prank(address(indexManager));
        vm.expectRevert(Index__NotPendingWeightUpdate.selector);
        initializedIndex.executeWeightUpdate();
    }

    function testExecuteWeightUpdateRevertsIfImplementationTimestampNotReached()
        public
    {
        vm.startPrank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY - 1 hours);

        vm.expectRevert(Index__NotPendingWeightUpdate.selector);
        initializedIndex.executeWeightUpdate();
        vm.stopPrank();
    }

    function testExecuteWeightUpdateUpdatesWeights() public {
        vm.startPrank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1 hours);

        initializedIndex.executeWeightUpdate();
        vm.stopPrank();

        (uint128 actualWeight0, uint128 actualWeight1) = initializedIndex
            .getAssetsWeights();
        (
            uint128 pendingWeight0,
            uint128 pendingWeight1,
            uint256 implementationTimestamp
        ) = initializedIndex.getAssetsPendingWeights();
        assertEq(actualWeight0, weight70);
        assertEq(actualWeight1, weight30);
        assertEq(pendingWeight0, 0);
        assertEq(pendingWeight1, 0);
        assertEq(implementationTimestamp, 0);
    }

    function testExecuteWeightUpdateEmitsEventsWhenRebalanceNotNeeded() public {
        // Update price feeds to change the index effective weights
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        (uint128 effectiveWeight0, uint128 effectiveWeight1) = initializedIndex
            .getAssetsEffectiveWeights();

        vm.startPrank(address(indexManager));
        initializedIndex.proposeUpdateWeights(effectiveWeight0);
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1 hours);

        // Update price feeds again avoiding steal price
        _refreshPriceFeeds();
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);

        vm.recordLogs();
        initializedIndex.executeWeightUpdate();
        vm.stopPrank();

        bytes32 expectedRebalanceFailedEventSig = WeightUpdateRebalanceFailed
            .selector;
        bytes32 expectedWeightUpdateExecutedEventSig = IndexWeightsUpdated
            .selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool rebalanceFailedEventEmitted;
        bool weightUpdateExecutedEventEmitted;

        uint256 rebalanceFaildeIndex;
        uint256 weightUpdateExecutedIndex;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedWeightUpdateExecutedEventSig) {
                weightUpdateExecutedEventEmitted = true;
                weightUpdateExecutedIndex = i;
            }
            if (logs[i].topics[0] == expectedRebalanceFailedEventSig) {
                rebalanceFailedEventEmitted = true;
                rebalanceFaildeIndex = i;
            }
        }

        assertTrue(
            weightUpdateExecutedEventEmitted,
            "Weights update executed event should be emitted"
        );
        assertTrue(
            rebalanceFailedEventEmitted,
            "Rebalance failed event should be emitted"
        );

        // bytes memory reason = logs[rebalanceFaildeIndex].data;
        // bytes4 expectedReason = Index__RebalanceNotNeeded.selector;
        // assertEq(reason, expectedReason, "Rebalance failed reason should be Index__RebalanceNotNeeded");

        uint256 updateTimestampFromEvent = uint256(
            logs[weightUpdateExecutedIndex].topics[1]
        );
        (uint128 newWeight0FromEvent, uint128 newWeight1FromEvent) = abi.decode(
            logs[weightUpdateExecutedIndex].data,
            (uint128, uint128)
        );
        assertEq(
            updateTimestampFromEvent,
            block.timestamp,
            "Weights update executed event timestamp should be current block timestamp"
        );
        assertEq(
            newWeight0FromEvent,
            effectiveWeight0,
            "New weight0 from event should be 70%"
        );
        assertEq(
            newWeight1FromEvent,
            effectiveWeight1,
            "New weight1 from event should be 30%"
        );
    }

    function testExecuteWeightUpdateEmitsEventWhenRebalanceSuccess() public {
        vm.startPrank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1 hours);

        _refreshPriceFeeds();
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);

        (uint128 initialReserve0, uint128 initialReserve1) = initializedIndex
            .getAssetsReserves();

        vm.recordLogs();
        initializedIndex.executeWeightUpdate();
        vm.stopPrank();

        bytes32 expectedRebalanceEventSig = IndexRebalanced.selector;
        bytes32 expectedWeightUpdateExecutedEventSig = IndexWeightsUpdated
            .selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool rebalanceEventEmitted;
        bool weightUpdateExecutedEventEmitted;

        uint256 rebalanceEventIndex;
        uint256 weightUpdateExecutedIndex;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedWeightUpdateExecutedEventSig) {
                weightUpdateExecutedEventEmitted = true;
                weightUpdateExecutedIndex = i;
            }
            if (logs[i].topics[0] == expectedRebalanceEventSig) {
                rebalanceEventEmitted = true;
                rebalanceEventIndex = i;
            }
        }

        (uint128 finalReserve0, uint128 finalReserve1) = initializedIndex
            .getAssetsReserves();

        assertTrue(
            weightUpdateExecutedEventEmitted,
            "Weights update executed event should be emitted"
        );
        assertTrue(rebalanceEventEmitted, "Rebalance event should be emitted");

        uint256 updateTimestampFromEvent = uint256(
            logs[weightUpdateExecutedIndex].topics[1]
        );
        (uint128 newWeight0FromEvent, uint128 newWeight1FromEvent) = abi.decode(
            logs[weightUpdateExecutedIndex].data,
            (uint128, uint128)
        );
        assertEq(
            updateTimestampFromEvent,
            block.timestamp,
            "Weights update executed event timestamp should be current block timestamp"
        );
        assertEq(
            newWeight0FromEvent,
            weight70,
            "New weight0 from event should be 70%"
        );
        assertEq(
            newWeight1FromEvent,
            weight30,
            "New weight1 from event should be 30%"
        );

        // weight0 went from 50% to 70%, so its reserve should increase
        assertGt(
            finalReserve0,
            initialReserve0,
            "Reserve0 should increase after rebalance"
        );
        // weight1 went from 50% to 30%, so its reserve should decrease
        assertLt(
            finalReserve1,
            initialReserve1,
            "Reserve1 should decrease after rebalance"
        );
    }

    //============================================================================
    // RebalanceIndex
    //============================================================================
}
