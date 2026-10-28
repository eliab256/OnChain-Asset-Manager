import { priceFeedManagerAbi } from "@oam/abi";
import type { Address } from "viem";
import { aggregatorV3Abi } from "../abis/fragments.js";

export type PendingFeedUpdate = {
  feed: Address;
  /** Seconds. */
  maxDelay: number;
  /** Unix timestamp in seconds. */
  executableAt: bigint;
};

/**
 * Reads of the PriceFeedManager and of the Chainlink feeds. Writes (register, propose, execute, cancel) are in
 * `PriceFeedManagerCalls`.
 */
export abstract class PriceFeedReads {
  /** USD price with 18 decimals. Reverts if the feed is missing, stale or non-positive. */
  static priceRead(params: { priceFeedManager: Address; asset: Address }) {
    return {
      address: params.priceFeedManager,
      abi: priceFeedManagerAbi,
      functionName: "getPrice",
      args: [params.asset],
    } as const;
  }

  static hasPriceFeedRead(params: { priceFeedManager: Address; asset: Address }) {
    return {
      address: params.priceFeedManager,
      abi: priceFeedManagerAbi,
      functionName: "hasPriceFeed",
      args: [params.asset],
    } as const;
  }

  /** `{ feed, maxDelay }`: pass `maxDelay` and the feed's `updatedAt` to `isPriceFeedStale`. */
  static feedConfigRead(params: { priceFeedManager: Address; asset: Address }) {
    return {
      address: params.priceFeedManager,
      abi: priceFeedManagerAbi,
      functionName: "getPriceFeedConfig",
      args: [params.asset],
    } as const;
  }

  static pendingFeedUpdateRead(params: { priceFeedManager: Address; asset: Address }) {
    return {
      address: params.priceFeedManager,
      abi: priceFeedManagerAbi,
      functionName: "getPendingPriceFeedUpdate",
      args: [params.asset],
    } as const;
  }

  /** `undefined` when no replacement is pending (`executableAt` = 0). */
  static toPendingFeedUpdate(result: PendingFeedUpdate): PendingFeedUpdate | undefined {
    return result.executableAt === 0n ? undefined : result;
  }

  /** On the feed itself (address from `feedConfigRead`); `updatedAt` is the 4th value. */
  static latestRoundDataRead(feed: Address) {
    return { address: feed, abi: aggregatorV3Abi, functionName: "latestRoundData" } as const;
  }
}
