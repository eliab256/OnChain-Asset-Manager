import { fc, test } from "@fast-check/vitest";
import { priceFeedManagerAbi } from "@oam/abi";
import { bytesToHex, decodeFunctionData, getAddress, zeroAddress, type Address, type Hex } from "viem";
import { describe, expect, it } from "vitest";
import { MAX_FEED_DELAY } from "../constants/public.js";
import { InvalidMaxDelayError, ZeroAddressError } from "../errors.js";
import { PriceFeedManagerCalls } from "./PriceFeedManagerCalls.js";

const PRICE_FEED_MANAGER = getAddress("0xa12fFA0B9f159BB4C54bce579611927Addc51610");
const LINK = getAddress("0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9");
const FEED = getAddress("0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6");

const address = fc
  .uint8Array({ minLength: 20, maxLength: 20 })
  .map((bytes) => getAddress(bytesToHex(bytes)))
  .filter((value) => value !== zeroAddress);
// PriceFeedManager._validatePriceFeed: maxDelay == 0 || maxDelay > MAX_FEED_DELAY_LIMIT reverts.
const validDelay = fc.integer({ min: 1, max: MAX_FEED_DELAY });

function decode(calldata: Hex) {
  return decodeFunctionData({ abi: priceFeedManagerAbi, data: calldata });
}

// Arrows keep the static builders bound to their class (unbound-method).
type FeedParams = Parameters<typeof PriceFeedManagerCalls.registerPriceFeedCallParameters>[0];
type AssetParams = Parameters<typeof PriceFeedManagerCalls.executePriceFeedUpdateCallParameters>[0];

const feedCalls = [
  ["registerPriceFeedCallParameters", (p: FeedParams) => PriceFeedManagerCalls.registerPriceFeedCallParameters(p), "registerPriceFeed"],
  ["proposePriceFeedUpdateCallParameters", (p: FeedParams) => PriceFeedManagerCalls.proposePriceFeedUpdateCallParameters(p), "proposePriceFeedUpdate"],
] as const;

const assetCalls = [
  ["executePriceFeedUpdateCallParameters", (p: AssetParams) => PriceFeedManagerCalls.executePriceFeedUpdateCallParameters(p), "executePriceFeedUpdate"],
  ["cancelPriceFeedUpdateCallParameters", (p: AssetParams) => PriceFeedManagerCalls.cancelPriceFeedUpdateCallParameters(p), "cancelPriceFeedUpdate"],
] as const;

describe("register / propose", () => {
  it.each(feedCalls)("%s calls %s(asset, feed, maxDelay) with no value", (_name, build, functionName) => {
    const call = build({ priceFeedManager: PRICE_FEED_MANAGER, asset: LINK, feed: FEED, maxDelay: 3600 });
    expect(call.to).toBe(PRICE_FEED_MANAGER);
    expect(call.value).toBe(0n);
    expect(decode(call.calldata)).toEqual({ functionName, args: [LINK, FEED, 3600] });
  });

  test.prop([fc.constantFrom(...feedCalls), address, address, address, validDelay], { numRuns: 200 })(
    "decoded calldata equals the inputs for every valid maxDelay",
    ([, build, functionName], priceFeedManager, asset, feed, maxDelay) => {
      const call = build({ priceFeedManager, asset, feed, maxDelay });
      expect(call.to).toBe(priceFeedManager);
      expect(decode(call.calldata)).toEqual({ functionName, args: [asset, feed, maxDelay] });
    },
  );

  it.each(feedCalls)("%s accepts maxDelay 1 and MAX_FEED_DELAY (bounds of _validatePriceFeed)", (_name, build) => {
    for (const maxDelay of [1, MAX_FEED_DELAY]) {
      expect(() => build({ priceFeedManager: PRICE_FEED_MANAGER, asset: LINK, feed: FEED, maxDelay })).not.toThrow();
    }
  });

  const badDelays = [0, -1, MAX_FEED_DELAY + 1, 2 ** 32, 1.5, Number.NaN, Number.POSITIVE_INFINITY];
  it.each(feedCalls.flatMap(([name, build]) => badDelays.map((maxDelay) => [name, build, maxDelay] as const)))(
    "%s with maxDelay %s -> InvalidMaxDelayError",
    (_name, build, maxDelay) => {
      expect(() => build({ priceFeedManager: PRICE_FEED_MANAGER, asset: LINK, feed: FEED, maxDelay })).toThrow(InvalidMaxDelayError);
    },
  );

  it.each(
    feedCalls.flatMap(([name, build]) => [
      [name, build, "asset", { asset: zeroAddress, feed: FEED }] as const,
      [name, build, "feed", { asset: LINK, feed: zeroAddress }] as const,
    ]),
  )("%s with a zero %s -> ZeroAddressError", (_name, build, _field, addresses) => {
    expect(() => build({ priceFeedManager: PRICE_FEED_MANAGER, maxDelay: 3600, ...addresses })).toThrow(ZeroAddressError);
  });

  test.prop([fc.constantFrom(...feedCalls), fc.integer({ min: -(2 ** 40), max: 2 ** 40 })], { numRuns: 1000 })(
    "a maxDelay is accepted exactly when it is an integer in [1, MAX_FEED_DELAY]",
    ([, build], maxDelay) => {
      const run = () => build({ priceFeedManager: PRICE_FEED_MANAGER, asset: LINK, feed: FEED, maxDelay });
      if (maxDelay >= 1 && maxDelay <= MAX_FEED_DELAY) expect(run).not.toThrow();
      else expect(run).toThrow(InvalidMaxDelayError);
    },
  );
});

describe("execute / cancel", () => {
  it.each(assetCalls)("%s calls %s(asset) with no value", (_name, build, functionName) => {
    const call = build({ priceFeedManager: PRICE_FEED_MANAGER, asset: LINK });
    expect(call.to).toBe(PRICE_FEED_MANAGER);
    expect(call.value).toBe(0n);
    expect(decode(call.calldata)).toEqual({ functionName, args: [LINK] });
  });

  test.prop([fc.constantFrom(...assetCalls), address, address], { numRuns: 200 })(
    "decoded calldata equals the inputs",
    ([, build, functionName], priceFeedManager, asset: Address) => {
      const call = build({ priceFeedManager, asset });
      expect(call.to).toBe(priceFeedManager);
      expect(decode(call.calldata)).toEqual({ functionName, args: [asset] });
    },
  );
});
