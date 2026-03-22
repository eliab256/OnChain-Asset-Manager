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

import "../../../src/errors/IndexManagerErrors.sol";
import "../../../src/events/IndexManagerEvents.sol";
import "../../../src/errors/IndexErrors.sol";

contract IndexManagerTest is BaseTest {
    IndexAsset wethAsset60;
    IndexAsset linkAsset40;

    function setUp() public override {
        super.setUp();
    }

    function _createDefaultIndex(
        address _assetA,
        address _assetB,
        address _priceFeedA,
        address _priceFeedB
    ) internal returns (address indexAddress, address token0, address token1) {
        IndexAsset memory assetA = IndexAsset({
            asset: _assetA,
            weightPercentage: weight60,
            priceFeed: _priceFeedA
        });
        IndexAsset memory assetB = IndexAsset({
            asset: _assetB,
            weightPercentage: weight40,
            priceFeed: _priceFeedB
        });

        vm.prank(deployer);
        (indexAddress, token0, token1) = indexManager.createIndex(
            validFeePercentage,
            assetA,
            assetB
        );
    }

    /**
     * @dev Creates AND initialises the default WETH/LINK index.
     *
     *      Index.initialize transfers assets FROM IndexManager, so we must:
     *        1. deal() → give IndexManager a balance of both assets.
     *        2. vm.prank(indexManager) + approve → allow the Index contract to
     *           pull those tokens from IndexManager via safeTransferFrom.
     *
     *      Amount rationale (50/50, WETH at 2000, LINK at 7):
     *        initAmount0 = 1e18 WETH  → USD value = 2 000e18
     *        initAmount1 ≈ 285.7e18 LINK → USD value ≈ 2 000e18
     */
    function _createAndInitializeDefaultIndex(
        address _assetA,
        address _assetB,
        address _priceFeedA,
        address _priceFeedB
    ) internal returns (address indexAddress, address token0, address token1) {
        (indexAddress, token0, token1) = _createDefaultIndex(
            _assetA,
            _assetB,
            _priceFeedA,
            _priceFeedB
        );

        uint256 initAmount = 1e18; // 1 unit of token0 in 18-decimal standard

        // Fund IndexManager with plenty of both assets.
        deal(token0, address(indexManager), initAmount * 10);
        deal(token1, address(indexManager), 10_000e18); // ~285 LINK needed

        // Grant Index an allowance to pull from IndexManager.
        vm.prank(address(indexManager));
        IERC20(token0).approve(indexAddress, type(uint256).max);
        vm.prank(address(indexManager));
        IERC20(token1).approve(indexAddress, type(uint256).max);

        (
            SwapRoute memory r0,
            SwapRoute memory r1,
            SwapRoute memory r01
        ) = helperConfig.getDefaultSwapRoutes(token0, token1);

        vm.prank(deployer);
        indexManager.initializeIndex(
            msg.sender,
            indexAddress,
            initAmount,
            r0,
            r1,
            r01
        );
    }



    // =========================================================================
    //  retreiveAmountFromAmount
    // =========================================================================

    // @audit-issue testare la funzione

    // =========================================================================
    //  rebalanceSingleIndex
    // =========================================================================

    function testRebalanceSingleIndexRevertIfIndexNotInitialized() public {
        vm.prank(deployer);
        vm.expectRevert(IndexManager__NotIndexInitialized.selector);
        indexManager.rebalanceSingleIndex(address(nonInitializedIndex));
    }

    function testRebalanceSingleIndexRevertIfCallerNotRebalancer() public {
        vm.prank(user1);
        vm.expectRevert();
        indexManager.rebalanceSingleIndex(address(nonInitializedIndex));
    }

    function testRebalanceIndexEmitsIndexRebalanceFailedWhenBalanced() public {
        // index is already initialized in Base.setUp() and is balanced,
        // so we can directly call rebalanceIndex without setup here.

        vm.prank(deployer);
        vm.expectEmit(true, false, false, true);
        emit IndexRebalanceFailed(
            address(initializedIndex),
            abi.encodePacked(Index__RebalanceNotNeeded.selector)
        );
        indexManager.rebalanceSingleIndex(address(initializedIndex));
    }

    // function testRebalanceIndexEmitsIndexRebalanceWhenBalancedSuccessfully()
    //     public
    // {

    //     // change price of unerlying assets to make index unbalanced and trigger rebalance logic
    //     vm.warp(block.timestamp + 3600);
    //     _refreshPriceFeeds();
    //     mockWethPriceFeed.updateAnswer(WETH_INITIAL_PRICE * 6);
    //     console2.log("WETH price updated to:", mockWethPriceFeed.latestAnswer());
    //     console2.log("WBTC price is:        ", mockWbtcPriceFeed.latestAnswer());
    //     (uint256 target0, ) = initializedIndex
    //         .getAssetsEffectiveWeights();
    //     (uint256 effective0, ) = initializedIndex.getAssetsEffectiveWeights();
    //     bool rebalanceNeeded = effective0 > target0
    //         ? (effective0 - target0) > REBALANCE_THRESHOLD
    //         : (target0 - effective0) > REBALANCE_THRESHOLD;

    //     assertTrue(rebalanceNeeded, "rebalance not needed with current prices");

    //     vm.prank(deployer);
    //     vm.expectEmit(true, true, false, false);
    //     emit IndexRebalanced(
    //         address(initializedIndex),
    //         deployer
    //         //abi.encodePacked(IndexRebalanced.selector)
    //     );
    //     indexManager.rebalanceSingleIndex(address(initializedIndex));
    // }

    // // =========================================================================
    // //  rebalanceMultipleIndexes
    // // =========================================================================

    // function test_rebalanceMultipleIndexes_RevertIf_AnyIndexNotInitialized()
    //     public
    // {
    //     (address indexAddress, , ) = _createDefaultIndex();
    //     address[] memory indexes = new address[](1);
    //     indexes[0] = indexAddress;

    //     vm.prank(deployer);
    //     vm.expectRevert(IndexManager__NotIndexInitialized.selector);
    //     indexManager.rebalanceMultipleIndexes(indexes);
    // }

    // function test_rebalanceMultipleIndexes_DoesNotRevert_WhenIndexIsBalanced()
    //     public
    // {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();
    //     address[] memory indexes = new address[](1);
    //     indexes[0] = indexAddress;

    //     // Emits IndexRebalanceFailed for the balanced index, no revert.
    //     vm.prank(deployer);
    //     indexManager.rebalanceMultipleIndexes(indexes);
    // }

    // function test_rebalanceMultipleIndexes_RevertIf_CallerNotRebalancer()
    //     public
    // {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();
    //     address[] memory indexes = new address[](1);
    //     indexes[0] = indexAddress;

    //     vm.prank(user1);
    //     vm.expectRevert();
    //     indexManager.rebalanceMultipleIndexes(indexes);
    // }

    // // =========================================================================
    // //  rebalanceAllIndexes
    // // =========================================================================

    // function test_rebalanceAllIndexes_WithNoIndexes_DoesNotRevert() public {
    //     vm.prank(deployer);
    //     indexManager.rebalanceAllIndexes();
    // }

    // function test_rebalanceAllIndexes_WithInitializedIndex_DoesNotRevert()
    //     public
    // {
    //     _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     indexManager.rebalanceAllIndexes();
    // }

    // function test_rebalanceAllIndexes_RevertIf_CallerNotRebalancer() public {
    //     vm.prank(user1);
    //     vm.expectRevert();
    //     indexManager.rebalanceAllIndexes();
    // }

    // // =========================================================================
    // //  proposeNewWeights
    // // =========================================================================

    // function test_proposeNewWeights_EmitsNewIndexWeightsProposedEvent() public {
    //     uint128 expectedNewWeight1 = MAX_WEIGHT - weight30;
    //     (uint128 lastWeight0, uint128 lastWeight1) = initializedIndex.getAssetsWeights();
    //     // checkData = false because implementationTimestamp is block-dependent.
    //     vm.expectEmit(true, true, false, false);
    //     emit NewIndexWeightsProposed(
    //         address(initializedIndex),
    //         deployer,
    //         lastWeight0,
    //         lastWeight1,
    //         weight30,
    //         expectedNewWeight1,
    //         block.timestamp + WEIGHT_UPDATE_DELAY
    //     );

    //     vm.prank(deployer);
    //     indexManager.proposeNewWeights(address(initializedIndex), weight30);

    //     (uint128 previousWeight0, uint128 previousWeight1) = initializedIndex.getAssetsWeights();
    //     (uint128 pendingWeight0, uint128 pendingWeight1, uint256 weightUpdateExecutableAt) = initializedIndex.getAssetsPendingWeights();
    //     assertEq(pendingWeight0, weight30);
    //     assertEq(pendingWeight1, expectedNewWeight1);
    //     assertEq(previousWeight0, previousWeight0);
    //     assertEq(previousWeight1, previousWeight1);
    //     assertEq(weightUpdateExecutableAt, block.timestamp + WEIGHT_UPDATE_DELAY);
    // }

    // function test_proposeNewWeights_AcceptsLowerBoundaryWeight() public {
    //     // Lower boundary: 500_000 - 30_000 = 470_000
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     indexManager.proposeNewWeights(indexAddress, 470_000);
    // }

    // function test_proposeNewWeights_AcceptsUpperBoundaryWeight() public {
    //     // Upper boundary: 500_000 + 30_000 = 530_000
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     indexManager.proposeNewWeights(indexAddress, 530_000);
    // }

    // function test_proposeNewWeights_RevertIf_IndexNotInitialized() public {
    //     (address indexAddress, , ) = _createDefaultIndex();

    //     vm.prank(deployer);
    //     vm.expectRevert(IndexManager__NotIndexInitialized.selector);
    //     indexManager.proposeNewWeights(indexAddress, VALID_NEW_WEIGHT);
    // }

    // function test_proposeNewWeights_RevertIf_WeightExceedsMaxPercentage()
    //     public
    // {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     vm.expectRevert(IndexManager__InvalidPercentage.selector);
    //     indexManager.proposeNewWeights(indexAddress, 1_000_001);
    // }

    // function test_proposeNewWeights_RevertIf_WeightAboveThreshold() public {
    //     // 530_001 > 500_000 + 30_000 → Index__InvalidWeight (bubbles up)
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     vm.expectRevert();
    //     indexManager.proposeNewWeights(indexAddress, 530_001);
    // }

    // function test_proposeNewWeights_RevertIf_WeightBelowThreshold() public {
    //     // 469_999 + 30_000 < 500_000 → Index__InvalidWeight (bubbles up)
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     vm.expectRevert();
    //     indexManager.proposeNewWeights(indexAddress, 469_999);
    // }

    // function test_proposeNewWeights_RevertIf_WeightIsZero() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     vm.expectRevert();
    //     indexManager.proposeNewWeights(indexAddress, 0);
    // }

    // function test_proposeNewWeights_RevertIf_PreviousPendingUpdateNotExecuted()
    //     public
    // {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     indexManager.proposeNewWeights(indexAddress, VALID_NEW_WEIGHT);

    //     // A second proposal while the first is still pending must revert.
    //     vm.prank(deployer);
    //     vm.expectRevert();
    //     indexManager.proposeNewWeights(indexAddress, VALID_NEW_WEIGHT);
    // }

    // function test_proposeNewWeights_RevertIf_CallerNotAssetManager() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(user1);
    //     vm.expectRevert();
    //     indexManager.proposeNewWeights(indexAddress, VALID_NEW_WEIGHT);
    // }

    // // =========================================================================
    // //  executeWeightUpdate
    // // =========================================================================

    // function test_executeWeightUpdate_RevertIf_IndexNotInitialized() public {
    //     (address indexAddress, , ) = _createDefaultIndex();

    //     vm.prank(deployer);
    //     vm.expectRevert(IndexManager__NotIndexInitialized.selector);
    //     indexManager.executeWeightUpdate(indexAddress);
    // }

    // function test_executeWeightUpdate_EmitsWeightUpdateFailed_WhenNoPendingUpdate()
    //     public
    // {
    //     // No proposal → Index.executeWeightUpdate reverts.
    //     // IndexManager catches it and emits WeightUpdateFailed — no revert.
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     vm.expectEmit(true, false, false, false);
    //     emit WeightUpdateFailed(indexAddress, "");
    //     indexManager.executeWeightUpdate(indexAddress);
    // }

    // function test_executeWeightUpdate_EmitsWeightUpdateFailed_WhenExecutedTooEarly()
    //     public
    // {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     indexManager.proposeNewWeights(indexAddress, VALID_NEW_WEIGHT);

    //     // Attempt execution before WEIGHT_UPDATE_DELAY (2 days) has elapsed.
    //     vm.prank(deployer);
    //     vm.expectEmit(true, false, false, false);
    //     emit WeightUpdateFailed(indexAddress, "");
    //     indexManager.executeWeightUpdate(indexAddress);
    // }

    // function test_executeWeightUpdate_DoesNotRevert_AfterDelay() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     indexManager.proposeNewWeights(indexAddress, VALID_NEW_WEIGHT);

    //     // Advance past the 2-day delay and refresh price feeds to avoid staleness.
    //     vm.warp(block.timestamp + 2 days + 1);
    //     _refreshPriceFeeds();

    //     // The rebalance swap fails (no Uniswap router on Anvil), but IndexManager
    //     // catches the error via try/catch — no revert.
    //     vm.prank(deployer);
    //     indexManager.executeWeightUpdate(indexAddress);
    // }

    // function test_executeWeightUpdate_RevertIf_CallerNotAssetManager() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(user1);
    //     vm.expectRevert();
    //     indexManager.executeWeightUpdate(indexAddress);
    // }

    // // =========================================================================
    // //  executeWeightUpdateForMultipleIndexes
    // // =========================================================================

    // function test_executeWeightUpdateForMultipleIndexes_RevertIf_AnyNotInitialized()
    //     public
    // {
    //     (address indexAddress, , ) = _createDefaultIndex();
    //     address[] memory indexes = new address[](1);
    //     indexes[0] = indexAddress;

    //     vm.prank(deployer);
    //     vm.expectRevert(IndexManager__NotIndexInitialized.selector);
    //     indexManager.executeWeightUpdateForMultipleIndexes(indexes);
    // }

    // function test_executeWeightUpdateForMultipleIndexes_DoesNotRevert_WithNoPending()
    //     public
    // {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();
    //     address[] memory indexes = new address[](1);
    //     indexes[0] = indexAddress;

    //     // No pending update → WeightUpdateFailed is emitted, no revert.
    //     vm.prank(deployer);
    //     indexManager.executeWeightUpdateForMultipleIndexes(indexes);
    // }

    // function test_executeWeightUpdateForMultipleIndexes_RevertIf_CallerNotAssetManager()
    //     public
    // {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();
    //     address[] memory indexes = new address[](1);
    //     indexes[0] = indexAddress;

    //     vm.prank(user1);
    //     vm.expectRevert();
    //     indexManager.executeWeightUpdateForMultipleIndexes(indexes);
    // }

    // // =========================================================================
    // //  executeWeightUpdateForAllIndexes
    // // =========================================================================

    // function test_executeWeightUpdateForAllIndexes_WithNoIndexes_DoesNotRevert()
    //     public
    // {
    //     vm.prank(deployer);
    //     indexManager.executeWeightUpdateForAllIndexes();
    // }

    // function test_executeWeightUpdateForAllIndexes_WithInitializedIndex_DoesNotRevert()
    //     public
    // {
    //     _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     indexManager.executeWeightUpdateForAllIndexes();
    // }

    // function test_executeWeightUpdateForAllIndexes_RevertIf_CallerNotAssetManager()
    //     public
    // {
    //     vm.prank(user1);
    //     vm.expectRevert();
    //     indexManager.executeWeightUpdateForAllIndexes();
    // }

    // // =========================================================================
    // //  collectFees
    // // =========================================================================

    // function test_collectFees_SucceedsWhenZeroFeesAccrued() public {
    //     // s_totalFees == 0; Index.collectFees transfers 0 USDC → should not revert.
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     indexManager.collectFees(indexAddress);
    // }

    // function test_collectFees_EmitsFeesCollectedEvent() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.expectEmit(true, true, true, true, address(indexManager));
    //     emit FeesCollected(indexAddress, deployer, 0);

    //     vm.prank(deployer);
    //     indexManager.collectFees(indexAddress);
    // }

    // function test_collectFees_IncreasesTotalFeesCollectedByFeesAmount() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();
    //     uint256 before = indexManager.getTotalFeesCollected();

    //     vm.prank(deployer);
    //     indexManager.collectFees(indexAddress);

    //     // With zero fees the value stays 0; assertGe documents the invariant.
    //     assertGe(indexManager.getTotalFeesCollected(), before);
    // }

    // function test_collectFees_RevertIf_IndexNotInitialized() public {
    //     (address indexAddress, , ) = _createDefaultIndex();

    //     vm.prank(deployer);
    //     vm.expectRevert(IndexManager__NotIndexInitialized.selector);
    //     indexManager.collectFees(indexAddress);
    // }

    // function test_collectFees_RevertIf_CallerNotFeeCollector() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(user1);
    //     vm.expectRevert();
    //     indexManager.collectFees(indexAddress);
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
