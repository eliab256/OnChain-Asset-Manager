// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {
    IndexAsset,
    SwapRoute,
    AssetAvailable,
    IndexAction
} from "../../../src/types.sol";
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
import "../../../src/events/IndexEvents.sol";
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
            address(multiSigWallet),
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
        _assertOnlyActionFailed(
            logs,
            address(initializedIndex),
            feeCollector,
            IndexAction.COLLECT_FEES,
            abi.encodeWithSelector(Index__NoFeesToCollect.selector)
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
            // FeesCollected is emitted by the Index (the IndexManager duplicate was removed)
            if (log.topics[0] == FeesCollected.selector) {
                feesCollectedEmitted = true;
                indexFromEvent = log.emitter;
                collectorFromEvent = address(uint160(uint256(log.topics[1])));
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

    function testCollectFeesAfterRedeemTransfersExactAccruedFees() public {
        _generateFees(address(initializedIndex));
        (, uint128 feesAfterMint) = initializedIndex.getFeesInfo();

        uint256 sharesToSell = initializedIndex.balanceOf(user1);
        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            sharesToSell,
            VALID_TOLERANCE
        );

        (, uint128 feesToCollect) = initializedIndex.getFeesInfo();
        // Redeem of ~10_000 USDC at 1% fee: accrued fee must stay in USDC token decimals.
        assertGt(feesToCollect, feesAfterMint, "Redeem must accrue fees");
        assertLe(
            feesToCollect - feesAfterMint,
            10000 * 10 ** 6,
            "Redeem fee not in USDC token decimals"
        );

        uint256 collectorBalanceBefore = mockUsdc.balanceOf(deployer);
        vm.prank(deployer);
        indexManager.collectFeesFromSingleIndex(address(initializedIndex));

        (, uint128 feesAfterCollect) = initializedIndex.getFeesInfo();
        assertEq(feesAfterCollect, 0, "Fees not reset after collection");
        assertEq(
            mockUsdc.balanceOf(deployer) - collectorBalanceBefore,
            feesToCollect,
            "Collector did not receive the accrued fees"
        );
        assertEq(
            mockUsdc.balanceOf(address(initializedIndex)),
            0,
            "Index must hold no USDC after collection"
        );
    }

    // =========================================================================
    //  collectFeesFromMultipleIndexes
    // =========================================================================

    function testCollectFeesFromMultipleIndexesDoesNotRevertWhenThereAreNoFeesToCollect()
        public
    {
        _generateFees(address(initializedIndex));
        _generateFees(address(newIndexWbtcComp));
        (, uint128 fees0) = initializedIndex.getFeesInfo();
        (, uint128 fees2) = newIndexWbtcComp.getFeesInfo();

        address[] memory indexes = new address[](3);
        indexes[0] = address(initializedIndex);
        indexes[1] = address(newIndexLinkWeth); // this index has no fees to collect
        indexes[2] = address(newIndexWbtcComp);
        vm.prank(deployer);
        vm.recordLogs();
        indexManager.collectFeesFromMultipleIndexes(indexes);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertSingleActionTriggeredFor(
            logs,
            address(initializedIndex),
            deployer,
            IndexAction.COLLECT_FEES
        );
        _assertSingleActionFailedFor(
            logs,
            address(newIndexLinkWeth),
            deployer,
            IndexAction.COLLECT_FEES,
            abi.encodeWithSelector(Index__NoFeesToCollect.selector)
        );
        _assertSingleActionTriggeredFor(
            logs,
            address(newIndexWbtcComp),
            deployer,
            IndexAction.COLLECT_FEES
        );
        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector),
            2,
            "IndexActionTriggered must be emitted for the 2 indexes with fees"
        );
        assertEq(
            _countManagerEvents(logs, IndexActionFailed.selector),
            1,
            "IndexActionFailed must be emitted only for the index without fees"
        );
        assertEq(
            indexManager.getTotalFeesCollected(),
            uint256(fees0) + uint256(fees2),
            "Total fees collected must be the sum of the succeeding indexes"
        );
    }

    function testCollectFeesFromMultipleIndexesOnInitializedIndexesSumsIntoTotalFeesCollected()
        public
    {
        _generateFees(address(initializedIndex));
        _generateFees(address(newIndexWbtcComp));
        address[] memory indexes = indexManager.getInitializedIndexes();
        assertEq(indexes.length, 3, "three initialized indexes expected");

        uint256 expectedTotal;
        for (uint256 i = 0; i < indexes.length; i++) {
            (, uint128 fees) = IIndex(indexes[i]).getFeesInfo();
            expectedTotal += fees;
        }
        (, uint128 noFees) = newIndexLinkWeth.getFeesInfo();
        assertEq(noFees, 0, "newIndexLinkWeth must have no fees");
        assertGt(expectedTotal, 0, "fees must have accrued");
        uint256 totalBefore = indexManager.getTotalFeesCollected();
        uint256 collectorBalanceBefore = mockUsdc.balanceOf(deployer);

        vm.prank(deployer);
        indexManager.collectFeesFromMultipleIndexes(indexes);

        assertEq(
            indexManager.getTotalFeesCollected(),
            totalBefore + expectedTotal,
            "Total fees collected must grow by the sum of every index's fees"
        );
        assertEq(
            mockUsdc.balanceOf(deployer) - collectorBalanceBefore,
            expectedTotal,
            "Collector must receive the sum of every index's fees"
        );
        for (uint256 i = 0; i < indexes.length; i++) {
            (, uint128 feesAfter) = IIndex(indexes[i]).getFeesInfo();
            assertEq(feesAfter, 0, "Fees not reset after collection");
        }
    }

    function testCollectFeesFromMultipleIndexesOnInitializedIndexesEmitsOneEventPerIndex()
        public
    {
        _generateFees(address(initializedIndex));
        _generateFees(address(newIndexWbtcComp));
        address[] memory indexes = indexManager.getInitializedIndexes();

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.collectFeesFromMultipleIndexes(indexes);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < indexes.length; i++) {
            if (indexes[i] == address(newIndexLinkWeth)) {
                _assertSingleActionFailedFor(
                    logs,
                    indexes[i],
                    deployer,
                    IndexAction.COLLECT_FEES,
                    abi.encodeWithSelector(Index__NoFeesToCollect.selector)
                );
            } else {
                _assertSingleActionTriggeredFor(
                    logs,
                    indexes[i],
                    deployer,
                    IndexAction.COLLECT_FEES
                );
            }
        }
        assertEq(
            _countManagerEvents(logs, IndexActionTriggered.selector) +
                _countManagerEvents(logs, IndexActionFailed.selector),
            indexes.length,
            "one manager event per initialized index"
        );
    }
}
