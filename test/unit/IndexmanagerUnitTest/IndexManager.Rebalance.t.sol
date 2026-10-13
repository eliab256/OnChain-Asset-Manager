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
import "../../../src/events/IndexEvents.sol";
import "../../../src/errors/IndexErrors.sol";

contract IndexManagerRebalanceTest is BaseTest {
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
    //  rebalanceSingleIndex
    // =========================================================================

    function testRebalanceSingleIndexRevertIfIndexNotInitialized() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__NotIndexInitialized.selector,
                address(nonInitializedIndex)
            )
        );
        indexManager.rebalanceSingleIndex(address(nonInitializedIndex));
    }

    function testRebalanceSingleIndexRevertIfCallerNotRebalancer() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                keccak256("REBALANCER_ROLE")
            )
        );
        indexManager.rebalanceSingleIndex(address(initializedIndex));
    }

    function testRebalanceIndexEmitsIndexActionFailedWhenBalanced() public {
        vm.prank(deployer);
        vm.recordLogs();
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

    function testRebalanceIndexEmitsIndexRebalanceWhenBalancedSuccessfully()
        public
    {
        // change price of unerlying assets to make index unbalanced and trigger rebalance logic
        vm.warp(block.timestamp + 3600);
        _refreshPriceFeeds();
        int256 newWethPrice = WETH_INITIAL_PRICE * 6; // $12000
        mockWethPriceFeed.updateAnswer(newWethPrice);
        _refreshExchangeRates();

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.rebalanceSingleIndex(address(initializedIndex));

        bytes32 expectedSig = IndexRebalanced.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool rebalanceEmitted = false;
        address indexFromEvent;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSig && !rebalanceEmitted) {
                rebalanceEmitted = true;
                // IndexRebalanced is now emitted only by the Index itself
                indexFromEvent = logs[i].emitter;
            }
        }

        assertTrue(rebalanceEmitted, "IndexRebalanced event not emitted");
        assertEq(
            indexFromEvent,
            address(initializedIndex),
            "Event emitted by wrong index"
        );
        _assertOnlyActionTriggered(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.REBALANCE
        );
    }

    // =========================================================================
    //  rebalanceMultipleIndexes
    // =========================================================================

    function testRebalanceMultipleIndexesRevertIfAnyIndexNotInitialized()
        public
    {
        address[] memory indexes = new address[](2);
        indexes[0] = address(initializedIndex);
        indexes[1] = address(nonInitializedIndex);

        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__NotIndexInitialized.selector,
                address(nonInitializedIndex)
            )
        );
        indexManager.rebalanceMultipleIndexes(indexes);
    }

    function testRebalanceMultipleIndexesDoesNotRevertWhenIndexIsBalanced()
        public
    {
        address[] memory indexes = new address[](2);
        indexes[0] = address(initializedIndex);
        indexes[1] = address(newIndexLinkWeth);
        vm.prank(deployer);
        vm.recordLogs();
        indexManager.rebalanceMultipleIndexes(indexes);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Both indexes are balanced: each gets IndexActionFailed(Index__RebalanceNotNeeded)
        // and the transaction does not revert.
        for (uint256 i = 0; i < indexes.length; i++) {
            _assertSingleActionFailedFor(
                logs,
                indexes[i],
                deployer,
                IndexAction.REBALANCE,
                abi.encodeWithSelector(Index__RebalanceNotNeeded.selector)
            );
        }
        assertEq(
            _countManagerEvents(logs, IndexActionFailed.selector),
            indexes.length,
            "IndexActionFailed must be emitted for both balanced indexes"
        );
        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            0,
            "no IndexActionTriggered when every rebalance fails"
        );
    }

    function testRebalanceMultipleIndexesRevertIfCallerNotRebalancer() public {
        address[] memory indexes = new address[](2);
        indexes[0] = address(newIndexLinkWeth);
        indexes[1] = address(initializedIndex);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                keccak256("REBALANCER_ROLE")
            )
        );
        indexManager.rebalanceMultipleIndexes(indexes);
    }

    function testRebalanceMultipleIndexesWorksAndEmitsEvents() public {
        // change price of unerlying assets to make indexes unbalanced and trigger rebalance logic
        vm.warp(block.timestamp + 3600);
        _refreshPriceFeeds();
        int256 newWethPrice = WETH_INITIAL_PRICE * 6; // $12000
        mockWethPriceFeed.updateAnswer(newWethPrice);
        int256 newCompPrice = COMP_INITIAL_PRICE * 3; // $150
        mockCompPriceFeed.updateAnswer(newCompPrice);
        _refreshExchangeRates();

        address[] memory indexes = new address[](3);
        indexes[0] = address(newIndexLinkWeth);
        indexes[1] = address(newIndexWbtcComp);
        indexes[2] = address(initializedIndex);

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.rebalanceMultipleIndexes(indexes);

        bytes32 rebalanceFailedSig = IndexActionFailed.selector;
        bytes32 rebalanceSuccessSig = IndexRebalanced.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 rebalanceFailedCount = 0;
        uint256 rebalanceSuccessCount = 0;
        address[] memory indexesFromEvent = new address[](3);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == rebalanceFailedSig) {
                rebalanceFailedCount++;
            } else if (logs[i].topics[0] == rebalanceSuccessSig) {
                // IndexRebalanced is emitted by each Index: the index is the emitter
                indexesFromEvent[rebalanceSuccessCount] = logs[i].emitter;
                rebalanceSuccessCount++;
            }
        }

        assertEq(
            rebalanceSuccessCount,
            indexes.length,
            "IndexRebalanced event should be emitted for both indexes"
        );
        assertEq(
            rebalanceFailedCount,
            0,
            "IndexActionFailed event should not be emitted"
        );
        assertEq(
            indexesFromEvent[0],
            address(newIndexLinkWeth),
            "Event emitted by wrong index"
        );
        assertEq(
            indexesFromEvent[1],
            address(newIndexWbtcComp),
            "Event emitted by wrong index"
        );
        assertEq(
            indexesFromEvent[2],
            address(initializedIndex),
            "Event emitted by wrong index"
        );
        for (uint256 i = 0; i < indexes.length; i++) {
            _assertSingleActionTriggeredFor(
                logs,
                indexes[i],
                deployer,
                IndexAction.REBALANCE
            );
        }
        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            indexes.length,
            "one IndexActionTriggered per successfully rebalanced index"
        );
        assertEq(
            _countManagerEvents(logs, IndexActionFailed.selector),
            0,
            "IndexManager must not emit IndexActionFailed when every rebalance succeeds"
        );
    }

    function testRebalanceMultipleIndexesOnInitializedIndexesContinuesPastFailingIndex()
        public
    {
        // Only WETH moves: the two WETH indexes become unbalanced, WBTC/COMP stays balanced.
        vm.warp(block.timestamp + 3600);
        _refreshPriceFeeds();
        mockWethPriceFeed.updateAnswer(WETH_INITIAL_PRICE * 6); // $12000
        _refreshExchangeRates();

        address[] memory indexes = indexManager.getInitializedIndexes();
        assertEq(indexes.length, 3, "three initialized indexes expected");

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.rebalanceMultipleIndexes(indexes);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertSingleActionTriggeredFor(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.REBALANCE
        );
        _assertSingleActionTriggeredFor(
            logs,
            address(newIndexLinkWeth),
            deployer,
            IndexAction.REBALANCE
        );
        _assertSingleActionFailedFor(
            logs,
            address(newIndexWbtcComp),
            deployer,
            IndexAction.REBALANCE,
            abi.encodeWithSelector(Index__RebalanceNotNeeded.selector)
        );
        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            2,
            "IndexActionTriggered only for the two rebalanced indexes"
        );
        assertEq(
            _countManagerEvents(logs, IndexActionFailed.selector),
            1,
            "IndexActionFailed only for the balanced index"
        );
    }
}
