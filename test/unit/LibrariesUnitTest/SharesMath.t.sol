// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {SharesMath} from "../../../src/libraries/SharesMath.sol";


contract SharesMathTest is Test {

    // =========================================================================
    //  Constants — no magic numbers
    // =========================================================================

    /// @dev 100% expressed with 4-decimal precision: 100 * 10_000 = 1_000_000
    uint256 constant MAX_PERCENTAGE = 1_000_000;

    /// @dev 4-decimal precision base unit (1% = 10_000)
    uint256 constant PERCENTAGE_FEE_PRECISION = 10_000;

    /// @dev 1% fee expressed in 4-decimal precision
    uint256 constant FEE_ONE_PERCENT = 1 * PERCENTAGE_FEE_PRECISION;

    /// @dev 5% tolerance expressed in 4-decimal precision
    uint256 constant TOLERANCE_FIVE_PERCENT = 5 * PERCENTAGE_FEE_PRECISION;

    /// @dev 50% tolerance expressed in 4-decimal precision
    uint256 constant TOLERANCE_FIFTY_PERCENT = 50 * PERCENTAGE_FEE_PRECISION;

    /// @dev 99% tolerance (1% left)
    uint256 constant TOLERANCE_NINETY_NINE_PERCENT = 99 * PERCENTAGE_FEE_PRECISION;

    /// @dev Minimal non-zero USDC deposit ($1 000 in 18-dec standard)
    uint256 constant USDC_DEPOSIT_1000 = 1_000e18;

    /// @dev Larger USDC deposit ($10 000 in 18-dec standard)
    uint256 constant USDC_DEPOSIT_10000 = 10_000e18;

    /// @dev Index total USD value after initialization ($40 000 in 18-dec standard)
    uint256 constant TOTAL_USD_VALUE_40000 = 40_000e18;

    /// @dev Total supply of shares after initialization (equal to initial USD value)
    uint256 constant TOTAL_SHARES_40000 = 40_000e18;

    /// @dev Shares representing half the supply
    uint256 constant HALF_SHARES = TOTAL_SHARES_40000 / 2;

    /// @dev Shares representing one quarter of the supply
    uint256 constant QUARTER_SHARES = TOTAL_SHARES_40000 / 4;

    // =========================================================================
    //  calculateSharesToMintFromUsdcAmount
    // =========================================================================

    // ── Branch 1: totalShares == 0 (first mint) ───────────────────────────────

    function testCalculateSharesToMint_WhenTotalSharesIsZero_ReturnUsdcAmount()
        public
        pure
    {
        // First mint: totalShares == 0 → shares = usdcAmount (1:1 ratio)
        uint256 result = SharesMath.calculateSharesToMintFromUsdcAmount(
            USDC_DEPOSIT_1000,
            0, // totalAssetUsdValue irrelevant for this branch
            0  // totalShares == 0
        );
        assertEq(result, USDC_DEPOSIT_1000);
    }

    function testCalculateSharesToMint_WhenTotalSharesIsZeroAndZeroDeposit_ReturnZero()
        public
        pure
    {
        uint256 result = SharesMath.calculateSharesToMintFromUsdcAmount(0, 0, 0);
        assertEq(result, 0);
    }

    function testCalculateSharesToMint_WhenTotalSharesIsZero_TotalAssetUsdValueIsIgnored()
        public
        pure
    {
        // totalAssetUsdValue should be irrelevant when totalShares == 0
        uint256 result = SharesMath.calculateSharesToMintFromUsdcAmount(
            USDC_DEPOSIT_1000,
            TOTAL_USD_VALUE_40000, // non-zero but ignored
            0
        );
        assertEq(result, USDC_DEPOSIT_1000);
    }

    // ── Branch 2: totalShares > 0 (subsequent mints) ─────────────────────────

    function testCalculateSharesToMint_WhenIndexIsBalanced_ReturnProportionalShares()
        public
        pure
    {
        // Deposit $1 000 into a $40 000 index with 40 000 shares.
        // Expected: 1000 / 40000 * 40000 = 1000 shares
        uint256 result = SharesMath.calculateSharesToMintFromUsdcAmount(
            USDC_DEPOSIT_1000,
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        assertEq(result, USDC_DEPOSIT_1000);
    }

    function testCalculateSharesToMint_LargeDeposit_ReturnProportionalShares()
        public
        pure
    {
        // Deposit $10 000 into a $40 000 index with 40 000 shares.
        // Expected: 10000 / 40000 * 40000 = 10000 shares
        uint256 result = SharesMath.calculateSharesToMintFromUsdcAmount(
            USDC_DEPOSIT_10000,
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        assertEq(result, USDC_DEPOSIT_10000);
    }

    function testCalculateSharesToMint_DoubleIndexValue_ReturnHalfShares()
        public
        pure
    {
        // Index grew: same shares (40 000) now back $80 000 USD.
        // Deposit $1 000 → 1000/80000 * 40000 = 500 shares
        uint256 doubledUsdValue = TOTAL_USD_VALUE_40000 * 2;
        uint256 expected = USDC_DEPOSIT_1000 * TOTAL_SHARES_40000 / doubledUsdValue;

        uint256 result = SharesMath.calculateSharesToMintFromUsdcAmount(
            USDC_DEPOSIT_1000,
            doubledUsdValue,
            TOTAL_SHARES_40000
        );
        assertEq(result, expected);
    }

    function testCalculateSharesToMint_ZeroDeposit_ReturnZero() public pure {
        uint256 result = SharesMath.calculateSharesToMintFromUsdcAmount(
            0,
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        assertEq(result, 0);
    }

    function testCalculateSharesToMint_DepositEqualsFullIndexValue_ReturnSameShares()
        public
        pure
    {
        // Depositing exactly the current index value should double the supply
        // (1:1 ratio maintained)
        uint256 result = SharesMath.calculateSharesToMintFromUsdcAmount(
            TOTAL_USD_VALUE_40000,
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        assertEq(result, TOTAL_SHARES_40000);
    }

    function testCalculateSharesToMint_SharesCanDifferFromUsdcWhenRatioChanges()
        public
        pure
    {
        // If index appreciated to $80 000, 1 USDC = 0.5 shares
        uint256 appreciatedValue = TOTAL_USD_VALUE_40000 * 2;
        uint256 result = SharesMath.calculateSharesToMintFromUsdcAmount(
            USDC_DEPOSIT_1000,
            appreciatedValue,
            TOTAL_SHARES_40000
        );
        assertLt(result, USDC_DEPOSIT_1000, "shares should be fewer than USDC deposited");
    }

    // =========================================================================
    //  calculateShareValueInUsd
    // =========================================================================

    // ── Branch 1: totalAssetUsdValue == 0 ────────────────────────────────────

    function testCalculateShareValue_WhenTotalAssetUsdValueIsZero_ReturnZero()
        public
        pure
    {
        uint256 result = SharesMath.calculateShareValueInUsd(
            HALF_SHARES,
            0, // totalAssetUsdValue == 0
            TOTAL_SHARES_40000
        );
        assertEq(result, 0);
    }

    function testCalculateShareValue_WhenTotalAssetUsdValueIsZeroAndSharesZero_ReturnZero()
        public
        pure
    {
        uint256 result = SharesMath.calculateShareValueInUsd(0, 0, 0);
        assertEq(result, 0);
    }

    // ── Branch 2: totalAssetUsdValue > 0 ─────────────────────────────────────

    function testCalculateShareValue_HalfShares_ReturnHalfUsdValue() public pure {
        // Half the shares → half the USD value
        uint256 result = SharesMath.calculateShareValueInUsd(
            HALF_SHARES,
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        assertEq(result, TOTAL_USD_VALUE_40000 / 2);
    }

    function testCalculateShareValue_AllShares_ReturnFullUsdValue() public pure {
        uint256 result = SharesMath.calculateShareValueInUsd(
            TOTAL_SHARES_40000,
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        assertEq(result, TOTAL_USD_VALUE_40000);
    }

    function testCalculateShareValue_QuarterShares_ReturnQuarterUsdValue()
        public
        pure
    {
        uint256 result = SharesMath.calculateShareValueInUsd(
            QUARTER_SHARES,
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        assertEq(result, TOTAL_USD_VALUE_40000 / 4);
    }

    function testCalculateShareValue_ZeroShares_ReturnZero() public pure {
        uint256 result = SharesMath.calculateShareValueInUsd(
            0,
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        assertEq(result, 0);
    }

    function testCalculateShareValue_OneShare_ReturnCorrectValue() public pure {
        // 1 share out of 40 000 total → 1/40 000 of $40 000 = $1
        uint256 result = SharesMath.calculateShareValueInUsd(
            1e18,                  // 1 share in 18-dec
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        assertEq(result, 1e18); // $1 in 18-dec standard
    }

    function testCalculateShareValue_TotalSharesDifferentFromUsdValue_ReturnsProportional()
        public
        pure
    {
        // 500 shares from a 2000-share supply, total value = $40 000
        // Expected: 500/2000 * 40000 = $10 000
        uint256 totalShares = 2_000e18;
        uint256 sharesAmount = 500e18;
        uint256 expected = sharesAmount * TOTAL_USD_VALUE_40000 / totalShares;

        uint256 result = SharesMath.calculateShareValueInUsd(
            sharesAmount,
            TOTAL_USD_VALUE_40000,
            totalShares
        );
        assertEq(result, expected);
    }

    // =========================================================================
    //  calculateNetAmountFromTolerance
    // =========================================================================

    function testCalculateNetAmount_ZeroTolerance_ReturnFullAmount() public pure {
        // tolerance = 0 → net = amount * maxPercentage / maxPercentage = amount
        uint256 result = SharesMath.calculateNetAmountFromTolerance(
            USDC_DEPOSIT_1000,
            0,
            MAX_PERCENTAGE
        );
        assertEq(result, USDC_DEPOSIT_1000);
    }

    function testCalculateNetAmount_OnePercentTolerance_ReturnNinetyNinePercent()
        public
        pure
    {
        // tolerance = 1% → net = amount * 99% / 100%
        uint256 expected = USDC_DEPOSIT_1000 * (MAX_PERCENTAGE - FEE_ONE_PERCENT) / MAX_PERCENTAGE;
        uint256 result = SharesMath.calculateNetAmountFromTolerance(
            USDC_DEPOSIT_1000,
            FEE_ONE_PERCENT,
            MAX_PERCENTAGE
        );
        assertEq(result, expected);
    }

    function testCalculateNetAmount_FivePercentTolerance_ReturnNinetyFivePercent()
        public
        pure
    {
        uint256 expected = USDC_DEPOSIT_1000 * (MAX_PERCENTAGE - TOLERANCE_FIVE_PERCENT) / MAX_PERCENTAGE;
        uint256 result = SharesMath.calculateNetAmountFromTolerance(
            USDC_DEPOSIT_1000,
            TOLERANCE_FIVE_PERCENT,
            MAX_PERCENTAGE
        );
        assertEq(result, expected);
    }

    function testCalculateNetAmount_FiftyPercentTolerance_ReturnHalfAmount()
        public
        pure
    {
        uint256 result = SharesMath.calculateNetAmountFromTolerance(
            USDC_DEPOSIT_1000,
            TOLERANCE_FIFTY_PERCENT,
            MAX_PERCENTAGE
        );
        assertEq(result, USDC_DEPOSIT_1000 / 2);
    }

    function testCalculateNetAmount_NinetyNinePercentTolerance_ReturnOnePercent()
        public
        pure
    {
        // tolerance = 99% → net = amount * 1% = amount / 100
        uint256 expected = USDC_DEPOSIT_1000 * PERCENTAGE_FEE_PRECISION / MAX_PERCENTAGE;
        uint256 result = SharesMath.calculateNetAmountFromTolerance(
            USDC_DEPOSIT_1000,
            TOLERANCE_NINETY_NINE_PERCENT,
            MAX_PERCENTAGE
        );
        assertEq(result, expected);
    }

    function testCalculateNetAmount_ZeroAmount_ReturnZero() public pure {
        uint256 result = SharesMath.calculateNetAmountFromTolerance(
            0,
            TOLERANCE_FIVE_PERCENT,
            MAX_PERCENTAGE
        );
        assertEq(result, 0);
    }

    function testCalculateNetAmount_ToleranceEqualsMaxMinusOne_ReturnMinimalAmount()
        public
        pure
    {
        // tolerance = MAX_PERCENTAGE - 1 → net = amount * 1 / MAX_PERCENTAGE
        uint256 tolerance = MAX_PERCENTAGE - 1;
        uint256 expected = USDC_DEPOSIT_1000 / MAX_PERCENTAGE;
        uint256 result = SharesMath.calculateNetAmountFromTolerance(
            USDC_DEPOSIT_1000,
            tolerance,
            MAX_PERCENTAGE
        );
        assertEq(result, expected);
    }

    function testCalculateNetAmount_LargerAmount_ScalesLinearly() public pure {
        uint256 smallResult = SharesMath.calculateNetAmountFromTolerance(
            USDC_DEPOSIT_1000,
            FEE_ONE_PERCENT,
            MAX_PERCENTAGE
        );
        uint256 largeResult = SharesMath.calculateNetAmountFromTolerance(
            USDC_DEPOSIT_10000,
            FEE_ONE_PERCENT,
            MAX_PERCENTAGE
        );
        assertEq(largeResult, smallResult * 10);
    }

    // =========================================================================
    //  Invariant checks
    // =========================================================================

    function testCalculateSharesToMint_InvariantSharesProportionalToDeposit()
        public
        pure
    {
        uint256 shares1 = SharesMath.calculateSharesToMintFromUsdcAmount(
            USDC_DEPOSIT_1000,
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        uint256 shares2 = SharesMath.calculateSharesToMintFromUsdcAmount(
            USDC_DEPOSIT_10000,
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        assertEq(shares2, shares1 * 10, "shares must scale linearly with deposit");
    }

    function testCalculateShareValue_InvariantFullRedemptionEqualsFullValue()
        public
        pure
    {
        uint256 value = SharesMath.calculateShareValueInUsd(
            TOTAL_SHARES_40000,
            TOTAL_USD_VALUE_40000,
            TOTAL_SHARES_40000
        );
        assertEq(value, TOTAL_USD_VALUE_40000);
    }

    function testCalculateNetAmount_InvariantResultAlwaysLeOrEqualToAmount()
        public
        pure
    {
        uint256 result = SharesMath.calculateNetAmountFromTolerance(
            USDC_DEPOSIT_1000,
            TOLERANCE_FIVE_PERCENT,
            MAX_PERCENTAGE
        );
        assertLe(result, USDC_DEPOSIT_1000);
    }

    function testCalculateNetAmount_InvariantZeroToleranceReturnsExactAmount()
        public
        pure
    {
        uint256 result = SharesMath.calculateNetAmountFromTolerance(
            USDC_DEPOSIT_10000,
            0,
            MAX_PERCENTAGE
        );
        assertEq(result, USDC_DEPOSIT_10000);
    }
}
