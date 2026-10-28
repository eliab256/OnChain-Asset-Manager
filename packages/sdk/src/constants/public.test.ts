import { describe, expect, it } from "vitest";
import {
  INDEX_ACTIONS,
  MAX_FEE_PERCENTAGE,
  MAX_FEED_DELAY,
  MAX_TOLERANCE,
  MIN_FEE_PERCENTAGE,
  MAX_WEIGHT,
  MIN_WEIGHT,
  PERCENTAGE_SCALE,
  REBALANCE_THRESHOLD,
  SHARES_DECIMALS,
  STANDARD_DECIMALS,
  USDC_DECIMALS,
} from "./public.js";
import { MAX_ESTIMATE_DOUBLINGS, STANDARD_UNIT } from "./internal.js";

// Expected values are recomputed from src/ContractCodeConstants.sol, not copied from public.ts:
// a drift between the two would let the SDK accept inputs the contracts reject.
const PERCENTAGE_FEE_PRECISION = 10_000n;
const WEIGHT_PRECISION = 10_000n;

describe("constants equal the on-chain values", () => {
  it("PERCENTAGE_SCALE = MAX_PERCENTAGE = 100 * PERCENTAGE_FEE_PRECISION", () => {
    expect(PERCENTAGE_SCALE).toBe(100n * PERCENTAGE_FEE_PRECISION);
  });

  it("MAX_TOLERANCE = MAX_TOLERANCE (10) * PERCENTAGE_FEE_PRECISION, as Router._validTolerance and getMaxTolerance", () => {
    expect(MAX_TOLERANCE).toBe(10n * PERCENTAGE_FEE_PRECISION);
  });

  it("weights and rebalance threshold use WEIGHT_PRECISION", () => {
    expect(MIN_WEIGHT).toBe(1n * WEIGHT_PRECISION);
    expect(MAX_WEIGHT).toBe(100n * WEIGHT_PRECISION);
    expect(REBALANCE_THRESHOLD).toBe(3n * WEIGHT_PRECISION);
    // Weights and fees share one scale in the SDK: true only because both precisions are 1e4.
    expect(MAX_WEIGHT).toBe(PERCENTAGE_SCALE);
  });

  it("fees: MIN_FEES_PERCENTAGE = PERCENTAGE_FEE_PRECISION / 10 (0.1%), MAX_FEES_PERCENTAGE = 10 * PERCENTAGE_FEE_PRECISION (10%)", () => {
    // IndexManager.sol: (1 * PERCENTAGE_FEE_PRECISION) / 10 and 10 * PERCENTAGE_FEE_PRECISION, both uint32.
    expect(MIN_FEE_PERCENTAGE).toBe((1n * PERCENTAGE_FEE_PRECISION) / 10n);
    expect(MAX_FEE_PERCENTAGE).toBe(10n * PERCENTAGE_FEE_PRECISION);
    expect(MIN_FEE_PERCENTAGE < MAX_FEE_PERCENTAGE).toBe(true);
    expect(MAX_FEE_PERCENTAGE < 2n ** 32n).toBe(true);
  });

  it("MAX_FEED_DELAY = MAX_FEED_DELAY_LIMIT = 2 days in seconds, and fits the uint32 maxDelay", () => {
    expect(MAX_FEED_DELAY).toBe(2 * 24 * 60 * 60);
    expect(Number.isInteger(MAX_FEED_DELAY)).toBe(true);
    expect(MAX_FEED_DELAY < 2 ** 32).toBe(true);
  });

  it("decimals: DECIMALS_STANDARD 18, shares 18, USDC 6 (mainnet USDC and USDCMock)", () => {
    expect(STANDARD_DECIMALS).toBe(18);
    expect(SHARES_DECIMALS).toBe(18);
    expect(USDC_DECIMALS).toBe(6);
  });

  it("INDEX_ACTIONS follows the order of enum IndexAction in src/types.sol", () => {
    expect(INDEX_ACTIONS).toEqual([
      "INITIALIZE",
      "REBALANCE",
      "PROPOSE_WEIGHTS",
      "EXECUTE_WEIGHTS",
      "CANCEL_WEIGHTS",
      "COLLECT_FEES",
    ]);
  });
});

describe("internal constants", () => {
  it("STANDARD_UNIT is 10^STANDARD_DECIMALS", () => {
    expect(STANDARD_UNIT).toBe(10n ** BigInt(STANDARD_DECIMALS));
  });

  // The estimates double from a guess of at least 1: 256 doublings reach 2^256, past maxUint256,
  // so the limit never cuts off a target an uint256 input could reach.
  it("MAX_ESTIMATE_DOUBLINGS is an integer that covers the whole uint256 range", () => {
    expect(Number.isInteger(MAX_ESTIMATE_DOUBLINGS)).toBe(true);
    expect(2n ** BigInt(MAX_ESTIMATE_DOUBLINGS) > 2n ** 256n - 1n).toBe(true);
  });
});
