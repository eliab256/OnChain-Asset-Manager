import { fc, test } from "@fast-check/vitest";
import { priceFeedManagerAbi } from "@oam/abi";
import { bytesToHex, decodeFunctionResult, encodeFunctionData, encodeFunctionResult, getAddress } from "viem";
import { describe, expect, it } from "vitest";
import { aggregatorV3Abi } from "../abis/fragments.js";
import { PriceFeedReads } from "./PriceFeedReads.js";

const PRICE_FEED_MANAGER = getAddress("0xa12fFA0B9f159BB4C54bce579611927Addc51610");
const WBTC = getAddress("0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0");
const FEED = getAddress("0xa513E6E4b8f2a923D98304ec87F64353C4D5C853");

const address = fc.uint8Array({ minLength: 20, maxLength: 20 }).map((bytes) => getAddress(bytesToHex(bytes)));

describe("PriceFeedManager reads", () => {
  const params = { priceFeedManager: PRICE_FEED_MANAGER, asset: WBTC };
  const reads = [
    ["priceRead", PriceFeedReads.priceRead(params), "getPrice"],
    ["hasPriceFeedRead", PriceFeedReads.hasPriceFeedRead(params), "hasPriceFeed"],
    ["feedConfigRead", PriceFeedReads.feedConfigRead(params), "getPriceFeedConfig"],
    ["pendingFeedUpdateRead", PriceFeedReads.pendingFeedUpdateRead(params), "getPendingPriceFeedUpdate"],
  ] as const;

  it.each(reads)("%s calls %s(asset) on the PriceFeedManager", (_name, read, functionName) => {
    expect(read).toEqual({ address: PRICE_FEED_MANAGER, abi: priceFeedManagerAbi, functionName, args: [WBTC] });
  });

  it.each(reads)("%s is a view function that encodes", (_name, read) => {
    expect(() => encodeFunctionData(read as Parameters<typeof encodeFunctionData>[0])).not.toThrow();
    const item = priceFeedManagerAbi.find((entry) => entry.type === "function" && entry.name === read.functionName);
    expect(item?.type === "function" ? item.stateMutability : undefined).toMatch(/^(view|pure)$/);
  });
});

describe("toPendingFeedUpdate", () => {
  it("executableAt 0 means no replacement is pending", () => {
    expect(PriceFeedReads.toPendingFeedUpdate({ feed: FEED, maxDelay: 3600, executableAt: 0n })).toBeUndefined();
  });

  it("returns the pending replacement unchanged", () => {
    const pending = { feed: FEED, maxDelay: 3600, executableAt: 1_900_000_000n };
    expect(PriceFeedReads.toPendingFeedUpdate(pending)).toEqual(pending);
  });

  // The struct is decoded by viem from getPendingPriceFeedUpdate: uint32 -> number, uint64 -> bigint.
  test.prop([address, fc.integer({ min: 0, max: 2 ** 32 - 1 }), fc.bigInt({ min: 1n, max: 2n ** 64n - 1n })], { numRuns: 200 })(
    "accepts the struct exactly as viem decodes it",
    (feed, maxDelay, executableAt) => {
      const data = encodeFunctionResult({
        abi: priceFeedManagerAbi,
        functionName: "getPendingPriceFeedUpdate",
        result: { feed, maxDelay, executableAt },
      });
      const decoded = decodeFunctionResult({ abi: priceFeedManagerAbi, functionName: "getPendingPriceFeedUpdate", data });
      expect(PriceFeedReads.toPendingFeedUpdate(decoded)).toEqual({ feed, maxDelay, executableAt });
    },
  );
});

describe("latestRoundDataRead", () => {
  it("reads latestRoundData on the feed itself", () => {
    expect(PriceFeedReads.latestRoundDataRead(FEED)).toEqual({ address: FEED, abi: aggregatorV3Abi, functionName: "latestRoundData" });
  });

  it("updatedAt is the 4th value of the decoded result", () => {
    const data = encodeFunctionResult({
      abi: aggregatorV3Abi,
      functionName: "latestRoundData",
      result: [1n, 3_000_000_000_000n, 100n, 200n, 1n],
    });
    const decoded = decodeFunctionResult({ abi: aggregatorV3Abi, functionName: "latestRoundData", data });
    expect(decoded[3]).toBe(200n);
  });
});
