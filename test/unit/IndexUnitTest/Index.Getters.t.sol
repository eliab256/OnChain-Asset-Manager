//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import "../../../src/errors/IndexErrors.sol";

contract IndexGettersTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testGetLatestPriceReturnsCorrectPriceForAsset0() public view {
        uint256 price = initializedIndex.getLatestPrice(address(mockWeth));
        uint256 expectedPrice = uint256(WETH_INITIAL_PRICE) * 1e10; // 8 -> 18 decimals
        assertEq(price, expectedPrice);
    }

    function testGetLatestPriceReturnsCorrectPriceForAsset1() public view {
        uint256 price = initializedIndex.getLatestPrice(address(mockWbtc));
        uint256 expectedPrice = uint256(WBTC_INITIAL_PRICE) * 1e10; // 8 -> 18 decimals
        assertEq(price, expectedPrice);
    }

    function testGetLatestPriceReturnsCorrectPriceForUsdc() public view {
        uint256 price = initializedIndex.getLatestPrice(address(mockUsdc));
        uint256 expectedPrice = uint256(USDC_INITIAL_PRICE) * 1e10; // 8 -> 18 decimals
        assertEq(price, expectedPrice);
    }

    function testGetLatestPriceRevertIfAssetNotSupported() public {
        // LINK is not supported
        vm.expectRevert(Index__AssetNotSupported.selector);
        initializedIndex.getLatestPrice(address(mockLink));
    }

    function testGetLatestPriceRevertIfPriceIsStale() public {
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(Index__PriceIsStale.selector);
        initializedIndex.getLatestPrice(address(mockWeth));
    }

    function testGetLatestPriceRevertIfAnswerIsZero() public {
        mockWethPriceFeed.updateAnswer(0);

        vm.expectRevert(Index__PriceFeedNotAvailable.selector);
        initializedIndex.getLatestPrice(address(mockWeth));
    }

    function testGetLatestPriceRevertIfAnswerIsNegative() public {
        mockWethPriceFeed.updateAnswer(-1);

        vm.expectRevert(Index__PriceFeedNotAvailable.selector);
        initializedIndex.getLatestPrice(address(mockWeth));
    }

    function testGetLatestPriceReflectsUpdatedFeedValue() public {
        // Aggiorniamo il prezzo WETH a $5 000 e verifichiamo che il getter lo restituisca
        mockWethPriceFeed.updateAnswer(5_000 * 10 ** 8);

        uint256 price = initializedIndex.getLatestPrice(address(mockWeth));
        assertEq(price, 5_000e18);
    }

    // =========================================================================
    //  getAssetsUsdValue
    // =========================================================================

    function testGetAssetsUsdValueReturnsNonZeroValuesForInitializedIndex()
        public
        view
    {
        (uint256 v0, uint256 v1, uint256 total) = initializedIndex
            .getAssetsUsdValue();

        assertGt(v0, 0, "asset0 USD value  must be > 0");
        assertGt(v1, 0, "asset1 USD value must be > 0");
        assertEq(total, v0 + v1, "total must be the sum of v0 and v1");
    }

    function testGetAssetsUsdValueTotalEqualsSum() public view {
        (uint256 v0, uint256 v1, uint256 total) = initializedIndex
            .getAssetsUsdValue();
        assertEq(total, v0 + v1);
    }

    function testGetAssetsUsdValueReflectsAsset0PriceChange() public {
        (, , uint256 totalBefore) = initializedIndex.getAssetsUsdValue();

        int256 priceMultiplier = 2;
        mockWethPriceFeed.updateAnswer(WETH_INITIAL_PRICE * priceMultiplier);
        mockWbtcPriceFeed.updateAnswer(WBTC_INITIAL_PRICE * priceMultiplier);

        (, , uint256 totalAfter) = initializedIndex.getAssetsUsdValue();
        assertEq(
            totalAfter,
            totalBefore * uint256(priceMultiplier),
            "total USD must increase with price"
        );
    }

    function testGetAssetsUsdValueReflectsAsset1PriceChange() public {
        (uint256 v0Before, uint256 v1Before, ) = initializedIndex
            .getAssetsUsdValue();

        int256 priceMultiplier = 2;
        mockWbtcPriceFeed.updateAnswer(WBTC_INITIAL_PRICE * priceMultiplier);
        mockWethPriceFeed.updateAnswer(
            WETH_INITIAL_PRICE * (priceMultiplier + 1)
        );

        (uint256 v0After, uint256 v1After, ) = initializedIndex
            .getAssetsUsdValue();

        assertEq(
            v0After,
            v0Before * uint256(priceMultiplier + 1),
            "asset0 USD should not change with asset1 price change"
        );

        assertEq(
            v1After,
            v1Before * uint256(priceMultiplier),
            "asset1 USD should double with 2x price change"
        );
    }

    function testGetAssetsUsdValueAsset0IsHigherForHigherWeightIndex()
        public
        view
    {
        (uint256 v0, uint256 v1, uint256 total) = initializedIndex
            .getAssetsUsdValue();

        uint256 effectiveWeight0 = (v0 * MAX_PERCENTAGE) / total;
        uint256 target = weight60; // 600_000
        uint256 tolerance = REBALANCE_THRESHOLD; // 30_000

        assertApproxEqAbs(
            effectiveWeight0,
            target,
            tolerance,
            "effective weight of asset0 should be close to 60%"
        );
    }

    // =========================================================================
    //  getAssetsEffectiveWeights
    // =========================================================================

    function testGetAssetsEffectiveWeightsSumToMaxPercentage() public view {
        (uint256 eff0, uint256 eff1) = initializedIndex
            .getAssetsEffectiveWeights();
        assertEq(
            eff0 + eff1,
            MAX_PERCENTAGE,
            "effective weights should sum to MAX_PERCENTAGE"
        );
    }

    function testGetAssetsEffectiveWeightsAreNonZero() public view {
        (uint256 eff0, uint256 eff1) = initializedIndex
            .getAssetsEffectiveWeights();
        assertGt(eff0, 0);
        assertGt(eff1, 0);
    }

    function testGetAssetsEffectiveWeightsReflectTargetWeightsAfterInit()
        public
        view
    {
        (uint256 eff0, uint256 eff1) = initializedIndex
            .getAssetsEffectiveWeights();

        assertApproxEqAbs(eff0, weight60, REBALANCE_THRESHOLD);
        assertApproxEqAbs(eff1, weight40, REBALANCE_THRESHOLD);
    }

    function testGetAssetsEffectiveWeightsChangeAfterPriceShift() public {
        (uint256 eff0Before, ) = initializedIndex.getAssetsEffectiveWeights();

        mockWethPriceFeed.updateAnswer(WETH_INITIAL_PRICE * 3);

        (uint256 eff0After, ) = initializedIndex.getAssetsEffectiveWeights();
        assertGt(
            eff0After,
            eff0Before,
            "asset0 effective weight should increase"
        );
    }

    // =========================================================================
    //  getAssetsAndUsdcDecimals
    // =========================================================================

    function testGetAssetsAndUsdcDecimalsMatchMockDecimals() public view {
        (uint8 dec0, uint8 dec1, uint8 decUsdc) = initializedIndex
            .getAssetsAndUsdcDecimals();

        assertEq(
            dec0,
            mockWeth.decimals(),
            "asset0 decimals should match WETH"
        );
        assertEq(
            dec1,
            mockWbtc.decimals(),
            "asset1 decimals should match WBTC"
        );
        assertEq(decUsdc, mockUsdc.decimals(), "USDC decimals should match");
    }

    function testGetAssetsAndUsdcDecimalsNonInitializedIndex() public view {
        (uint8 dec0, uint8 dec1, uint8 decUsdc) = nonInitializedIndex
            .getAssetsAndUsdcDecimals();

        assertEq(dec0, mockWbtc.decimals()); // 8
        assertEq(dec1, mockLink.decimals()); // 18
        assertEq(decUsdc, mockUsdc.decimals()); // 6
    }

    function testGetAssetsAndUsdcDecimalsReturnExpectedValues() public view {
        (uint8 dec0, uint8 dec1, uint8 decUsdc) = initializedIndex
            .getAssetsAndUsdcDecimals();

        assertEq(dec0, 18); // WETH
        assertEq(dec1, 8); // WBTC
        assertEq(decUsdc, 6); // USDC
    }

    // =========================================================================
    //  getAssetsWeights
    // =========================================================================

    function testGetAssetsWeightsReturnTargetWeightsSetAtDeployment()
        public
        view
    {
        // initializedIndex: 60% WETH / 40% WBTC
        (uint128 w0, uint128 w1) = initializedIndex.getAssetsWeights();
        assertEq(w0, weight60, "asset0 weight should be 60%");
        assertEq(w1, weight40, "asset1 weight should be 40%");
    }

    function testGetAssetsWeightsSumToMaxWeight() public view {
        (uint128 w0, uint128 w1) = initializedIndex.getAssetsWeights();
        assertEq(
            uint256(w0) + uint256(w1),
            uint256(MAX_WEIGHT),
            "weights should sum to MAX_WEIGHT"
        );
    }

    function testGetAssetsWeightsNonInitializedIndexReturnCorrectValues()
        public
        view
    {
        // nonInitializedIndex: 40% WBTC / 60% LINK
        (uint128 w0, uint128 w1) = nonInitializedIndex.getAssetsWeights();
        assertEq(w0, weight40);
        assertEq(w1, weight60);
    }

    function testGetAssetsWeightsDoNotChangeWithPriceMovements() public {
        (uint128 w0Before, uint128 w1Before) = initializedIndex
            .getAssetsWeights();

        // Cambiamo drasticamente i prezzi: i target weights non devono cambiare
        mockWethPriceFeed.updateAnswer(WETH_INITIAL_PRICE * 10);
        mockWbtcPriceFeed.updateAnswer(WBTC_INITIAL_PRICE / 2);

        (uint128 w0After, uint128 w1After) = initializedIndex
            .getAssetsWeights();
        assertEq(w0After, w0Before, "target weight0 should not change");
        assertEq(w1After, w1Before, "target weight1 should not change");
    }

    // =========================================================================
    //  getAssetsPendingWeights
    // =========================================================================

    function testGetAssetsPendingWeightsAreZeroBeforeAnyProposal() public view {
        (uint128 p0, uint128 p1, uint256 execAt) = initializedIndex
            .getAssetsPendingWeights();
        assertEq(p0, 0, "pendingWeight0 should be 0 before any proposal");
        assertEq(p1, 0, "pendingWeight1 should be 0 before any proposal");
        assertEq(execAt, 0, "executableAt should be 0 before any proposal");
    }

    function testGetAssetsPendingWeightsAreSetAfterProposal() public {
        // Proposed weight must be within REBALANCE_THRESHOLD of current weight0 (600_000)
        uint128 proposedWeight0 = weight60 + REBALANCE_THRESHOLD; // 630_000
        uint128 expectedWeight1 = uint128(MAX_WEIGHT) - proposedWeight0;

        vm.prank(address(indexManager));
        initializedIndex.proposeUpdateWeights(proposedWeight0);

        (uint128 p0, uint128 p1, uint256 execAt) = initializedIndex
            .getAssetsPendingWeights();

        assertEq(
            p0,
            proposedWeight0,
            "pendingWeight0 does not match the proposal"
        );
        assertEq(
            p1,
            expectedWeight1,
            "pendingWeight1 does not match the proposal"
        );
        assertEq(
            execAt,
            block.timestamp + WEIGHT_UPDATE_DELAY,
            "executableAt should be now + WEIGHT_UPDATE_DELAY"
        );
    }

    function testGetAssetsPendingWeightsAreResetToZeroAfterDelayExpires()
        public
    {
        uint128 proposedWeight0 = 620_000;

        vm.prank(address(indexManager));
        initializedIndex.proposeUpdateWeights(proposedWeight0);

        vm.warp(block.timestamp + WEIGHT_UPDATE_DELAY + 1);
        _refreshPriceFeeds();

        (, , uint256 execAt) = initializedIndex.getAssetsPendingWeights();
        assertLt(execAt, block.timestamp, "executableAt should be in the past");
    }

    // =========================================================================
    //  getAssetsReserves
    // =========================================================================

    function testGetAssetsReservesAreZeroBeforeInitialization() public view {
        (uint128 r0, uint128 r1) = nonInitializedIndex.getAssetsReserves();
        assertEq(r0, 0, "reserve0 should be 0 before initialization");
        assertEq(r1, 0, "reserve1 should be 0 before initialization");
    }

    function testGetAssetsReservesAreNonZeroAfterInitialization() public view {
        (uint128 r0, uint128 r1) = initializedIndex.getAssetsReserves();
        assertGt(r0, 0, "reserve0 should be > 0 after initialization");
        assertGt(r1, 0, "reserve1 should be > 0 after initialization");
    }

    function testGetAssetsReservesAreInTokenDecimals() public view {
        (uint128 r0, uint128 r1) = initializedIndex.getAssetsReserves();

        uint256 balance0 = mockWeth.balanceOf(address(initializedIndex));
        uint256 balance1 = mockWbtc.balanceOf(address(initializedIndex));

        // Reserves are in token decimals, must match balanceOf
        assertEq(
            r0,
            balance0,
            "reserve0 should match balanceOf in token decimals"
        );
        assertEq(
            r1,
            balance1,
            "reserve1 should match balanceOf in token decimals"
        );
    }

    function testGetAssetsReservesAsset1IsConsistentWithWeightRatioAndPrices()
        public
        view
    {
        // Use getAssetsEffectiveWeights which correctly handles reserves
        // in token decimals internally via _initFunctionValues
        (uint256 effectiveWeight0, ) = initializedIndex
            .getAssetsEffectiveWeights();

        assertApproxEqAbs(
            effectiveWeight0,
            weight60,
            REBALANCE_THRESHOLD,
            "effective weight of asset0 should be ~60%"
        );
    }

    // =========================================================================
    //  getAsset0 / getAsset1
    // =========================================================================

    function testGetAsset0ReturnsCorrectAddress() public view {
        // initializedIndex: asset0 = WETH (indirizzo minore tra WETH e WBTC)
        assertEq(initializedIndex.getAsset0(), address(mockWeth));
    }

    function testGetAsset1ReturnsCorrectAddress() public view {
        assertEq(initializedIndex.getAsset1(), address(mockWbtc));
    }

    function testGetAsset0IsAlwaysLessThanGetAsset1() public view {
        // sortAssets garantisce token0 < token1
        address asset0 = initializedIndex.getAsset0();
        address asset1 = initializedIndex.getAsset1();
        assertTrue(
            asset0 < asset1,
            "asset0 deve essere < asset1 dopo il sorting"
        );
    }

    function testGetAssetsAreConsistentWithIndexManagerRecords() public view {
        (address managerAsset0, address managerAsset1) = indexManager
            .getIndexAssets(address(initializedIndex));

        assertEq(
            initializedIndex.getAsset0(),
            managerAsset0,
            "asset0 deve corrispondere a quello registrato in IndexManager"
        );
        assertEq(
            initializedIndex.getAsset1(),
            managerAsset1,
            "asset1 deve corrispondere a quello registrato in IndexManager"
        );
    }

    function testGetAssetsDifferFromEachOther() public view {
        assertNotEq(
            initializedIndex.getAsset0(),
            initializedIndex.getAsset1(),
            "asset0 e asset1 non possono essere lo stesso token"
        );
    }

    // =========================================================================
    //  getUsdc
    // =========================================================================

    function testGetUsdcReturnsCorrectAddress() public view {
        assertEq(initializedIndex.getUsdc(), address(mockUsdc));
    }

    function testGetUsdcReturnsSameAddressForBothIndexes() public view {
        // Entrambi gli index condividono lo stesso USDC
        assertEq(
            initializedIndex.getUsdc(),
            nonInitializedIndex.getUsdc(),
            "entrambi gli index devono usare lo stesso USDC"
        );
    }

    // =========================================================================
    //  getAsset0PriceFeed / getAsset1PriceFeed / getUsdcPriceFeed
    // =========================================================================

    function testGetAsset0PriceFeedReturnsCorrectAddress() public view {
        assertEq(
            initializedIndex.getAsset0PriceFeed(),
            address(mockWethPriceFeed)
        );
    }

    function testGetAsset1PriceFeedReturnsCorrectAddress() public view {
        assertEq(
            initializedIndex.getAsset1PriceFeed(),
            address(mockWbtcPriceFeed)
        );
    }

    function testGetUsdcPriceFeedReturnsCorrectAddress() public view {
        assertEq(
            initializedIndex.getUsdcPriceFeed(),
            address(mockUsdcPriceFeed)
        );
    }

    function testPriceFeedsAreDistinctAddresses() public view {
        address feed0 = initializedIndex.getAsset0PriceFeed();
        address feed1 = initializedIndex.getAsset1PriceFeed();
        address feedUsdc = initializedIndex.getUsdcPriceFeed();

        assertNotEq(
            feed0,
            feed1,
            "feed asset0 e feed asset1 devono essere diversi"
        );
        assertNotEq(
            feed0,
            feedUsdc,
            "feed asset0 e feed USDC devono essere diversi"
        );
        assertNotEq(
            feed1,
            feedUsdc,
            "feed asset1 e feed USDC devono essere diversi"
        );
    }

    function testNonInitializedIndexHasCorrectPriceFeeds() public view {
        // nonInitializedIndex: WBTC / LINK
        assertEq(
            nonInitializedIndex.getAsset0PriceFeed(),
            address(mockWbtcPriceFeed),
            "asset0 price feed deve essere mockWbtcPriceFeed"
        );
        assertEq(
            nonInitializedIndex.getAsset1PriceFeed(),
            address(mockLinkPriceFeed),
            "asset1 price feed deve essere mockLinkPriceFeed"
        );
        assertEq(
            nonInitializedIndex.getUsdcPriceFeed(),
            address(mockUsdcPriceFeed),
            "USDC price feed deve essere mockUsdcPriceFeed"
        );
    }

    // =========================================================================
    //  getFeesInfo
    // =========================================================================

    function testGetFeesInfoReturnsFeePercentageSetAtDeployment() public view {
        (uint32 feePerc, ) = initializedIndex.getFeesInfo();
        assertEq(
            feePerc,
            validFeePercentage,
            "feePercentage deve corrispondere a quello impostato al deploy"
        );
    }

    function testGetFeesInfoTotalFeesAreZeroBeforeAnySwap() public view {
        // Nessuno swap è stato fatto sull'index: le fees accumulato devono essere 0
        (, uint128 totalFees) = initializedIndex.getFeesInfo();
        assertEq(totalFees, 0, "totalFees deve essere 0 senza swap");
    }

    function testGetFeesInfoFeePercentageDoesNotChange() public {
        (uint32 feeBefore, ) = initializedIndex.getFeesInfo();

        // Cambiamo i prezzi: la fee percentage non deve cambiare
        mockWethPriceFeed.updateAnswer(WETH_INITIAL_PRICE * 5);

        (uint32 feeAfter, ) = initializedIndex.getFeesInfo();
        assertEq(feeAfter, feeBefore, "feePercentage non deve cambiare");
    }

    function testGetFeesInfoFeePercentageIsExpressedWith4DecimalPrecision()
        public
        view
    {
        // validFeePercentage = 1 * PERCENTAGE_FEE_PRECISION = 10_000 (1.00%)
        (uint32 feePerc, ) = initializedIndex.getFeesInfo();
        assertEq(feePerc, 1 * PERCENTAGE_FEE_PRECISION);
    }

    // =========================================================================
    //  getInitializationStatus
    // =========================================================================

    function testGetInitializationStatusReturnsFalseBeforeInitialization()
        public
        view
    {
        assertFalse(
            nonInitializedIndex.getInitializationStatus(),
            "index non inizializzato deve restituire false"
        );
    }

    function testGetInitializationStatusReturnsTrueAfterInitialization()
        public
        view
    {
        assertTrue(
            initializedIndex.getInitializationStatus(),
            "index inizializzato deve restituire true"
        );
    }

    function testGetInitializationStatusIsConsistentWithIndexManagerRecord()
        public
        view
    {
        // IndexManager e Index devono avere la stessa visione dello stato
        bool indexManagerSaysInitialized = indexManager.checkIsIndexInitialized(
            address(initializedIndex)
        );
        bool indexSaysInitialized = initializedIndex.getInitializationStatus();

        assertEq(
            indexSaysInitialized,
            indexManagerSaysInitialized,
            "Index e IndexManager devono concordare sullo stato di inizializzazione"
        );
    }

    function testGetInitializationStatusIsConsistentForNonInitializedIndex()
        public
        view
    {
        bool indexManagerSays = indexManager.checkIsIndexInitialized(
            address(nonInitializedIndex)
        );
        bool indexSays = nonInitializedIndex.getInitializationStatus();

        assertEq(indexSays, indexManagerSays);
        assertFalse(indexSays);
    }
}
