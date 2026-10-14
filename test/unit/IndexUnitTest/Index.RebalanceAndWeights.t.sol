//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
import "../../../src/errors/IndexErrors.sol";
import "../../../src/events/IndexEvents.sol";
import {UniversalRouterMock} from "../../mocks/UniversalRouterMock.sol";

contract IndexRebalanceAndWeightsTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  helpers
    // =========================================================================

    /// @dev Returns how many logs from `_emitter` match `_sig` and the position of the first one.
    function _findLogs(
        Vm.Log[] memory _logs,
        address _emitter,
        bytes32 _sig
    ) internal pure returns (uint256 count, uint256 firstIndex) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (_logs[i].emitter != _emitter || _logs[i].topics[0] != _sig)
                continue;
            if (count == 0) firstIndex = i;
            count++;
        }
    }

    // =========================================================================
    //  proposeWeightUpdate
    // =========================================================================

    function testProposeWeightUpdateRevertsIfNotManager() public {
        vm.prank(user1);
        vm.expectRevert(Index__CallerNotIndexManager.selector);
        initializedIndex.proposeUpdateWeights(weight70);
    }

    function test_proposeNewWeights_RevertIf_PreviousPendingUpdateNotExecuted()
        public
    {
        vm.prank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight50);

        // A second proposal while the first is still pending must revert.
        vm.prank(address(indexManager));
        vm.expectRevert(Index__PendingWeightUpdate.selector);
        initializedIndex.proposeUpdateWeights(weight30);
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

    function testProposeNewWeightsAcceptsLowerBoundaryWeight() public {
        (uint128 currentWeight0, ) = initializedIndex.getAssetsWeights();
        vm.prank(address(indexManager));
        initializedIndex.proposeUpdateWeights(
            currentWeight0 - REBALANCE_THRESHOLD - 1
        );
    }

    function testProposeNewWeightsAcceptsUpperBoundaryWeight() public {
        (uint128 currentWeight0, ) = initializedIndex.getAssetsWeights();
        vm.prank(address(indexManager));
        initializedIndex.proposeUpdateWeights(
            currentWeight0 + REBALANCE_THRESHOLD + 1
        );
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
        (uint128 oldWeight0, uint128 oldWeight1) = initializedIndex
            .getAssetsWeights();
        uint256 expectedExecutableAt = block.timestamp + WEIGHT_UPDATE_DELAY;

        vm.recordLogs();
        vm.prank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 count, uint256 idx) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateProposed.selector
        );
        assertEq(count, 1, "WeightsUpdateProposed must be emitted once");
        assertEq(logs[idx].topics.length, 1, "no indexed params expected");
        assertEq(
            logs[idx].data,
            abi.encode(
                oldWeight0,
                oldWeight1,
                weight70,
                weight30,
                expectedExecutableAt
            ),
            "WeightsUpdateProposed payload mismatch"
        );
    }

    // =========================================================================
    //  executeWeightUpdate
    // =========================================================================

    function testExecuteWeightUpdateRevertsIfNotManager() public {
        vm.prank(user1);
        vm.expectRevert(Index__CallerNotIndexManager.selector);
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

        bytes32 expectedRebalanceSkippedEventSig = WeightsUpdateRebalanceSkipped
            .selector;
        bytes32 rebalanceFailedEventSig = WeightsUpdateRebalanceFailed
            .selector;
        bytes32 expectedWeightUpdateExecutedEventSig = WeightsUpdated.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool rebalanceSkippedEventEmitted;
        bool rebalanceFailedEventEmitted;
        bool weightUpdateExecutedEventEmitted;

        uint256 weightUpdateExecutedIndex;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(initializedIndex)) continue;
            if (logs[i].topics[0] == expectedWeightUpdateExecutedEventSig) {
                weightUpdateExecutedEventEmitted = true;
                weightUpdateExecutedIndex = i;
            }
            if (logs[i].topics[0] == expectedRebalanceSkippedEventSig) {
                rebalanceSkippedEventEmitted = true;
            }
            if (logs[i].topics[0] == rebalanceFailedEventSig) {
                rebalanceFailedEventEmitted = true;
            }
        }

        assertTrue(
            weightUpdateExecutedEventEmitted,
            "Weights update executed event should be emitted"
        );
        assertTrue(
            rebalanceSkippedEventEmitted,
            "Rebalance skipped event should be emitted"
        );
        assertFalse(
            rebalanceFailedEventEmitted,
            "Rebalance failed event must not be emitted when rebalance is not needed"
        );

        (uint128 newWeight0FromEvent, uint128 newWeight1FromEvent) = abi.decode(
            logs[weightUpdateExecutedIndex].data,
            (uint128, uint128)
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

        mockUniRouter.setExchangeRate(
            initializedToken1, // WBTC (asset venduto)
            initializedToken0, // WETH (asset comprato)
            mockUniRouter.computeRate(1e8, 30e18)
        );

        (uint128 initialReserve0, uint128 initialReserve1) = initializedIndex
            .getAssetsReserves();

        vm.recordLogs();
        initializedIndex.executeWeightUpdate();
        vm.stopPrank();

        bytes32 expectedRebalanceEventSig = IndexRebalanced.selector;
        bytes32 expectedWeightUpdateExecutedEventSig = WeightsUpdated.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool rebalanceEventEmitted;
        bool weightUpdateExecutedEventEmitted;

        uint256 rebalanceEventIndex;
        uint256 weightUpdateExecutedIndex;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(initializedIndex)) continue;
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
        assertLt(
            weightUpdateExecutedIndex,
            rebalanceEventIndex,
            "WeightsUpdated must be emitted before IndexRebalanced"
        );

        (uint128 newWeight0FromEvent, uint128 newWeight1FromEvent) = abi.decode(
            logs[weightUpdateExecutedIndex].data,
            (uint128, uint128)
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

    function testRebalanceIndexRevertsIfNotManager() public {
        vm.prank(user1);
        vm.expectRevert(Index__CallerNotIndexManager.selector);
        initializedIndex.rebalanceIndex();
    }

    function testRebalanceIndexRevertsIfCalledByRouter() public {
        // The router is privileged only for mint/redeem, not for manager functions.
        vm.prank(address(router));
        vm.expectRevert(Index__CallerNotIndexManager.selector);
        initializedIndex.rebalanceIndex();
    }

    function testFuzz_RebalanceIndexRevertsIfCallerIsNotManagerOrSelf(
        address _caller
    ) public {
        vm.assume(_caller != address(indexManager));
        vm.assume(_caller != address(initializedIndex));

        vm.prank(_caller);
        vm.expectRevert(Index__CallerNotIndexManager.selector);
        initializedIndex.rebalanceIndex();
    }

    function testRebalanceIndexSucceedsIfCalledByIndexItself() public {
        // Arrange: WBTC price doubles → WBTC overweight → swap WBTC → WETH.
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        _setWbtcToWethRateRelativeToOracle(10_000);

        (uint128 reserveBefore0, uint128 reserveBefore1) = initializedIndex
            .getAssetsReserves();

        // The index itself is allowed by onlyIndexManager (self-call path used
        // by executeWeightUpdate).
        vm.prank(address(initializedIndex));
        initializedIndex.rebalanceIndex();

        (uint128 reserveAfter0, uint128 reserveAfter1) = initializedIndex
            .getAssetsReserves();
        assertGt(reserveAfter0, reserveBefore0, "reserve0 must increase");
        assertLt(reserveAfter1, reserveBefore1, "reserve1 must decrease");
    }

    function testExecuteWeightUpdateSelfCallToRebalanceIsAuthorized() public {
        vm.startPrank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1 hours);
        _refreshPriceFeeds();
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        _setWbtcToWethRateRelativeToOracle(10_000);

        vm.recordLogs();
        initializedIndex.executeWeightUpdate();
        vm.stopPrank();

        // The inner this.rebalanceIndex() call has msg.sender == index: it must
        // pass the access check and rebalance instead of failing with
        // Index__CallerNotIndexManager.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool rebalancedEmitted;
        bool rebalanceFailedEmitted;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(initializedIndex)) continue;
            if (logs[i].topics[0] == IndexRebalanced.selector) {
                rebalancedEmitted = true;
            }
            if (logs[i].topics[0] == WeightsUpdateRebalanceFailed.selector) {
                rebalanceFailedEmitted = true;
            }
        }
        assertTrue(rebalancedEmitted, "IndexRebalanced must be emitted");
        assertFalse(
            rebalanceFailedEmitted,
            "self-call rebalance must not fail on the access check"
        );
    }

    function testExecuteWeightUpdateSucceedsAtEndOfExecutionWindow() public {
        vm.startPrank(address(indexManager));
        uint256 executableAt = initializedIndex.proposeUpdateWeights(weight70);
        vm.warp(executableAt + WEIGHT_UPDATE_EXECUTION_WINDOW);
        _refreshPriceFeeds();

        initializedIndex.executeWeightUpdate();
        vm.stopPrank();

        (uint128 actualWeight0, ) = initializedIndex.getAssetsWeights();
        assertEq(actualWeight0, weight70);
    }

    function testExecuteWeightUpdateRevertsIfProposalExpired() public {
        vm.startPrank(address(indexManager));
        uint256 executableAt = initializedIndex.proposeUpdateWeights(weight70);
        vm.warp(executableAt + WEIGHT_UPDATE_EXECUTION_WINDOW + 1);

        vm.expectRevert(Index__WeightUpdateExpired.selector);
        initializedIndex.executeWeightUpdate();
        vm.stopPrank();
    }

    function testProposeUpdateWeightsOverwritesExpiredProposal() public {
        vm.startPrank(address(indexManager));
        uint256 executableAt = initializedIndex.proposeUpdateWeights(weight70);
        vm.warp(executableAt + WEIGHT_UPDATE_EXECUTION_WINDOW + 1);

        uint256 newExecutableAt = initializedIndex.proposeUpdateWeights(
            weight30
        );
        vm.stopPrank();

        (
            uint128 pendingWeight0,
            ,
            uint256 implementationTimestamp
        ) = initializedIndex.getAssetsPendingWeights();
        assertEq(pendingWeight0, weight30);
        assertEq(implementationTimestamp, newExecutableAt);
    }

    // =========================================================================
    //  cancelWeightUpdate
    // =========================================================================

    function testCancelWeightUpdateRevertsIfNotManager() public {
        vm.prank(user1);
        vm.expectRevert(Index__CallerNotIndexManager.selector);
        initializedIndex.cancelWeightUpdate();
    }

    function testCancelWeightUpdateRevertsIfNoPendingUpdate() public {
        vm.prank(address(indexManager));
        vm.expectRevert(Index__NotPendingWeightUpdate.selector);
        initializedIndex.cancelWeightUpdate();
    }

    function testCancelWeightUpdateResetsStorageAndEmitsEvent() public {
        vm.startPrank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);

        vm.recordLogs();
        initializedIndex.cancelWeightUpdate();
        vm.stopPrank();

        {
            Vm.Log[] memory logs = vm.getRecordedLogs();
            (uint256 count, uint256 idx) = _findLogs(
                logs,
                address(initializedIndex),
                WeightsUpdateCancelled.selector
            );
            assertEq(count, 1, "WeightsUpdateCancelled must be emitted once");
            assertEq(logs[idx].topics.length, 1, "no indexed params expected");
            (uint128 cancelled0, uint128 cancelled1) = abi.decode(
                logs[idx].data,
                (uint128, uint128)
            );
            assertEq(cancelled0, weight70, "cancelled weight0 mismatch");
            assertEq(cancelled1, weight30, "cancelled weight1 mismatch");
        }

        (
            uint128 pendingWeight0,
            uint128 pendingWeight1,
            uint256 implementationTimestamp
        ) = initializedIndex.getAssetsPendingWeights();
        assertEq(pendingWeight0, 0);
        assertEq(pendingWeight1, 0);
        assertEq(implementationTimestamp, 0);
    }

    function testCancelWeightUpdatePreventsExecution() public {
        vm.startPrank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);
        initializedIndex.cancelWeightUpdate();
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1 hours);

        vm.expectRevert(Index__NotPendingWeightUpdate.selector);
        initializedIndex.executeWeightUpdate();
        vm.stopPrank();
    }

    function testCancelWeightUpdateAllowsNewProposalDuringDelay() public {
        vm.startPrank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);
        initializedIndex.cancelWeightUpdate();

        // Without cancellation this would revert with Index__PendingWeightUpdate.
        initializedIndex.proposeUpdateWeights(weight30);
        vm.stopPrank();

        (uint128 pendingWeight0, , ) = initializedIndex
            .getAssetsPendingWeights();
        assertEq(pendingWeight0, weight30);
    }

    function testRebalanceCheckDoesNotUnderflowWithWeightBelowThreshold()
        public
    {
        // Target weight0 below REBALANCE_THRESHOLD (3%) but above MIN_WEIGHT (1%).
        uint128 lowWeight0 = 2 * WEIGHT_PRECISION;
        assertLt(lowWeight0, REBALANCE_THRESHOLD);

        vm.startPrank(address(indexManager));
        initializedIndex.proposeUpdateWeights(lowWeight0);
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1 hours);
        _refreshPriceFeeds();
        initializedIndex.executeWeightUpdate();

        (uint128 weight0, ) = initializedIndex.getAssetsWeights();
        assertEq(weight0, lowWeight0, "Weight0 must be updated");

        // The rebalance check must run without an arithmetic panic. Any other
        // outcome (success, RebalanceNotNeeded, slippage) is acceptable here.
        try initializedIndex.rebalanceIndex() {} catch (bytes memory reason) {
            assertNotEq(
                keccak256(reason),
                keccak256(abi.encodeWithSignature("Panic(uint256)", 0x11)),
                "Rebalance check underflowed"
            );
        }
        vm.stopPrank();
    }

    function testRebalanceIndexRevertsIfNotNeeded() public {
        vm.prank(address(indexManager));
        // weights didn't change
        vm.expectRevert(Index__RebalanceNotNeeded.selector);
        initializedIndex.rebalanceIndex();
    }

    function testRebalanceIndexRevertsInRouterIfOutputBelowMinOut() public {
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);

        mockUniRouter.setExchangeRate(
            initializedToken1, // WBTC (the overweight asset being sold)
            initializedToken0, // WETH (the target asset to buy)
            1
        );

        vm.prank(address(indexManager));
        vm.expectPartialRevert(
            UniversalRouterMock.UniversalRouterMock__TooLittleReceived.selector
        );
        initializedIndex.rebalanceIndex();
    }

    /// @dev Oracle-fair rate after WBTC doubles: 1 WBTC = 30 WETH. Scaled by `_bps` / 10_000.
    function _setWbtcToWethRateRelativeToOracle(uint256 _bps) internal {
        mockUniRouter.setExchangeRate(
            initializedToken1, // WBTC → sell
            initializedToken0, // WETH → buy
            mockUniRouter.computeRate(1e8, (30e18 * _bps) / 10_000)
        );
    }

    function testRebalanceIndexSucceedsWithSlippageJustBelowLimit() public {
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        _setWbtcToWethRateRelativeToOracle(9_910); // -0.9 %

        (, uint128 reserveBefore1) = initializedIndex.getAssetsReserves();
        vm.prank(address(indexManager));
        initializedIndex.rebalanceIndex();

        (, uint128 reserveAfter1) = initializedIndex.getAssetsReserves();
        assertLt(reserveAfter1, reserveBefore1, "WBTC must be sold");
    }

    function testRebalanceIndexRevertsWithSlippageJustAboveLimit() public {
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        _setWbtcToWethRateRelativeToOracle(9_890); // -1.1 %

        vm.prank(address(indexManager));
        vm.expectPartialRevert(
            UniversalRouterMock.UniversalRouterMock__TooLittleReceived.selector
        );
        initializedIndex.rebalanceIndex();
    }

    function testRebalanceIndexPostSwapCheckRevertsIfRouterIgnoresMinOut()
        public
    {
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        _setWbtcToWethRateRelativeToOracle(9_800); // -2 % of the notional
        mockUniRouter.setEnforceMinAmountOut(false);

        // The loss is ~0.2 % of the TVL (below the old 2 %-of-TVL limit) but 2 % of
        // the notional, so the notional-based check must reject it.
        vm.prank(address(indexManager));
        vm.expectRevert(Index__RebalanceSlippageTooHigh.selector);
        initializedIndex.rebalanceIndex();
    }

    function testExecuteWeightUpdateKeepsReservesIfRebalanceSandwiched()
        public
    {
        vm.startPrank(address(indexManager));
        initializedIndex.proposeUpdateWeights(weight70);
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1 hours);
        _refreshPriceFeeds();
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        _setWbtcToWethRateRelativeToOracle(9_000); // pool price pushed 10 % away

        (uint128 reserveBefore0, uint128 reserveBefore1) = initializedIndex
            .getAssetsReserves();

        vm.recordLogs();
        initializedIndex.executeWeightUpdate();
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool rebalanceFailedEmitted;
        bytes memory reasonData;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(initializedIndex) &&
                logs[i].topics[0] == WeightsUpdateRebalanceFailed.selector
            ) {
                rebalanceFailedEmitted = true;
                reasonData = abi.decode(logs[i].data, (bytes));
            }
        }
        assertTrue(rebalanceFailedEmitted, "Rebalance must fail");
        assertEq(
            bytes4(reasonData),
            UniversalRouterMock.UniversalRouterMock__TooLittleReceived.selector,
            "Rebalance must fail on the router minOut"
        );

        (uint128 weight0, ) = initializedIndex.getAssetsWeights();
        assertEq(weight0, weight70, "Weights must still be updated");

        (uint128 reserveAfter0, uint128 reserveAfter1) = initializedIndex
            .getAssetsReserves();
        assertEq(reserveAfter0, reserveBefore0);
        assertEq(reserveAfter1, reserveBefore1);
    }

    function testRebalanceIndexSucceedsUpdatesStateAndEmitsEvent() public {
        // Arrange: WBTC price doubles → WBTC overweight → swap WBTC → WETH.
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);

        mockUniRouter.setExchangeRate(
            initializedToken1, // WBTC → sell
            initializedToken0, // WETH → buy
            mockUniRouter.computeRate(1e8, 30e18)
        );

        (uint128 reserveBefore0, uint128 reserveBefore1) = initializedIndex
            .getAssetsReserves();

        // Act
        bytes32 expectedSig = IndexRebalanced.selector;
        vm.recordLogs();
        vm.prank(address(indexManager));
        initializedIndex.rebalanceIndex();

        // Assert — state: WBTC (asset1) sold → reserve1 decreased;
        //                  WETH (asset0) received → reserve0 increased.
        (uint128 reserveAfter0, uint128 reserveAfter1) = initializedIndex
            .getAssetsReserves();

        assertGt(
            reserveAfter0,
            reserveBefore0,
            "reserve0 (WETH) must increase after rebalance"
        );
        assertLt(
            reserveAfter1,
            reserveBefore1,
            "reserve1 (WBTC) must decrease after rebalance"
        );

        // Assert — event: IndexRebalanced must be emitted with correct
        //                  prev/new reserves and current timestamp.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(initializedIndex) &&
                logs[i].topics[0] == expectedSig
            ) {
                found = true;
                assertEq(
                    logs[i].topics.length,
                    1,
                    "IndexRebalanced must have no indexed parameters"
                );
                (
                    uint256 logPrevR0,
                    uint256 logPrevR1,
                    uint256 logNewR0,
                    uint256 logNewR1
                ) = abi.decode(
                        logs[i].data,
                        (uint256, uint256, uint256, uint256)
                    );

                assertEq(
                    logPrevR0,
                    reserveBefore0,
                    "logged prevReserve0 mismatch"
                );
                assertEq(
                    logPrevR1,
                    reserveBefore1,
                    "logged prevReserve1 mismatch"
                );
                assertEq(
                    logNewR0,
                    reserveAfter0,
                    "logged newReserve0 mismatch"
                );
                assertEq(
                    logNewR1,
                    reserveAfter1,
                    "logged newReserve1 mismatch"
                );
                break;
            }
        }
        assertTrue(found, "IndexRebalanced event not emitted");
    }

}
