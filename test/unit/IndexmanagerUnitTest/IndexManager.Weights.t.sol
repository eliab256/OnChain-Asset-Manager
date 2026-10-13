//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {Index} from "../../../src/Index.sol";
import {
    IndexAsset,
    SwapRoute,
    AssetAvailable,
    IndexAction
} from "../../../src/types.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    DeployAndInitNewIndex,
    RunParams
} from "../../../script/DeployAndInitNewIndex.s.sol";

import "../../../src/errors/IndexManagerErrors.sol";
import "../../../src/events/IndexManagerEvents.sol";
import "../../../src/errors/IndexErrors.sol";
import "../../../src/events/IndexEvents.sol";

contract IndexManagerWeightsTest is BaseTest {
    IIndex public newIndexLinkWeth;
    IIndex public newIndexWbtcComp;

    function setUp() public override {
        super.setUp();

        RunParams memory firstIndexParams = RunParams({
            assetA: AssetAvailable.WETH,
            assetB: AssetAvailable.LINK,
            weightA: 60 * WEIGHT_PRECISION,
            weightB: 40 * WEIGHT_PRECISION,
            feePercentage: 1 * PERCENTAGE_FEE_PRECISION, // 1%
            initialAssetADeposit: 0, // computed by the script via UnderlyingMath.calculateComplementaryAssetAmount
            initialAssetBDeposit: 1000 * 10 ** 18 // 1000 units of assetB
        });

        DeployAndInitNewIndex deployScript = new DeployAndInitNewIndex();
        newIndexLinkWeth = deployScript.run(
            helperConfig,
            address(indexManager),
            address(multiSigWallet),
            firstIndexParams
        );
        // asset0 = newIndex.getAsset0();
        // asset1 = newIndex.getAsset1();

        RunParams memory secondIndexParams = RunParams({
            assetA: AssetAvailable.WBTC,
            assetB: AssetAvailable.COMP,
            weightA: 60 * WEIGHT_PRECISION,
            weightB: 40 * WEIGHT_PRECISION,
            feePercentage: 1 * PERCENTAGE_FEE_PRECISION, // 1%
            initialAssetADeposit: 0,
            initialAssetBDeposit: 1_000_000 * 10 ** 18 // 1,000,000 COMP
        });

        newIndexWbtcComp = deployScript.run(
            helperConfig,
            address(indexManager),
            address(multiSigWallet),
            secondIndexParams
        );
    }

    // =========================================================================
    //  proposeNewWeights
    // =========================================================================

    function testProposeNewWeightsEmitsWeightsUpdateProposedEvent() public {
        uint128 expectedNewWeight1 = MAX_WEIGHT - weight30;
        (uint128 lastWeight0, uint128 lastWeight1) = initializedIndex
            .getAssetsWeights();

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.proposeNewWeights(address(initializedIndex), weight30);

        (uint128 previousWeight0, uint128 previousWeight1) = initializedIndex
            .getAssetsWeights();
        (
            uint128 pendingWeight0,
            uint128 pendingWeight1,
            uint256 weightUpdateExecutableAt
        ) = initializedIndex.getAssetsPendingWeights();

        //verify state update
        assertEq(pendingWeight0, weight30);
        assertEq(pendingWeight1, expectedNewWeight1);
        assertEq(previousWeight0, lastWeight0);
        assertEq(previousWeight1, lastWeight1);
        assertEq(
            weightUpdateExecutableAt,
            block.timestamp + WEIGHT_UPDATE_DELAY
        );

        {
            Vm.Log[] memory logs = vm.getRecordedLogs();

            // The proposal data is logged by the Index (WeightsUpdateProposed);
            // the IndexManager only logs IndexActionTriggered(PROPOSE_WEIGHTS).
            bytes32 expectedSig = WeightsUpdateProposed.selector;
            bool eventFound = false;
            address indexFromEvent;

            bytes memory dataEncodedFromEvent;
            for (uint256 i = 0; i < logs.length; i++) {
                if (logs[i].topics[0] == expectedSig) {
                    eventFound = true;
                    indexFromEvent = logs[i].emitter;
                    assertEq(
                        logs[i].topics.length,
                        1,
                        "WeightsUpdateProposed must have no indexed params"
                    );
                    dataEncodedFromEvent = logs[i].data;
                }
            }

            bytes memory dataEncodeFromStorage = abi.encode(
                previousWeight0,
                previousWeight1,
                pendingWeight0,
                pendingWeight1,
                weightUpdateExecutableAt
            );

            //verify event emission
            assertTrue(eventFound, "WeightsUpdateProposed event not emitted");
            assertEq(
                indexFromEvent,
                address(initializedIndex),
                "Incorrect index address in event"
            );
            _assertOnlyActionTriggered(
                logs,
                address(initializedIndex),
                deployer,
                IndexAction.PROPOSE_WEIGHTS
            );

            assertEq(
                dataEncodedFromEvent,
                dataEncodeFromStorage,
                "Incorrect data in event"
            );
        }
    }

    function testProposeNewWeightsRevertIfIndexNotInitialized() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__NotIndexInitialized.selector,
                address(nonInitializedIndex)
            )
        );
        indexManager.proposeNewWeights(address(nonInitializedIndex), weight40);
    }

    function test_proposeNewWeights_RevertIf_CallerNotAssetManager() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                keccak256("ASSET_MANAGER_ROLE")
            )
        );
        indexManager.proposeNewWeights(address(initializedIndex), weight40);
    }

    // // =========================================================================
    // //  executeWeightUpdate
    // // =========================================================================

    function testExecuteWeightUpdateRevertIfIndexNotInitialized() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__NotIndexInitialized.selector,
                address(nonInitializedIndex)
            )
        );
        indexManager.executeSingleWeightUpdate(address(nonInitializedIndex));
    }

    function testExecuteWeightUpdateEmitsIndexActionFailedWhenNoPendingUpdate()
        public
    {
        vm.prank(deployer);
        vm.recordLogs();
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

    function testExecuteWeightUpdateSuccessAlsoIfRebalanceFails() public {
        vm.prank(deployer);
        indexManager.proposeNewWeights(address(initializedIndex), weight30);

        // Drain the mock router so the internal rebalance swap will fail
        deal(address(mockWeth), address(mockUniRouter), 0);
        deal(address(mockWbtc), address(mockUniRouter), 0);

        // Attempt execution after WEIGHT_UPDATE_DELAY (2 days) has elapsed.
        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1);
        _refreshPriceFeeds();
        vm.prank(deployer);
        vm.recordLogs();
        indexManager.executeSingleWeightUpdate(address(initializedIndex));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Index emits WeightsUpdated (the weight update succeeded).
        // Index internally emits WeightsUpdateRebalanceFailed (rebalance failed).
        // IndexManager does NOT emit IndexActionFailed because Index.executeWeightUpdate() did not revert:
        // it emits only IndexActionTriggered(EXECUTE_WEIGHTS).
        bytes32 expectedSuccessSig = WeightsUpdated.selector;
        bytes32 expectedRebalanceFailedSig = WeightsUpdateRebalanceFailed
            .selector;
        bool successEventFound = false;
        bool rebalanceFailedEventFound = false;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(initializedIndex)) continue;
            if (logs[i].topics[0] == expectedSuccessSig) {
                successEventFound = true;
            } else if (logs[i].topics[0] == expectedRebalanceFailedSig) {
                rebalanceFailedEventFound = true;
            }
        }
        assertTrue(
            successEventFound,
            "WeightsUpdated event should be emitted even if rebalance fails"
        );
        assertTrue(
            rebalanceFailedEventFound,
            "WeightsUpdateRebalanceFailed event should be emitted from Index when rebalance fails"
        );
        _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.EXECUTE_WEIGHTS
        );

        // Verify weights were actually updated despite rebalance failure
        (uint128 newWeight0, uint128 newWeight1) = initializedIndex
            .getAssetsWeights();
        assertEq(newWeight0, weight30, "Weight0 should be updated to weight30");
        assertEq(
            newWeight1,
            MAX_WEIGHT - weight30,
            "Weight1 should be updated to MAX_WEIGHT - weight30"
        );
    }

    function testExecuteWeightUpdateEmitsIndexActionFailedWhenExecutedTooEarly()
        public
    {
        vm.prank(deployer);
        indexManager.proposeNewWeights(address(initializedIndex), weight50);

        // Attempt execution before WEIGHT_UPDATE_DELAY (2 days) has elapsed.
        vm.prank(deployer);
        vm.recordLogs();
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

    function testExecuteWeightUpdateEmitsIndexActionFailedWhenProposalExpired()
        public
    {
        vm.prank(deployer);
        indexManager.proposeNewWeights(address(initializedIndex), weight50);

        vm.warp(
            block.timestamp +
                WEIGHT_UPDATE_DELAY +
                WEIGHT_UPDATE_EXECUTION_WINDOW +
                1
        );
        vm.prank(deployer);
        vm.recordLogs();
        indexManager.executeSingleWeightUpdate(address(initializedIndex));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertOnlyActionFailed(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.EXECUTE_WEIGHTS,
            abi.encodeWithSelector(Index__WeightUpdateExpired.selector)
        );
    }

    // // =========================================================================
    // //  cancelWeightUpdate
    // // =========================================================================

    function testCancelWeightUpdateResetsPendingWeightsAndEmitsEvent() public {
        vm.prank(deployer);
        indexManager.proposeNewWeights(address(initializedIndex), weight50);

        // The IndexManager duplicate (WeightUpdateCancelled) was removed:
        // the cancellation is logged by the Index with the cancelled weights.
        vm.expectEmit(true, true, true, true, address(initializedIndex));
        emit WeightsUpdateCancelled(weight50, MAX_WEIGHT - weight50);
        vm.prank(deployer);
        indexManager.cancelWeightUpdate(address(initializedIndex));

        (
            uint128 pendingWeight0,
            uint128 pendingWeight1,
            uint256 implementationTimestamp
        ) = initializedIndex.getAssetsPendingWeights();
        assertEq(pendingWeight0, 0);
        assertEq(pendingWeight1, 0);
        assertEq(implementationTimestamp, 0);
    }

    function testCancelWeightUpdateRevertIfNoPendingUpdate() public {
        vm.prank(deployer);
        vm.expectRevert(Index__NotPendingWeightUpdate.selector);
        indexManager.cancelWeightUpdate(address(initializedIndex));
    }

    function testCancelWeightUpdateRevertIfIndexNotInitialized() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__NotIndexInitialized.selector,
                address(nonInitializedIndex)
            )
        );
        indexManager.cancelWeightUpdate(address(nonInitializedIndex));
    }

    function testCancelWeightUpdateRevertIfCallerNotAssetManager() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                keccak256("ASSET_MANAGER_ROLE")
            )
        );
        indexManager.cancelWeightUpdate(address(initializedIndex));
    }

    // // =========================================================================
    // //  executeWeightUpdateForMultipleIndexes
    // // =========================================================================

    function testExecuteWeightUpdateForMultipleIndexesRevertIfAnyNotInitialized()
        public
    {
        address[] memory indexes = new address[](2);
        indexes[0] = address(nonInitializedIndex);
        indexes[1] = address(initializedIndex);

        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__NotIndexInitialized.selector,
                address(nonInitializedIndex)
            )
        );
        indexManager.executeWeightUpdateForMultipleIndexes(indexes);
    }

    function test_executeWeightUpdateForMultipleIndexesDoesNotRevertWithNoPending()
        public
    {
        // Propose new weights for the two initialized indexes, so 2 executions will success but the 3rd will not
        vm.startPrank(deployer);
        indexManager.proposeNewWeights(address(initializedIndex), weight30);
        indexManager.proposeNewWeights(address(newIndexLinkWeth), weight30);
        vm.stopPrank();

        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1);
        _refreshPriceFeeds();
        address[] memory indexes = new address[](3);
        indexes[0] = address(initializedIndex);
        indexes[1] = address(newIndexLinkWeth);
        indexes[2] = address(newIndexWbtcComp); // this will fail execution because it has no pending weight update

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.executeWeightUpdateForMultipleIndexes(indexes);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Success is now logged only by each Index (WeightsUpdated, emitter = index).
        bytes32 expectedSuccessSig = WeightsUpdated.selector;
        bytes32 expectedFailedSig = IndexActionFailed.selector;
        uint256 successCount = 0;
        uint256 failedCount = 0;
        address[] memory indexesFromSuccessEvents = new address[](2);
        address[] memory indexesFromFailedEvents = new address[](1);

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSuccessSig) {
                indexesFromSuccessEvents[successCount] = logs[i].emitter;
                successCount++;
            } else if (
                logs[i].emitter == address(indexManager) &&
                logs[i].topics[0] == expectedFailedSig
            ) {
                address indexFromEvent = address(
                    uint160(uint256(logs[i].topics[1]))
                );
                indexesFromFailedEvents[failedCount] = indexFromEvent;
                failedCount++;
            }
        }

        assertEq(successCount, 2, "There should be 2 successful executions");
        assertEq(failedCount, 1, "There should be 1 failed execution");
        assertEq(
            indexesFromSuccessEvents[0],
            address(initializedIndex),
            "First success event should be for initializedIndex"
        );
        assertEq(
            indexesFromSuccessEvents[1],
            address(newIndexLinkWeth),
            "Second success event should be for newIndexLinkWeth"
        );
        assertEq(
            indexesFromFailedEvents[0],
            address(newIndexWbtcComp),
            "Failed event should be for newIndexWbtcComp"
        );
        _assertSingleActionFailedFor(
            logs,
            address(newIndexWbtcComp),
            deployer,
            IndexAction.EXECUTE_WEIGHTS,
            abi.encodeWithSelector(Index__NotPendingWeightUpdate.selector)
        );
    }

    function testExecuteWeightUpdateForMultipleIndexesOnInitializedIndexesUpdatesOnlyPending()
        public
    {
        vm.startPrank(deployer);
        indexManager.proposeNewWeights(address(initializedIndex), weight30);
        indexManager.proposeNewWeights(address(newIndexLinkWeth), weight30);
        vm.stopPrank();
        (uint128 untouchedWeight0Before, uint128 untouchedWeight1Before) = newIndexWbtcComp
            .getAssetsWeights();

        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1);
        _refreshPriceFeeds();

        address[] memory indexes = indexManager.getInitializedIndexes();
        assertEq(indexes.length, 3, "three initialized indexes expected");

        vm.prank(deployer);
        indexManager.executeWeightUpdateForMultipleIndexes(indexes);

        (uint128 w0, uint128 w1) = initializedIndex.getAssetsWeights();
        assertEq(w0, weight30, "initializedIndex weight0 must be updated");
        assertEq(w1, MAX_WEIGHT - weight30, "initializedIndex weight1");
        (w0, w1) = newIndexLinkWeth.getAssetsWeights();
        assertEq(w0, weight30, "newIndexLinkWeth weight0 must be updated");
        assertEq(w1, MAX_WEIGHT - weight30, "newIndexLinkWeth weight1");
        (w0, w1) = newIndexWbtcComp.getAssetsWeights();
        assertEq(
            w0,
            untouchedWeight0Before,
            "index without pending update must keep weight0"
        );
        assertEq(
            w1,
            untouchedWeight1Before,
            "index without pending update must keep weight1"
        );

        (uint128 pending0, , uint256 executableAt) = initializedIndex
            .getAssetsPendingWeights();
        assertEq(pending0, 0, "pending weights must be cleared");
        assertEq(executableAt, 0, "pending timestamp must be cleared");
    }

    function testExecuteWeightUpdateForMultipleIndexesOnInitializedIndexesEmitsOneEventPerIndex()
        public
    {
        vm.startPrank(deployer);
        indexManager.proposeNewWeights(address(initializedIndex), weight30);
        indexManager.proposeNewWeights(address(newIndexLinkWeth), weight30);
        vm.stopPrank();

        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1);
        _refreshPriceFeeds();

        address[] memory indexes = indexManager.getInitializedIndexes();

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.executeWeightUpdateForMultipleIndexes(indexes);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < indexes.length; i++) {
            if (indexes[i] == address(newIndexWbtcComp)) {
                _assertSingleActionFailedFor(
                    logs,
                    indexes[i],
                    deployer,
                    IndexAction.EXECUTE_WEIGHTS,
                    abi.encodeWithSelector(
                        Index__NotPendingWeightUpdate.selector
                    )
                );
            } else {
                _assertSingleActionTriggeredFor(
                    logs,
                    indexes[i],
                    deployer,
                    IndexAction.EXECUTE_WEIGHTS
                );
            }
        }
        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            2,
            "IndexActionTriggered only for the indexes with a pending update"
        );
        assertEq(
            _countManagerEvents(logs, IndexActionFailed.selector),
            1,
            "IndexActionFailed only for the index without a pending update"
        );
    }
}
