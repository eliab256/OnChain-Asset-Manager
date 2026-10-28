import { fc, test } from "@fast-check/vitest";
import { describe, expect, it } from "vitest";
import { convertDecimals, formatShares, formatUsdc, formatUsdValue, parseShares, parseUsdc } from "./decimals.js";

// uint128 is the width of the Index reserves; scaled up by at most 1e18 it stays inside uint256,
// so these inputs never overflow on-chain (TS bigint would not overflow anyway).
const UINT128_MAX = 2n ** 128n - 1n;
const amount = fc.bigInt({ min: 0n, max: UINT128_MAX });
const decimals = fc.integer({ min: 0, max: 18 });

describe("parse / format", () => {
  it("uses 6 decimals for USDC", () => {
    expect(parseUsdc("1")).toBe(1_000_000n);
    expect(parseUsdc("100.25")).toBe(100_250_000n);
    expect(formatUsdc(1_500_000n)).toBe("1.5");
  });

  it("uses 18 decimals for shares and USD values", () => {
    expect(parseShares("1")).toBe(10n ** 18n);
    expect(formatShares(65_340_000_000_000_000_000n)).toBe("65.34");
    expect(formatUsdValue(6_000n * 10n ** 18n)).toBe("6000");
  });

  test.prop([amount], { numRuns: 1000 })("formatUsdc and parseUsdc are inverse", (value) => {
    expect(parseUsdc(formatUsdc(value))).toBe(value);
  });

  test.prop([amount], { numRuns: 1000 })("formatShares and parseShares are inverse", (value) => {
    expect(parseShares(formatShares(value))).toBe(value);
  });
});

describe("convertDecimals", () => {
  it("scales up exactly and truncates when scaling down, like UnderlyingMath.convertToSpecificDecimal", () => {
    expect(convertDecimals(1n, 6, 18)).toBe(10n ** 12n);
    expect(convertDecimals(123_456_789n, 8, 18)).toBe(123_456_789n * 10n ** 10n);
    expect(convertDecimals(10n ** 12n - 1n, 18, 6)).toBe(0n);
    expect(convertDecimals(1_999_999_999_999n, 18, 6)).toBe(1n);
    expect(convertDecimals(42n, 8, 8)).toBe(42n);
  });

  test.prop([amount, decimals, decimals], { numRuns: 1000 })("round trip up then down is the identity", (value, a, b) => {
    const [low, high] = a <= b ? [a, b] : [b, a];
    expect(convertDecimals(convertDecimals(value, low, high), high, low)).toBe(value);
  });

  test.prop([amount, decimals, decimals], { numRuns: 1000 })("scaling down equals floor division", (value, a, b) => {
    const [low, high] = a <= b ? [a, b] : [b, a];
    expect(convertDecimals(value, high, low)).toBe(value / 10n ** BigInt(high - low));
  });

  test.prop([amount, decimals, decimals], { numRuns: 1000 })("down then up never exceeds the input (truncation)", (value, a, b) => {
    const [low, high] = a <= b ? [a, b] : [b, a];
    const back = convertDecimals(convertDecimals(value, high, low), low, high);
    expect(back <= value).toBe(true);
    expect(value - back < 10n ** BigInt(high - low)).toBe(true);
  });
});
