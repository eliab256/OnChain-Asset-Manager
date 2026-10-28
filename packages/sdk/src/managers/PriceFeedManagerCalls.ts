import { encodeFunctionData, isAddressEqual, zeroAddress, type Address, type Hex } from "viem";
import { priceFeedManagerWithErrorsAbi } from "../abis/fragments.js";
import { MAX_FEED_DELAY } from "../constants/public.js";
import { InvalidMaxDelayError, ZeroAddressError } from "../errors.js";
import type { MethodParameters } from "./types.js";

type FeedParams = { priceFeedManager: Address; asset: Address; feed: Address; maxDelay: number };
type AssetParams = { priceFeedManager: Address; asset: Address };

function call(priceFeedManager: Address, calldata: Hex): MethodParameters {
  return { to: priceFeedManager, calldata, value: 0n };
}

function assertFeedParams(operation: string, params: FeedParams): void {
  if (isAddressEqual(params.asset, zeroAddress)) throw new ZeroAddressError(operation, "asset");
  if (isAddressEqual(params.feed, zeroAddress)) throw new ZeroAddressError(operation, "feed");
  if (!Number.isInteger(params.maxDelay) || params.maxDelay <= 0 || params.maxDelay > MAX_FEED_DELAY) {
    throw new InvalidMaxDelayError(params.maxDelay, MAX_FEED_DELAY);
  }
}

/**
 * Writes of the PriceFeedManager (reads are in `PriceFeedReads`). All of them require `ASSET_MANAGER_ROLE` on the
 * IndexManager, held by the MultiSig: wrap them in `MultiSigCalls.submitCallParameters`. The contract also checks
 * the asset (ERC20 with at most 18 decimals) and the feed (positive answer, at most 18 decimals).
 */
export abstract class PriceFeedManagerCalls {
  /**
   * First feed of an asset. An Index can be created only when both its assets and USDC have a feed.
   * @throws {ZeroAddressError} @throws {InvalidMaxDelayError}
   */
  static registerPriceFeedCallParameters(params: FeedParams): MethodParameters {
    assertFeedParams("registerPriceFeed", params);
    return call(
      params.priceFeedManager,
      encodeFunctionData({
        abi: priceFeedManagerWithErrorsAbi,
        functionName: "registerPriceFeed",
        args: [params.asset, params.feed, params.maxDelay],
      }),
    );
  }

  /**
   * Replacement of a registered feed: executable after 2 days, for 3 days (`PriceFeedReads.pendingFeedUpdateRead`).
   * @throws {ZeroAddressError} @throws {InvalidMaxDelayError}
   */
  static proposePriceFeedUpdateCallParameters(params: FeedParams): MethodParameters {
    assertFeedParams("proposePriceFeedUpdate", params);
    return call(
      params.priceFeedManager,
      encodeFunctionData({
        abi: priceFeedManagerWithErrorsAbi,
        functionName: "proposePriceFeedUpdate",
        args: [params.asset, params.feed, params.maxDelay],
      }),
    );
  }

  static executePriceFeedUpdateCallParameters(params: AssetParams): MethodParameters {
    return call(
      params.priceFeedManager,
      encodeFunctionData({
        abi: priceFeedManagerWithErrorsAbi,
        functionName: "executePriceFeedUpdate",
        args: [params.asset],
      }),
    );
  }

  static cancelPriceFeedUpdateCallParameters(params: AssetParams): MethodParameters {
    return call(
      params.priceFeedManager,
      encodeFunctionData({
        abi: priceFeedManagerWithErrorsAbi,
        functionName: "cancelPriceFeedUpdate",
        args: [params.asset],
      }),
    );
  }
}
