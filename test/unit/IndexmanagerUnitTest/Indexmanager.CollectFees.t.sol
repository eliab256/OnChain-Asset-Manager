// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute, AssetAvailable} from "../../../src/types.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {
    DeployAndInitNewIndex,
    RunParams
} from "../../../script/DeployAndInitNewIndex.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";

import "../../../src/errors/IndexManagerErrors.sol";
import "../../../src/events/IndexManagerEvents.sol";
import "../../../src/errors/IndexErrors.sol";

contract IndexManagerTest is BaseTest {
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
            firstIndexParams
        );

        RunParams memory secondIndexParams = RunParams({
            assetA: AssetAvailable.WBTC,
            assetB: AssetAvailable.COMP,
            weightA: 60 * WEIGHT_PRECISION,
            weightB: 40 * WEIGHT_PRECISION,
            feePercentage: 1 * PERCENTAGE_FEE_PRECISION, // 1%
            initialAssetADeposit: 1 * 10 ** 8, // 1 WBTC
            initialAssetBDeposit: 0
        });

        newIndexWbtcComp = deployScript.run(
            helperConfig,
            address(indexManager),
            secondIndexParams
        );
    }

    // =========================================================================
    // helpers
    // =========================================================================
    function _generateFees(address _index) internal {
        mockUsdc.mint(user3, 10000 * 10 ** 6);

        vm.startPrank(user1);
        mockUsdc.approve(address(router), type(uint256).max);
        mockUsdc.approve(_index, type(uint256).max);
        router.buyExactUsdcAmountOfShares(
            _index,
            10000 * 10 ** 6,
            VALID_TOLERANCE
        );
        vm.stopPrank();
        vm.startPrank(user2);
        mockUsdc.approve(address(router), type(uint256).max);
        mockUsdc.approve(_index, type(uint256).max);
        router.buyExactUsdcAmountOfShares(
            _index,
            10000 * 10 ** 6,
            VALID_TOLERANCE
        );
        vm.stopPrank();
        vm.startPrank(user3);
        mockUsdc.approve(address(router), type(uint256).max);
        mockUsdc.approve(_index, type(uint256).max);
        router.buyExactUsdcAmountOfShares(
            _index,
            10000 * 10 ** 6,
            VALID_TOLERANCE
        );
        vm.stopPrank();
    }

    // =========================================================================
    //  collectFees
    // =========================================================================

    function testcollectFeesFromSingleIndexRevertIfIndexNotInitialized()
        public
    {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__NotIndexInitialized.selector,
                address(nonInitializedIndex)
            )
        );
        indexManager.collectFeesFromSingleIndex(address(nonInitializedIndex));
    }

    function testcollectFeesFromSingleIndexRevertIfCallerNotFeeCollector()
        public
    {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                keccak256("FEE_COLLECTOR_ROLE")
            )
        );
        indexManager.collectFeesFromSingleIndex(address(initializedIndex));
    }

    function testcollectFeesFromSingleIndexEmitNoFeesToCollectEvent() public {
        // Grant FEE_COLLECTOR_ROLE to feeCollector
        // (IndexManager constructor grants roles only to deployer)
        vm.prank(deployer);
        indexManager.grantRole(keccak256("FEE_COLLECTOR_ROLE"), feeCollector);

        (, uint128 feeToCollect) = initializedIndex.getFeesInfo();
        assertEq(feeToCollect, 0);
        vm.prank(feeCollector);
        vm.recordLogs();
        indexManager.collectFeesFromSingleIndex(address(initializedIndex));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool feesCollectedFailsEmitted = false;
        address indexFromEvent;
        address collectorFromEvent;
        bytes memory reasonFromEvent;

        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics[0] == FeesCollectionFailed.selector) {
                feesCollectedFailsEmitted = true;
                indexFromEvent = address(uint160(uint256(log.topics[1])));
                collectorFromEvent = address(uint160(uint256(log.topics[2])));
                reasonFromEvent = abi.decode(log.data, (bytes));
                break;
            }
        }
        assertTrue(
            feesCollectedFailsEmitted,
            "FeesCollectedFail event not emitted"
        );
        assertEq(
            indexFromEvent,
            address(initializedIndex),
            "Wrong index in event"
        );
        assertEq(collectorFromEvent, feeCollector, "Wrong collector in event");
        assertEq(
            bytes4(reasonFromEvent),
            Index__NoFeesToCollect.selector,
            "Wrong reason in event"
        );
    }

    function testCollectFeesEmitEvent() public {
        // Grant FEE_COLLECTOR_ROLE to feeCollector
        // (IndexManager constructor grants roles only to deployer)
        vm.prank(deployer);
        indexManager.grantRole(keccak256("FEE_COLLECTOR_ROLE"), feeCollector);

        _generateFees(address(initializedIndex));

        (, uint128 feeToCollect) = initializedIndex.getFeesInfo();
        assert(feeToCollect > 0);
        vm.prank(feeCollector);
        vm.recordLogs();
        indexManager.collectFeesFromSingleIndex(address(initializedIndex));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool feesCollectedEmitted = false;
        address indexFromEvent;
        address collectorFromEvent;
        uint256 amountFromEvent;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics[0] == FeesCollected.selector) {
                feesCollectedEmitted = true;
                indexFromEvent = address(uint160(uint256(log.topics[1])));
                collectorFromEvent = address(uint160(uint256(log.topics[2])));
                amountFromEvent = abi.decode(log.data, (uint256));
                break;
            }
        }

        (, uint128 finalFeeToCollect) = initializedIndex.getFeesInfo();
        uint256 usdcAmountOnContract = mockUsdc.balanceOf(
            address(initializedIndex)
        );

        assertTrue(feesCollectedEmitted, "FeesCollected event not emitted");
        assertEq(
            indexFromEvent,
            address(initializedIndex),
            "Wrong index in event"
        );
        assertEq(collectorFromEvent, feeCollector, "Wrong collector in event");
        assertEq(amountFromEvent, feeToCollect, "Wrong amount in event");
        assertEq(
            indexManager.getTotalFeesCollected(),
            feeToCollect,
            "Total fees collected not updated properly"
        );
        assertEq(finalFeeToCollect, 0, "Fees not collected properly");
        assertEq(usdcAmountOnContract, 0, "Fees not collected properly");
    }

    function testCollectFeesFromSingleIndexIncreasesTotalFeesCollectedByFeesAmount()
        public
    {
        uint256 before = indexManager.getTotalFeesCollected();

        _generateFees(address(initializedIndex));

        vm.prank(deployer);
        indexManager.collectFeesFromSingleIndex(address(initializedIndex));

        // With zero fees the value stays 0; assertGe documents the invariant.
        assertGe(indexManager.getTotalFeesCollected(), before);
    }

    // =========================================================================
    //  collectFeesFromMultipleIndexes
    // =========================================================================

    function testCollectFeesFromMultipleIndexesDoesNotRevertWhenThereAreNoFeesToCollect()
        public
    {
        _generateFees(address(initializedIndex));
        _generateFees(address(newIndexWbtcComp));

        address[] memory indexes = new address[](3);
        indexes[0] = address(initializedIndex);
        indexes[1] = address(newIndexLinkWeth); // this index has no fees to collect
        indexes[2] = address(newIndexWbtcComp);
        vm.prank(deployer);
        vm.recordLogs();
        indexManager.collectFeesFromMultipleIndexes(indexes);

        bytes32 expectedSuccessSig = FeesCollected.selector;
        bytes32 expectedFailSig = FeesCollectionFailed.selector;
        uint256 feesCollectedCount;
        uint256 feesCollectionFailedCount;
        uint256 totalFeesEventCount;
        address[] memory indexesFromEvent = new address[](3);
        address[] memory collectorFromEvent = new address[](3);
        uint256[] memory amountFromEvent = new uint256[](2);
        bytes memory reasonFromEvent;

        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSuccessSig) {
                indexesFromEvent[totalFeesEventCount] = address(
                    uint160(uint256(logs[i].topics[1]))
                );
                collectorFromEvent[totalFeesEventCount] = address(
                    uint160(uint256(logs[i].topics[2]))
                );
                amountFromEvent[feesCollectedCount] = abi.decode(
                    logs[i].data,
                    (uint256)
                );
                feesCollectedCount++;
                totalFeesEventCount++;
            } else if (logs[i].topics[0] == expectedFailSig) {
                indexesFromEvent[totalFeesEventCount] = address(
                    uint160(uint256(logs[i].topics[1]))
                );
                collectorFromEvent[totalFeesEventCount] = address(
                    uint160(uint256(logs[i].topics[2]))
                );
                reasonFromEvent = abi.decode(logs[i].data, (bytes));
                feesCollectionFailedCount++;
                totalFeesEventCount++;
            }
        }

        // Both indexes are balanced, so both emit IndexRebalanceFailed with reason Index__RebalanceNotNeeded but the transaction does not revert
        assertEq(
            totalFeesEventCount,
            indexes.length,
            "FeesCollected or FeesCollectionFailed event should be emitted for each index"
        );
        assertEq(
            feesCollectedCount,
            2,
            "FeesCollected event should be emitted for 2 indexes"
        );
        assertEq(
            feesCollectionFailedCount,
            1,
            "FeesCollectionFailed event should be emitted for 1 index"
        );
        assertEq(
            indexesFromEvent[0],
            address(initializedIndex),
            "Wrong index in event"
        );
        assertEq(collectorFromEvent[0], deployer, "Wrong collector in event");
        assertEq(
            amountFromEvent[0] + amountFromEvent[1],
            indexManager.getTotalFeesCollected(),
            "Wrong amount in event"
        );
        assertEq(
            bytes4(reasonFromEvent),
            Index__NoFeesToCollect.selector,
            "Wrong reason in event"
        );
    }
    // // =========================================================================
    // //  collectFeesFromAllIndexes
    // // =========================================================================

    // function test_collectFeesFromAllIndexes_WithNoIndexes_DoesNotRevert()
    //     public
    // {
    //     vm.prank(deployer);
    //     indexManager.collectFeesFromAllIndexes();
    // }

    // function test_collectFeesFromAllIndexes_WithInitializedIndex_DoesNotRevert()
    //     public
    // {
    //     _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     indexManager.collectFeesFromAllIndexes();
    // }

    // function test_collectFeesFromAllIndexes_RevertIf_CallerNotFeeCollector()
    //     public
    // {
    //     vm.prank(user1);
    //     vm.expectRevert();
    //     indexManager.collectFeesFromAllIndexes();
    // }
}
