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
import {GasBurningIndexMock} from "../../mocks/GasBurningIndexMock.sol";

import {
    IndexActionTriggered,
    IndexActionFailed
} from "../../../src/events/IndexManagerEvents.sol";

/**
 * @dev Tests for the common-error handling of IndexManager._tryIndexAction.
 *      Single entry points (rebalanceSingleIndex, executeSingleWeightUpdate, collectFeesFromSingleIndex)
 *      revert with exactly the Index revert data when it is a common error (less than 4 bytes, Error(string),
 *      Panic(uint256)) and emit no IndexActionFailed; any other revert data of at least 4 bytes is a custom
 *      error and produces IndexActionFailed without reverting (the real custom errors are covered by
 *      IndexManager.ActionTriggered.t.sol, here only the 4-byte boundary).
 *      Batch entry points emit IndexActionFailed for any failure and continue with the next index.
 *      Index failures are simulated with vm.mockCallRevert; the real out-of-gas uses GasBurningIndexMock
 *      etched over the initialized index.
 */
contract IndexManagerCommonErrorsTest is BaseTest {
    // =========================================================================
    //  Contracts and addresses
    // =========================================================================

    /// Second initialized index (WETH/LINK), used as the failing index in batch tests
    IIndex internal s_secondIndex;

    // =========================================================================
    //  Constants
    // =========================================================================

    /// USDC deposited to accrue fees on the initialized index (6 decimals)
    uint256 constant FEE_GENERATING_DEPOSIT = 1_000e6;

    /// LINK deposited to initialize the second index (18 decimals)
    uint256 constant SECOND_INDEX_LINK_DEPOSIT = 1_000e18;

    /// Message of the simulated require/revert("...") of the Index
    string constant ERROR_MESSAGE = "index failure";

    /// Panic code 0x11: arithmetic overflow or underflow
    uint256 constant PANIC_ARITHMETIC_OVERFLOW = 0x11;

    /// Revert data one byte below the 4-byte selector threshold (common error)
    bytes constant THREE_BYTES_REVERT_DATA = hex"aabbcc";

    /// Shortest non-empty revert data (common error)
    bytes constant ONE_BYTE_REVERT_DATA = hex"01";

    /// 4-byte selector that is neither Error(string) nor Panic(uint256): treated as a custom error
    bytes constant UNKNOWN_SELECTOR_REVERT_DATA = hex"deadbeef";

    /// Loop length of GasBurningIndexMock: large enough that the burned gas dwarfs the manager overhead
    uint256 constant GAS_BURNER_ITERATIONS = 50_000;

    /// Extra gas, on top of twice the burner cost, given to the call that must succeed
    uint256 constant SUFFICIENT_GAS_MARGIN = 200_000;

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

        bytes32 feeCollectorRole = indexManager.FEE_COLLECTOR_ROLE();
        vm.prank(deployer);
        indexManager.grantRole(feeCollectorRole, feeCollector);
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev Account holding the role required by `_action` (REBALANCER, ASSET_MANAGER or FEE_COLLECTOR).
    function _callerFor(IndexAction _action) internal view returns (address) {
        return _action == IndexAction.COLLECT_FEES ? feeCollector : deployer;
    }

    /// @dev Calldata the IndexManager sends to the Index for `_action` (collectFees always to the caller).
    function _indexCallData(
        IndexAction _action
    ) internal view returns (bytes memory) {
        if (_action == IndexAction.REBALANCE) {
            return abi.encodeCall(IIndex.rebalanceIndex, ());
        }
        if (_action == IndexAction.EXECUTE_WEIGHTS) {
            return abi.encodeCall(IIndex.executeWeightUpdate, ());
        }
        return abi.encodeCall(IIndex.collectFees, (feeCollector));
    }

    /// @dev Calldata of the single-index IndexManager entry point for `_action`.
    function _singleCallData(
        IndexAction _action,
        address _index
    ) internal view returns (bytes memory) {
        if (_action == IndexAction.REBALANCE) {
            return
                abi.encodeCall(indexManager.rebalanceSingleIndex, (_index));
        }
        if (_action == IndexAction.EXECUTE_WEIGHTS) {
            return
                abi.encodeCall(
                    indexManager.executeSingleWeightUpdate,
                    (_index)
                );
        }
        return
            abi.encodeCall(indexManager.collectFeesFromSingleIndex, (_index));
    }

    /// @dev Calldata of the batch IndexManager entry point for `_action`.
    function _batchCallData(
        IndexAction _action,
        address[] memory _indexes
    ) internal view returns (bytes memory) {
        if (_action == IndexAction.REBALANCE) {
            return
                abi.encodeCall(
                    indexManager.rebalanceMultipleIndexes,
                    (_indexes)
                );
        }
        if (_action == IndexAction.EXECUTE_WEIGHTS) {
            return
                abi.encodeCall(
                    indexManager.executeWeightUpdateForMultipleIndexes,
                    (_indexes)
                );
        }
        return
            abi.encodeCall(
                indexManager.collectFeesFromMultipleIndexes,
                (_indexes)
            );
    }

    /// @dev Makes the call the IndexManager sends to `_index` for `_action` revert with `_revertData`.
    function _mockIndexRevert(
        address _index,
        IndexAction _action,
        bytes memory _revertData
    ) internal {
        vm.mockCallRevert(_index, _indexCallData(_action), _revertData);
    }

    /// @dev Mocks the initialized index to revert with `_revertData`, calls the single entry point for
    ///      `_action` with a low-level call and returns its outcome and the recorded logs.
    function _callSingleWithIndexRevert(
        IndexAction _action,
        bytes memory _revertData
    )
        internal
        returns (bool success, bytes memory returnData, Vm.Log[] memory logs)
    {
        _mockIndexRevert(address(initializedIndex), _action, _revertData);

        vm.recordLogs();
        vm.prank(_callerFor(_action));
        (success, returnData) = address(indexManager).call(
            _singleCallData(_action, address(initializedIndex))
        );
        logs = vm.getRecordedLogs();
    }

    /// @dev Asserts the single entry point for `_action` reverts with exactly `_revertData` when the Index
    ///      reverts with it, and that the IndexManager emits neither IndexActionFailed nor IndexActionTriggered.
    function _assertSingleBubblesUp(
        IndexAction _action,
        bytes memory _revertData
    ) internal {
        uint256 totalFeesBefore = indexManager.getTotalFeesCollected();

        (
            bool success,
            bytes memory returnData,
            Vm.Log[] memory logs
        ) = _callSingleWithIndexRevert(_action, _revertData);

        assertFalse(success, "a common error must make the call revert");
        assertEq(
            returnData,
            _revertData,
            "the revert data must be exactly the Index revert data"
        );
        _assertNoManagerActionEvents(logs);
        assertEq(
            indexManager.getTotalFeesCollected(),
            totalFeesBefore,
            "total fees collected must not change"
        );
    }

    /// @dev Same as _assertSingleBubblesUp, checked through vm.expectRevert with the full revert data.
    function _expectSingleRevert(
        IndexAction _action,
        bytes memory _revertData
    ) internal {
        _mockIndexRevert(address(initializedIndex), _action, _revertData);
        address index = address(initializedIndex);

        vm.recordLogs();
        vm.prank(_callerFor(_action));
        vm.expectRevert(_revertData);
        if (_action == IndexAction.REBALANCE) {
            indexManager.rebalanceSingleIndex(index);
        } else if (_action == IndexAction.EXECUTE_WEIGHTS) {
            indexManager.executeSingleWeightUpdate(index);
        } else {
            indexManager.collectFeesFromSingleIndex(index);
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertNoManagerActionEvents(logs);
    }

    /// @dev Asserts the IndexManager emitted no IndexActionFailed and no IndexActionTriggered.
    function _assertNoManagerActionEvents(Vm.Log[] memory _logs) internal view {
        assertEq(
            _countManagerEvents(_logs, IndexActionFailed.selector),
            0,
            "a common error must not emit IndexActionFailed"
        );
        assertEq(
            _countManagerEvents(_logs, IndexActionTriggered.selector),
            0,
            "a failed action must not emit IndexActionTriggered"
        );
    }

    /// @dev Asserts the single entry point for `_action` does not revert and emits only
    ///      IndexActionFailed with `_revertData` when the Index reverts with it.
    function _assertSingleEmitsFailed(
        IndexAction _action,
        bytes memory _revertData
    ) internal {
        (
            bool success,
            ,
            Vm.Log[] memory logs
        ) = _callSingleWithIndexRevert(_action, _revertData);

        assertTrue(success, "a custom error must not make the call revert");
        _assertOnlyActionFailed(
            logs,
            address(initializedIndex),
            _callerFor(_action),
            _action,
            _revertData
        );
    }

    function _twoIndexes() internal view returns (address[] memory indexes) {
        indexes = new address[](2);
        indexes[0] = address(s_secondIndex);
        indexes[1] = address(initializedIndex);
    }

    /// @dev Prepares the initialized index so that `_action` succeeds on it for real.
    function _prepareSuccessOnInitializedIndex(IndexAction _action) internal {
        if (_action == IndexAction.REBALANCE) {
            _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
            _refreshExchangeRates();
        } else if (_action == IndexAction.EXECUTE_WEIGHTS) {
            vm.prank(deployer);
            indexManager.proposeNewWeights(address(initializedIndex), weight70);
            vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1);
            _refreshPriceFeeds();
            _refreshExchangeRates();
        } else {
            _mintSharesViaRouter(user1, FEE_GENERATING_DEPOSIT);
        }
    }

    /// @dev Batch with the second index (first in the array) failing with `_revertData` and the initialized
    ///      index succeeding: the call must not revert, IndexActionFailed(_revertData) for the second index,
    ///      IndexActionTriggered for the initialized one, nothing else from the manager.
    function _assertBatchContinuesPastFailure(
        IndexAction _action,
        bytes memory _revertData
    ) internal {
        _prepareSuccessOnInitializedIndex(_action);
        _mockIndexRevert(address(s_secondIndex), _action, _revertData);
        address caller = _callerFor(_action);

        vm.recordLogs();
        vm.prank(caller);
        (bool success, ) = address(indexManager).call(
            _batchCallData(_action, _twoIndexes())
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(success, "a batch must never revert on an index failure");
        uint256 failedPosition = _assertSingleActionFailedFor(
            logs,
            address(s_secondIndex),
            caller,
            _action,
            _revertData
        );
        uint256 triggeredPosition = _assertSingleActionTriggeredFor(
            logs,
            address(initializedIndex),
            caller,
            _action
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
    }

    /// @dev Replaces the initialized index code with GasBurningIndexMock and returns the gas one call
    ///      to it for `_action` consumes.
    function _etchGasBurner(
        IndexAction _action
    ) internal returns (uint256 burnCost) {
        GasBurningIndexMock burner = new GasBurningIndexMock(
            GAS_BURNER_ITERATIONS
        );
        vm.etch(address(initializedIndex), address(burner).code);

        bytes memory callData = _indexCallData(_action);
        uint256 gasBefore = gasleft();
        (bool success, ) = address(initializedIndex).call(callData);
        burnCost = gasBefore - gasleft();
        assertTrue(success, "the gas burner must succeed with enough gas");
    }

    /// @dev The single entry point for `_action`, called with half the gas the Index needs, fails with empty
    ///      revert data (the Index runs out of gas) and emits no IndexActionFailed.
    function _assertSingleOutOfGasReverts(IndexAction _action) internal {
        uint256 burnCost = _etchGasBurner(_action);
        bytes memory callData = _singleCallData(
            _action,
            address(initializedIndex)
        );

        vm.recordLogs();
        vm.prank(_callerFor(_action));
        (bool success, bytes memory returnData) = address(indexManager).call{
            gas: burnCost / 2
        }(callData);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertFalse(success, "an out-of-gas Index call must make the call revert");
        assertEq(
            returnData.length,
            0,
            "an out-of-gas revert carries empty revert data"
        );
        _assertNoManagerActionEvents(logs);
    }

    /// @dev The single entry point for `_action`, called with more than enough gas for the burner, succeeds.
    function _assertSingleWithEnoughGasSucceeds(IndexAction _action) internal {
        uint256 burnCost = _etchGasBurner(_action);
        bytes memory callData = _singleCallData(
            _action,
            address(initializedIndex)
        );

        vm.recordLogs();
        vm.prank(_callerFor(_action));
        (bool success, ) = address(indexManager).call{
            gas: burnCost * 2 + SUFFICIENT_GAS_MARGIN
        }(callData);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(success, "with enough gas the action must succeed");
        _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            _callerFor(_action),
            _action
        );
    }

    // =========================================================================
    //  rebalanceSingleIndex
    // =========================================================================

    function testRebalanceSingleIndexUnknownFourByteSelectorEmitsActionFailed()
        public
    {
        _assertSingleEmitsFailed(
            IndexAction.REBALANCE,
            UNKNOWN_SELECTOR_REVERT_DATA
        );
    }

    function testRebalanceSingleIndexEmptyRevertBubblesUp() public {
        _assertSingleBubblesUp(IndexAction.REBALANCE, "");
    }

    function testRebalanceSingleIndexOneByteRevertBubblesUp() public {
        _assertSingleBubblesUp(IndexAction.REBALANCE, ONE_BYTE_REVERT_DATA);
    }

    function testRebalanceSingleIndexThreeByteRevertBubblesUp() public {
        _assertSingleBubblesUp(IndexAction.REBALANCE, THREE_BYTES_REVERT_DATA);
    }

    function testRebalanceSingleIndexErrorStringBubblesUp() public {
        _expectSingleRevert(
            IndexAction.REBALANCE,
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );
    }

    function testRebalanceSingleIndexBareErrorStringSelectorBubblesUp()
        public
    {
        // Only the Error(string) selector, without the abi-encoded message: still a common error.
        _assertSingleBubblesUp(
            IndexAction.REBALANCE,
            abi.encodePacked(bytes4(keccak256("Error(string)")))
        );
    }

    function testRebalanceSingleIndexPanicBubblesUp() public {
        _expectSingleRevert(
            IndexAction.REBALANCE,
            abi.encodeWithSignature(
                "Panic(uint256)",
                PANIC_ARITHMETIC_OVERFLOW
            )
        );
    }

    function testRebalanceSingleIndexOutOfGasReverts() public {
        _assertSingleOutOfGasReverts(IndexAction.REBALANCE);
    }

    function testRebalanceSingleIndexWithEnoughGasSucceeds() public {
        _assertSingleWithEnoughGasSucceeds(IndexAction.REBALANCE);
    }

    // =========================================================================
    //  executeSingleWeightUpdate
    // =========================================================================

    function testExecuteSingleWeightUpdateUnknownFourByteSelectorEmitsActionFailed()
        public
    {
        _assertSingleEmitsFailed(
            IndexAction.EXECUTE_WEIGHTS,
            UNKNOWN_SELECTOR_REVERT_DATA
        );
    }

    function testExecuteSingleWeightUpdateEmptyRevertBubblesUp() public {
        _assertSingleBubblesUp(IndexAction.EXECUTE_WEIGHTS, "");
    }

    function testExecuteSingleWeightUpdateOneByteRevertBubblesUp() public {
        _assertSingleBubblesUp(
            IndexAction.EXECUTE_WEIGHTS,
            ONE_BYTE_REVERT_DATA
        );
    }

    function testExecuteSingleWeightUpdateThreeByteRevertBubblesUp() public {
        _assertSingleBubblesUp(
            IndexAction.EXECUTE_WEIGHTS,
            THREE_BYTES_REVERT_DATA
        );
    }

    function testExecuteSingleWeightUpdateErrorStringBubblesUp() public {
        _expectSingleRevert(
            IndexAction.EXECUTE_WEIGHTS,
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );
    }

    function testExecuteSingleWeightUpdatePanicBubblesUp() public {
        _expectSingleRevert(
            IndexAction.EXECUTE_WEIGHTS,
            abi.encodeWithSignature(
                "Panic(uint256)",
                PANIC_ARITHMETIC_OVERFLOW
            )
        );
    }

    function testExecuteSingleWeightUpdateOutOfGasReverts() public {
        _assertSingleOutOfGasReverts(IndexAction.EXECUTE_WEIGHTS);
    }

    function testExecuteSingleWeightUpdateWithEnoughGasSucceeds() public {
        _assertSingleWithEnoughGasSucceeds(IndexAction.EXECUTE_WEIGHTS);
    }

    // =========================================================================
    //  collectFeesFromSingleIndex
    // =========================================================================

    function testCollectFeesFromSingleIndexUnknownFourByteSelectorEmitsActionFailed()
        public
    {
        _assertSingleEmitsFailed(
            IndexAction.COLLECT_FEES,
            UNKNOWN_SELECTOR_REVERT_DATA
        );
    }

    function testCollectFeesFromSingleIndexEmptyRevertBubblesUp() public {
        _assertSingleBubblesUp(IndexAction.COLLECT_FEES, "");
    }

    function testCollectFeesFromSingleIndexOneByteRevertBubblesUp() public {
        _assertSingleBubblesUp(IndexAction.COLLECT_FEES, ONE_BYTE_REVERT_DATA);
    }

    function testCollectFeesFromSingleIndexThreeByteRevertBubblesUp() public {
        _assertSingleBubblesUp(
            IndexAction.COLLECT_FEES,
            THREE_BYTES_REVERT_DATA
        );
    }

    function testCollectFeesFromSingleIndexErrorStringBubblesUp() public {
        _expectSingleRevert(
            IndexAction.COLLECT_FEES,
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );
    }

    function testCollectFeesFromSingleIndexPanicBubblesUp() public {
        _expectSingleRevert(
            IndexAction.COLLECT_FEES,
            abi.encodeWithSignature(
                "Panic(uint256)",
                PANIC_ARITHMETIC_OVERFLOW
            )
        );
    }

    function testCollectFeesFromSingleIndexOutOfGasReverts() public {
        _assertSingleOutOfGasReverts(IndexAction.COLLECT_FEES);
    }

    function testCollectFeesFromSingleIndexWithEnoughGasSucceeds() public {
        _assertSingleWithEnoughGasSucceeds(IndexAction.COLLECT_FEES);
    }

    // =========================================================================
    //  rebalanceMultipleIndexes
    // =========================================================================

    function testRebalanceMultipleIndexesContinuesPastEmptyRevert() public {
        _assertBatchContinuesPastFailure(IndexAction.REBALANCE, "");
    }

    function testRebalanceMultipleIndexesContinuesPastErrorString() public {
        _assertBatchContinuesPastFailure(
            IndexAction.REBALANCE,
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );
    }

    function testRebalanceMultipleIndexesContinuesPastPanic() public {
        _assertBatchContinuesPastFailure(
            IndexAction.REBALANCE,
            abi.encodeWithSignature(
                "Panic(uint256)",
                PANIC_ARITHMETIC_OVERFLOW
            )
        );
    }

    // =========================================================================
    //  executeWeightUpdateForMultipleIndexes
    // =========================================================================

    function testExecuteWeightUpdateForMultipleIndexesContinuesPastEmptyRevert()
        public
    {
        _assertBatchContinuesPastFailure(IndexAction.EXECUTE_WEIGHTS, "");
    }

    function testExecuteWeightUpdateForMultipleIndexesContinuesPastErrorString()
        public
    {
        _assertBatchContinuesPastFailure(
            IndexAction.EXECUTE_WEIGHTS,
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );
    }

    function testExecuteWeightUpdateForMultipleIndexesContinuesPastPanic()
        public
    {
        _assertBatchContinuesPastFailure(
            IndexAction.EXECUTE_WEIGHTS,
            abi.encodeWithSignature(
                "Panic(uint256)",
                PANIC_ARITHMETIC_OVERFLOW
            )
        );
    }

    // =========================================================================
    //  collectFeesFromMultipleIndexes
    // =========================================================================

    function testCollectFeesFromMultipleIndexesContinuesPastEmptyRevert()
        public
    {
        _assertBatchContinuesPastFailure(IndexAction.COLLECT_FEES, "");
    }

    function testCollectFeesFromMultipleIndexesContinuesPastErrorString()
        public
    {
        _assertBatchContinuesPastFailure(
            IndexAction.COLLECT_FEES,
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );
    }

    function testCollectFeesFromMultipleIndexesContinuesPastPanic() public {
        _assertBatchContinuesPastFailure(
            IndexAction.COLLECT_FEES,
            abi.encodeWithSignature(
                "Panic(uint256)",
                PANIC_ARITHMETIC_OVERFLOW
            )
        );
    }
}
