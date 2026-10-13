// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {SwapRoute, AssetAvailable, IndexAction} from "../../../src/types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    DeployAndInitNewIndex,
    RunParams
} from "../../../script/DeployAndInitNewIndex.s.sol";

import "../../../src/errors/IndexManagerErrors.sol";
import "../../../src/errors/IndexErrors.sol";
import "../../../src/events/IndexManagerEvents.sol";
import "../../../src/events/IndexEvents.sol";

/**
 * @dev Event-only tests for IndexManager.IndexActionTriggered: one log per successful
 *      action, emitted by the manager after the Index's own state event in the same
 *      transaction; never emitted when the call to the Index fails or reverts.
 */
contract IndexManagerActionTriggeredTest is BaseTest {
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

    /// @dev Returns how many logs from `_emitter` match `_sig` and the position of the first one.
    function _findIndexEvent(
        Vm.Log[] memory _logs,
        address _emitter,
        bytes32 _sig
    ) internal pure returns (uint256 count, uint256 position) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (_logs[i].emitter != _emitter || _logs[i].topics[0] != _sig)
                continue;
            if (count == 0) position = i;
            count++;
        }
    }

    /// @dev Asserts the Index emitted `_indexSig` once, before the manager IndexActionTriggered at `_actionPosition`.
    function _assertIndexEventBeforeAction(
        Vm.Log[] memory _logs,
        address _index,
        bytes32 _indexSig,
        uint256 _actionPosition
    ) internal pure {
        (uint256 count, uint256 position) = _findIndexEvent(
            _logs,
            _index,
            _indexSig
        );
        assertEq(count, 1, "the Index state event must be emitted once");
        assertLt(
            position,
            _actionPosition,
            "IndexActionTriggered must follow the Index state event"
        );
    }

    /// @dev Makes the initialized index (WETH/WBTC) need a rebalance while the second
    ///      index (WETH/LINK) stays balanced, by doubling the WBTC price.
    function _unbalanceInitializedIndexOnly() internal {
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        _refreshExchangeRates();
    }

    /// @dev Proposes `_weight0` on `_index` as deployer and warps to the executable window.
    function _proposeAndWarpToExecutable(
        address _index,
        uint128 _weight0
    ) internal {
        vm.prank(deployer);
        indexManager.proposeNewWeights(_index, _weight0);
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1);
        _refreshPriceFeeds();
    }

    function _twoIndexes() internal view returns (address[] memory indexes) {
        indexes = new address[](2);
        indexes[0] = address(initializedIndex);
        indexes[1] = address(s_secondIndex);
    }

    /// @dev Batch outcome: one IndexActionTriggered for the initialized index, one
    ///      IndexActionFailed(_failedReason) and no IndexActionTriggered for the second index.
    function _assertBatchOneSuccessOneFailure(
        Vm.Log[] memory _logs,
        address _caller,
        IndexAction _action,
        bytes memory _failedReason,
        bytes32 _indexSuccessSig
    ) internal view {
        uint256 actionPosition = _assertSingleActionTriggeredFor(
            _logs,
            address(initializedIndex),
            _caller,
            _action
        );
        _assertIndexEventBeforeAction(
            _logs,
            address(initializedIndex),
            _indexSuccessSig,
            actionPosition
        );
        assertEq(
            _countManagerEvents(
                _logs,
                IndexActionFailed.selector,
                address(initializedIndex)
            ),
            0,
            "the succeeding index must not get IndexActionFailed"
        );

        assertEq(
            _countManagerEvents(
                _logs,
                IndexActionTriggered.selector,
                address(s_secondIndex)
            ),
            0,
            "the failing index must not get IndexActionTriggered"
        );
        _assertSingleActionFailedFor(
            _logs,
            address(s_secondIndex),
            _caller,
            _action,
            _failedReason
        );

        assertEq(
            _countManagerEvents(_logs, IndexActionTriggered.selector),
            1,
            "exactly one IndexActionTriggered in the batch"
        );
        assertEq(
            _countManagerEvents(_logs, IndexActionFailed.selector),
            1,
            "exactly one IndexActionFailed in the batch"
        );
    }

    // =========================================================================
    //  initializeIndex — INITIALIZE
    // =========================================================================

    function testInitializeIndexEmitsActionTriggeredAfterIndexInitialized()
        public
    {
        (uint8 decimals0, , ) = nonInitializedIndex.getAssetsAndUsdcDecimals();
        uint256 initAmount = 10 ** decimals0;
        vm.startPrank(deployer);
        IERC20(nonInitializedToken0).approve(
            address(nonInitializedIndex),
            type(uint256).max
        );
        IERC20(nonInitializedToken1).approve(
            address(nonInitializedIndex),
            type(uint256).max
        );
        vm.stopPrank();
        (
            SwapRoute memory r0,
            SwapRoute memory r1,
            SwapRoute memory r01
        ) = helperConfig.getDefaultSwapRoutes(
                nonInitializedToken0,
                nonInitializedToken1
            );

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.initializeIndex(
            deployer,
            address(nonInitializedIndex),
            initAmount,
            r0,
            r1,
            r01
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 actionPosition = _assertOnlyActionTriggered(
            logs,
            address(nonInitializedIndex),
            deployer,
            IndexAction.INITIALIZE
        );
        _assertIndexEventBeforeAction(
            logs,
            address(nonInitializedIndex),
            IndexInitialized.selector,
            actionPosition
        );
    }

    function testInitializeIndexRevertEmitsNoActionTriggered() public {
        (
            SwapRoute memory r0,
            SwapRoute memory r1,
            SwapRoute memory r01
        ) = helperConfig.getDefaultSwapRoutes(
                initializedToken0,
                initializedToken1
            );

        vm.recordLogs();
        vm.prank(deployer);
        vm.expectRevert(IndexManager__IndexAlreadyInitialized.selector);
        indexManager.initializeIndex(
            deployer,
            address(initializedIndex),
            1,
            r0,
            r1,
            r01
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            0,
            "a reverted initializeIndex must not emit IndexActionTriggered"
        );
    }

    // =========================================================================
    //  rebalance — REBALANCE
    // =========================================================================

    function testRebalanceSingleIndexEmitsActionTriggeredAfterIndexRebalanced()
        public
    {
        _unbalanceInitializedIndexOnly();

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.rebalanceSingleIndex(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 actionPosition = _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.REBALANCE
        );
        _assertIndexEventBeforeAction(
            logs,
            address(initializedIndex),
            IndexRebalanced.selector,
            actionPosition
        );
    }

    function testRebalanceSingleIndexFailureEmitsNoActionTriggered() public {
        vm.recordLogs();
        vm.prank(deployer);
        indexManager.rebalanceSingleIndex(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            0,
            "a failed rebalance must not emit IndexActionTriggered"
        );
        _assertSingleActionFailedFor(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.REBALANCE,
            abi.encodeWithSelector(Index__RebalanceNotNeeded.selector)
        );
    }

    function testRebalanceMultipleIndexesEmitsActionTriggeredOnlyForSucceedingIndex()
        public
    {
        _unbalanceInitializedIndexOnly();

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.rebalanceMultipleIndexes(_twoIndexes());
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertBatchOneSuccessOneFailure(
            logs,
            deployer,
            IndexAction.REBALANCE,
            abi.encodeWithSelector(Index__RebalanceNotNeeded.selector),
            IndexRebalanced.selector
        );
    }

    // =========================================================================
    //  proposeNewWeights — PROPOSE_WEIGHTS
    // =========================================================================

    function testProposeNewWeightsViaMultiSigEmitsActionTriggeredWithMultiSigAsCaller()
        public
    {
        vm.recordLogs();
        vm.prank(address(multiSigWallet));
        indexManager.proposeNewWeights(address(initializedIndex), weight30);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 actionPosition = _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            address(multiSigWallet),
            IndexAction.PROPOSE_WEIGHTS
        );
        _assertIndexEventBeforeAction(
            logs,
            address(initializedIndex),
            WeightsUpdateProposed.selector,
            actionPosition
        );
    }

    function testProposeNewWeightsRevertEmitsNoActionTriggered() public {
        (uint128 currentWeight0, ) = initializedIndex.getAssetsWeights();

        vm.recordLogs();
        vm.prank(deployer);
        vm.expectRevert(Index__InvalidWeight.selector);
        indexManager.proposeNewWeights(
            address(initializedIndex),
            currentWeight0
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            0,
            "a reverted proposeNewWeights must not emit IndexActionTriggered"
        );
    }

    // =========================================================================
    //  executeWeightUpdate — EXECUTE_WEIGHTS
    // =========================================================================

    function testExecuteSingleWeightUpdateEmitsActionTriggeredAfterWeightsUpdated()
        public
    {
        _proposeAndWarpToExecutable(address(initializedIndex), weight70);
        _refreshExchangeRates();

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.executeSingleWeightUpdate(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 actionPosition = _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.EXECUTE_WEIGHTS
        );
        _assertIndexEventBeforeAction(
            logs,
            address(initializedIndex),
            WeightsUpdated.selector,
            actionPosition
        );
    }

    function testExecuteSingleWeightUpdateEmitsActionTriggeredWhenInnerRebalanceSkipped()
        public
    {
        // Propose the current effective weight as target so the post-update rebalance is not needed.
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        (uint128 effectiveWeight0, ) = initializedIndex
            .getAssetsEffectiveWeights();
        _proposeAndWarpToExecutable(address(initializedIndex), effectiveWeight0);
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.executeSingleWeightUpdate(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 actionPosition = _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.EXECUTE_WEIGHTS
        );
        _assertIndexEventBeforeAction(
            logs,
            address(initializedIndex),
            WeightsUpdateRebalanceSkipped.selector,
            actionPosition
        );
    }

    function testExecuteSingleWeightUpdateEmitsActionTriggeredWhenInnerRebalanceFails()
        public
    {
        _proposeAndWarpToExecutable(address(initializedIndex), weight30);
        // Drain the router so the post-update rebalance swap reverts.
        deal(address(mockWeth), address(mockUniRouter), 0);
        deal(address(mockWbtc), address(mockUniRouter), 0);

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.executeSingleWeightUpdate(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 actionPosition = _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.EXECUTE_WEIGHTS
        );
        _assertIndexEventBeforeAction(
            logs,
            address(initializedIndex),
            WeightsUpdateRebalanceFailed.selector,
            actionPosition
        );
    }

    function testExecuteSingleWeightUpdateFailureEmitsNoActionTriggered()
        public
    {
        vm.recordLogs();
        vm.prank(deployer);
        indexManager.executeSingleWeightUpdate(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            0,
            "a failed weight update must not emit IndexActionTriggered"
        );
        _assertSingleActionFailedFor(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.EXECUTE_WEIGHTS,
            abi.encodeWithSelector(Index__NotPendingWeightUpdate.selector)
        );
    }

    function testExecuteWeightUpdateForMultipleIndexesEmitsActionTriggeredOnlyForSucceedingIndex()
        public
    {
        _proposeAndWarpToExecutable(address(initializedIndex), weight70);
        _refreshExchangeRates();

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.executeWeightUpdateForMultipleIndexes(_twoIndexes());
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertBatchOneSuccessOneFailure(
            logs,
            deployer,
            IndexAction.EXECUTE_WEIGHTS,
            abi.encodeWithSelector(Index__NotPendingWeightUpdate.selector),
            WeightsUpdated.selector
        );
    }

    // =========================================================================
    //  cancelWeightUpdate — CANCEL_WEIGHTS
    // =========================================================================

    function testCancelWeightUpdateViaMultiSigEmitsActionTriggeredWithMultiSigAsCaller()
        public
    {
        vm.prank(address(multiSigWallet));
        indexManager.proposeNewWeights(address(initializedIndex), weight30);

        vm.recordLogs();
        vm.prank(address(multiSigWallet));
        indexManager.cancelWeightUpdate(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 actionPosition = _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            address(multiSigWallet),
            IndexAction.CANCEL_WEIGHTS
        );
        _assertIndexEventBeforeAction(
            logs,
            address(initializedIndex),
            WeightsUpdateCancelled.selector,
            actionPosition
        );
    }

    function testCancelWeightUpdateRevertEmitsNoActionTriggered() public {
        vm.recordLogs();
        vm.prank(deployer);
        vm.expectRevert(Index__NotPendingWeightUpdate.selector);
        indexManager.cancelWeightUpdate(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            0,
            "a reverted cancelWeightUpdate must not emit IndexActionTriggered"
        );
    }

    // =========================================================================
    //  collectFees — COLLECT_FEES
    // =========================================================================

    function testCollectFeesFromSingleIndexEmitsActionTriggeredWithFeeCollectorAsCaller()
        public
    {
        _mintSharesViaRouter(user1, FEE_GENERATING_DEPOSIT);

        vm.recordLogs();
        vm.prank(feeCollector);
        indexManager.collectFeesFromSingleIndex(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 actionPosition = _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            feeCollector,
            IndexAction.COLLECT_FEES
        );
        _assertIndexEventBeforeAction(
            logs,
            address(initializedIndex),
            FeesCollected.selector,
            actionPosition
        );
    }

    function testCollectFeesFromSingleIndexFailureEmitsNoActionTriggered()
        public
    {
        vm.recordLogs();
        vm.prank(feeCollector);
        indexManager.collectFeesFromSingleIndex(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            0,
            "a failed fee collection must not emit IndexActionTriggered"
        );
        _assertSingleActionFailedFor(
            logs,
            address(initializedIndex),
            feeCollector,
            IndexAction.COLLECT_FEES,
            abi.encodeWithSelector(Index__NoFeesToCollect.selector)
        );
    }

    function testCollectFeesFromMultipleIndexesEmitsActionTriggeredOnlyForSucceedingIndex()
        public
    {
        _mintSharesViaRouter(user1, FEE_GENERATING_DEPOSIT);
        (, uint128 secondIndexFees) = s_secondIndex.getFeesInfo();
        assertEq(secondIndexFees, 0, "the second index must have no fees");

        vm.recordLogs();
        vm.prank(feeCollector);
        indexManager.collectFeesFromMultipleIndexes(_twoIndexes());
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertBatchOneSuccessOneFailure(
            logs,
            feeCollector,
            IndexAction.COLLECT_FEES,
            abi.encodeWithSelector(Index__NoFeesToCollect.selector),
            FeesCollected.selector
        );
    }
}
