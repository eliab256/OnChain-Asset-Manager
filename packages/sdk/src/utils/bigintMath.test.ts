import { fc, test } from "@fast-check/vitest";
import { describe, expect, it } from "vitest";
import { absDiff, ceilDiv } from "./bigintMath.js";

// uint256 range: TS bigint is unbounded, so the bound keeps inputs representable on-chain.
const UINT256_MAX = 2n ** 256n - 1n;
const uint = fc.bigInt({ min: 0n, max: UINT256_MAX });
const positive = fc.bigInt({ min: 1n, max: UINT256_MAX });

describe("ceilDiv", () => {
  it("rounds up only when there is a remainder", () => {
    expect(ceilDiv(0n, 7n)).toBe(0n);
    expect(ceilDiv(1n, 7n)).toBe(1n);
    expect(ceilDiv(7n, 7n)).toBe(1n);
    expect(ceilDiv(8n, 7n)).toBe(2n);
    expect(ceilDiv(14n, 7n)).toBe(2n);
    expect(ceilDiv(5n, 1n)).toBe(5n);
  });

  test.prop([uint, positive], { numRuns: 1000 })("a/b <= ceilDiv(a,b) < a/b + 1 (exact rational bounds)", (a, b) => {
    const c = ceilDiv(a, b);
    // c*b >= a proves c >= a/b; (c-1)*b < a proves c < a/b + 1.
    expect(c * b >= a).toBe(true);
    expect((c - 1n) * b < a || c === 0n).toBe(true);
    expect(c >= a / b).toBe(true);
    expect(c <= a / b + 1n).toBe(true);
  });

  test.prop([uint, positive], { numRuns: 1000 })("equals floor division exactly when b divides a", (a, b) => {
    expect(ceilDiv(a, b) === a / b).toBe(a % b === 0n);
  });
});

describe("absDiff", () => {
  it("is the distance in both directions", () => {
    expect(absDiff(10n, 3n)).toBe(7n);
    expect(absDiff(3n, 10n)).toBe(7n);
    expect(absDiff(5n, 5n)).toBe(0n);
  });

  test.prop([uint, uint], { numRuns: 1000 })("is symmetric and never negative", (a, b) => {
    expect(absDiff(a, b)).toBe(absDiff(b, a));
    expect(absDiff(a, b) >= 0n).toBe(true);
    expect(absDiff(a, b)).toBe(a > b ? a - b : b - a);
  });
});
