import { fc, test } from "@fast-check/vitest";
import { describe, expect, it } from "vitest";
import { isPriceFeedStale } from "./priceFeed.js";

describe("isPriceFeedStale (PriceFeedManager.getPrice age check)", () => {
  const updatedAt = 1_800_000_000n;
  const maxDelay = 4_500;

  it("age equal to maxDelay is not stale, one second more is", () => {
    expect(isPriceFeedStale({ updatedAt, blockTimestamp: updatedAt + 4_500n, maxDelay })).toBe(false);
    expect(isPriceFeedStale({ updatedAt, blockTimestamp: updatedAt + 4_501n, maxDelay })).toBe(true);
  });

  it("a fresh round is not stale", () => {
    expect(isPriceFeedStale({ updatedAt, blockTimestamp: updatedAt, maxDelay })).toBe(false);
  });

  // maxDelay is a uint32 on-chain (at most 2 days by MAX_FEED_DELAY_LIMIT, but any uint32 is storable).
  test.prop(
    [fc.bigInt({ min: 0n, max: 2n ** 40n }), fc.bigInt({ min: 0n, max: 2n ** 33n }), fc.integer({ min: 0, max: 2 ** 32 - 1 })],
    { numRuns: 1000 },
  )("stale iff blockTimestamp - updatedAt > maxDelay", (updated, age, delay) => {
    expect(isPriceFeedStale({ updatedAt: updated, blockTimestamp: updated + age, maxDelay: delay })).toBe(
      age > BigInt(delay),
    );
  });
});
