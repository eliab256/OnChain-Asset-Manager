//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/contracts/periphery/IndexManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {Index} from "../../../src/contracts/core/Index.sol";
import {IndexAsset, SwapRoute, AssetAvailable} from "../../../src/contracts/types.sol";
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

    function testRebalanceSingleIndexRevertIfSwapManagerNotSet() public {
        //set swaprouter to address(0) to trigger the revert
        vm.prank(deployer);
        indexManager.setSwapManagerAddress(address(0));

        vm.prank(deployer);
        vm.expectRevert(IndexManager__SwapManagerAddressNotSet.selector);
        indexManager.rebalanceSingleIndex(address(initializedIndex));
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

    function testRebalanceIndexEmitsIndexRebalanceFailedWhenBalanced() public {
        vm.prank(deployer);
        vm.recordLogs();
        indexManager.rebalanceSingleIndex(address(initializedIndex));

        bytes32 expectedSig = IndexRebalanceFailed.selector;
        bytes32 expectedReason = Index__RebalanceNotNeeded.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool rebalanceFailedEmitted = false;
        bytes memory reason;
        address indexEmitter;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSig) {
                rebalanceFailedEmitted = true;
                indexEmitter = address(uint160(uint256(logs[i].topics[1])));
                reason = logs[i].data;
                break;
            }
        }

        assertTrue(
            rebalanceFailedEmitted,
            "IndexRebalanceFailed event not emitted"
        );
        assertEq(
            indexEmitter,
            address(initializedIndex),
            "Event emitted by wrong index"
        );
        // `reason` is the raw log data, which ABI-encodes the `bytes` field
        // (offset + length + value). Decode it first to get the raw bytes.
        bytes memory decodedReason = abi.decode(reason, (bytes));
        assertEq(
            bytes4(decodedReason),
            expectedReason,
            "Event emitted with wrong reason"
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
        address rebalancerFromEvent;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSig) {
                rebalanceEmitted = true;
                indexFromEvent = address(uint160(uint256(logs[i].topics[1])));
                rebalancerFromEvent = address(
                    uint160(uint256(logs[i].topics[2]))
                );
                break;
            }
        }

        assertTrue(rebalanceEmitted, "IndexRebalanced event not emitted");
        assertEq(
            indexFromEvent,
            address(initializedIndex),
            "Event emitted by wrong index"
        );
        assertEq(
            rebalancerFromEvent,
            deployer,
            "Event emitted by wrong rebalancer"
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

        bytes32 expectedSig = IndexRebalanceFailed.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 rebalanceFailedCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSig) {
                rebalanceFailedCount++;
            }
        }

        // Both indexes are balanced, so both emit IndexRebalanceFailed with reason Index__RebalanceNotNeeded but the transaction does not revert
        assertEq(
            rebalanceFailedCount,
            indexes.length,
            "IndexRebalanceFailed event should be emitted for both balanced indexes"
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

        bytes32 rebalanceFailedSig = IndexRebalanceFailed.selector;
        bytes32 rebalanceSuccessSig = IndexRebalanced.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 rebalanceFailedCount = 0;
        uint256 rebalanceSuccessCount = 0;
        address[] memory indexesFromEvent = new address[](3);
        address[] memory rebalancerFromEvent = new address[](3);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == rebalanceFailedSig) {
                rebalanceFailedCount++;
            } else if (logs[i].topics[0] == rebalanceSuccessSig) {
                indexesFromEvent[rebalanceSuccessCount] = address(
                    uint160(uint256(logs[i].topics[1]))
                );
                rebalancerFromEvent[rebalanceSuccessCount] = address(
                    uint160(uint256(logs[i].topics[2]))
                );
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
            "IndexRebalanceFailed event should not be emitted"
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
        assertEq(
            rebalancerFromEvent[0],
            deployer,
            "Event emitted by wrong rebalancer"
        );
        assertEq(
            rebalancerFromEvent[1],
            deployer,
            "Event emitted by wrong rebalancer"
        );
        assertEq(
            rebalancerFromEvent[2],
            deployer,
            "Event emitted by wrong rebalancer"
        );
    }

    // =========================================================================
    //  rebalanceAllIndexes
    // =========================================================================

    function testRebalanceAllIndexesEmitEventForEveryIndex() public {
        uint256 indexAmount = indexManager.getInitializedIndexes().length;

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.rebalanceAllIndexes();

        bytes32 rebalanceFailedSig = IndexRebalanceFailed.selector;
        bytes32 rebalanceSuccessSig = IndexRebalanced.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 rebalanceFailedCount = 0;
        uint256 rebalanceSuccessCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == rebalanceFailedSig) {
                rebalanceFailedCount++;
            } else if (logs[i].topics[0] == rebalanceSuccessSig) {
                rebalanceSuccessCount++;
            }
        }

        assertEq(
            rebalanceFailedCount + rebalanceSuccessCount,
            indexAmount,
            "Event count does not match initialized index count"
        );
    }

    function testRebalanceAllIndexesWorksAndEmitsEvents() public {
        // change price of unerlying assets to make indexes unbalanced and trigger rebalance logic
        vm.warp(block.timestamp + 3600);
        _refreshPriceFeeds();
        int256 newWethPrice = WETH_INITIAL_PRICE * 6; // $12000
        mockWethPriceFeed.updateAnswer(newWethPrice);
        int256 newCompPrice = COMP_INITIAL_PRICE * 3; // $150
        mockCompPriceFeed.updateAnswer(newCompPrice);
        _refreshExchangeRates();

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.rebalanceAllIndexes();

        bytes32 rebalanceFailedSig = IndexRebalanceFailed.selector;
        bytes32 rebalanceSuccessSig = IndexRebalanced.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 rebalanceFailedCount = 0;
        uint256 rebalanceSuccessCount = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == rebalanceFailedSig) {
                rebalanceFailedCount++;
            } else if (logs[i].topics[0] == rebalanceSuccessSig) {
                rebalanceSuccessCount++;
            }
        }

        assertEq(
            rebalanceSuccessCount,
            indexManager.getInitializedIndexes().length,
            "IndexRebalanced event should be emitted for all initialized indexes"
        );
        assertEq(
            rebalanceFailedCount,
            0,
            "IndexRebalanceFailed event should not be emitted"
        );
    }
}
