// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {AssetAvailable, IndexAction} from "../../../src/types.sol";
import {
    DeployAndInitNewIndex,
    RunParams
} from "../../../script/DeployAndInitNewIndex.s.sol";
import {Index__RebalanceNotNeeded} from "../../../src/errors/IndexErrors.sol";
import {
    PriceFeedManager__PriceIsStale
} from "../../../src/errors/PriceFeedManagerErrors.sol";
import {
    WeightsUpdated,
    WeightsUpdateRebalanceFailed,
    WeightsUpdateRebalanceSkipped,
    IndexRebalanced
} from "../../../src/events/IndexEvents.sol";
import {
    IndexActionTriggered,
    IndexActionFailed
} from "../../../src/events/IndexManagerEvents.sol";

/// @dev Target, pending weights and proposal timestamp of an index, read through its getters.
struct WeightState {
    uint128 weight0;
    uint128 weight1;
    uint128 pendingWeight0;
    uint128 pendingWeight1;
    uint256 executableAt;
}

/**
 * @dev Tests for the error handling of the rebalance that Index.executeWeightUpdate attempts after applying
 *      the new weights (_tryRebalanceIndex -> try this.rebalanceIndex()), driven through the IndexManager.
 *      - Common error in the inner rebalance (revert data < 4 bytes incl. out-of-gas, Error(string), Panic):
 *        the whole executeWeightUpdate reverts with the same revert data; executeSingleWeightUpdate bubbles it
 *        up, executeWeightUpdateForMultipleIndexes emits IndexActionFailed for that index and goes on.
 *      - Custom error in the inner rebalance: weights applied, WeightsUpdated + WeightsUpdateRebalanceFailed.
 *      The inner failure is simulated with vm.mockCallRevert on the index's own rebalanceIndex() selector: the
 *      mock intercepts the external self-call (the IndexManager never calls rebalanceIndex in these flows, so the
 *      mock only hits the self-call). The real out-of-gas runs the real rebalance with a calibrated gas limit.
 *      The 4-byte boundary of the IndexManager classification (executeWeightUpdate mocked as a whole) is covered
 *      by IndexManager.CommonErrors.t.sol and is not repeated here.
 */
contract IndexManagerWeightUpdateInnerRebalanceTest is BaseTest {
    // =========================================================================
    //  Contracts and addresses
    // =========================================================================

    /// Second initialized index (WETH/LINK), the failing index in the batch tests
    IIndex internal s_secondIndex;

    // =========================================================================
    //  Constants
    // =========================================================================

    /// LINK deposited to initialize the second index (18 decimals)
    uint256 constant SECOND_INDEX_LINK_DEPOSIT = 1_000e18;

    /// Message of the simulated require/revert("...") in the inner rebalance
    string constant ERROR_MESSAGE = "inner rebalance failure";

    /// Panic code 0x11: arithmetic overflow or underflow
    uint256 constant PANIC_ARITHMETIC_OVERFLOW = 0x11;

    /// Shortest non-empty revert data (common error)
    bytes constant ONE_BYTE_REVERT_DATA = hex"01";

    /// Revert data one byte below the 4-byte selector threshold (common error)
    bytes constant THREE_BYTES_REVERT_DATA = hex"aabbcc";

    /// 4-byte selector that is neither Error(string) nor Panic(uint256): treated as a custom error
    bytes constant UNKNOWN_SELECTOR_REVERT_DATA = hex"deadbeef";

    /// Extra gas, on top of twice the measured cost, given to the call that must succeed
    uint256 constant SUFFICIENT_GAS_MARGIN = 200_000;

    // =========================================================================
    //  Test values derived from the contracts
    // =========================================================================

    /// Asset0 target weight proposed on both indexes (weight units)
    uint128 internal s_proposedWeight0;

    /// Asset1 target weight implied by s_proposedWeight0 (weight units)
    uint128 internal s_proposedWeight1;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();

        DeployAndInitNewIndex deployScript = new DeployAndInitNewIndex();
        s_secondIndex = deployScript.run(
            helperConfig,
            address(indexManager),
            address(multiSigWallet),
            RunParams({
                assetA: AssetAvailable.WETH,
                assetB: AssetAvailable.LINK,
                weightA: weight60,
                weightB: weight40,
                feePercentage: validFeePercentage,
                initialAssetADeposit: 0,
                initialAssetBDeposit: SECOND_INDEX_LINK_DEPOSIT
            })
        );

        // Executable proposal on both indexes; the target differs from the current weights by more than the
        // rebalance threshold, so the inner rebalance is needed and runs a real swap when not mocked.
        s_proposedWeight0 = weight70;
        s_proposedWeight1 = uint128(MAX_PERCENTAGE) - weight70;
        vm.startPrank(deployer);
        indexManager.proposeNewWeights(
            address(initializedIndex),
            s_proposedWeight0
        );
        indexManager.proposeNewWeights(
            address(s_secondIndex),
            s_proposedWeight0
        );
        vm.stopPrank();
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1);
        _refreshPriceFeeds();
        _refreshExchangeRates();
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev Reads target weights, pending weights and proposal timestamp of `_index`.
    function _weightState(
        IIndex _index
    ) internal view returns (WeightState memory state) {
        (state.weight0, state.weight1) = _index.getAssetsWeights();
        (
            state.pendingWeight0,
            state.pendingWeight1,
            state.executableAt
        ) = _index.getAssetsPendingWeights();
    }

    /// @dev Asserts every field of `_after` equals `_before`.
    function _assertWeightStateUnchanged(
        WeightState memory _before,
        WeightState memory _after
    ) internal pure {
        assertEq(_after.weight0, _before.weight0, "weight0 must not change");
        assertEq(_after.weight1, _before.weight1, "weight1 must not change");
        assertEq(
            _after.pendingWeight0,
            _before.pendingWeight0,
            "pending weight0 must not change"
        );
        assertEq(
            _after.pendingWeight1,
            _before.pendingWeight1,
            "pending weight1 must not change"
        );
        assertEq(
            _after.executableAt,
            _before.executableAt,
            "proposal executableAt must not change"
        );
    }

    /// @dev Asserts the proposed weights are applied and the proposal is cleared.
    function _assertProposedWeightsApplied(IIndex _index) internal view {
        WeightState memory state = _weightState(_index);
        assertEq(state.weight0, s_proposedWeight0, "weight0 must be applied");
        assertEq(state.weight1, s_proposedWeight1, "weight1 must be applied");
        assertEq(state.pendingWeight0, 0, "pending weight0 must be reset");
        assertEq(state.pendingWeight1, 0, "pending weight1 must be reset");
        assertEq(state.executableAt, 0, "proposal timestamp must be reset");
    }

    /// @dev Makes the index's own call to rebalanceIndex() (the self-call of _tryRebalanceIndex) revert with `_revertData`.
    function _mockInnerRebalanceRevert(
        address _index,
        bytes memory _revertData
    ) internal {
        vm.mockCallRevert(
            _index,
            abi.encodeCall(IIndex.rebalanceIndex, ()),
            _revertData
        );
    }

    function _singleCallData() internal view returns (bytes memory) {
        return
            abi.encodeCall(
                indexManager.executeSingleWeightUpdate,
                (address(initializedIndex))
            );
    }

    /// @dev Calls executeSingleWeightUpdate on the initialized index as deployer with `_gas` gas
    ///      (all the available gas when 0) and returns the outcome and the recorded logs.
    function _callSingle(
        uint256 _gas
    )
        internal
        returns (bool success, bytes memory returnData, Vm.Log[] memory logs)
    {
        bytes memory callData = _singleCallData();
        vm.recordLogs();
        vm.prank(deployer);
        if (_gas == 0) {
            (success, returnData) = address(indexManager).call(callData);
        } else {
            (success, returnData) = address(indexManager).call{gas: _gas}(
                callData
            );
        }
        logs = vm.getRecordedLogs();
    }

    /// @dev Mocks the inner rebalance of the initialized index to revert with `_revertData` and
    ///      calls executeSingleWeightUpdate on it.
    function _callSingleWithInnerRevert(
        bytes memory _revertData
    )
        internal
        returns (bool success, bytes memory returnData, Vm.Log[] memory logs)
    {
        _mockInnerRebalanceRevert(address(initializedIndex), _revertData);
        return _callSingle(0);
    }

    /// @dev A common error in the inner rebalance makes executeSingleWeightUpdate revert with exactly
    ///      `_revertData`, leaving weights, proposal and reserves untouched.
    function _assertSingleRevertsKeepingState(
        bytes memory _revertData
    ) internal {
        WeightState memory before = _weightState(initializedIndex);
        (uint128 reserve0Before, uint128 reserve1Before) = initializedIndex
            .getAssetsReserves();

        (bool success, bytes memory returnData, ) = _callSingleWithInnerRevert(
            _revertData
        );

        assertFalse(success, "a common error must revert the weight update");
        assertEq(
            returnData,
            _revertData,
            "the revert data must be exactly the inner rebalance revert data"
        );
        _assertWeightStateUnchanged(before, _weightState(initializedIndex));
        (uint128 reserve0After, uint128 reserve1After) = initializedIndex
            .getAssetsReserves();
        assertEq(reserve0After, reserve0Before, "reserve0 must not change");
        assertEq(reserve1After, reserve1Before, "reserve1 must not change");
    }

    /// @dev Number of logs in `_logs` emitted by `_emitter`.
    function _countLogsFrom(
        Vm.Log[] memory _logs,
        address _emitter
    ) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (_logs[i].emitter == _emitter) count++;
        }
    }

    /// @dev Number of logs emitted by `_emitter` with signature `_sig`, and the position of the last one.
    function _findLogs(
        Vm.Log[] memory _logs,
        address _emitter,
        bytes32 _sig
    ) internal pure returns (uint256 count, uint256 position) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (_logs[i].emitter == _emitter && _logs[i].topics[0] == _sig) {
                count++;
                position = i;
            }
        }
    }

    /// @dev Asserts `_index` emitted none of the events that follow the classification of the inner rebalance
    ///      outcome (WeightsUpdateRebalanceFailed, WeightsUpdateRebalanceSkipped, IndexRebalanced).
    ///      WeightsUpdated is not checked here: vm.recordLogs also returns the logs of frames that reverted, so the
    ///      WeightsUpdated emitted before the re-thrown common error shows up in `_logs` although it is discarded
    ///      on-chain together with the reverted executeWeightUpdate frame. Its absence on-chain follows from the
    ///      revert itself, asserted by the behavior tests (call failed or proposal still pending).
    function _assertNoRebalanceOutcomeEvents(
        Vm.Log[] memory _logs,
        address _index
    ) internal pure {
        (uint256 failedCount, ) = _findLogs(
            _logs,
            _index,
            WeightsUpdateRebalanceFailed.selector
        );
        (uint256 skippedCount, ) = _findLogs(
            _logs,
            _index,
            WeightsUpdateRebalanceSkipped.selector
        );
        (uint256 rebalancedCount, ) = _findLogs(
            _logs,
            _index,
            IndexRebalanced.selector
        );
        assertEq(
            failedCount,
            0,
            "a common error must not emit WeightsUpdateRebalanceFailed"
        );
        assertEq(
            skippedCount,
            0,
            "a common error must not emit WeightsUpdateRebalanceSkipped"
        );
        assertEq(rebalancedCount, 0, "IndexRebalanced must not be emitted");
    }

    /// @dev A common error in the inner rebalance: no rebalance-outcome event from the Index and no event
    ///      from the IndexManager.
    function _assertSingleEmitsNothing(bytes memory _revertData) internal {
        (, , Vm.Log[] memory logs) = _callSingleWithInnerRevert(_revertData);

        _assertNoRebalanceOutcomeEvents(logs, address(initializedIndex));
        assertEq(
            _countLogsFrom(logs, address(indexManager)),
            0,
            "the IndexManager must emit no event"
        );
    }

    /// @dev Asserts the Index logs of an applied update whose inner rebalance failed with `_reason`:
    ///      WeightsUpdated(proposed weights) then WeightsUpdateRebalanceFailed(_reason), nothing skipped,
    ///      and IndexActionTriggered as the only IndexManager log after them.
    function _assertRebalanceFailedEvents(
        Vm.Log[] memory _logs,
        bytes memory _reason
    ) internal view {
        address index = address(initializedIndex);
        (uint256 updatedCount, uint256 updatedPosition) = _findLogs(
            _logs,
            index,
            WeightsUpdated.selector
        );
        (uint256 failedCount, uint256 failedPosition) = _findLogs(
            _logs,
            index,
            WeightsUpdateRebalanceFailed.selector
        );
        (uint256 skippedCount, ) = _findLogs(
            _logs,
            index,
            WeightsUpdateRebalanceSkipped.selector
        );
        (uint256 rebalancedCount, ) = _findLogs(
            _logs,
            index,
            IndexRebalanced.selector
        );

        assertEq(updatedCount, 1, "WeightsUpdated must be emitted once");
        assertEq(
            failedCount,
            1,
            "WeightsUpdateRebalanceFailed must be emitted once"
        );
        assertEq(skippedCount, 0, "the rebalance must not be reported skipped");
        assertEq(rebalancedCount, 0, "IndexRebalanced must not be emitted");
        assertLt(
            updatedPosition,
            failedPosition,
            "WeightsUpdated must precede WeightsUpdateRebalanceFailed"
        );

        (uint128 loggedWeight0, uint128 loggedWeight1) = abi.decode(
            _logs[updatedPosition].data,
            (uint128, uint128)
        );
        assertEq(
            loggedWeight0,
            s_proposedWeight0,
            "WeightsUpdated must log weight0"
        );
        assertEq(
            loggedWeight1,
            s_proposedWeight1,
            "WeightsUpdated must log weight1"
        );
        assertEq(
            _logs[failedPosition].topics.length,
            1,
            "WeightsUpdateRebalanceFailed has no indexed params"
        );
        assertEq(
            abi.decode(_logs[failedPosition].data, (bytes)),
            _reason,
            "reasonData must be the raw inner rebalance revert data"
        );

        uint256 actionPosition = _assertOnlyActionTriggered(
            _logs,
            index,
            deployer,
            IndexAction.EXECUTE_WEIGHTS
        );
        assertLt(
            failedPosition,
            actionPosition,
            "IndexActionTriggered must follow the Index events"
        );
    }

    /// @dev Warps past the longest price feed max delay (still inside the execution window), so the
    ///      inner rebalance reverts with PriceFeedManager__PriceIsStale.
    function _makePricesStale() internal {
        uint256 maxDelay = assetPriceFeedMaxDelay > usdcPriceFeedMaxDelay
            ? assetPriceFeedMaxDelay
            : usdcPriceFeedMaxDelay;
        vm.warp(block.timestamp + maxDelay + 1);
    }

    /// @dev Gas consumed by one executeSingleWeightUpdate on the current state; the state is rolled back.
    function _measureSingleGas() internal returns (uint256 gasUsed) {
        bytes memory callData = _singleCallData();
        uint256 snapshot = vm.snapshotState();
        vm.prank(deployer);
        uint256 gasBefore = gasleft();
        (bool success, ) = address(indexManager).call(callData);
        gasUsed = gasBefore - gasleft();
        assertTrue(success, "the measured call must succeed");
        vm.revertToState(snapshot);
    }

    /// @dev Gas limits for the out-of-gas tests. `fullCost`: cost with the real rebalance.
    ///      `tightLimit`: halfway between the cost without the rebalance work (inner call mocked to revert with
    ///      Index__RebalanceNotNeeded) and `fullCost`, so everything but the rebalance fits.
    function _calibrateGas()
        internal
        returns (uint256 fullCost, uint256 tightLimit)
    {
        fullCost = _measureSingleGas();

        _mockInnerRebalanceRevert(
            address(initializedIndex),
            abi.encodeWithSelector(Index__RebalanceNotNeeded.selector)
        );
        uint256 costWithoutRebalance = _measureSingleGas();
        vm.clearMockedCalls();

        assertLt(
            costWithoutRebalance,
            fullCost,
            "the rebalance must account for part of the cost"
        );
        tightLimit = costWithoutRebalance + (fullCost - costWithoutRebalance) / 2;
    }

    function _twoIndexes() internal view returns (address[] memory indexes) {
        indexes = new address[](2);
        indexes[0] = address(s_secondIndex);
        indexes[1] = address(initializedIndex);
    }

    /// @dev Mocks the inner rebalance of the second index (first in the batch) to revert with `_revertData`
    ///      and runs executeWeightUpdateForMultipleIndexes on both indexes.
    function _callBatchWithInnerRevertOnSecond(
        bytes memory _revertData
    ) internal returns (bool success, Vm.Log[] memory logs) {
        _mockInnerRebalanceRevert(address(s_secondIndex), _revertData);
        bytes memory callData = abi.encodeCall(
            indexManager.executeWeightUpdateForMultipleIndexes,
            (_twoIndexes())
        );
        vm.recordLogs();
        vm.prank(deployer);
        (success, ) = address(indexManager).call(callData);
        logs = vm.getRecordedLogs();
    }

    /// @dev The batch does not revert: the failing index keeps its proposal and weights, the other index
    ///      gets the proposed weights.
    function _assertBatchKeepsFailingProposal(
        bytes memory _revertData
    ) internal {
        WeightState memory secondBefore = _weightState(s_secondIndex);
        assertEq(
            secondBefore.pendingWeight0,
            s_proposedWeight0,
            "the second index must have a pending proposal"
        );

        (bool success, ) = _callBatchWithInnerRevertOnSecond(_revertData);

        assertTrue(success, "a batch must never revert on an index failure");
        _assertWeightStateUnchanged(secondBefore, _weightState(s_secondIndex));
        _assertProposedWeightsApplied(initializedIndex);
    }

    /// @dev Batch events: IndexActionFailed(_revertData) for the failing index, then IndexActionTriggered for
    ///      the other one; no Index event from the failing index, WeightsUpdated from the other.
    function _assertBatchEmitsFailedThenTriggered(
        bytes memory _revertData
    ) internal {
        (, Vm.Log[] memory logs) = _callBatchWithInnerRevertOnSecond(
            _revertData
        );

        uint256 failedPosition = _assertSingleActionFailedFor(
            logs,
            address(s_secondIndex),
            deployer,
            IndexAction.EXECUTE_WEIGHTS,
            _revertData
        );
        uint256 triggeredPosition = _assertSingleActionTriggeredFor(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.EXECUTE_WEIGHTS
        );
        assertLt(
            failedPosition,
            triggeredPosition,
            "the loop must continue after the failing index"
        );
        assertEq(
            _countManagerEvents(logs, IndexActionFailed.selector),
            1,
            "exactly one IndexActionFailed in the batch"
        );
        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            1,
            "exactly one IndexActionTriggered in the batch"
        );
        _assertNoRebalanceOutcomeEvents(logs, address(s_secondIndex));
        (uint256 updatedCount, ) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdated.selector
        );
        assertEq(
            updatedCount,
            1,
            "the succeeding index must emit WeightsUpdated"
        );
    }

    // =========================================================================
    //  executeSingleWeightUpdate — common error in the inner rebalance
    // =========================================================================

    function testExecuteSingleWeightUpdateInnerRebalanceEmptyRevertRevertsKeepingState()
        public
    {
        _assertSingleRevertsKeepingState("");
    }

    function testExecuteSingleWeightUpdateInnerRebalanceOneByteRevertRevertsKeepingState()
        public
    {
        _assertSingleRevertsKeepingState(ONE_BYTE_REVERT_DATA);
    }

    function testExecuteSingleWeightUpdateInnerRebalanceThreeByteRevertRevertsKeepingState()
        public
    {
        _assertSingleRevertsKeepingState(THREE_BYTES_REVERT_DATA);
    }

    function testExecuteSingleWeightUpdateInnerRebalanceErrorStringRevertsKeepingState()
        public
    {
        _assertSingleRevertsKeepingState(
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );
    }

    function testExecuteSingleWeightUpdateInnerRebalancePanicRevertsKeepingState()
        public
    {
        _assertSingleRevertsKeepingState(
            abi.encodeWithSignature(
                "Panic(uint256)",
                PANIC_ARITHMETIC_OVERFLOW
            )
        );
    }

    function testExecuteSingleWeightUpdateInnerRebalanceEmptyRevertEmitsNothing()
        public
    {
        _assertSingleEmitsNothing("");
    }

    function testExecuteSingleWeightUpdateInnerRebalanceOneByteRevertEmitsNothing()
        public
    {
        _assertSingleEmitsNothing(ONE_BYTE_REVERT_DATA);
    }

    function testExecuteSingleWeightUpdateInnerRebalanceThreeByteRevertEmitsNothing()
        public
    {
        _assertSingleEmitsNothing(THREE_BYTES_REVERT_DATA);
    }

    function testExecuteSingleWeightUpdateInnerRebalanceErrorStringEmitsNothing()
        public
    {
        _assertSingleEmitsNothing(
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );
    }

    function testExecuteSingleWeightUpdateInnerRebalancePanicEmitsNothing()
        public
    {
        _assertSingleEmitsNothing(
            abi.encodeWithSignature(
                "Panic(uint256)",
                PANIC_ARITHMETIC_OVERFLOW
            )
        );
    }

    // =========================================================================
    //  executeSingleWeightUpdate — custom error in the inner rebalance
    // =========================================================================

    function testExecuteSingleWeightUpdateInnerRebalanceUnknownSelectorAppliesWeights()
        public
    {
        // Also proves the mock intercepts the self-call: without it the real rebalance would succeed.
        (bool success, , ) = _callSingleWithInnerRevert(
            UNKNOWN_SELECTOR_REVERT_DATA
        );

        assertTrue(success, "a custom error must not revert the weight update");
        _assertProposedWeightsApplied(initializedIndex);
    }

    function testExecuteSingleWeightUpdateInnerRebalanceUnknownSelectorEmitsRebalanceFailed()
        public
    {
        (, , Vm.Log[] memory logs) = _callSingleWithInnerRevert(
            UNKNOWN_SELECTOR_REVERT_DATA
        );

        _assertRebalanceFailedEvents(logs, UNKNOWN_SELECTOR_REVERT_DATA);
    }

    function testExecuteSingleWeightUpdateStalePriceAppliesWeightsWithoutRebalance()
        public
    {
        _makePricesStale();
        (uint128 reserve0Before, uint128 reserve1Before) = initializedIndex
            .getAssetsReserves();

        (bool success, , ) = _callSingle(0);

        assertTrue(success, "a stale price must not revert the weight update");
        _assertProposedWeightsApplied(initializedIndex);
        (uint128 reserve0After, uint128 reserve1After) = initializedIndex
            .getAssetsReserves();
        assertEq(reserve0After, reserve0Before, "reserve0 must not change");
        assertEq(reserve1After, reserve1Before, "reserve1 must not change");
    }

    function testExecuteSingleWeightUpdateStalePriceEmitsRebalanceFailedWithStaleError()
        public
    {
        _makePricesStale();

        (, , Vm.Log[] memory logs) = _callSingle(0);

        _assertRebalanceFailedEvents(
            logs,
            abi.encodeWithSelector(PriceFeedManager__PriceIsStale.selector)
        );
    }

    // =========================================================================
    //  executeSingleWeightUpdate — real out-of-gas in the inner rebalance
    // =========================================================================

    function testExecuteSingleWeightUpdateTightGasPassesWhenRebalanceIsSkipped()
        public
    {
        // Calibration check: the tight limit is enough for everything except the rebalance work.
        (, uint256 tightLimit) = _calibrateGas();
        _mockInnerRebalanceRevert(
            address(initializedIndex),
            abi.encodeWithSelector(Index__RebalanceNotNeeded.selector)
        );

        (bool success, , ) = _callSingle(tightLimit);

        assertTrue(
            success,
            "the tight limit must cover the update without the rebalance"
        );
        _assertProposedWeightsApplied(initializedIndex);
    }

    function testExecuteSingleWeightUpdateInnerRebalanceOutOfGasRevertsKeepingState()
        public
    {
        (, uint256 tightLimit) = _calibrateGas();
        WeightState memory before = _weightState(initializedIndex);
        (uint128 reserve0Before, uint128 reserve1Before) = initializedIndex
            .getAssetsReserves();

        (bool success, bytes memory returnData, ) = _callSingle(tightLimit);

        assertFalse(success, "an out-of-gas rebalance must revert the update");
        assertEq(
            returnData.length,
            0,
            "an out-of-gas revert carries empty revert data"
        );
        _assertWeightStateUnchanged(before, _weightState(initializedIndex));
        (uint128 reserve0After, uint128 reserve1After) = initializedIndex
            .getAssetsReserves();
        assertEq(reserve0After, reserve0Before, "reserve0 must not change");
        assertEq(reserve1After, reserve1Before, "reserve1 must not change");
    }

    function testExecuteSingleWeightUpdateInnerRebalanceOutOfGasEmitsNothing()
        public
    {
        (, uint256 tightLimit) = _calibrateGas();

        (, , Vm.Log[] memory logs) = _callSingle(tightLimit);

        _assertNoRebalanceOutcomeEvents(logs, address(initializedIndex));
        assertEq(
            _countLogsFrom(logs, address(indexManager)),
            0,
            "the IndexManager must emit no event"
        );
    }

    function testExecuteSingleWeightUpdateWithEnoughGasAppliesWeightsAndRebalances()
        public
    {
        (uint256 fullCost, ) = _calibrateGas();
        (uint128 reserve0Before, uint128 reserve1Before) = initializedIndex
            .getAssetsReserves();

        (bool success, , ) = _callSingle(fullCost * 2 + SUFFICIENT_GAS_MARGIN);

        assertTrue(success, "with enough gas the update must succeed");
        _assertProposedWeightsApplied(initializedIndex);
        (uint128 reserve0After, uint128 reserve1After) = initializedIndex
            .getAssetsReserves();
        assertTrue(
            reserve0After != reserve0Before && reserve1After != reserve1Before,
            "the rebalance must move both reserves"
        );
    }

    function testExecuteSingleWeightUpdateWithEnoughGasEmitsIndexRebalanced()
        public
    {
        (uint256 fullCost, ) = _calibrateGas();

        (, , Vm.Log[] memory logs) = _callSingle(
            fullCost * 2 + SUFFICIENT_GAS_MARGIN
        );

        (uint256 updatedCount, uint256 updatedPosition) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdated.selector
        );
        (uint256 rebalancedCount, uint256 rebalancedPosition) = _findLogs(
            logs,
            address(initializedIndex),
            IndexRebalanced.selector
        );
        (uint256 failedCount, ) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateRebalanceFailed.selector
        );
        assertEq(updatedCount, 1, "WeightsUpdated must be emitted once");
        assertEq(rebalancedCount, 1, "IndexRebalanced must be emitted once");
        assertEq(failedCount, 0, "the rebalance must not fail");
        assertLt(
            updatedPosition,
            rebalancedPosition,
            "WeightsUpdated must precede IndexRebalanced"
        );
        _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.EXECUTE_WEIGHTS
        );
    }

    // =========================================================================
    //  executeWeightUpdateForMultipleIndexes — common error in the inner rebalance
    // =========================================================================

    function testExecuteWeightUpdateForMultipleIndexesInnerEmptyRevertKeepsProposal()
        public
    {
        _assertBatchKeepsFailingProposal("");
    }

    function testExecuteWeightUpdateForMultipleIndexesInnerErrorStringKeepsProposal()
        public
    {
        _assertBatchKeepsFailingProposal(
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );
    }

    function testExecuteWeightUpdateForMultipleIndexesInnerPanicKeepsProposal()
        public
    {
        _assertBatchKeepsFailingProposal(
            abi.encodeWithSignature(
                "Panic(uint256)",
                PANIC_ARITHMETIC_OVERFLOW
            )
        );
    }

    function testExecuteWeightUpdateForMultipleIndexesInnerEmptyRevertEmitsActionFailed()
        public
    {
        _assertBatchEmitsFailedThenTriggered("");
    }

    function testExecuteWeightUpdateForMultipleIndexesInnerErrorStringEmitsActionFailed()
        public
    {
        _assertBatchEmitsFailedThenTriggered(
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );
    }

    function testExecuteWeightUpdateForMultipleIndexesInnerPanicEmitsActionFailed()
        public
    {
        _assertBatchEmitsFailedThenTriggered(
            abi.encodeWithSignature(
                "Panic(uint256)",
                PANIC_ARITHMETIC_OVERFLOW
            )
        );
    }
}
