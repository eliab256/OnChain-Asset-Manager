//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {Index} from "../../../src/Index.sol";
import {IndexAsset, SwapRoute, AssetAvailable} from "../../../src/types.sol";
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
            initialAssetADeposit: 0, // computed by the script via retrieveAmountFromAmount
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

    function testProposeNewWeightsEmitsNewIndexWeightsProposedEvent() public {
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

            bytes32 expectedSig = NewIndexWeightsProposed.selector;
            bool eventFound = false;
            address indexFromEvent;
            address assetManagerFromEvent;

            bytes memory dataEncodedFromEvent;
            // uint128 previousWeight0FromEvent;
            // uint128 previousWeight1FromEvent;
            // uint128 pendingWeight0FromEvent;
            // uint128 pendingWeight1FromEvent;
            // uint256 implementationTimestampFromEvent;
            for (uint256 i = 0; i < logs.length; i++) {
                if (logs[i].topics[0] == expectedSig) {
                    eventFound = true;
                    indexFromEvent = address(
                        uint160(uint256(logs[i].topics[1]))
                    );

                    assetManagerFromEvent = address(
                        uint160(uint256(logs[i].topics[2]))
                    );
                    dataEncodedFromEvent = logs[i].data;
                    break;
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
            assertTrue(eventFound, "NewIndexWeightsProposed event not emitted");
            assertEq(
                indexFromEvent,
                address(initializedIndex),
                "Incorrect index address in event"
            );
            assertEq(
                assetManagerFromEvent,
                deployer,
                "Incorrect asset manager address in event"
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

    function testExecuteWeightUpdateEmitsWeightUpdateFailedWhenNoPendingUpdate()
        public
    {
        vm.prank(deployer);
        vm.recordLogs();
        indexManager.executeSingleWeightUpdate(address(initializedIndex));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 expectedSig = WeightUpdateFailed.selector;
        bool eventFound = false;
        address indexFromEvent;
        bytes memory reasonDataFromEvent;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSig) {
                eventFound = true;
                indexFromEvent = address(uint160(uint256(logs[i].topics[1])));
                reasonDataFromEvent = logs[i].data;
                break;
            }
        }
        assertTrue(eventFound, "WeightUpdateFailed event not emitted");
        assertEq(
            indexFromEvent,
            address(initializedIndex),
            "Incorrect index address in event"
        );
        bytes memory reasonBytes = abi.decode(reasonDataFromEvent, (bytes));
        assertEq(
            bytes4(reasonBytes),
            Index__NotPendingWeightUpdate.selector,
            "Incorrect reason in event"
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
        // IndexManager emits WeightUpdateExecuted (the weight update succeeded).
        // Index internally emits WeightUpdateRebalanceFailed (rebalance failed).
        // IndexManager does NOT emit WeightUpdateFailed because Index.executeWeightUpdate() did not revert.
        bytes32 expectedSuccessSig = WeightUpdateExecuted.selector;
        bytes32 expectedRebalanceFailedSig = WeightUpdateRebalanceFailed
            .selector;
        bool successEventFound = false;
        bool rebalanceFailedEventFound = false;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSuccessSig) {
                successEventFound = true;
            } else if (logs[i].topics[0] == expectedRebalanceFailedSig) {
                rebalanceFailedEventFound = true;
            }
        }
        assertTrue(
            successEventFound,
            "WeightUpdateExecuted event should be emitted even if rebalance fails"
        );
        assertTrue(
            rebalanceFailedEventFound,
            "WeightUpdateRebalanceFailed event should be emitted from Index when rebalance fails"
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

    function testExecuteWeightUpdateEmitsWeightUpdateFailedWhenExecutedTooEarly()
        public
    {
        vm.prank(deployer);
        indexManager.proposeNewWeights(address(initializedIndex), weight50);

        // Attempt execution before WEIGHT_UPDATE_DELAY (2 days) has elapsed.
        vm.prank(deployer);
        vm.recordLogs();
        indexManager.executeSingleWeightUpdate(address(initializedIndex));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 expectedSig = WeightUpdateFailed.selector;
        bool eventFound = false;
        address indexFromEvent;
        bytes memory reasonDataFromEvent;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSig) {
                eventFound = true;
                indexFromEvent = address(uint160(uint256(logs[i].topics[1])));
                reasonDataFromEvent = logs[i].data;
                break;
            }
        }
        assertTrue(eventFound, "WeightUpdateFailed event not emitted");
        assertEq(
            indexFromEvent,
            address(initializedIndex),
            "Incorrect index address in event"
        );
        bytes memory reasonBytes = abi.decode(reasonDataFromEvent, (bytes));
        assertEq(
            bytes4(reasonBytes),
            Index__NotPendingWeightUpdate.selector,
            "Incorrect reason in event"
        );
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
        bytes32 expectedSuccessSig = WeightUpdateExecuted.selector;
        bytes32 expectedFailedSig = WeightUpdateFailed.selector;
        uint256 successCount = 0;
        uint256 failedCount = 0;
        address[] memory indexesFromSuccessEvents = new address[](2);
        address[] memory indexesFromFailedEvents = new address[](1);

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSuccessSig) {
                address indexFromEvent = address(
                    uint160(uint256(logs[i].topics[1]))
                );
                indexesFromSuccessEvents[successCount] = indexFromEvent;
                successCount++;
            } else if (logs[i].topics[0] == expectedFailedSig) {
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
    }

    // =========================================================================
    //  executeWeightUpdateForAllIndexes
    // =========================================================================

    function testExecuteWeightUpdateForAllIndexesWithInitializedIndexesEmitEvents()
        public
    {
        vm.startPrank(deployer);
        indexManager.proposeNewWeights(address(initializedIndex), weight30);
        indexManager.proposeNewWeights(address(newIndexLinkWeth), weight30);
        vm.stopPrank();

        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1);
        _refreshPriceFeeds();

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.executeWeightUpdateForAllIndexes();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 expectedSuccessSig = WeightUpdateExecuted.selector;
        bytes32 expectedFailedSig = WeightUpdateFailed.selector;
        uint256 successCount = 0;
        uint256 failedCount = 0;
        address[] memory indexesFromSuccessEvents = new address[](2);
        address[] memory indexesFromFailedEvents = new address[](1);
        bytes memory reasonDataFromFailedEvent;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSuccessSig) {
                address indexFromEvent = address(
                    uint160(uint256(logs[i].topics[1]))
                );
                indexesFromSuccessEvents[successCount] = indexFromEvent;
                successCount++;
            } else if (logs[i].topics[0] == expectedFailedSig) {
                address indexFromEvent = address(
                    uint160(uint256(logs[i].topics[1]))
                );
                indexesFromFailedEvents[failedCount] = indexFromEvent;
                failedCount++;
                reasonDataFromFailedEvent = logs[i].data;
            }
        }

        uint256 totalIndexes = indexManager.getInitializedIndexes().length;
        assertEq(
            successCount + failedCount,
            totalIndexes,
            "Total events should equal total initialized indexes"
        );
        assertEq(
            successCount,
            2,
            "There should be 2 successful executions for indexes with pending updates"
        );
        assertEq(
            failedCount,
            totalIndexes - 2,
            "The rest of the events should be failed executions for indexes without pending updates"
        );
        bytes memory reasonBytes = abi.decode(
            reasonDataFromFailedEvent,
            (bytes)
        );
        assertEq(
            bytes4(reasonBytes),
            Index__NotPendingWeightUpdate.selector,
            "Incorrect reason in event"
        );

        // control non initialized index is not included in the function
        for (uint256 i = 0; i < failedCount; i++) {
            assertTrue(
                indexesFromFailedEvents[i] != address(nonInitializedIndex),
                "Non initialized index should not be included in failed events"
            );
        }

        for (uint256 i = 0; i < successCount; i++) {
            assertTrue(
                indexesFromSuccessEvents[i] != address(nonInitializedIndex),
                "Non initialized index should not be included in success events"
            );
        }
    }
}
