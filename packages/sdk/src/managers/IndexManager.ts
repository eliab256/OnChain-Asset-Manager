import type { Address } from "viem";
import { indexWithErrorsAbi } from "../abis/fragments.js";
import type { IndexPrices, IndexSnapshot } from "../entities/Index.js";

/** Results of `IndexManager.snapshotReads`, in the same order. */
export type IndexSnapshotResults = readonly [
  asset0: Address,
  asset1: Address,
  decimals: readonly [number, number, number],
  reserves: readonly [bigint, bigint],
  weights: readonly [bigint, bigint],
  fees: readonly [number, bigint],
  totalSupply: bigint,
  isInitialized: boolean,
];

export type PendingWeightUpdate = {
  weight0: bigint;
  weight1: bigint;
  /** Unix timestamp in seconds. */
  executableAt: bigint;
};

/**
 * Reads of the Index contract. Despite the name, the IndexManager contract is handled by
 * `IndexManagerCalls`. Writes on the Index go through the Router and the IndexManager, never directly.
 */
export abstract class IndexManager {
  /**
   * Everything `Index.fromSnapshot` needs except prices, in one batch: pass the array to wagmi
   * `useReadContracts` or viem `multicall`, then the results to `toSnapshot`.
   */
  static snapshotReads(index: Address) {
    const contract = { address: index, abi: indexWithErrorsAbi } as const;
    return [
      { ...contract, functionName: "getAsset0" },
      { ...contract, functionName: "getAsset1" },
      { ...contract, functionName: "getAssetsAndUsdcDecimals" },
      { ...contract, functionName: "getAssetsReserves" },
      { ...contract, functionName: "getAssetsWeights" },
      { ...contract, functionName: "getFeesInfo" },
      { ...contract, functionName: "totalSupply" },
      { ...contract, functionName: "getInitializationStatus" },
    ] as const;
  }

  /** Prices come from `PriceFeedReads.priceRead` for asset0, asset1 and USDC (second batch: assets are known only after the first). */
  static toSnapshot(index: Address, results: IndexSnapshotResults, prices: IndexPrices): IndexSnapshot {
    const [asset0, asset1, decimals, reserves, weights, fees, totalSupply, isInitialized] = results;
    return {
      address: index,
      asset0,
      asset1,
      decimals0: decimals[0],
      decimals1: decimals[1],
      usdcDecimals: decimals[2],
      reserve0: reserves[0],
      reserve1: reserves[1],
      weight0: weights[0],
      weight1: weights[1],
      feePercentage: BigInt(fees[0]),
      totalFees: fees[1],
      totalSupply,
      isInitialized,
      ...prices,
    };
  }

  static pendingWeightsRead(index: Address) {
    return { address: index, abi: indexWithErrorsAbi, functionName: "getAssetsPendingWeights" } as const;
  }

  /** `undefined` when no proposal is pending (the contract returns `executableAt` = 0). */
  static toPendingWeightUpdate(result: readonly [bigint, bigint, bigint]): PendingWeightUpdate | undefined {
    const [weight0, weight1, executableAt] = result;
    return executableAt === 0n ? undefined : { weight0, weight1, executableAt };
  }

  /** Computed by the contract with live prices; `Index.getValuation` gives the same from a snapshot. */
  static usdValueRead(index: Address) {
    return { address: index, abi: indexWithErrorsAbi, functionName: "getAssetsUsdValue" } as const;
  }

  static effectiveWeightsRead(index: Address) {
    return { address: index, abi: indexWithErrorsAbi, functionName: "getAssetsEffectiveWeights" } as const;
  }
}
