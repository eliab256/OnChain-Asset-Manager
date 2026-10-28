import { fc, test } from "@fast-check/vitest";
import { describe, expect, it } from "vitest";
import { MAX_TOLERANCE, MAX_WEIGHT, MIN_WEIGHT } from "../constants/public.js";
import { isValidTolerance, isValidWeight, toleranceFromBasisPoints } from "./percentages.js";

describe("toleranceFromBasisPoints", () => {
  it("maps bps to the 1e6 scale", () => {
    expect(toleranceFromBasisPoints(50n)).toBe(5_000n);
    expect(toleranceFromBasisPoints(100n)).toBe(10_000n);
    expect(toleranceFromBasisPoints(0n)).toBe(0n);
  });
});

describe("isValidTolerance (Router._validTolerance)", () => {
  it.each([
    [0n, false],
    [1n, true],
    [99_999n, true],
    [100_000n, false],
    [100_001n, false],
    [-1n, false],
  ])("tolerance %s -> %s", (tolerance, expected) => {
    expect(isValidTolerance(tolerance)).toBe(expected);
  });

  test.prop([fc.bigInt({ min: -(2n ** 64n), max: 2n ** 64n })], { numRuns: 1000 })(
    "valid exactly on the open interval (0, MAX_TOLERANCE)",
    (tolerance) => {
      expect(isValidTolerance(tolerance)).toBe(tolerance > 0n && tolerance < MAX_TOLERANCE);
    },
  );
});

describe("isValidWeight (Index.proposeUpdateWeights bounds)", () => {
  it.each([
    [10_000n, false],
    [10_001n, true],
    [500_000n, true],
    [999_999n, true],
    [1_000_000n, false],
    [0n, false],
  ])("weight %s -> %s", (weight, expected) => {
    expect(isValidWeight(weight)).toBe(expected);
  });

  test.prop([fc.bigInt({ min: 0n, max: 2n ** 128n - 1n })], { numRuns: 1000 })(
    "valid exactly on the open interval (MIN_WEIGHT, MAX_WEIGHT)",
    (weight) => {
      expect(isValidWeight(weight)).toBe(weight > MIN_WEIGHT && weight < MAX_WEIGHT);
    },
  );
});
