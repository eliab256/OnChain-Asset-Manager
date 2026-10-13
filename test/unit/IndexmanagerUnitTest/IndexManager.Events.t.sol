//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IndexAsset, IndexAction} from "../../../src/types.sol";
import {Index} from "../../../src/Index.sol";
import {UniversalRouterMock} from "../../mocks/UniversalRouterMock.sol";

import "../../../src/errors/IndexErrors.sol";
import "../../../src/events/IndexEvents.sol";
import "../../../src/events/IndexManagerEvents.sol";

/**
 * @dev Event-only tests for the IndexManager after the event refactor:
 *      IndexActionFailed with the raw reasonData on failed actions, IndexActionTriggered as the only
 *      manager event on successful actions and IndexCreated payloads.
 *      Proxy-upgrade events are covered by ProxyUpgradeViaTimelock.t.sol (TimelockController + IERC1967.Upgraded).
 */
contract IndexManagerEventsTest is BaseTest {
    // =========================================================================
    //  Constants
    // =========================================================================

    /// USDC deposited to accrue fees on the initialized index (6 decimals)
    uint256 constant FEE_GENERATING_DEPOSIT = 1_000e6;

    // =========================================================================
    //  Values derived from the contracts
    // =========================================================================

    /// Fee used for the extra index created in the IndexCreated test (2%)
    uint32 internal s_createIndexFee;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();

        s_createIndexFee = 2 * PERCENTAGE_FEE_PRECISION;
    }

    // =========================================================================
    //  Helpers
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

    function _topicToAddress(bytes32 _topic) internal pure returns (address) {
        return address(uint160(uint256(_topic)));
    }

    /// @dev Makes the initialized index unbalanced and removes the router rate the
    ///      rebalance needs. Returns the revert data the router will produce.
    function _breakRebalanceSwap() internal returns (bytes memory expectedReason) {
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        _refreshExchangeRates();

        (uint128 targetWeight0, ) = initializedIndex.getAssetsWeights();
        (uint128 effectiveWeight0, ) = initializedIndex
            .getAssetsEffectiveWeights();
        (address tokenIn, address tokenOut) = effectiveWeight0 > targetWeight0
            ? (initializedToken0, initializedToken1)
            : (initializedToken1, initializedToken0);

        mockUniRouter.setExchangeRate(tokenIn, tokenOut, 0);
        expectedReason = abi.encodeWithSelector(
            UniversalRouterMock.UniversalRouterMock__RateNotSet.selector,
            tokenIn,
            tokenOut
        );
    }

    // =========================================================================
    //  createIndex — IndexCreated
    // =========================================================================

    function testCreateIndexEventLogsSortedWeightsAndFee() public {
        IndexAsset memory compAsset = IndexAsset({
            asset: address(mockComp),
            weightPercentage: weight30
        });
        IndexAsset memory linkAsset = IndexAsset({
            asset: address(mockLink),
            weightPercentage: MAX_WEIGHT - weight30
        });

        vm.recordLogs();
        vm.prank(deployer);
        (address index, address asset0, address asset1) = indexManager
            .createIndex(s_createIndexFee, compAsset, linkAsset);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 count, uint256 eventIndex) = _findLogs(
            logs,
            address(indexManager),
            IndexCreated.selector
        );
        assertEq(count, 1, "IndexCreated was not emitted");

        Vm.Log memory log = logs[eventIndex];
        assertEq(_topicToAddress(log.topics[1]), index, "index address");
        assertEq(_topicToAddress(log.topics[2]), asset0, "asset0");
        assertEq(_topicToAddress(log.topics[3]), asset1, "asset1");

        (
            uint128 weight0,
            uint128 weight1,
            uint32 feePercentage,
            address assetManager
        ) = abi.decode(log.data, (uint128, uint128, uint32, address));

        uint128 expectedWeight0 = asset0 == address(mockComp)
            ? compAsset.weightPercentage
            : linkAsset.weightPercentage;
        (uint128 indexWeight0, uint128 indexWeight1) = Index(index)
            .getAssetsWeights();

        assertEq(weight0, expectedWeight0, "weight0 must follow sorted asset0");
        assertEq(weight1, MAX_WEIGHT - expectedWeight0, "weight1");
        assertEq(weight0, indexWeight0, "weight0 must match the index");
        assertEq(weight1, indexWeight1, "weight1 must match the index");
        assertEq(feePercentage, s_createIndexFee, "fee percentage");
        assertEq(assetManager, deployer, "asset manager");
    }

    // =========================================================================
    //  Failure events — IndexActionFailed with raw reasonData
    // =========================================================================

    function testCollectFeesFromSingleIndexFailureEmitsActionFailedWithNoFeesToCollect()
        public
    {
        vm.recordLogs();
        vm.prank(deployer);
        indexManager.collectFeesFromSingleIndex(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertOnlyActionFailed(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.COLLECT_FEES,
            abi.encodeWithSelector(Index__NoFeesToCollect.selector)
        );
    }

    function testRebalanceSingleIndexFailureEmitsActionFailedWithRebalanceNotNeeded()
        public
    {
        vm.recordLogs();
        vm.prank(deployer);
        indexManager.rebalanceSingleIndex(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertOnlyActionFailed(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.REBALANCE,
            abi.encodeWithSelector(Index__RebalanceNotNeeded.selector)
        );
    }

    function testRebalanceSingleIndexFailureEmitsActionFailedWithCustomErrorArgs()
        public
    {
        bytes memory expectedReason = _breakRebalanceSwap();

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.rebalanceSingleIndex(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertOnlyActionFailed(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.REBALANCE,
            expectedReason
        );
    }

    function testExecuteSingleWeightUpdateFailureEmitsActionFailedWithNotPendingWeightUpdate()
        public
    {
        vm.recordLogs();
        vm.prank(deployer);
        indexManager.executeSingleWeightUpdate(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertOnlyActionFailed(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.EXECUTE_WEIGHTS,
            abi.encodeWithSelector(Index__NotPendingWeightUpdate.selector)
        );
    }

    function testExecuteSingleWeightUpdateFailureViaMultiSigLogsMultiSigAsCaller()
        public
    {
        vm.recordLogs();
        vm.prank(address(multiSigWallet));
        indexManager.executeSingleWeightUpdate(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertOnlyActionFailed(
            logs,
            address(initializedIndex),
            address(multiSigWallet),
            IndexAction.EXECUTE_WEIGHTS,
            abi.encodeWithSelector(Index__NotPendingWeightUpdate.selector)
        );
    }

    // =========================================================================
    //  Successful manager actions — only IndexActionTriggered from the manager
    // =========================================================================

    function testCollectFeesFromSingleIndexSuccessEmitsOnlyActionTriggered()
        public
    {
        _mintSharesViaRouter(user1, FEE_GENERATING_DEPOSIT);
        (, uint128 feesToCollect) = initializedIndex.getFeesInfo();
        assertGt(feesToCollect, 0, "fees must have accrued");

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.collectFeesFromSingleIndex(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.COLLECT_FEES
        );

        (uint256 count, uint256 eventIndex) = _findLogs(
            logs,
            address(initializedIndex),
            FeesCollected.selector
        );
        assertEq(count, 1, "Index FeesCollected was not emitted");
        assertEq(
            _topicToAddress(logs[eventIndex].topics[1]),
            deployer,
            "fee collector"
        );
        assertEq(
            abi.decode(logs[eventIndex].data, (uint256)),
            feesToCollect,
            "fee amount"
        );
    }

    function testExecuteSingleWeightUpdateSuccessEmitsOnlyActionTriggered()
        public
    {
        vm.prank(deployer);
        indexManager.proposeNewWeights(address(initializedIndex), weight70);
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1);
        _refreshPriceFeeds();
        _refreshExchangeRates();

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.executeSingleWeightUpdate(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.EXECUTE_WEIGHTS
        );
        (uint256 count, ) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdated.selector
        );
        assertEq(count, 1, "Index WeightsUpdated was not emitted");
    }

    function testCancelWeightUpdateEmitsIndexEventAndOnlyActionTriggered()
        public
    {
        vm.prank(deployer);
        indexManager.proposeNewWeights(address(initializedIndex), weight70);

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.cancelWeightUpdate(address(initializedIndex));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.CANCEL_WEIGHTS
        );
        (uint256 count, uint256 eventIndex) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateCancelled.selector
        );
        assertEq(count, 1, "Index WeightsUpdateCancelled was not emitted");
        (uint128 cancelled0, uint128 cancelled1) = abi.decode(
            logs[eventIndex].data,
            (uint128, uint128)
        );
        assertEq(cancelled0, weight70, "cancelled weight0");
        assertEq(cancelled1, MAX_WEIGHT - weight70, "cancelled weight1");
    }
}
