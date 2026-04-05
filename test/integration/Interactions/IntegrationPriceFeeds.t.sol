// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IntegrationBase} from "./IntegrationBase.t.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {Index} from "../../../src/Index.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../../../src/errors/IndexErrors.sol";
import {ContractCodeConstants} from "../../../src/ContractCodeConstants.sol";

contract IntegrationPriceFeeds is IntegrationBase, ContractCodeConstants {
    function setUp() public override {
        super.setUp();
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  WBTC price feed
    // ─────────────────────────────────────────────────────────────────────────

    function test_getLatestPrice_wbtc_returnsPositivePrice() public view {
        uint256 price = wbtcWethIndex.getLatestPrice(address(wbtc));
        assertGt(price, 0, "WBTC price must be positive");
    }

    /**
     * @dev  Price is returned in 18-decimal standard by Index.getLatestPrice.
     *       Range: $10 000 – $200 000 per BTC.
     */
    function test_getLatestPrice_wbtc_isInExpectedRange() public view {
        uint256 price = wbtcWethIndex.getLatestPrice(address(wbtc));
        assertGt(price, 10_000e18, "WBTC price below $10 000 floor");
        assertLt(price, 200_000e18, "WBTC price above $200 000 ceiling");
    }

    function test_getLatestPrice_weth_returnsPositivePrice() public view {
        uint256 price = wbtcWethIndex.getLatestPrice(address(weth));
        assertGt(price, 0, "WETH price must be positive");
    }

    /**
     * @dev  Range: $500 – $50 000 per ETH.
     */
    function test_getLatestPrice_weth_isInExpectedRange() public view {
        uint256 price = wbtcWethIndex.getLatestPrice(address(weth));
        assertGt(price, 500e18, "WETH price below $500 floor");
        assertLt(price, 50_000e18, "WETH price above $50 000 ceiling");
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  USDC price feed
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev  USDC should always be within 5 % of its $1 peg.
     */
    function test_getLatestPrice_usdc_isCloseToDollarPeg() public view {
        uint256 price = wbtcWethIndex.getLatestPrice(address(usdc));
        assertGt(price, 0.95e18, "USDC below $0.95 peg band");
        assertLt(price, 1.05e18, "USDC above $1.05 peg band");
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Price relationship sanity: WBTC >> WETH
    // ─────────────────────────────────────────────────────────────────────────

    function test_wbtcPrice_isGreaterThan_wethPrice() public view {
        uint256 wbtcPrice = wbtcWethIndex.getLatestPrice(address(wbtc));
        uint256 wethPrice = wbtcWethIndex.getLatestPrice(address(weth));
        assertGt(wbtcPrice, wethPrice, "WBTC must be priced above WETH");
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  USD value calculations
    // ─────────────────────────────────────────────────────────────────────────

    function test_getAssetsUsdValue_returnsPositiveComponentsAndCorrectTotal()
        public
        view
    {
        (uint256 asset0Usd, uint256 asset1Usd, uint256 totalUsd) = wbtcWethIndex
            .getAssetsUsdValue();
        assertGt(asset0Usd, 0, "asset0 USD value must be positive");
        assertGt(asset1Usd, 0, "asset1 USD value must be positive");
        assertEq(
            totalUsd,
            asset0Usd + asset1Usd,
            "Total USD must equal sum of both assets"
        );
    }

    /**
     * @dev  The index was seeded with 10 WBTC.  Even at the lowest plausible
     *       BTC price of $10 000 the total should exceed $100 000.
     */
    function test_getAssetsUsdValue_totalReflectsInitialSeed() public view {
        (, , uint256 totalUsd) = wbtcWethIndex.getAssetsUsdValue();
        assertGt(totalUsd, 100_000e18, "Total USD too low for a 10-WBTC seed");
    }

    /**
     * @dev  asset0 is WBTC (60 % target); its USD share must dominate asset1.
     */
    function test_getAssetsUsdValue_asset0DominatesGivenWeights() public view {
        (uint256 asset0Usd, uint256 asset1Usd, ) = wbtcWethIndex
            .getAssetsUsdValue();
        // With 60/40 target and fresh initialisation, asset0 should hold more value.
        assertGt(
            asset0Usd,
            asset1Usd,
            "asset0 (60 % weight) should hold more USD than asset1"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Effective weights
    // ─────────────────────────────────────────────────────────────────────────


    function test_effectiveWeights_closeToTargetWeightsAfterInit() public view {
        (uint128 ew0, uint128 ew1) = wbtcWethIndex.getAssetsEffectiveWeights();
        (uint128 tw0, uint128 tw1) = wbtcWethIndex.getAssetsWeights();

        assertApproxEqAbs(
            uint256(ew0),
            uint256(tw0),
            REBALANCE_THRESHOLD,
            "effectiveWeight0 exceeds threshold vs target"
        );
        assertApproxEqAbs(
            uint256(ew1),
            uint256(tw1),
            REBALANCE_THRESHOLD,
            "effectiveWeight1 exceeds threshold vs target"
        );
    }

    function test_effectiveWeights_sumToMaxPercentage() public view {
        (uint128 ew0, uint128 ew1) = wbtcWethIndex.getAssetsEffectiveWeights();
        assertEq(
            uint256(ew0) + uint256(ew1),
            MAX_PERCENTAGE,
            "Effective weights must sum to MAX_PERCENTAGE"
        );
    }

    function test_targetWeights_sumToMaxWeight() public view {
        (uint128 tw0, uint128 tw1) = wbtcWethIndex.getAssetsWeights();
        assertEq(
            uint256(tw0) + uint256(tw1),
            MAX_PERCENTAGE,
            "Target weights must sum to MAX_WEIGHT"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Staleness guard — MAX_DELAY = 1 hour
    // ─────────────────────────────────────────────────────────────────────────


    function test_getLatestPrice_revertsWhenPriceIsStale() public {
        vm.warp(block.timestamp + MAX_DELAY + 1);

        vm.expectRevert(Index__PriceIsStale.selector);
        wbtcWethIndex.getLatestPrice(address(wbtc));
    }

    function test_getLatestPrice_weth_revertsWhenPriceIsStale() public {
        vm.warp(block.timestamp + MAX_DELAY + 1);

        vm.expectRevert(Index__PriceIsStale.selector);
        wbtcWethIndex.getLatestPrice(address(weth));
    }

    function test_getLatestPrice_usdc_revertsWhenPriceIsStale() public {
        vm.warp(block.timestamp + MAX_USDC_DELAY + 1);

        vm.expectRevert(Index__PriceIsStale.selector);
        wbtcWethIndex.getLatestPrice(address(usdc));
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Unsupported asset guard
    // ─────────────────────────────────────────────────────────────────────────

    function test_getLatestPrice_revertsForAssetNotInIndex() public {
        vm.expectRevert(Index__AssetNotSupported.selector);
        wbtcWethIndex.getLatestPrice(address(comp));
    }

    function test_getLatestPrice_revertsForZeroAddress() public {
        vm.expectRevert(Index__AssetNotSupported.selector);
        wbtcWethIndex.getLatestPrice(address(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Reserves are consistent with prices
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev  Compute the expected USD value of the stored reserves manually and
     *       compare with getAssetsUsdValue() to verify price-to-value consistency.
     */
    function test_reservesUsdValue_consistentWithPriceFeedPrices() public view {
        (uint256 reserve0Std, uint256 reserve1Std) = wbtcWethIndex
            .getAssetsReservesStdDecimals();

        uint256 wbtcPrice = wbtcWethIndex.getLatestPrice(address(wbtc));
        uint256 wethPrice = wbtcWethIndex.getLatestPrice(address(weth));

        // USD value = (reserve_in_18_dec * price_in_18_dec) / 1e18
        uint256 expected0Usd = (reserve0Std * wbtcPrice) / 1e18;
        uint256 expected1Usd = (reserve1Std * wethPrice) / 1e18;

        (uint256 actual0Usd, uint256 actual1Usd, ) = wbtcWethIndex
            .getAssetsUsdValue();

        // Allow tiny rounding delta (1 USD = 1e18 units)
        assertApproxEqAbs(
            actual0Usd,
            expected0Usd,
            1e18,
            "asset0 USD value diverges from manual calculation"
        );
        assertApproxEqAbs(
            actual1Usd,
            expected1Usd,
            1e18,
            "asset1 USD value diverges from manual calculation"
        );
    }
}
