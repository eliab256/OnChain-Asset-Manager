// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BasePriceFeedManagerTest} from "./BasePriceFeedManager.t.sol";
import {
    PriceFeedManager__PriceFeedNotSet,
    PriceFeedManager__PriceFeedNotAvailable,
    PriceFeedManager__PriceFeedRoundStale,
    PriceFeedManager__PriceIsStale
} from "../../../src/errors/PriceFeedManagerErrors.sol";

contract PriceFeedManagerGetPriceTest is BasePriceFeedManagerTest {
    /// L-03: Chainlink ETH/USD heartbeat (1h) plus the 15 min margin, as used by the deploy scripts
    uint32 internal constant HEARTBEAT_PLUS_MARGIN = 1 hours + 15 minutes;
    /// Age of an answer published just after a 1h heartbeat, still within the margin
    uint256 internal constant ANSWER_AGE_WITHIN_MARGIN = 1 hours + 5 minutes;

    uint80 internal constant LATEST_ROUND_ID = 5;
    uint80 internal constant PREVIOUS_ROUND_ID = 4;

    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  getPrice — normalization
    // =========================================================================

    function testGetPriceNormalizes8DecimalFeedTo18Decimals() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        assertEq(
            priceFeedManager.getPrice(s_asset),
            uint256(PRICE_8_DECIMALS) * 10 ** (DECIMALS_STANDARD - FEED_DECIMALS_8)
        );
    }

    function testGetPriceReturns18DecimalFeedUnchanged() public {
        _register(s_asset, address(s_feed18Decimals), s_validMaxDelay);

        assertEq(priceFeedManager.getPrice(s_asset), uint256(PRICE_18_DECIMALS));
    }

    function testGetPriceReturnsDeployScriptFeedsPrices() public view {
        assertEq(
            priceFeedManager.getPrice(address(mockWeth)),
            uint256(WETH_INITIAL_PRICE) * 1e10
        );
        assertEq(
            priceFeedManager.getPrice(address(mockUsdc)),
            uint256(USDC_INITIAL_PRICE) * 1e10
        );
    }

    // =========================================================================
    //  getPrice — reverts
    // =========================================================================

    function testGetPriceRevertsIfFeedNotSet() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager__PriceFeedNotSet.selector,
                s_asset
            )
        );
        priceFeedManager.getPrice(s_asset);
    }

    function testGetPriceRevertsIfAnswerIsZero() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        s_feed8Decimals.setAnswer(0);

        vm.expectRevert(PriceFeedManager__PriceFeedNotAvailable.selector);
        priceFeedManager.getPrice(s_asset);
    }

    function testGetPriceRevertsIfAnswerIsNegative() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        s_feed8Decimals.setAnswer(-1);

        vm.expectRevert(PriceFeedManager__PriceFeedNotAvailable.selector);
        priceFeedManager.getPrice(s_asset);
    }

    function testGetPriceRevertsIfRoundIsStale() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        s_feed8Decimals.setRoundData(
            LATEST_ROUND_ID,
            PRICE_8_DECIMALS,
            block.timestamp,
            PREVIOUS_ROUND_ID
        );

        vm.expectRevert(PriceFeedManager__PriceFeedRoundStale.selector);
        priceFeedManager.getPrice(s_asset);
    }

    function testGetPriceAcceptsAnsweredInRoundEqualToRoundId() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        s_feed8Decimals.setRoundData(
            LATEST_ROUND_ID,
            PRICE_8_DECIMALS,
            block.timestamp,
            LATEST_ROUND_ID
        );

        assertGt(priceFeedManager.getPrice(s_asset), 0);
    }

    // =========================================================================
    //  getPrice — staleness boundary (per-feed maxDelay)
    // =========================================================================

    function testGetPriceSucceedsWhenAnswerAgeEqualsMaxDelay() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        vm.warp(block.timestamp + s_validMaxDelay);

        assertEq(
            priceFeedManager.getPrice(s_asset),
            uint256(PRICE_8_DECIMALS) * 10 ** (DECIMALS_STANDARD - FEED_DECIMALS_8)
        );
    }

    function testGetPriceRevertsWhenAnswerAgeExceedsMaxDelayByOneSecond()
        public
    {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        vm.warp(block.timestamp + s_validMaxDelay + 1);

        vm.expectRevert(PriceFeedManager__PriceIsStale.selector);
        priceFeedManager.getPrice(s_asset);
    }

    function testGetPriceUsesPerFeedMaxDelay() public {
        // Same answer age, different maxDelay per asset: only the short-delay feed is stale.
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);
        _register(s_otherAsset, address(s_feed18Decimals), s_otherValidMaxDelay);
        vm.warp(block.timestamp + s_validMaxDelay + 1);

        assertEq(priceFeedManager.getPrice(s_otherAsset), uint256(PRICE_18_DECIMALS));
        vm.expectRevert(PriceFeedManager__PriceIsStale.selector);
        priceFeedManager.getPrice(s_asset);
    }

    function testGetPriceUsdcAcceptsAnswerUpToUsdcMaxDelay() public {
        vm.warp(block.timestamp + usdcPriceFeedMaxDelay);
        assertEq(
            priceFeedManager.getPrice(address(mockUsdc)),
            uint256(USDC_INITIAL_PRICE) * 1e10
        );

        vm.warp(block.timestamp + 1);
        vm.expectRevert(PriceFeedManager__PriceIsStale.selector);
        priceFeedManager.getPrice(address(mockUsdc));
    }

    // =========================================================================
    //  L-03 — heartbeat + margin
    // =========================================================================

    function testGetPriceAcceptsAnswerOlderThanHeartbeatWithinMargin() public {
        // Make sure the warp leaves room for the answer age.
        vm.warp(block.timestamp + 1 days);
        _register(s_asset, address(s_feed8Decimals), HEARTBEAT_PLUS_MARGIN);
        _setAnswerAge(s_feed8Decimals, PRICE_8_DECIMALS, ANSWER_AGE_WITHIN_MARGIN);

        assertEq(
            priceFeedManager.getPrice(s_asset),
            uint256(PRICE_8_DECIMALS) * 10 ** (DECIMALS_STANDARD - FEED_DECIMALS_8)
        );
    }

    function testHelperConfigAssetMaxDelayIsHeartbeatPlusMargin() public view {
        assertEq(assetPriceFeedMaxDelay, HEARTBEAT_PLUS_MARGIN);
    }
}
