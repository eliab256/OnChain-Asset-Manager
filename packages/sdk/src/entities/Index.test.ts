import { fc, test } from "@fast-check/vitest";
import { describe, expect, it } from "vitest";
import { PERCENTAGE_SCALE } from "../constants/public.js";
import {
  EstimateNotFoundError,
  IndexNotInitializedError,
  InvalidDecimalsError,
  InvalidPriceError,
  InvalidToleranceError,
  ZeroAmountError,
} from "../errors.js";
import { ceilDiv } from "../utils/bigintMath.js";
import { Index, type IndexSnapshot } from "./Index.js";

const E18 = 10n ** 18n;

/** WBTC (8) / WETH (18) Index worth 6000 USD with 4000 shares: 0.1 WBTC at 30000 + 1.5 WETH at 2000. */
function baseSnapshot(overrides: Partial<IndexSnapshot> = {}): IndexSnapshot {
  return {
    address: "0x00000000000000000000000000000000000000A1",
    asset0: "0x00000000000000000000000000000000000000B0",
    asset1: "0x00000000000000000000000000000000000000B1",
    decimals0: 8,
    decimals1: 18,
    usdcDecimals: 6,
    reserve0: 10_000_000n,
    reserve1: 1_500_000_000_000_000_000n,
    weight0: 500_000n,
    weight1: 500_000n,
    feePercentage: 10_000n,
    totalFees: 0n,
    totalSupply: 4_000n * E18,
    isInitialized: true,
    priceAsset0: 30_000n * E18,
    priceAsset1: 2_000n * E18,
    priceUsdc: E18,
    ...overrides,
  };
}

describe("Index.fromSnapshot validation", () => {
  it.each([
    ["priceAsset0", 0n],
    ["priceAsset1", -1n],
    ["priceUsdc", 0n],
  ] as const)("rejects %s = %s with InvalidPriceError", (field, value) => {
    expect(() => Index.fromSnapshot(baseSnapshot({ [field]: value }))).toThrow(InvalidPriceError);
  });

  it.each([["decimals0"], ["decimals1"], ["usdcDecimals"]] as const)("rejects %s = 19 with InvalidDecimalsError", (field) => {
    expect(() => Index.fromSnapshot(baseSnapshot({ [field]: 19 }))).toThrow(InvalidDecimalsError);
  });

  it("accepts 18 decimals and a price of 1 wei", () => {
    expect(() => Index.fromSnapshot(baseSnapshot({ decimals0: 18, reserve0: E18 / 10n, priceUsdc: 1n }))).not.toThrow();
  });
});

describe("immutability", () => {
  it("freezes the snapshot", () => {
    const index = Index.fromSnapshot(baseSnapshot());
    expect(Object.isFrozen(index.snapshot)).toBe(true);
    expect(() => {
      (index.snapshot as IndexSnapshot).reserve0 = 1n;
    }).toThrow(TypeError);
  });

  it("mutating the input after construction does not change the entity", () => {
    const input = baseSnapshot();
    const index = Index.fromSnapshot(input);
    const before = index.minMintPreview(100_000_000n, 10_000n);
    input.reserve0 = 0n;
    input.totalSupply = 1n;
    input.priceAsset0 = 1n;
    expect(index.snapshot.reserve0).toBe(10_000_000n);
    expect(index.minMintPreview(100_000_000n, 10_000n)).toBe(before);
  });

  it("withPrices returns a new instance and leaves the old one unchanged", () => {
    const index = Index.fromSnapshot(baseSnapshot());
    const valuation = index.getValuation();
    const repriced = index.withPrices({ priceAsset0: 36_000n * E18, priceAsset1: 2_000n * E18, priceUsdc: E18 });
    expect(repriced).not.toBe(index);
    expect(repriced).toBeInstanceOf(Index);
    expect(index.snapshot.priceAsset0).toBe(30_000n * E18);
    expect(index.getValuation()).toEqual(valuation);
    expect(repriced.getValuation().usdValue0).toBe(3_600n * E18);
    expect(repriced.address).toBe(index.address);
  });

  it("withPrices validates the new prices", () => {
    const index = Index.fromSnapshot(baseSnapshot());
    expect(() => index.withPrices({ priceAsset0: 0n, priceAsset1: E18, priceUsdc: E18 })).toThrow(InvalidPriceError);
  });
});

describe("hand-computed example", () => {
  const index = Index.fromSnapshot(baseSnapshot());

  it("valuation: 3000 + 3000 USD, 50/50, 1.5 USD per share", () => {
    expect(index.getValuation()).toEqual({
      usdValue0: 3_000n * E18,
      usdValue1: 3_000n * E18,
      totalUsdValue: 6_000n * E18,
      effectiveWeight0: 500_000n,
      effectiveWeight1: 500_000n,
      sharePrice: 1_500_000_000_000_000_000n,
    });
  });

  it("100 USDC, fee 1%, tolerance 1%, 6000 USD, 4000 shares -> 65.34 shares", () => {
    // 100 -> 99 after fee -> 98.01 after tolerance -> 98.01 * 4000 / 6000 = 65.34
    expect(index.minMintPreview(100_000_000n, 10_000n)).toBe(65_340_000_000_000_000_000n);
  });

  it("65.34 shares, fee 1%, tolerance 1% -> 96.059601 USDC", () => {
    // 65.34 * 1.5 = 98.01 USD -> 97.0299 after fee -> 96.059601 after tolerance
    expect(index.minRedeemPreview(65_340_000_000_000_000_000n, 10_000n)).toBe(96_059_601n);
  });

  it("a USDC depeg lowers the shares minted", () => {
    const depegged = index.withPrices({ ...index.snapshot, priceUsdc: 990_000_000_000_000_000n });
    // 99 USDC * 0.99 = 98.01 USD -> 97.0299 -> * 4000 / 6000
    expect(depegged.minMintPreview(100_000_000n, 10_000n)).toBe(64_686_600_000_000_000_000n);
  });

  it("rounding of the previews is down (towards the protocol)", () => {
    // 1 USDC unit = 1e12 std -> 0.99e12 -> 0.9801e12 USD -> * 2/3 = 653_400_000_000
    expect(index.minMintPreview(1n, 10_000n)).toBe(653_400_000_000n);
    // One extra share unit adds 98.01e18 / 6000e18 < 1 unit to the result, which is dropped
    const odd = Index.fromSnapshot(baseSnapshot({ totalSupply: 4_000n * E18 + 1n }));
    expect(odd.minMintPreview(100_000_000n, 10_000n)).toBe(65_340_000_000_000_000_000n);
    // 1 share unit is worth 1.5e-18 USD: the redeem preview truncates to 0 USDC
    expect(index.minRedeemPreview(1n, 10_000n)).toBe(0n);
  });
});

describe("decimals 6, 8 and 18", () => {
  // Same USD value held with assets of different decimals gives identical numbers.
  const variants = [
    { decimals0: 6, reserve0: 100_000n, decimals1: 6, reserve1: 1_500_000n },
    { decimals0: 8, reserve0: 10_000_000n, decimals1: 18, reserve1: 1_500_000_000_000_000_000n },
    { decimals0: 18, reserve0: E18 / 10n, decimals1: 8, reserve1: 150_000_000n },
  ];

  it.each(variants)("decimals0 $decimals0 / decimals1 $decimals1", (variant) => {
    const index = Index.fromSnapshot(baseSnapshot(variant));
    expect(index.getValuation().totalUsdValue).toBe(6_000n * E18);
    expect(index.minMintPreview(100_000_000n, 10_000n)).toBe(65_340_000_000_000_000_000n);
    expect(index.minRedeemPreview(65_340_000_000_000_000_000n, 10_000n)).toBe(96_059_601n);
  });

  it("an 18-decimal USDC returns redeem previews in 18 decimals", () => {
    const index = Index.fromSnapshot(baseSnapshot({ usdcDecimals: 18 }));
    expect(index.minMintPreview(100n * E18, 10_000n)).toBe(65_340_000_000_000_000_000n);
    expect(index.minRedeemPreview(65_340_000_000_000_000_000n, 10_000n)).toBe(96_059_601_000_000_000_000n);
  });
});

describe("guards", () => {
  const uninitialized = Index.fromSnapshot(baseSnapshot({ isInitialized: false }));
  const index = Index.fromSnapshot(baseSnapshot());

  it("previews, estimates and needsRebalance throw IndexNotInitializedError on a non-initialized Index", () => {
    expect(() => uninitialized.minMintPreview(1n, 10_000n)).toThrow(IndexNotInitializedError);
    expect(() => uninitialized.minRedeemPreview(1n, 10_000n)).toThrow(IndexNotInitializedError);
    expect(() => uninitialized.needsRebalance()).toThrow(IndexNotInitializedError);
    expect(() => uninitialized.estimateUsdcForShares(1n, 10_000n)).toThrow(IndexNotInitializedError);
    expect(() => uninitialized.estimateSharesForUsdc(1n, 10_000n)).toThrow(IndexNotInitializedError);
  });

  it("getValuation works on a non-initialized Index", () => {
    expect(uninitialized.getValuation().totalUsdValue).toBe(6_000n * E18);
  });

  it.each([0n, 100_000n, 100_001n, -1n])("tolerance %s throws InvalidToleranceError", (tolerance) => {
    expect(() => index.minMintPreview(1n, tolerance)).toThrow(InvalidToleranceError);
    expect(() => index.minRedeemPreview(1n, tolerance)).toThrow(InvalidToleranceError);
    expect(() => index.estimateUsdcForShares(1n, tolerance)).toThrow(InvalidToleranceError);
    expect(() => index.estimateSharesForUsdc(1n, tolerance)).toThrow(InvalidToleranceError);
  });

  it.each([1n, 99_999n])("tolerance %s is accepted", (tolerance) => {
    expect(() => index.minMintPreview(1n, tolerance)).not.toThrow();
  });

  it.each([0n, -5n])("estimates reject a target of %s with ZeroAmountError", (target) => {
    expect(() => index.estimateUsdcForShares(target, 10_000n)).toThrow(ZeroAmountError);
    expect(() => index.estimateSharesForUsdc(target, 10_000n)).toThrow(ZeroAmountError);
  });

  it("estimates throw EstimateNotFoundError when one probe unit yields nothing", () => {
    // A share worth 1e30 USD: 1 USDC buys 0 shares.
    const expensive = Index.fromSnapshot(baseSnapshot({ totalSupply: 1n, reserve1: 10n ** 45n }));
    expect(() => expensive.estimateUsdcForShares(1n, 10_000n)).toThrow(EstimateNotFoundError);
    // A share worth almost nothing: 1e18 share units redeem 0 USDC.
    const cheap = Index.fromSnapshot(baseSnapshot({ totalSupply: 10n ** 40n }));
    expect(() => cheap.estimateSharesForUsdc(1n, 10_000n)).toThrow(EstimateNotFoundError);
  });
});

describe("supply zero", () => {
  const empty = Index.fromSnapshot(baseSnapshot({ reserve0: 0n, reserve1: 0n, totalSupply: 0n }));

  it("valuation is all zero", () => {
    expect(empty.getValuation()).toEqual({
      usdValue0: 0n,
      usdValue1: 0n,
      totalUsdValue: 0n,
      effectiveWeight0: 0n,
      effectiveWeight1: 0n,
      sharePrice: 0n,
    });
  });

  it("mints 1 share per USD after fee and tolerance, like SharesMath on an empty supply", () => {
    expect(empty.minMintPreview(100_000_000n, 10_000n)).toBe(98_010_000_000_000_000_000n);
  });

  it("redeems nothing", () => {
    expect(empty.minRedeemPreview(E18, 10_000n)).toBe(0n);
  });
});

describe("needsRebalance", () => {
  it("50/50 is balanced", () => {
    expect(Index.fromSnapshot(baseSnapshot()).needsRebalance()).toBe(false);
  });

  it("exactly 3% away is not a rebalance, just above is (both directions)", () => {
    // Both assets priced at 1 USD so the reserves are the USD values; amounts in cents.
    const at = (cents0: bigint, cents1: bigint) =>
      Index.fromSnapshot(
        baseSnapshot({ reserve0: cents0 * 10n ** 6n, priceAsset0: E18, reserve1: cents1 * 10n ** 16n, priceAsset1: E18 }),
      );
    expect(at(530_000n, 470_000n).needsRebalance()).toBe(false);
    expect(at(470_000n, 530_000n).needsRebalance()).toBe(false);
    expect(at(530_001n, 469_999n).needsRebalance()).toBe(true);
    expect(at(469_999n, 530_001n).needsRebalance()).toBe(true);
  });

  it("a 20% rise of asset0 triggers a rebalance", () => {
    const index = Index.fromSnapshot(baseSnapshot()).withPrices({ priceAsset0: 36_000n * E18, priceAsset1: 2_000n * E18, priceUsdc: E18 });
    expect(index.getValuation().effectiveWeight0).toBe(545_454n);
    expect(index.needsRebalance()).toBe(true);
  });
});

// Random but realistic Index states, built from USD values so every asset holds 1 USD to 10B USD:
// prices from 0.001 to 1M USD, USDC within 10% of the peg, share price from 0.01 to 1M USD.
// Every intermediate product stays far below uint256, so the unbounded TS bigint computes exactly
// what the contract computes (it would not revert on overflow where Solidity does).
const snapshotArb = fc
  .record({
    decimals0: fc.integer({ min: 0, max: 18 }),
    decimals1: fc.integer({ min: 0, max: 18 }),
    usdcDecimals: fc.constantFrom(6, 18),
    usd0: fc.bigInt({ min: 1n, max: 10n ** 10n }),
    usd1: fc.bigInt({ min: 1n, max: 10n ** 10n }),
    priceAsset0: fc.bigInt({ min: 10n ** 15n, max: 10n ** 24n }),
    priceAsset1: fc.bigInt({ min: 10n ** 15n, max: 10n ** 24n }),
    priceUsdc: fc.bigInt({ min: 900_000_000_000_000_000n, max: 1_100_000_000_000_000_000n }),
    sharePrice: fc.bigInt({ min: 10n ** 16n, max: 10n ** 24n }),
    weight0: fc.bigInt({ min: 10_001n, max: 999_999n }),
    feePercentage: fc.bigInt({ min: 1_000n, max: 100_000n }),
  })
  .map((r) => {
    const atLeastOne = (value: bigint) => (value === 0n ? 1n : value);
    const reserve0 = atLeastOne((r.usd0 * E18 * 10n ** BigInt(r.decimals0)) / r.priceAsset0);
    const reserve1 = atLeastOne((r.usd1 * E18 * 10n ** BigInt(r.decimals1)) / r.priceAsset1);
    // The supply is derived from the value of the reserves actually held, not from usd0 + usd1:
    // a reserve clamped to 1 unit of a 0-decimal token priced at 89 USD holds far more than the
    // 1 USD drawn, and deriving the supply from the drawn value pushed the share price to ~4e7 USD,
    // outside the range declared above (this produced the original counterexamples).
    const heldUsd =
      (reserve0 * 10n ** BigInt(18 - r.decimals0) * r.priceAsset0) / E18 +
      (reserve1 * 10n ** BigInt(18 - r.decimals1) * r.priceAsset1) / E18;
    const totalSupply = atLeastOne((heldUsd * E18) / r.sharePrice);
    return baseSnapshot({
      decimals0: r.decimals0,
      decimals1: r.decimals1,
      usdcDecimals: r.usdcDecimals,
      reserve0,
      reserve1,
      priceAsset0: r.priceAsset0,
      priceAsset1: r.priceAsset1,
      priceUsdc: r.priceUsdc,
      weight0: r.weight0,
      weight1: PERCENTAGE_SCALE - r.weight0,
      feePercentage: r.feePercentage,
      totalSupply,
    });
  });

/** Smallest input whose preview reaches `target`, by binary search: the previews are non-decreasing. */
function trueMinimum(preview: (input: bigint) => bigint, target: bigint, upper: bigint): bigint {
  let low = 0n;
  let high = upper;
  while (low < high) {
    const mid = (low + high) / 2n;
    if (preview(mid) >= target) high = mid;
    else low = mid + 1n;
  }
  return low;
}
const tolerance = fc.bigInt({ min: 1n, max: 99_999n });
const usdcAmount = fc.bigInt({ min: 0n, max: 10n ** 15n });
const sharesAmount = fc.bigInt({ min: 0n, max: 10n ** 30n });
// Targets are drawn as a fraction of the Index (up to 10x its supply or value): buying billions
// of times the supply is not a realistic exact-out request.
const fraction = fc.bigInt({ min: 1n, max: 10n ** 7n });

describe("properties", () => {
  // The JSDoc promises the smallest input: the estimate must equal the binary-search minimum, and
  // one unit less must miss the target. An overshoot means the user overpays (buy) or sells more
  // shares than needed (sell).
  test.prop([snapshotArb, fraction, tolerance], { numRuns: 1000 })(
    "estimateUsdcForShares is sufficient and minimal",
    (snapshot, part, tol) => {
      const index = Index.fromSnapshot(snapshot);
      const sharesWanted = 1n + (snapshot.totalSupply * part) / 10n ** 6n;
      const usdc = index.estimateUsdcForShares(sharesWanted, tol);
      expect(index.minMintPreview(usdc, tol) >= sharesWanted).toBe(true);
      expect(index.minMintPreview(usdc - 1n, tol) < sharesWanted).toBe(true);
      expect(usdc).toBe(trueMinimum((x) => index.minMintPreview(x, tol), sharesWanted, usdc));
    },
  );

  // Both 6- and 18-decimal USDC: the 18-decimal case used to give up on reachable targets.
  test.prop([snapshotArb, fraction, tolerance], { numRuns: 1000 })(
    "estimateSharesForUsdc is sufficient and minimal",
    (snapshot, part, tol) => {
      const index = Index.fromSnapshot(snapshot);
      const valueUsdc = index.minRedeemPreview(snapshot.totalSupply, tol);
      const usdcWanted = 1n + (valueUsdc * part) / 10n ** 6n;
      if (index.minRedeemPreview(E18, tol) === 0n) {
        expect(() => index.estimateSharesForUsdc(usdcWanted, tol)).toThrow(EstimateNotFoundError);
        return;
      }
      const shares = index.estimateSharesForUsdc(usdcWanted, tol);
      expect(index.minRedeemPreview(shares, tol) >= usdcWanted).toBe(true);
      expect(index.minRedeemPreview(shares - 1n, tol) < usdcWanted).toBe(true);
      expect(shares).toBe(trueMinimum((x) => index.minRedeemPreview(x, tol), usdcWanted, shares));
    },
  );

  test.prop([snapshotArb, usdcAmount, usdcAmount, tolerance], { numRuns: 1000 })(
    "minMintPreview is non-decreasing in the amount",
    (snapshot, a, b, tol) => {
      const index = Index.fromSnapshot(snapshot);
      const [low, high] = a <= b ? [a, b] : [b, a];
      expect(index.minMintPreview(low, tol) <= index.minMintPreview(high, tol)).toBe(true);
    },
  );

  test.prop([snapshotArb, sharesAmount, sharesAmount, tolerance], { numRuns: 1000 })(
    "minRedeemPreview is non-decreasing in the amount",
    (snapshot, a, b, tol) => {
      const index = Index.fromSnapshot(snapshot);
      const [low, high] = a <= b ? [a, b] : [b, a];
      expect(index.minRedeemPreview(low, tol) <= index.minRedeemPreview(high, tol)).toBe(true);
    },
  );

  test.prop([snapshotArb, usdcAmount, sharesAmount, tolerance, tolerance], { numRuns: 1000 })(
    "previews are non-increasing in the tolerance",
    (snapshot, usdc, shares, a, b) => {
      const index = Index.fromSnapshot(snapshot);
      const [low, high] = a <= b ? [a, b] : [b, a];
      expect(index.minMintPreview(usdc, high) <= index.minMintPreview(usdc, low)).toBe(true);
      expect(index.minRedeemPreview(shares, high) <= index.minRedeemPreview(shares, low)).toBe(true);
    },
  );

  test.prop(
    [snapshotArb, usdcAmount, sharesAmount, tolerance, fc.bigInt({ min: 0n, max: PERCENTAGE_SCALE }), fc.bigInt({ min: 0n, max: PERCENTAGE_SCALE })],
    { numRuns: 1000 },
  )("a higher fee never gives more shares or more USDC", (snapshot, usdc, shares, tol, a, b) => {
    const [low, high] = a <= b ? [a, b] : [b, a];
    const cheap = Index.fromSnapshot({ ...snapshot, feePercentage: low });
    const pricey = Index.fromSnapshot({ ...snapshot, feePercentage: high });
    expect(pricey.minMintPreview(usdc, tol) <= cheap.minMintPreview(usdc, tol)).toBe(true);
    expect(pricey.minRedeemPreview(shares, tol) <= cheap.minRedeemPreview(shares, tol)).toBe(true);
  });

  test.prop([snapshotArb], { numRuns: 1000 })("effective weights sum to PERCENTAGE_SCALE when the Index holds value", (snapshot) => {
    const valuation = Index.fromSnapshot(snapshot).getValuation();
    expect(valuation.totalUsdValue > 0n).toBe(true);
    expect(valuation.effectiveWeight0 + valuation.effectiveWeight1).toBe(PERCENTAGE_SCALE);
    expect(valuation.usdValue0 + valuation.usdValue1).toBe(valuation.totalUsdValue);
  });

  test.prop([snapshotArb, usdcAmount, tolerance], { numRuns: 1000 })(
    "buying then redeeming at the same state never returns more USDC than spent",
    (snapshot, usdc, tol) => {
      const index = Index.fromSnapshot(snapshot);
      const shares = index.minMintPreview(usdc, tol);
      expect(index.minRedeemPreview(shares, tol) <= usdc).toBe(true);
    },
  );
});

describe("estimateSharesForUsdc minimality", () => {
  // WBTC/WETH Index at Chainlink-like prices: one share redeems 1.485368 USDC, so the step is
  // ceil(1e18 / 1_485_368) share units.
  const index = Index.fromSnapshot(
    baseSnapshot({
      priceAsset0: 30_123_456_789_000_000_000_000n,
      priceAsset1: 2_012_345_678_900_000_000_000n,
      priceUsdc: 999_870_000_000_000_000n,
    }),
  );
  const tol = 5_000n;
  const step = ceilDiv(E18, index.minRedeemPreview(E18, tol));

  it("is minimal within one step for 1 USDC", () => {
    const shares = index.estimateSharesForUsdc(1_000_000n, tol);
    expect(index.minRedeemPreview(shares, tol) >= 1_000_000n).toBe(true);
    expect(index.minRedeemPreview(shares - step, tol) < 1_000_000n).toBe(true);
  });

  // The probe preview is truncated to whole USDC units, so for larger targets the linear guess
  // lands many steps above the minimum: the search must come back down from it.
  it("is minimal within one step for 100 USDC", () => {
    const shares = index.estimateSharesForUsdc(100_000_000n, tol);
    expect(index.minRedeemPreview(shares, tol) >= 100_000_000n).toBe(true);
    expect(index.minRedeemPreview(shares - step, tol) < 100_000_000n).toBe(true);
  });

  it.each([1_000_000n, 100_000_000n, 123_456_789_000n])("is the exact minimum for %s USDC units", (usdcWanted) => {
    const shares = index.estimateSharesForUsdc(usdcWanted, tol);
    expect(index.minRedeemPreview(shares, tol) >= usdcWanted).toBe(true);
    expect(index.minRedeemPreview(shares - 1n, tol) < usdcWanted).toBe(true);
  });
});

// Regression cases for the former linear-guess-then-step-up search: deterministic, so they hold
// for every seed.
describe("estimate regressions", () => {
  // Chainlink-like prices and a fee that does not divide round numbers, so the probe rounds.
  const odd = {
    priceAsset0: 30_123_456_789_000_000_000_000n,
    priceAsset1: 2_012_345_678_900_000_000_000n,
    priceUsdc: 999_870_000_000_000_000n,
    feePercentage: 7_777n,
  };
  const tol = 5_000n;

  describe("estimateUsdcForShares on shares worth ~1M USD", () => {
    const index = Index.fromSnapshot(baseSnapshot({ ...odd, totalSupply: 6_000n * 10n ** 12n + 12_345n }));
    const sharesWanted = 484_938_272_095_617n;

    it("is sufficient", () => {
      const usdc = index.estimateUsdcForShares(sharesWanted, tol);
      expect(index.minMintPreview(usdc, tol) >= sharesWanted).toBe(true);
    });

    // The truncated probe understates the slope, so the linear guess lands above the minimum:
    // here 1 USDC unit less than the guess still mints sharesWanted.
    it("is minimal, below the linear guess", () => {
      const usdc = index.estimateUsdcForShares(sharesWanted, tol);
      const probe = 10n ** 6n;
      const guess = ceilDiv(sharesWanted * probe, index.minMintPreview(probe, tol));
      expect(usdc < guess).toBe(true);
      expect(index.minMintPreview(usdc - 1n, tol) < sharesWanted).toBe(true);
    });
  });

  describe("estimateSharesForUsdc with an 18-decimal USDC", () => {
    const index = Index.fromSnapshot(baseSnapshot({ ...odd, usdcDecimals: 18 }));
    const usdcWanted = 1_000n * E18 + 123_456_789n;

    it("the target is reachable: the whole supply redeems more", () => {
      expect(index.minRedeemPreview(index.snapshot.totalSupply, tol) > usdcWanted).toBe(true);
      expect(index.minRedeemPreview(E18, tol) > 0n).toBe(true);
    });

    // With an 18-decimal USDC the fee rounds down at full precision, which favours the probe and
    // overstates the slope: the linear guess falls short by far more than a few steps. The
    // doubling search must still reach the target, and return its minimum.
    it("finds the minimal input for 1000 USDC", () => {
      const shares = index.estimateSharesForUsdc(usdcWanted, tol);
      expect(index.minRedeemPreview(shares, tol) >= usdcWanted).toBe(true);
      expect(index.minRedeemPreview(shares - 1n, tol) < usdcWanted).toBe(true);
    });
  });
});
