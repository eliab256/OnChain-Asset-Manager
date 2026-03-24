// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {UnderlyingMath} from "../../../src/libraries/UnderlyingMath.sol";

contract UnderlyingMathTest is Test {
    // ── Decimal constants ─────────────────────────────────────────────────────
    uint8 constant STD_DECIMALS = 18;
    uint8 constant PRICE_DECIMALS = 8;
    uint8 constant WETH_DECIMALS = 18;
    uint8 constant WBTC_DECIMALS = 8;
    uint8 constant USDC_DECIMALS = 6;
    uint8 constant LINK_DECIMALS = 18;

    // ── Price constants (Chainlink feed format, PRICE_DECIMALS = 8) ──────────
    uint256 constant WETH_PRICE_FEED = 2_000 * 10 ** PRICE_DECIMALS; // $2 000
    uint256 constant WBTC_PRICE_FEED = 30_000 * 10 ** PRICE_DECIMALS; // $30 000
    uint256 constant LINK_PRICE_FEED = 7 * 10 ** PRICE_DECIMALS; // $7
    uint256 constant USDC_PRICE_FEED = 1 * 10 ** PRICE_DECIMALS; // $1

    // ── Price constants (std-decimal form, 18 decimals) ───────────────────────
    uint256 constant WETH_PRICE_STD = 2_000e18;
    uint256 constant WBTC_PRICE_STD = 30_000e18;
    uint256 constant LINK_PRICE_STD = 7e18;
    uint256 constant USDC_PRICE_STD = 1e18;

    // ── Weight constants (4-decimal precision, MAX_WEIGHT = 1 000 000) ────────
    uint256 constant WEIGHT_PRECISION = 10_000;
    uint128 constant WEIGHT_50 = uint128(50 * WEIGHT_PRECISION); // 500_000
    uint128 constant WEIGHT_60 = uint128(60 * WEIGHT_PRECISION); // 600_000
    uint128 constant WEIGHT_40 = uint128(40 * WEIGHT_PRECISION); // 400_000
    uint128 constant WEIGHT_30 = uint128(30 * WEIGHT_PRECISION); // 300_000
    uint128 constant WEIGHT_70 = uint128(70 * WEIGHT_PRECISION); // 700_000
    uint128 constant MAX_WEIGHT = uint128(100 * WEIGHT_PRECISION); // 1_000_000

    // ── USD value constants (std-decimal = 18) ────────────────────────────────
    uint256 constant USD_1000 = 1_000e18;
    uint256 constant USD_2000 = 2_000e18;
    uint256 constant USD_4000 = 4_000e18;
    uint256 constant USD_10000 = 10_000e18;
    uint256 constant USD_20000 = 20_000e18;
    uint256 constant USD_40000 = 40_000e18;
    uint256 constant USD_60000 = 60_000e18;
    uint256 constant USD_100 = 100e18;

    // ── Token amount constants ────────────────────────────────────────────────
    /// 1 WETH in token decimals (18 dec)
    uint256 constant ONE_WETH = 1e18;
    /// 1 WBTC in token decimals (8 dec)
    uint256 constant ONE_WBTC = 1e8;
    /// 1 LINK in token decimals (18 dec)
    uint256 constant ONE_LINK = 1e18;
    /// 1 USDC in token decimals (6 dec)
    uint256 constant ONE_USDC = 1e6;
    /// 10 WETH in token decimals
    uint256 constant TEN_WETH = 10e18;
    /// Scaling factor: 10^(STD_DECIMALS - WBTC_DECIMALS) = 10^10
    uint256 constant WBTC_TO_STD_SCALE = 10 ** (STD_DECIMALS - WBTC_DECIMALS);
    /// Scaling factor: 10^(STD_DECIMALS - USDC_DECIMALS) = 10^12
    uint256 constant USDC_TO_STD_SCALE = 10 ** (STD_DECIMALS - USDC_DECIMALS);

    // =========================================================================
    //  calculateAmount1UsdFromAmount0UsdAndIndexWeights
    // =========================================================================

    function testCalculateAmount1Usd_EqualWeights_ReturnSameAmount()
        public
        pure
    {
        // 50/50: amount1 = amount0 * weight1 / weight0 = amount0 * 1 = amount0
        uint256 result = UnderlyingMath
            .calculateAmount1UsdFromAmount0UsdAndIndexWeights(
                USD_2000,
                WEIGHT_50,
                WEIGHT_50
            );
        assertEq(result, USD_2000);
    }

    function testCalculateAmount1Usd_SixtyFortyWeights_ReturnTwoThirdsOfAmount0()
        public
        pure
    {
        // 60/40: amount1 = amount0 * 40 / 60 = amount0 * 2/3
        // asset0 is worth $20 000 (60%), asset1 must be worth $13 333.33 (40%)
        uint256 result = UnderlyingMath
            .calculateAmount1UsdFromAmount0UsdAndIndexWeights(
                USD_20000,
                WEIGHT_60,
                WEIGHT_40
            );
        uint256 expected = (USD_20000 * WEIGHT_40) / WEIGHT_60;
        assertEq(result, expected);
    }

    function testCalculateAmount1Usd_ThirtySeventy_ReturnCorrectRatio()
        public
        pure
    {
        uint256 result = UnderlyingMath
            .calculateAmount1UsdFromAmount0UsdAndIndexWeights(
                USD_20000,
                WEIGHT_30,
                WEIGHT_70
            );
        uint256 expected = (USD_20000 * WEIGHT_70) / WEIGHT_30;
        assertEq(result, expected);
    }

    function testCalculateAmount1Usd_ZeroAmount0_ReturnZero() public pure {
        uint256 result = UnderlyingMath
            .calculateAmount1UsdFromAmount0UsdAndIndexWeights(
                0,
                WEIGHT_60,
                WEIGHT_40
            );
        assertEq(result, 0);
    }

    function testCalculateAmount1Usd_InvariantTotalValueConsistency()
        public
        pure
    {
        // amount0 + amount1 should equal amount0 / weight0 * MAX_WEIGHT
        uint256 amount0Usd = USD_20000;
        uint256 amount1Usd = UnderlyingMath
            .calculateAmount1UsdFromAmount0UsdAndIndexWeights(
                amount0Usd,
                WEIGHT_60,
                WEIGHT_40
            );
        uint256 totalUsd = amount0Usd + amount1Usd;
        // totalUsd = amount0 * (weight0 + weight1) / weight0 = amount0 * MAX_WEIGHT / weight0
        uint256 expectedTotal = (amount0Usd * uint256(MAX_WEIGHT)) /
            uint256(WEIGHT_60);
        assertEq(totalUsd, expectedTotal);
    }

    // =========================================================================
    //  calculateUsdValueOfTokenAmount
    // =========================================================================

    // ── Branch 1: decimalsPrecision == tokenDecimals ──────────────────────────
    // Example: WETH (18 dec), precision = 18 dec

    function testCalculateUsdValueOfToken_WhenPrecisionEqualsTokenDecimals_ReturnsCorrectValue()
        public
        pure
    {
        // 1 WETH @ $2 000: value = (1e18 * 2000e8) / 1e8 = 2000e18
        uint256 result = UnderlyingMath.calculateUsdValueOfTokenAmount(
            ONE_WETH,
            WETH_PRICE_FEED,
            PRICE_DECIMALS,
            WETH_DECIMALS,
            WETH_DECIMALS // decimalsPrecision == tokenDecimals == 18
        );
        assertEq(result, WETH_PRICE_STD);
    }

    function testCalculateUsdValueOfToken_PrecisionEqualsTokenDecimals_TenTokens()
        public
        pure
    {
        // 10 WETH @ $2 000 = $20 000
        uint256 result = UnderlyingMath.calculateUsdValueOfTokenAmount(
            TEN_WETH,
            WETH_PRICE_FEED,
            PRICE_DECIMALS,
            WETH_DECIMALS,
            WETH_DECIMALS
        );
        assertEq(result, USD_20000);
    }

    // ── Branch 2: decimalsPrecision > tokenDecimals ───────────────────────────
    // Example: WBTC (8 dec), precision = 18 dec

    function testCalculateUsdValueOfToken_WhenPrecisionGreaterThanTokenDecimals_ReturnsCorrectValue()
        public
        pure
    {
        // 1 WBTC (1e8) @ $30 000 in 18-dec precision:
        // value = (1e8 * 30_000e8 * 1e10) / 1e8 = 30_000e18
        uint256 result = UnderlyingMath.calculateUsdValueOfTokenAmount(
            ONE_WBTC,
            WBTC_PRICE_FEED,
            PRICE_DECIMALS,
            WBTC_DECIMALS,
            STD_DECIMALS // decimalsPrecision (18) > tokenDecimals (8)
        );
        assertEq(result, WBTC_PRICE_STD);
    }

    function testCalculateUsdValueOfToken_UsdcToken_PrecisionGreaterThanTokenDecimals()
        public
        pure
    {
        // 1 USDC (1e6) @ $1 in 18-dec precision:
        // value = (1e6 * 1e8 * 1e12) / 1e8 = 1e18
        uint256 result = UnderlyingMath.calculateUsdValueOfTokenAmount(
            ONE_USDC,
            USDC_PRICE_FEED,
            PRICE_DECIMALS,
            USDC_DECIMALS,
            STD_DECIMALS // 18 > 6
        );
        assertEq(result, USDC_PRICE_STD);
    }

    // ── Branch 3: decimalsPrecision < tokenDecimals ───────────────────────────
    // Example: 18-dec token, precision = 6 dec (like USDC)

    function testCalculateUsdValueOfToken_WhenPrecisionLessThanTokenDecimals_ReturnsCorrectValue()
        public
        pure
    {
        // 1 WETH (1e18) @ $2 000 with 6-dec precision result:
        // value = (1e18 * 2000e8 * 1e6) / (1e8 * 1e18) = 2000 * 1e6 = 2_000_000
        uint8 resultPrecision = USDC_DECIMALS; // 6 < WETH_DECIMALS (18)
        uint256 result = UnderlyingMath.calculateUsdValueOfTokenAmount(
            ONE_WETH,
            WETH_PRICE_FEED,
            PRICE_DECIMALS,
            WETH_DECIMALS,
            resultPrecision
        );
        // $2 000 in 6-decimal precision = 2_000 * 10^6 = 2_000_000
        uint256 expected = 2_000 * (10 ** USDC_DECIMALS);
        assertEq(result, expected);
    }

    function testCalculateUsdValueOfToken_ZeroAmount_ReturnsZeroForAllBranches()
        public
        pure
    {
        // Branch 1
        assertEq(
            UnderlyingMath.calculateUsdValueOfTokenAmount(
                0,
                WETH_PRICE_FEED,
                PRICE_DECIMALS,
                WETH_DECIMALS,
                WETH_DECIMALS
            ),
            0
        );
        // Branch 2
        assertEq(
            UnderlyingMath.calculateUsdValueOfTokenAmount(
                0,
                WBTC_PRICE_FEED,
                PRICE_DECIMALS,
                WBTC_DECIMALS,
                STD_DECIMALS
            ),
            0
        );
        // Branch 3
        assertEq(
            UnderlyingMath.calculateUsdValueOfTokenAmount(
                0,
                WETH_PRICE_FEED,
                PRICE_DECIMALS,
                WETH_DECIMALS,
                USDC_DECIMALS
            ),
            0
        );
    }

    // =========================================================================
    //  calculateUSDValueOfTokenAmountStdDecimals
    // =========================================================================

    function testCalculateUsdValueStdDecimals_OneWeth_ReturnsCorrectUsdValue()
        public
        pure
    {
        // 1 WETH in 18-dec standard * price in 18-dec / 1e18 = USD value in 18-dec
        // price = WETH_PRICE_STD = 2000e18
        // result = 1e18 * 2000e18 / 1e18 = 2000e18
        uint256 result = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                ONE_WETH,
                WETH_PRICE_STD,
                STD_DECIMALS
            );
        assertEq(result, WETH_PRICE_STD);
    }

    function testCalculateUsdValueStdDecimals_TenWeth_ReturnsTenTimesPrice()
        public
        pure
    {
        uint256 result = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                TEN_WETH,
                WETH_PRICE_STD,
                STD_DECIMALS
            );
        assertEq(result, USD_20000);
    }

    function testCalculateUsdValueStdDecimals_ZeroAmount_ReturnsZero()
        public
        pure
    {
        uint256 result = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                0,
                WETH_PRICE_STD,
                STD_DECIMALS
            );
        assertEq(result, 0);
    }

    function testCalculateUsdValueStdDecimals_ZeroPrice_ReturnsZero()
        public
        pure
    {
        uint256 result = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                ONE_WETH,
                0,
                STD_DECIMALS
            );
        assertEq(result, 0);
    }

    function testCalculateUsdValueStdDecimals_WbtcInStdDecimals_ReturnsCorrectValue()
        public
        pure
    {
        // 1 WBTC normalized to 18 dec = 1e18 (in std decimal form)
        // USD value = 1e18 * 30_000e18 / 1e18 = 30_000e18
        uint256 wbtcInStdDec = ONE_WBTC * WBTC_TO_STD_SCALE;
        uint256 result = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                wbtcInStdDec,
                WBTC_PRICE_STD,
                STD_DECIMALS
            );
        assertEq(result, WBTC_PRICE_STD);
    }

    // =========================================================================
    //  calculateTokenAmountFromUsdValue
    // =========================================================================

    function testCalculateTokenAmountFromUsd_WethFromUsdValue_ReturnsCorrectAmount()
        public
        pure
    {
        // $2 000 in std-dec at WETH price (2000e18):
        // tokenAmount = 2000e18 * 1e18 / 2000e18 = 1e18 (1 WETH in 18-dec)
        uint256 result = UnderlyingMath.calculateTokenAmountFromUsdValue(
            WETH_PRICE_STD,
            WETH_PRICE_STD,
            STD_DECIMALS
        );
        assertEq(result, ONE_WETH);
    }

    function testCalculateTokenAmountFromUsd_WbtcFromUsdValue_ReturnsCorrectAmount()
        public
        pure
    {
        // $30 000 at WBTC price ($30 000 in 18-dec):
        // tokenAmount = 30_000e18 * 1e18 / 30_000e18 = 1e18 (1 WBTC in std-dec)
        uint256 result = UnderlyingMath.calculateTokenAmountFromUsdValue(
            WBTC_PRICE_STD,
            WBTC_PRICE_STD,
            STD_DECIMALS
        );
        assertEq(result, ONE_WETH); // 1e18 in std-dec regardless of underlying token
    }

    function testCalculateTokenAmountFromUsd_ZeroUsdValue_ReturnsZero()
        public
        pure
    {
        uint256 result = UnderlyingMath.calculateTokenAmountFromUsdValue(
            0,
            WETH_PRICE_STD,
            STD_DECIMALS
        );
        assertEq(result, 0);
    }

    function testCalculateTokenAmountFromUsd_DoubleUsdValue_ReturnsDoubleTokenAmount()
        public
        pure
    {
        uint256 amount1 = UnderlyingMath.calculateTokenAmountFromUsdValue(
            WETH_PRICE_STD,
            WETH_PRICE_STD,
            STD_DECIMALS
        );
        uint256 amount2 = UnderlyingMath.calculateTokenAmountFromUsdValue(
            WETH_PRICE_STD * 2,
            WETH_PRICE_STD,
            STD_DECIMALS
        );
        assertEq(amount2, amount1 * 2);
    }

    // =========================================================================
    //  convertToSpecificDecimal
    // =========================================================================

    // ── Branch 1: currentDecimals == targetDecimals ───────────────────────────

    function testConvertToSpecificDecimal_EqualDecimals_ReturnUnchangedAmountAndZeroDiff()
        public
        pure
    {
        (uint256 converted, uint256 diff) = UnderlyingMath
            .convertToSpecificDecimal(ONE_WETH, STD_DECIMALS, STD_DECIMALS);
        assertEq(converted, ONE_WETH);
        assertEq(diff, 0);
    }

    function testConvertToSpecificDecimal_EqualDecimals_EightBit_ReturnUnchanged()
        public
        pure
    {
        (uint256 converted, uint256 diff) = UnderlyingMath
            .convertToSpecificDecimal(ONE_WBTC, WBTC_DECIMALS, WBTC_DECIMALS);
        assertEq(converted, ONE_WBTC);
        assertEq(diff, 0);
    }

    // ── Branch 2: targetDecimals > currentDecimals (scale up) ────────────────

    function testConvertToSpecificDecimal_ScaleUpWbtcToStd_ReturnScaledAmountAndCorrectDiff()
        public
        pure
    {
        // 1 WBTC (1e8) → 18 dec: multiply by 10^(18-8) = 10^10
        (uint256 converted, uint256 diff) = UnderlyingMath
            .convertToSpecificDecimal(ONE_WBTC, WBTC_DECIMALS, STD_DECIMALS);
        assertEq(converted, ONE_WBTC * WBTC_TO_STD_SCALE);
        assertEq(diff, STD_DECIMALS - WBTC_DECIMALS);
    }

    function testConvertToSpecificDecimal_ScaleUpUsdcToStd_ReturnScaledAmount()
        public
        pure
    {
        // 1 USDC (1e6) → 18 dec: multiply by 10^12
        (uint256 converted, uint256 diff) = UnderlyingMath
            .convertToSpecificDecimal(ONE_USDC, USDC_DECIMALS, STD_DECIMALS);
        assertEq(converted, ONE_USDC * USDC_TO_STD_SCALE);
        assertEq(diff, STD_DECIMALS - USDC_DECIMALS);
    }

    function testConvertToSpecificDecimal_ScaleUp_ZeroAmount_ReturnZeroAndCorrectDiff()
        public
        pure
    {
        (uint256 converted, uint256 diff) = UnderlyingMath
            .convertToSpecificDecimal(0, WBTC_DECIMALS, STD_DECIMALS);
        assertEq(converted, 0);
        assertEq(diff, STD_DECIMALS - WBTC_DECIMALS);
    }

    // ── Branch 3: targetDecimals < currentDecimals (scale down) ──────────────

    function testConvertToSpecificDecimal_ScaleDownStdToWbtc_ReturnScaledAmountAndCorrectDiff()
        public
        pure
    {
        // 1e18 (WBTC in std-dec) → 8 dec: divide by 10^10
        uint256 amountInStd = ONE_WBTC * WBTC_TO_STD_SCALE;
        (uint256 converted, uint256 diff) = UnderlyingMath
            .convertToSpecificDecimal(amountInStd, STD_DECIMALS, WBTC_DECIMALS);
        assertEq(converted, ONE_WBTC);
        assertEq(diff, STD_DECIMALS - WBTC_DECIMALS);
    }

    function testConvertToSpecificDecimal_ScaleDownStdToUsdc_ReturnScaledAmount()
        public
        pure
    {
        uint256 amountInStd = ONE_USDC * USDC_TO_STD_SCALE;
        (uint256 converted, uint256 diff) = UnderlyingMath
            .convertToSpecificDecimal(amountInStd, STD_DECIMALS, USDC_DECIMALS);
        assertEq(converted, ONE_USDC);
        assertEq(diff, STD_DECIMALS - USDC_DECIMALS);
    }

    function testConvertToSpecificDecimal_ScaleDown_ZeroAmount_ReturnZeroAndCorrectDiff()
        public
        pure
    {
        (uint256 converted, uint256 diff) = UnderlyingMath
            .convertToSpecificDecimal(0, STD_DECIMALS, WBTC_DECIMALS);
        assertEq(converted, 0);
        assertEq(diff, STD_DECIMALS - WBTC_DECIMALS);
    }

    function testConvertToSpecificDecimal_RoundTrip_ScaleUpThenDown_ReturnOriginal()
        public
        pure
    {
        // Scale up WBTC to std, then back to WBTC decimals
        (uint256 scaled, ) = UnderlyingMath.convertToSpecificDecimal(
            ONE_WBTC,
            WBTC_DECIMALS,
            STD_DECIMALS
        );
        (uint256 restored, ) = UnderlyingMath.convertToSpecificDecimal(
            scaled,
            STD_DECIMALS,
            WBTC_DECIMALS
        );
        assertEq(restored, ONE_WBTC);
    }

    // =========================================================================
    //  calculateRebalanceAmounts
    // =========================================================================

    // ── Branch 1: effectiveWeight0 > weight0 (swap token0 → token1) ──────────

    function testCalculateRebalanceAmounts_Token0Overweight_ReturnsAmount0ToSwap()
        public
        pure
    {
        // Setup: total = $100, token0 = $70 (70%), token1 = $30 (30%)
        // Target: 60/40. effectiveWeight0 = 700_000 > weight0 = 600_000
        // → swap token0 → token1
        // desiredToken0 = $100 * 60% = $60
        // diff = $70 - $60 = $10 USD
        // amount0ToSwap = $10e18 * 1e18 / 2000e18 = 5e15 (0.005 WETH in std-dec)
        uint256 totalUsd = USD_100 * 10; // use larger round numbers
        uint256 token0Usd = (totalUsd * 7) / 10; // 70%
        uint256 token1Usd = totalUsd - token0Usd;

        // WETH price in 18-dec standard = WETH_PRICE_STD
        (uint256 amount0ToSwap, uint256 amount1ToSwap) = UnderlyingMath
            .calculateRebalanceAmounts(
                totalUsd,
                token0Usd,
                token1Usd,
                WEIGHT_60,
                WEIGHT_40,
                WETH_PRICE_STD,
                WBTC_PRICE_STD,
                STD_DECIMALS
            );

        // desiredToken0 = totalUsd * WEIGHT_60 / MAX_WEIGHT = 1000e18 * 600_000 / 1_000_000 = 600e18
        uint256 desiredToken0 = (totalUsd * uint256(WEIGHT_60)) /
            uint256(MAX_WEIGHT);
        uint256 diff = token0Usd - desiredToken0;
        uint256 expectedAmount0 = (diff * 10 ** STD_DECIMALS) / WETH_PRICE_STD;

        assertEq(amount0ToSwap, expectedAmount0);
        assertEq(
            amount1ToSwap,
            0,
            "amount1ToSwap must be 0 when token0 is overweight"
        );
    }

    function testCalculateRebalanceAmounts_Token0Overweight_Amount1ToSwapIsZero()
        public
        pure
    {
        uint256 totalUsd = 1_000e18;
        uint256 token0Usd = 700e18; // 70%
        uint256 token1Usd = 300e18; // 30%

        (, uint256 amount1ToSwap) = UnderlyingMath.calculateRebalanceAmounts(
            totalUsd,
            token0Usd,
            token1Usd,
            WEIGHT_60,
            WEIGHT_40,
            WETH_PRICE_STD,
            WBTC_PRICE_STD,
            STD_DECIMALS
        );
        assertEq(amount1ToSwap, 0);
    }

    // ── Branch 2: effectiveWeight0 <= weight0 (swap token1 → token0) ─────────

    function testCalculateRebalanceAmounts_Token1Overweight_ReturnsAmount1ToSwap()
        public
        pure
    {
        // Setup: total = $1000, token0 = $500 (50%), token1 = $500 (50%)
        // Target: 60/40. effectiveWeight0 = 500_000 < weight0 = 600_000
        // → swap token1 → token0
        // desiredToken1 = $1000 * 40% = $400
        // diff = $500 - $400 = $100
        // amount1ToSwap = 100e18 * 1e18 / 30_000e18 = 100/30_000 * 1e18
        uint256 totalUsd = 1_000e18;
        uint256 token0Usd = 500e18;
        uint256 token1Usd = 500e18;

        (uint256 amount0ToSwap, uint256 amount1ToSwap) = UnderlyingMath
            .calculateRebalanceAmounts(
                totalUsd,
                token0Usd,
                token1Usd,
                WEIGHT_60,
                WEIGHT_40,
                WETH_PRICE_STD,
                WBTC_PRICE_STD,
                STD_DECIMALS
            );

        uint256 desiredToken1 = (totalUsd * uint256(WEIGHT_40)) /
            uint256(MAX_WEIGHT);
        uint256 diff = token1Usd - desiredToken1;
        uint256 expectedAmount1 = (diff * 10 ** STD_DECIMALS) / WBTC_PRICE_STD;

        assertEq(amount1ToSwap, expectedAmount1);
        assertEq(
            amount0ToSwap,
            0,
            "amount0ToSwap must be 0 when token1 is overweight"
        );
    }

    function testCalculateRebalanceAmounts_Token1Overweight_Amount0ToSwapIsZero()
        public
        pure
    {
        uint256 totalUsd = 1_000e18;
        uint256 token0Usd = 500e18;
        uint256 token1Usd = 500e18;

        (uint256 amount0ToSwap, ) = UnderlyingMath.calculateRebalanceAmounts(
            totalUsd,
            token0Usd,
            token1Usd,
            WEIGHT_60,
            WEIGHT_40,
            WETH_PRICE_STD,
            WBTC_PRICE_STD,
            STD_DECIMALS
        );
        assertEq(amount0ToSwap, 0);
    }

    function testCalculateRebalanceAmounts_ExactlyBalanced_SwapsToken1()
        public
        pure
    {
        // Exactly balanced: token0 = 60%, target = 60%
        // effectiveWeight0 = 600_000 == weight0 = 600_000 → goes to else branch
        uint256 totalUsd = 1_000e18;
        uint256 token0Usd = 600e18; // exactly 60%
        uint256 token1Usd = 400e18;

        (uint256 amount0ToSwap, uint256 amount1ToSwap) = UnderlyingMath
            .calculateRebalanceAmounts(
                totalUsd,
                token0Usd,
                token1Usd,
                WEIGHT_60,
                WEIGHT_40,
                WETH_PRICE_STD,
                WBTC_PRICE_STD,
                STD_DECIMALS
            );
        assertEq(amount0ToSwap, 0, "no token0 swap when perfectly balanced");
        assertEq(
            amount1ToSwap,
            0,
            "no token1 swap needed when perfectly balanced"
        );
    }

    // =========================================================================
    //  calculateSwapFromUsdcAmount
    // =========================================================================

    function testCalculateSwapFromUsdc_EqualWeights_ReturnHalfToEach()
        public
        pure
    {
        (uint256 amount0, uint256 amount1) = UnderlyingMath
            .calculateSwapFromUsdcAmount(USD_1000, WEIGHT_50, WEIGHT_50);
        assertEq(amount0, USD_1000 / 2);
        assertEq(amount1, USD_1000 / 2);
    }

    function testCalculateSwapFromUsdc_SixtyForty_ReturnCorrectSplit()
        public
        pure
    {
        // 60/40: amount0 = 1000 * 60/100 = 600, amount1 = 1000 * 40/100 = 400
        (uint256 amount0, uint256 amount1) = UnderlyingMath
            .calculateSwapFromUsdcAmount(USD_1000, WEIGHT_60, WEIGHT_40);
        uint256 expectedAmount0 = (USD_1000 * uint256(WEIGHT_60)) /
            uint256(MAX_WEIGHT);
        uint256 expectedAmount1 = (USD_1000 * uint256(WEIGHT_40)) /
            uint256(MAX_WEIGHT);
        assertEq(amount0, expectedAmount0);
        assertEq(amount1, expectedAmount1);
    }

    function testCalculateSwapFromUsdc_ZeroUsdc_ReturnZeroForBoth()
        public
        pure
    {
        (uint256 amount0, uint256 amount1) = UnderlyingMath
            .calculateSwapFromUsdcAmount(0, WEIGHT_60, WEIGHT_40);
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    function testCalculateSwapFromUsdc_SumEqualsInput() public pure {
        (uint256 amount0, uint256 amount1) = UnderlyingMath
            .calculateSwapFromUsdcAmount(USD_10000, WEIGHT_60, WEIGHT_40);
        assertEq(amount0 + amount1, USD_10000);
    }

    // =========================================================================
    //  calculateDepositAllocationInUsd
    // =========================================================================

    // ── Branch 1: targetToken0 <= currentToken0 (asset0 overweight, buy only asset1) ──

    function testCalculateDepositAllocation_WhenAsset0Overweight_BuyOnlyAsset1()
        public
        pure
    {
        // initTotal = $1000, effectiveWeight0 = 60%, targetWeight0 = 40%
        // deposit = $100
        // currentToken0 = 1000e18 * 60% = 600e18
        // updatedTotal = 1100e18
        // targetToken0 = 1100e18 * 40% = 440e18
        // 440e18 <= 600e18 → Branch 1
        (uint256 amount0, uint256 amount1) = UnderlyingMath
            .calculateDepositAllocationInUsd(
                USD_10000, // initTotalAssetUsdValue
                USD_1000, // depositAmountUsd
                WEIGHT_40, // targetWeight0 (40%)
                WEIGHT_60, // targetWeight1 (60%)
                WEIGHT_60 // effectiveWeight0 (currently 60%)
            );
        assertEq(amount0, 0);
        assertEq(amount1, USD_1000);
    }

    function testCalculateDepositAllocation_WhenAsset0Overweight_AllGoesToAsset1()
        public
        pure
    {
        (uint256 amount0, uint256 amount1) = UnderlyingMath
            .calculateDepositAllocationInUsd(
                USD_10000,
                USD_1000,
                WEIGHT_40,
                WEIGHT_60,
                WEIGHT_70 // very overweight
            );
        assertEq(amount0, 0, "no USDC should go to overweight asset0");
        assertEq(amount1, USD_1000, "all USDC should go to asset1");
    }

    // ── Branch 2: targetToken0 > currentToken0 (buy asset0 to rebalance) ─────

    function testCalculateDepositAllocation_WhenAsset1Overweight_SplitDeposit()
        public
        pure
    {
        // initTotal = $1000, effectiveWeight0 = 59% (slightly below 60% target)
        // deposit = $100
        // currentToken0 = 1000e18 * 590_000 / 1_000_000 = 590e18
        // updatedTotal = 1100e18
        // targetToken0 = 1100e18 * 600_000 / 1_000_000 = 660e18
        // 660e18 > 590e18 → Branch 2
        // amount0 = 660e18 - 590e18 = 70e18
        // amount1 = 100e18 - 70e18 = 30e18
        uint128 effectiveWeight0 = uint128(59 * WEIGHT_PRECISION); // 590_000

        (uint256 amount0, uint256 amount1) = UnderlyingMath
            .calculateDepositAllocationInUsd(
                USD_10000, // $1 000
                USD_100 * 10, // wait, USD_100 = 100e18, so USD_100 * 10 = $1000?
                // Let me recalculate with simpler numbers
                // initTotal = 10_000e18
                // deposit    = 1_000e18
                // effectiveWeight0 = 590_000 (59%)
                // currentToken0    = 10_000e18 * 590_000 / 1_000_000 = 5_900e18
                // updatedTotal     = 11_000e18
                // targetToken0     = 11_000e18 * 600_000 / 1_000_000 = 6_600e18
                // amount0 = 6_600e18 - 5_900e18 = 700e18
                // amount1 = 1_000e18 - 700e18   = 300e18
                WEIGHT_60,
                WEIGHT_40,
                effectiveWeight0
            );

        uint256 initTotal = USD_10000;
        uint256 deposit = USD_1000;
        uint256 updatedTotal = initTotal + deposit;
        uint256 targetToken0 = (updatedTotal * uint256(WEIGHT_60)) /
            uint256(MAX_WEIGHT);
        uint256 currentToken0 = (initTotal * uint256(effectiveWeight0)) /
            uint256(MAX_WEIGHT);
        uint256 expectedAmount0 = targetToken0 - currentToken0;
        uint256 expectedAmount1 = deposit - expectedAmount0;

        assertEq(amount0, expectedAmount0);
        assertEq(amount1, expectedAmount1);
    }

    function testCalculateDepositAllocation_BothBranches_SumEqualsDeposit()
        public
        pure
    {
        uint256 deposit = USD_1000;

        (uint256 a0Branch1, uint256 a1Branch1) = UnderlyingMath
            .calculateDepositAllocationInUsd(
                USD_10000,
                deposit,
                WEIGHT_40,
                WEIGHT_60,
                WEIGHT_60
            );
        assertEq(a0Branch1 + a1Branch1, deposit);

        (uint256 a0Branch2, uint256 a1Branch2) = UnderlyingMath
            .calculateDepositAllocationInUsd(
                USD_10000,
                deposit,
                WEIGHT_60,
                WEIGHT_40,
                uint128(59 * WEIGHT_PRECISION)
            );
        assertEq(a0Branch2 + a1Branch2, deposit);
    }

    function testCalculateDepositAllocation_ZeroDeposit_ReturnZeroForBoth()
        public
        pure
    {
        (uint256 amount0, uint256 amount1) = UnderlyingMath
            .calculateDepositAllocationInUsd(
                USD_10000,
                0,
                WEIGHT_60,
                WEIGHT_40,
                WEIGHT_50
            );
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    // =========================================================================
    //  calculateWithdrawUnderlyingAmountsInUsd
    // =========================================================================

    // ── Branch 1: targetToken0 >= currentToken0 (asset0 underweight, sell only asset1) ──

    function testCalculateWithdraw_WhenAsset0Underweight_SellOnlyAsset1()
        public
        pure
    {
        // total = $1000, effectiveWeight0 = 50% (below 60% target)
        // withdraw = $100
        // updatedTotal = 900e18
        // targetToken0 = 900e18 * 60% = 540e18
        // currentToken0 = 1000e18 * 50% = 500e18
        // 540e18 >= 500e18 → Branch 1
        (uint256 amount0, uint256 amount1) = UnderlyingMath
            .calculateWithdrawUnderlyingAmountsInUsd(
                USD_10000, // totalAssetUsdValue
                USD_1000, // withdrawAmountUsd
                WEIGHT_60, // targetWeight0
                WEIGHT_40, // targetWeight1
                WEIGHT_50 // effectiveWeight0 (50% < target 60%)
            );
        assertEq(
            amount0,
            0,
            "no asset0 should be sold when asset0 is underweight"
        );
        assertEq(amount1, USD_1000, "all withdraws from asset1");
    }

    // ── Branch 2: targetToken0 < currentToken0 (asset0 overweight, split) ────

    function testCalculateWithdraw_WhenAsset0Overweight_SplitWithdrawal()
        public
        pure
    {
        // total = $1000, effectiveWeight0 = 61% (above 60% target)
        // withdraw = $100
        // updatedTotal = 900e18
        // targetToken0 = 900e18 * 60% = 540e18
        // currentToken0 = 1000e18 * 61% = 610e18
        // 540e18 < 610e18 → Branch 2
        // amount0 = 610e18 - 540e18 = 70e18
        // amount1 = 100e18 - 70e18 = 30e18
        uint128 effectiveWeight0 = uint128(61 * WEIGHT_PRECISION); // 610_000

        (uint256 amount0, uint256 amount1) = UnderlyingMath
            .calculateWithdrawUnderlyingAmountsInUsd(
                USD_10000,
                USD_1000,
                WEIGHT_60,
                WEIGHT_40,
                effectiveWeight0
            );

        uint256 totalUsd = USD_10000;
        uint256 withdrawAmount = USD_1000;
        uint256 updatedTotal = totalUsd - withdrawAmount;
        uint256 targetToken0 = (updatedTotal * uint256(WEIGHT_60)) /
            uint256(MAX_WEIGHT);
        uint256 currentToken0 = (totalUsd * uint256(effectiveWeight0)) /
            uint256(MAX_WEIGHT);
        uint256 expectedAmount0 = currentToken0 - targetToken0;
        uint256 expectedAmount1 = withdrawAmount - expectedAmount0;

        assertEq(amount0, expectedAmount0);
        assertEq(amount1, expectedAmount1);
    }

    function testCalculateWithdraw_BothBranches_SumEqualsWithdrawAmount()
        public
        pure
    {
        uint256 withdraw = USD_1000;

        // Branch 1
        (uint256 a0B1, uint256 a1B1) = UnderlyingMath
            .calculateWithdrawUnderlyingAmountsInUsd(
                USD_10000,
                withdraw,
                WEIGHT_60,
                WEIGHT_40,
                WEIGHT_50
            );
        assertEq(a0B1 + a1B1, withdraw);

        // Branch 2
        (uint256 a0B2, uint256 a1B2) = UnderlyingMath
            .calculateWithdrawUnderlyingAmountsInUsd(
                USD_10000,
                withdraw,
                WEIGHT_60,
                WEIGHT_40,
                uint128(61 * WEIGHT_PRECISION)
            );
        assertEq(a0B2 + a1B2, withdraw);
    }

    function testCalculateWithdraw_ZeroWithdraw_ReturnZeroForBoth()
        public
        pure
    {
        (uint256 amount0, uint256 amount1) = UnderlyingMath
            .calculateWithdrawUnderlyingAmountsInUsd(
                USD_10000,
                0,
                WEIGHT_60,
                WEIGHT_40,
                WEIGHT_50
            );
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    // =========================================================================
    //  calculateEffectiveWeights
    // =========================================================================

    function testCalculateEffectiveWeights_EqualValues_ReturnHalfHalf()
        public
        pure
    {
        // token0 = 50% of total → effectiveWeight0 = 50% of MAX_WEIGHT
        (uint256 eff0, uint256 eff1) = UnderlyingMath.calculateEffectiveWeights(
            USD_10000,
            USD_20000,
            uint256(MAX_WEIGHT)
        );
        assertEq(eff0, uint256(WEIGHT_50));
        assertEq(eff1, uint256(MAX_WEIGHT) - uint256(WEIGHT_50));
    }

    function testCalculateEffectiveWeights_SixtyForty_ReturnCorrectWeights()
        public
        pure
    {
        // token0 = $600, total = $1000 → effectiveWeight0 = 60%
        (uint256 eff0, uint256 eff1) = UnderlyingMath.calculateEffectiveWeights(
            600e18,
            1_000e18,
            uint256(MAX_WEIGHT)
        );
        assertEq(eff0, uint256(WEIGHT_60));
        assertEq(eff1, uint256(WEIGHT_40));
    }

    function testCalculateEffectiveWeights_SumAlwaysEqualsTotalWeight()
        public
        pure
    {
        (uint256 eff0, uint256 eff1) = UnderlyingMath.calculateEffectiveWeights(
            700e18,
            1_000e18,
            uint256(MAX_WEIGHT)
        );
        assertEq(eff0 + eff1, uint256(MAX_WEIGHT));
    }

    function testCalculateEffectiveWeights_Token0IsZero_ReturnZeroAndFullWeight()
        public
        pure
    {
        (uint256 eff0, uint256 eff1) = UnderlyingMath.calculateEffectiveWeights(
            0,
            USD_10000,
            uint256(MAX_WEIGHT)
        );
        assertEq(eff0, 0);
        assertEq(eff1, uint256(MAX_WEIGHT));
    }

    function testCalculateEffectiveWeights_Token0EqualsTotal_ReturnFullAndZero()
        public
        pure
    {
        (uint256 eff0, uint256 eff1) = UnderlyingMath.calculateEffectiveWeights(
            USD_10000,
            USD_10000,
            uint256(MAX_WEIGHT)
        );
        assertEq(eff0, uint256(MAX_WEIGHT));
        assertEq(eff1, 0);
    }

    function testCalculateEffectiveWeights_ThirtyPercent_ReturnsCorrectWeights()
        public
        pure
    {
        // token0 = 30% of total
        (uint256 eff0, ) = UnderlyingMath.calculateEffectiveWeights(
            300e18,
            1_000e18,
            uint256(MAX_WEIGHT)
        );
        assertEq(eff0, uint256(WEIGHT_30));
    }

    function testCalculateEffectiveWeights_CustomTotalWeight_ScalesCorrectly()
        public
        pure
    {
        // Using a different totalWeight (e.g., MAX_WEIGHT is not 1_000_000)
        uint256 customTotalWeight = 200;
        (uint256 eff0, uint256 eff1) = UnderlyingMath.calculateEffectiveWeights(
            60e18,
            100e18,
            customTotalWeight
        );
        assertEq(eff0, 120); // 60% of 200
        assertEq(eff1, 80); // 40% of 200
        assertEq(eff0 + eff1, customTotalWeight);
    }

    // =========================================================================
    //  Cross-function invariant tests
    // =========================================================================

    function testInvariant_CalculateAmount1_ThenTokenAmount_RoundTrip()
        public
        pure
    {
        // Given amount0 USD, derive amount1 USD, then convert to token amounts
        uint256 amount0Usd = USD_20000; // $20 000 of WETH
        uint256 amount1Usd = UnderlyingMath
            .calculateAmount1UsdFromAmount0UsdAndIndexWeights(
                amount0Usd,
                WEIGHT_60,
                WEIGHT_40
            );

        // $20 000 of WETH → should be ≈ 10 WETH
        uint256 wethAmount = UnderlyingMath.calculateTokenAmountFromUsdValue(
            amount0Usd,
            WETH_PRICE_STD,
            STD_DECIMALS
        );
        assertEq(wethAmount, TEN_WETH);

        // amount1 USD at WBTC price
        uint256 wbtcAmount = UnderlyingMath.calculateTokenAmountFromUsdValue(
            amount1Usd,
            WBTC_PRICE_STD,
            STD_DECIMALS
        );
        assertGt(wbtcAmount, 0, "must receive some WBTC");

        // Round-trip check: USD value of received WBTC should equal amount1Usd
        uint256 recoveredUsd = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                wbtcAmount,
                WBTC_PRICE_STD,
                STD_DECIMALS
            );
        assertApproxEqAbs(recoveredUsd, amount1Usd, 1e5);
    }

    function testInvariant_EffectiveWeights_UseInDepositAllocation()
        public
        pure
    {
        // Compute effective weights, then feed into deposit allocation
        uint256 token0Usd = 590e18;
        uint256 totalUsd = 1_000e18;

        (uint256 eff0, uint256 eff1) = UnderlyingMath.calculateEffectiveWeights(
            token0Usd,
            totalUsd,
            uint256(MAX_WEIGHT)
        );
        assertEq(
            eff0 + eff1,
            uint256(MAX_WEIGHT),
            "weights must sum to MAX_WEIGHT"
        );

        // Use effectiveWeight0 in deposit allocation
        (uint256 dep0, uint256 dep1) = UnderlyingMath
            .calculateDepositAllocationInUsd(
                totalUsd,
                USD_100,
                WEIGHT_60,
                WEIGHT_40,
                uint128(eff0)
            );
        assertEq(dep0 + dep1, USD_100, "deposit sum must equal total deposit");
    }

    function testInvariant_ConvertToDecimalStd_PreservesValueRoundTrip()
        public
        pure
    {
        // 10 WBTC → std → back to WBTC decimals
        uint256 tenWbtc = 10 * ONE_WBTC;
        (uint256 scaled, ) = UnderlyingMath.convertToSpecificDecimal(
            tenWbtc,
            WBTC_DECIMALS,
            STD_DECIMALS
        );
        (uint256 restored, ) = UnderlyingMath.convertToSpecificDecimal(
            scaled,
            STD_DECIMALS,
            WBTC_DECIMALS
        );
        assertEq(restored, tenWbtc);
    }
}
