// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute} from "../../../src/types.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
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
    IndexAsset wethAsset60;
    IndexAsset linkAsset40;

    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    // helpers
    // =========================================================================
    function _generateFees() internal {
        mockUsdc.mint(user3, 10000 * 10 ** 6);

        vm.startPrank(user1);
        mockUsdc.approve(address(router), type(uint256).max);
        mockUsdc.approve(address(initializedIndex), type(uint256).max);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            10000 * 10 ** 6,
            VALID_TOLERANCE
        );
        vm.stopPrank();
        vm.startPrank(user2);
        mockUsdc.approve(address(router), type(uint256).max);
        mockUsdc.approve(address(initializedIndex), type(uint256).max);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            10000 * 10 ** 6,
            VALID_TOLERANCE
        );
        vm.stopPrank();
        vm.startPrank(user3);
        mockUsdc.approve(address(router), type(uint256).max);
        mockUsdc.approve(address(initializedIndex), type(uint256).max);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            10000 * 10 ** 6,
            VALID_TOLERANCE
        );
        vm.stopPrank();
    }

    // =========================================================================
    //  retreiveAmountFromAmount
    // =========================================================================

    // @audit-issue testare la funzione

    // =========================================================================
    //  collectFees
    // =========================================================================

        function testCollectFeesRevertIfIndexNotInitialized() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IndexManager__NotIndexInitialized.selector, address(nonInitializedIndex)));
        indexManager.collectFeesFromSingleIndex(address(nonInitializedIndex));
    }

    function testCollectFeesRevertIfCallerNotFeeCollector() public {
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

    function testCollectFeesEmitNoFeesToCollectEvent() public {
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

        _generateFees();

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


    // function test_collectFees_IncreasesTotalFeesCollectedByFeesAmount() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();
    //     uint256 before = indexManager.getTotalFeesCollected();

    //     vm.prank(deployer);
    //     indexManager.collectFees(indexAddress);

    //     // With zero fees the value stays 0; assertGe documents the invariant.
    //     assertGe(indexManager.getTotalFeesCollected(), before);
    // }



    // // =========================================================================
    // //  collectFeesFromMultipleIndexes
    // // =========================================================================

    // function test_collectFeesFromMultipleIndexes_Succeeds() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();
    //     address[] memory indexes = new address[](1);
    //     indexes[0] = indexAddress;

    //     vm.prank(deployer);
    //     indexManager.collectFeesFromMultipleIndexes(indexes);
    // }

    // function test_collectFeesFromMultipleIndexes_AccumulatesTotalFeesCollected()
    //     public
    // {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();
    //     address[] memory indexes = new address[](1);
    //     indexes[0] = indexAddress;

    //     uint256 before = indexManager.getTotalFeesCollected();

    //     vm.prank(deployer);
    //     indexManager.collectFeesFromMultipleIndexes(indexes);

    //     assertGe(indexManager.getTotalFeesCollected(), before);
    // }

    // function test_collectFeesFromMultipleIndexes_RevertIf_AnyNotInitialized()
    //     public
    // {
    //     (address indexAddress, , ) = _createDefaultIndex();
    //     address[] memory indexes = new address[](1);
    //     indexes[0] = indexAddress;

    //     vm.prank(deployer);
    //     vm.expectRevert(IndexManager__NotIndexInitialized.selector);
    //     indexManager.collectFeesFromMultipleIndexes(indexes);
    // }

    // function test_collectFeesFromMultipleIndexes_RevertIf_CallerNotFeeCollector()
    //     public
    // {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();
    //     address[] memory indexes = new address[](1);
    //     indexes[0] = indexAddress;

    //     vm.prank(user1);
    //     vm.expectRevert();
    //     indexManager.collectFeesFromMultipleIndexes(indexes);
    // }

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

    // // =========================================================================
    // //  sortAssets
    // // =========================================================================

    // function test_sortAssets_SmallAddressBecomesToken0() public view {
    //     address small = address(1);
    //     address large = address(2);

    //     (address t0, address t1) = indexManager.sortAssets(small, large);

    //     assertEq(t0, small);
    //     assertEq(t1, large);
    // }

    // function test_sortAssets_LargeAddressFirstGetsReordered() public view {
    //     address small = address(1);
    //     address large = address(2);

    //     (address t0, address t1) = indexManager.sortAssets(large, small);

    //     assertEq(t0, small);
    //     assertEq(t1, large);
    // }

    // function test_sortAssets_BothOrdersProduceSameResult() public view {
    //     (address t0A, address t1A) = indexManager.sortAssets(
    //         address(mockWeth),
    //         address(mockLink)
    //     );
    //     (address t0B, address t1B) = indexManager.sortAssets(
    //         address(mockLink),
    //         address(mockWeth)
    //     );

    //     assertEq(t0A, t0B);
    //     assertEq(t1A, t1B);
    // }

    // function test_sortAssets_ResultIsAlwaysOrdered() public view {
    //     (address t0, address t1) = indexManager.sortAssets(
    //         address(mockWbtc),
    //         address(mockWeth)
    //     );

    //     assertTrue(t0 < t1);
    // }

    // // =========================================================================
    // //  Getter functions
    // // =========================================================================

    // function test_getUsdcAddress_MatchesMockUsdc() public view {
    //     assertEq(indexManager.getUsdcAddress(), address(mockUsdc));
    // }

    // function test_getRouterAddress_MatchesDeployedRouter() public view {
    //     assertEq(indexManager.getRouterAddress(), address(router));
    // }

    // function test_getSwapManagerAddress_MatchesDeployedSwapManager()
    //     public
    //     view
    // {
    //     assertEq(indexManager.getSwapManagerAddress(), address(swapManager));
    // }

    // function test_getAllIndexes_IsEmptyOnDeploy() public view {
    //     assertEq(indexManager.getAllIndexes().length, 0);
    // }

    // function test_getAllIndexes_ReturnsOneAfterOneCreate() public {
    //     _createDefaultIndex();
    //     assertEq(indexManager.getAllIndexes().length, 1);
    // }

    // function test_getAllIndexes_ReturnsTwoAfterTwoCreates() public {
    //     _createDefaultIndex(); // WETH / LINK

    //     IndexAsset memory wethAsset = IndexAsset({
    //         asset: address(mockWeth),
    //         weightPercentage: WEIGHT_50,
    //         priceFeed: address(mockWethPriceFeed)
    //     });
    //     IndexAsset memory wbtcAsset = IndexAsset({
    //         asset: address(mockWbtc),
    //         weightPercentage: WEIGHT_50,
    //         priceFeed: address(mockWbtcPriceFeed)
    //     });

    //     vm.prank(deployer);
    //     indexManager.createIndex(DEFAULT_FEE, wethAsset, wbtcAsset);

    //     assertEq(indexManager.getAllIndexes().length, 2);
    // }

    // // function test_isIndexAddress_ReturnsFalse_ForUnknownAddress() public view {
    // //     assertFalse(indexManager.isIndexAddress(makeAddr("unknown")));
    // // }

    // function test_isIndexAddress_ReturnsTrue_AfterCreateIndex() public {
    //     (address indexAddress, , ) = _createDefaultIndex();
    //     assertTrue(indexManager.isIndexAddress(indexAddress));
    // }

    // function test_checkIsIndexInitialized_ReturnsFalse_BeforeInitialize()
    //     public
    // {
    //     (address indexAddress, , ) = _createDefaultIndex();
    //     assertFalse(indexManager.checkIsIndexInitialized(indexAddress));
    // }

    // function test_checkIsIndexInitialized_ReturnsTrue_AfterInitialize() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();
    //     assertTrue(indexManager.checkIsIndexInitialized(indexAddress));
    // }

    // function test_getIndexByAssetsAddresses_ReturnsZero_WhenPairDoesNotExist()
    //     public
    //     view
    // {
    //     assertEq(
    //         indexManager.getIndexByAssetsAddresses(
    //             address(mockWeth),
    //             address(mockLink)
    //         ),
    //         address(0)
    //     );
    // }

    // function test_getIndexByAssetsAddresses_ReturnsCorrectAddress_DirectOrder()
    //     public
    // {
    //     (address indexAddress, , ) = _createDefaultIndex();

    //     assertEq(
    //         indexManager.getIndexByAssetsAddresses(
    //             address(mockWeth),
    //             address(mockLink)
    //         ),
    //         indexAddress
    //     );
    // }

    // function test_getIndexByAssetsAddresses_ReturnsCorrectAddress_ReverseOrder()
    //     public
    // {
    //     (address indexAddress, , ) = _createDefaultIndex();

    //     assertEq(
    //         indexManager.getIndexByAssetsAddresses(
    //             address(mockLink),
    //             address(mockWeth)
    //         ),
    //         indexAddress
    //     );
    // }

    // function test_getTotalFeesCollected_IsZeroOnDeploy() public view {
    //     assertEq(indexManager.getTotalFeesCollected(), 0);
    // }

    // function test_getTotalFeesCollected_RemainsZeroWhenNoFeesAccrued() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     indexManager.collectFees(indexAddress);

    //     assertEq(indexManager.getTotalFeesCollected(), 0);
    // }
}
