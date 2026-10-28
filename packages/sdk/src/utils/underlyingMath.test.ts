import { fc, test } from "@fast-check/vitest";
import { describe, expect, it } from "vitest";
import { PERCENTAGE_SCALE, REBALANCE_THRESHOLD } from "../constants/public.js";
import {
  applyFee,
  applyTolerance,
  effectiveWeights,
  isRebalanceNeeded,
  shareValueInUsd,
  sharesToMintFromUsd,
  usdToUsdc,
  usdValueOfAmount,
  usdcToUsd,
} from "./underlyingMath.js";

const E18 = 10n ** 18n;

// Realistic bounds: 18-decimal amounts up to 1e30 (a trillion tokens) and prices up to 1e24
// ($1M), so every product stays far below uint256 and Solidity would not overflow where the
// unbounded TS bigint silently keeps going.
const amountStd = fc.bigInt({ min: 0n, max: 10n ** 30n });
const price = fc.bigInt({ min: 1n, max: 10n ** 24n });
const percentage = fc.bigInt({ min: 0n, max: PERCENTAGE_SCALE });

describe("hand-computed values", () => {
  it("usdValueOfAmount truncates like calculateUSDValueOfTokenAmountStdDecimals", () => {
    expect(usdValueOfAmount(2n * E18, 30_000n * E18)).toBe(60_000n * E18);
    expect(usdValueOfAmount(1n, E18 - 1n)).toBe(0n);
  });

  it("usdcToUsd and usdToUsdc use the USDC price", () => {
    expect(usdcToUsd(100n * E18, 999_900_000_000_000_000n)).toBe(99_990_000_000_000_000_000n);
    expect(usdToUsdc(100n * E18, 2n * E18)).toBe(50n * E18);
    expect(usdToUsdc(1n, 3n)).toBe(333_333_333_333_333_333n);
  });

  it("applyFee: 1% of 100 USDC", () => {
    expect(applyFee(100n * E18, 10_000n)).toEqual({ fee: E18, net: 99n * E18 });
    expect(applyFee(99n, 10_000n)).toEqual({ fee: 0n, net: 99n });
  });

  it("applyTolerance: 1% off 99", () => {
    expect(applyTolerance(99n * E18, 10_000n)).toBe(98_010_000_000_000_000_000n);
    expect(applyTolerance(1n, 1n)).toBe(0n);
  });

  it("sharesToMintFromUsd: 1:1 on an empty supply, proportional otherwise", () => {
    expect(sharesToMintFromUsd(5n * E18, 0n, 0n)).toBe(5n * E18);
    expect(sharesToMintFromUsd(98_010_000_000_000_000_000n, 6_000n * E18, 4_000n * E18)).toBe(65_340_000_000_000_000_000n);
  });

  it("shareValueInUsd is 0 when the Index holds nothing", () => {
    expect(shareValueInUsd(E18, 0n, 0n)).toBe(0n);
    expect(shareValueInUsd(E18, 6_000n * E18, 4_000n * E18)).toBe(1_500_000_000_000_000_000n);
  });

  it("effectiveWeights: the complement goes to asset1", () => {
    expect(effectiveWeights(1n, 3n)).toEqual({ weight0: 333_333n, weight1: 666_667n });
    expect(effectiveWeights(0n, 5n)).toEqual({ weight0: 0n, weight1: PERCENTAGE_SCALE });
  });
});

describe("isRebalanceNeeded", () => {
  it("a distance of exactly REBALANCE_THRESHOLD is not a rebalance, one more is (both directions)", () => {
    expect(isRebalanceNeeded(530_000n, 500_000n)).toBe(false);
    expect(isRebalanceNeeded(530_001n, 500_000n)).toBe(true);
    expect(isRebalanceNeeded(470_000n, 500_000n)).toBe(false);
    expect(isRebalanceNeeded(469_999n, 500_000n)).toBe(true);
  });

  it("does not underflow when the target is below the threshold", () => {
    expect(isRebalanceNeeded(0n, 20_000n)).toBe(false);
    expect(isRebalanceNeeded(60_000n, 20_000n)).toBe(true);
  });

  test.prop([percentage, percentage], { numRuns: 1000 })("is symmetric and matches the strict threshold", (a, b) => {
    const diff = a > b ? a - b : b - a;
    expect(isRebalanceNeeded(a, b)).toBe(diff > REBALANCE_THRESHOLD);
    expect(isRebalanceNeeded(a, b)).toBe(isRebalanceNeeded(b, a));
  });
});

describe("properties", () => {
  test.prop([amountStd, percentage], { numRuns: 1000 })("fee + net equals the amount and the fee rounds down", (amount, fee) => {
    const result = applyFee(amount, fee);
    expect(result.fee + result.net).toBe(amount);
    expect(result.fee * PERCENTAGE_SCALE <= amount * fee).toBe(true);
  });

  test.prop([amountStd, percentage, percentage], { numRuns: 1000 })("a higher fee never leaves more", (amount, a, b) => {
    const [low, high] = a <= b ? [a, b] : [b, a];
    expect(applyFee(amount, high).net <= applyFee(amount, low).net).toBe(true);
  });

  test.prop([amountStd, percentage, percentage], { numRuns: 1000 })("a higher tolerance never leaves more", (amount, a, b) => {
    const [low, high] = a <= b ? [a, b] : [b, a];
    expect(applyTolerance(amount, high) <= applyTolerance(amount, low)).toBe(true);
    expect(applyTolerance(amount, low) <= amount).toBe(true);
  });

  test.prop([amountStd, price], { numRuns: 1000 })("USD -> USDC -> USD never creates value", (usd, priceUsdc) => {
    expect(usdcToUsd(usdToUsdc(usd, priceUsdc), priceUsdc) <= usd).toBe(true);
  });

  test.prop([fc.bigInt({ min: 0n, max: 10n ** 30n }), fc.bigInt({ min: 1n, max: 10n ** 30n })], { numRuns: 1000 })(
    "effective weights sum to PERCENTAGE_SCALE and weight0 stays in range",
    (part, extra) => {
      const total = part + extra;
      const { weight0, weight1 } = effectiveWeights(part, total);
      expect(weight0 + weight1).toBe(PERCENTAGE_SCALE);
      expect(weight0 >= 0n && weight0 <= PERCENTAGE_SCALE).toBe(true);
    },
  );

  test.prop(
    [fc.bigInt({ min: 0n, max: 10n ** 30n }), fc.bigInt({ min: 1n, max: 10n ** 30n }), fc.bigInt({ min: 1n, max: 10n ** 30n })],
    { numRuns: 1000 },
  )("minting then valuing the new shares never returns more USD than deposited", (usd, totalUsd, totalShares) => {
    const shares = sharesToMintFromUsd(usd, totalUsd, totalShares);
    expect(shareValueInUsd(shares, totalUsd, totalShares) <= usd).toBe(true);
  });
});
