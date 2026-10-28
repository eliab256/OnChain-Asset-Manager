import { fc, test } from "@fast-check/vitest";
import { indexAbi } from "@oam/abi";
import { bytesToHex, decodeFunctionResult, encodeFunctionData, encodeFunctionResult, getAddress } from "viem";
import { describe, expect, it } from "vitest";
import { indexWithErrorsAbi } from "../abis/fragments.js";
import { Index } from "../entities/Index.js";
import { IndexManager, type IndexSnapshotResults } from "./IndexManager.js";

const INDEX = getAddress("0x2d2DF19A06b90e886EDcf42f0D9bB0147076084d");
const WBTC = getAddress("0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0");
const WETH = getAddress("0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512");
const E18 = 10n ** 18n;
const prices = { priceAsset0: 30_000n * E18, priceAsset1: 2_000n * E18, priceUsdc: E18 };

const address = fc.uint8Array({ minLength: 20, maxLength: 20 }).map((bytes) => getAddress(bytesToHex(bytes)));
const uint128 = fc.bigInt({ min: 0n, max: 2n ** 128n - 1n });

const results: IndexSnapshotResults = [
  WBTC,
  WETH,
  [8, 18, 6],
  [10_000_000n, 1_500_000_000_000_000_000n],
  [500_000n, 500_000n],
  [10_000, 123n],
  4_000n * E18,
  true,
];

describe("snapshotReads", () => {
  const reads = IndexManager.snapshotReads(INDEX);

  it("reads the eight values toSnapshot expects, in order, from the Index", () => {
    expect(reads.map((read) => read.functionName)).toEqual([
      "getAsset0",
      "getAsset1",
      "getAssetsAndUsdcDecimals",
      "getAssetsReserves",
      "getAssetsWeights",
      "getFeesInfo",
      "totalSupply",
      "getInitializationStatus",
    ]);
    for (const read of reads) {
      expect(read.address).toBe(INDEX);
      expect(read.abi).toBe(indexWithErrorsAbi);
      expect("args" in read).toBe(false);
    }
  });

  it("every read is a view function of the generated Index ABI", () => {
    for (const read of reads) {
      const item = indexAbi.find((entry) => entry.type === "function" && entry.name === read.functionName);
      expect(item?.type === "function" ? item.stateMutability : undefined).toMatch(/^(view|pure)$/);
      expect(() => encodeFunctionData({ abi: indexAbi, functionName: read.functionName })).not.toThrow();
    }
  });

  // Round trip through the ABI: what a multicall returns for these reads must fit toSnapshot's
  // tuple types (uint8 -> number, uint32 -> number, uint128 -> bigint), so no field is misplaced.
  test.prop(
    [
      address,
      address,
      fc.tuple(fc.integer({ min: 0, max: 18 }), fc.integer({ min: 0, max: 18 }), fc.integer({ min: 0, max: 18 })),
      fc.tuple(uint128, uint128),
      fc.tuple(uint128, uint128),
      fc.tuple(fc.integer({ min: 0, max: 2 ** 32 - 1 }), uint128),
      fc.bigInt({ min: 0n, max: 2n ** 256n - 1n }),
      fc.boolean(),
    ],
    { numRuns: 200 },
  )("ABI-decoded results map to the snapshot fields", (asset0, asset1, decimals, reserves, weights, fees, totalSupply, isInitialized) => {
    const values = [asset0, asset1, decimals, reserves, weights, fees, totalSupply, isInitialized] as const;
    const decoded = reads.map((read, i) => {
      const value = values[i];
      const encoded = encodeFunctionResult({
        abi: indexAbi,
        functionName: read.functionName,
        result: value,
      });
      return decodeFunctionResult({ abi: read.abi, functionName: read.functionName, data: encoded });
    }) as unknown as IndexSnapshotResults;
    expect(IndexManager.toSnapshot(INDEX, decoded, prices)).toEqual({
      address: INDEX,
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
    });
  });
});

describe("toSnapshot", () => {
  it("maps the results and the prices into an IndexSnapshot", () => {
    expect(IndexManager.toSnapshot(INDEX, results, prices)).toEqual({
      address: INDEX,
      asset0: WBTC,
      asset1: WETH,
      decimals0: 8,
      decimals1: 18,
      usdcDecimals: 6,
      reserve0: 10_000_000n,
      reserve1: 1_500_000_000_000_000_000n,
      weight0: 500_000n,
      weight1: 500_000n,
      feePercentage: 10_000n,
      totalFees: 123n,
      totalSupply: 4_000n * E18,
      isInitialized: true,
      ...prices,
    });
  });

  it("feeds Index.fromSnapshot: the snapshot values the Index at 6000 USD", () => {
    const index = Index.fromSnapshot(IndexManager.toSnapshot(INDEX, results, prices));
    expect(index.getValuation().totalUsdValue).toBe(6_000n * E18);
    expect(index.minMintPreview(100_000_000n, 10_000n)).toBe(65_340_000_000_000_000_000n);
  });

  it("does not mutate its inputs", () => {
    const frozenPrices = Object.freeze({ ...prices });
    const frozen = Object.freeze([...results]) as unknown as IndexSnapshotResults;
    const snapshot = IndexManager.toSnapshot(INDEX, frozen, frozenPrices);
    snapshot.reserve0 = 0n;
    expect(frozen[3][0]).toBe(10_000_000n);
  });
});

describe("pending weights", () => {
  it("pendingWeightsRead targets getAssetsPendingWeights on the Index", () => {
    expect(IndexManager.pendingWeightsRead(INDEX)).toEqual({
      address: INDEX,
      abi: indexWithErrorsAbi,
      functionName: "getAssetsPendingWeights",
    });
  });

  it("toPendingWeightUpdate: executableAt 0 means no proposal", () => {
    expect(IndexManager.toPendingWeightUpdate([0n, 0n, 0n])).toBeUndefined();
    // Stale weights left in storage with executableAt 0 still mean "nothing pending".
    expect(IndexManager.toPendingWeightUpdate([600_000n, 400_000n, 0n])).toBeUndefined();
  });

  it("toPendingWeightUpdate maps a pending proposal", () => {
    expect(IndexManager.toPendingWeightUpdate([600_000n, 400_000n, 1_900_000_000n])).toEqual({
      weight0: 600_000n,
      weight1: 400_000n,
      executableAt: 1_900_000_000n,
    });
  });

  test.prop([uint128, uint128, fc.bigInt({ min: 1n, max: 2n ** 256n - 1n })], { numRuns: 200 })(
    "toPendingWeightUpdate keeps every field of a pending proposal",
    (weight0, weight1, executableAt) => {
      expect(IndexManager.toPendingWeightUpdate([weight0, weight1, executableAt])).toEqual({ weight0, weight1, executableAt });
    },
  );
});

describe("valuation reads", () => {
  it("usdValueRead and effectiveWeightsRead target the Index", () => {
    expect(IndexManager.usdValueRead(INDEX)).toEqual({ address: INDEX, abi: indexWithErrorsAbi, functionName: "getAssetsUsdValue" });
    expect(IndexManager.effectiveWeightsRead(INDEX)).toEqual({
      address: INDEX,
      abi: indexWithErrorsAbi,
      functionName: "getAssetsEffectiveWeights",
    });
  });
});
