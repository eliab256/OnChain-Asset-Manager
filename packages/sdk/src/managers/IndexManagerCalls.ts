import {
  encodeFunctionData,
  isAddressEqual,
  keccak256,
  maxUint256,
  stringToHex,
  zeroAddress,
  zeroHash,
  type Address,
  type Hex,
} from "viem";
import { indexManagerWithErrorsAbi } from "../abis/fragments.js";
import { MAX_FEE_PERCENTAGE, MAX_WEIGHT, MIN_FEE_PERCENTAGE, MIN_WEIGHT } from "../constants/public.js";
import {
  EmptyIndexListError,
  IndexNotInitializedError,
  InvalidFeePercentageError,
  InvalidIndexAssetsError,
  InvalidWeightError,
  ValueOutOfRangeError,
  ZeroAddressError,
  ZeroAmountError,
} from "../errors.js";
import { isValidWeight } from "../utils/percentages.js";
import { assertRouteConnects, routeEndpoints, type SwapRoute } from "../utils/swapRoutes.js";
import type { MethodParameters } from "./types.js";

export type IndexManagerRole = "DEFAULT_ADMIN" | "ASSET_MANAGER" | "REBALANCER" | "FEE_COLLECTOR";

type SingleIndexParams = { indexManager: Address; index: Address };
type ManyIndexesParams = { indexManager: Address; indexes: readonly Address[] };

function call(
  indexManager: Address,
  calldata: Hex,
): MethodParameters {
  return { to: indexManager, calldata, value: 0n };
}

/** An asset of a new Index and its target weight in weight units (1_000_000 = 100%). */
export type IndexAssetParams = { asset: Address; weight: bigint };

/** The three routes the SwapManager stores for an Index, each connecting its pair in either direction. */
export type IndexRoutes = { asset0Usdc: SwapRoute; asset1Usdc: SwapRoute; asset0Asset1: SwapRoute };

function assertNonZero(operation: string, field: string, address: Address): void {
  if (isAddressEqual(address, zeroAddress)) throw new ZeroAddressError(operation, field);
}

function assertNotEmpty(operation: string, indexes: readonly Address[]): void {
  if (indexes.length === 0) throw new EmptyIndexListError(operation);
}

/**
 * Calls to the IndexManager contract (the `IndexManager` class is the manager of the Index contract). An action that fails on an
 * Index does not revert the transaction: the IndexManager emits `IndexActionFailed`, which
 * `parseIndexActionFailure` reads from the receipt logs. The required role is on each function.
 */
export abstract class IndexManagerCalls {
  /** `REBALANCER_ROLE`. */
  static rebalanceCallParameters(params: SingleIndexParams): MethodParameters {
    return call(
      params.indexManager,
      encodeFunctionData({ abi: indexManagerWithErrorsAbi, functionName: "rebalanceSingleIndex", args: [params.index] }),
    );
  }

  /** `REBALANCER_ROLE`. One transaction for many Indexes; gas grows with each Index rebalanced. @throws {EmptyIndexListError} */
  static rebalanceManyCallParameters(params: ManyIndexesParams): MethodParameters {
    assertNotEmpty("rebalanceMany", params.indexes);
    return call(
      params.indexManager,
      encodeFunctionData({
        abi: indexManagerWithErrorsAbi,
        functionName: "rebalanceMultipleIndexes",
        args: [params.indexes],
      }),
    );
  }

  /** `ASSET_MANAGER_ROLE`. Executes a weight proposal whose timelock has elapsed. */
  static executeWeightUpdateCallParameters(params: SingleIndexParams): MethodParameters {
    return call(
      params.indexManager,
      encodeFunctionData({
        abi: indexManagerWithErrorsAbi,
        functionName: "executeSingleWeightUpdate",
        args: [params.index],
      }),
    );
  }

  /** `ASSET_MANAGER_ROLE`. @throws {EmptyIndexListError} */
  static executeWeightUpdateManyCallParameters(params: ManyIndexesParams): MethodParameters {
    assertNotEmpty("executeWeightUpdateMany", params.indexes);
    return call(
      params.indexManager,
      encodeFunctionData({
        abi: indexManagerWithErrorsAbi,
        functionName: "executeWeightUpdateForMultipleIndexes",
        args: [params.indexes],
      }),
    );
  }

  /** `FEE_COLLECTOR_ROLE`. The USDC go to the caller. */
  static collectFeesCallParameters(params: SingleIndexParams): MethodParameters {
    return call(
      params.indexManager,
      encodeFunctionData({
        abi: indexManagerWithErrorsAbi,
        functionName: "collectFeesFromSingleIndex",
        args: [params.index],
      }),
    );
  }

  /** `FEE_COLLECTOR_ROLE`. @throws {EmptyIndexListError} */
  static collectFeesManyCallParameters(params: ManyIndexesParams): MethodParameters {
    assertNotEmpty("collectFeesMany", params.indexes);
    return call(
      params.indexManager,
      encodeFunctionData({
        abi: indexManagerWithErrorsAbi,
        functionName: "collectFeesFromMultipleIndexes",
        args: [params.indexes],
      }),
    );
  }

  /**
   * `ASSET_MANAGER_ROLE`. Proposes a new target weight for asset0; asset1 gets the complement.
   * The contract also rejects the current weight. @throws {InvalidWeightError}
   */
  static proposeNewWeightsCallParameters(params: SingleIndexParams & { newWeight0: bigint }): MethodParameters {
    if (!isValidWeight(params.newWeight0)) throw new InvalidWeightError(params.newWeight0, MIN_WEIGHT, MAX_WEIGHT);
    return call(
      params.indexManager,
      encodeFunctionData({
        abi: indexManagerWithErrorsAbi,
        functionName: "proposeNewWeights",
        args: [params.index, params.newWeight0],
      }),
    );
  }

  /** `ASSET_MANAGER_ROLE`. */
  static cancelWeightUpdateCallParameters(params: SingleIndexParams): MethodParameters {
    return call(
      params.indexManager,
      encodeFunctionData({ abi: indexManagerWithErrorsAbi, functionName: "cancelWeightUpdate", args: [params.index] }),
    );
  }

  /**
   * `ASSET_MANAGER_ROLE` (the MultiSig). Assets can be passed in any order: the contract sorts them and stores the
   * lower address as asset0. Both assets and USDC need a registered feed (`PriceFeedManagerCalls`). The address of
   * the new Index is in the receipt: `parseIndexCreated`.
   * @throws {ZeroAddressError} @throws {InvalidIndexAssetsError} @throws {InvalidWeightError}
   * @throws {InvalidFeePercentageError}
   */
  static createIndexCallParameters(params: {
    indexManager: Address;
    /** 1e6 scale (10_000 = 1%), between `MIN_FEE_PERCENTAGE` and `MAX_FEE_PERCENTAGE`. */
    feePercentage: bigint;
    assetA: IndexAssetParams;
    assetB: IndexAssetParams;
    /** When passed, an asset equal to USDC is rejected here instead of on-chain. */
    usdc?: Address;
  }): MethodParameters {
    const { assetA, assetB } = params;
    assertNonZero("createIndex", "assetA", assetA.asset);
    assertNonZero("createIndex", "assetB", assetB.asset);
    if (isAddressEqual(assetA.asset, assetB.asset)) {
      throw new InvalidIndexAssetsError(assetA.asset, assetB.asset, "the two assets are the same");
    }
    if (params.usdc && (isAddressEqual(assetA.asset, params.usdc) || isAddressEqual(assetB.asset, params.usdc))) {
      throw new InvalidIndexAssetsError(assetA.asset, assetB.asset, "USDC cannot be an Index asset");
    }
    for (const weight of [assetA.weight, assetB.weight]) {
      if (!isValidWeight(weight)) throw new InvalidWeightError(weight, MIN_WEIGHT, MAX_WEIGHT);
    }
    if (assetA.weight + assetB.weight !== MAX_WEIGHT) {
      throw new InvalidIndexAssetsError(
        assetA.asset,
        assetB.asset,
        `the weights sum to ${assetA.weight + assetB.weight}, expected ${MAX_WEIGHT}`,
      );
    }
    if (params.feePercentage < MIN_FEE_PERCENTAGE || params.feePercentage > MAX_FEE_PERCENTAGE) {
      throw new InvalidFeePercentageError(params.feePercentage, MIN_FEE_PERCENTAGE, MAX_FEE_PERCENTAGE);
    }
    return call(
      params.indexManager,
      encodeFunctionData({
        abi: indexManagerWithErrorsAbi,
        functionName: "createIndex",
        args: [
          Number(params.feePercentage),
          { asset: assetA.asset, weightPercentage: assetA.weight },
          { asset: assetB.asset, weightPercentage: assetB.weight },
        ],
      }),
    );
  }

  /**
   * `ASSET_MANAGER_ROLE` (the MultiSig). Registers the swap routes and seeds the Index: it pulls `amount0` of asset0
   * and the matching amount of asset1 (from the target weights and the current prices) from `depositor`, who must
   * have approved the Index for both. When the MultiSig is the depositor, the approves are MultiSig proposals too.
   * @throws {ZeroAddressError} @throws {ZeroAmountError} @throws {ValueOutOfRangeError} @throws {InvalidSwapRouteError}
   * @throws {InvalidIndexAssetsError} `tokens.asset0` not lower than `tokens.asset1`
   */
  static initializeIndexCallParameters(params: {
    indexManager: Address;
    depositor: Address;
    index: Address;
    /** Asset0 token decimals. */
    amount0: bigint;
    routes: IndexRoutes;
    /** When passed, each route must connect its pair, as the SwapManager checks on-chain. */
    tokens?: { asset0: Address; asset1: Address; usdc: Address };
  }): MethodParameters {
    assertNonZero("initializeIndex", "depositor", params.depositor);
    assertNonZero("initializeIndex", "index", params.index);
    if (params.amount0 === 0n) throw new ZeroAmountError("initializeIndex", params.amount0);
    if (params.amount0 < 0n || params.amount0 > maxUint256) {
      throw new ValueOutOfRangeError("initializeIndex", "amount0", params.amount0, maxUint256);
    }
    const { asset0Usdc, asset1Usdc, asset0Asset1 } = params.routes;
    if (params.tokens) {
      const { asset0, asset1, usdc } = params.tokens;
      if (BigInt(asset0) >= BigInt(asset1)) {
        throw new InvalidIndexAssetsError(asset0, asset1, "asset0 must be the lower address, as the Index stores them");
      }
      assertRouteConnects(asset0Usdc, asset0, usdc, "asset0Usdc");
      assertRouteConnects(asset1Usdc, asset1, usdc, "asset1Usdc");
      assertRouteConnects(asset0Asset1, asset0, asset1, "asset0Asset1");
    } else {
      [asset0Usdc, asset1Usdc, asset0Asset1].forEach(routeEndpoints);
    }
    return call(
      params.indexManager,
      encodeFunctionData({
        abi: indexManagerWithErrorsAbi,
        functionName: "initializeIndex",
        args: [params.depositor, params.index, params.amount0, asset0Usdc, asset1Usdc, asset0Asset1],
      }),
    );
  }

  /** `DEFAULT_ADMIN_ROLE` (the MultiSig). @throws {ZeroAddressError} */
  static grantRoleCallParameters(params: {
    indexManager: Address;
    role: IndexManagerRole;
    account: Address;
  }): MethodParameters {
    assertNonZero("grantRole", "account", params.account);
    return call(
      params.indexManager,
      encodeFunctionData({
        abi: indexManagerWithErrorsAbi,
        functionName: "grantRole",
        args: [IndexManagerCalls.roleHash(params.role), params.account],
      }),
    );
  }

  /** `DEFAULT_ADMIN_ROLE` (the MultiSig). @throws {ZeroAddressError} */
  static revokeRoleCallParameters(params: {
    indexManager: Address;
    role: IndexManagerRole;
    account: Address;
  }): MethodParameters {
    assertNonZero("revokeRole", "account", params.account);
    return call(
      params.indexManager,
      encodeFunctionData({
        abi: indexManagerWithErrorsAbi,
        functionName: "revokeRole",
        args: [IndexManagerCalls.roleHash(params.role), params.account],
      }),
    );
  }

  /**
   * Same check as the `isIndexInitialized` / `areIndexesInitialized` modifiers on a list already read with
   * `initializedIndexesRead`: every address in `indexes` must be in `initializedIndexes`. Use it before rebalance,
   * weight update and fee collection (single or batch): on-chain one address that is not an initialized Index makes
   * the whole batch revert. Comparison ignores the address case.
   * @throws {IndexNotInitializedError} the first address that is not an initialized Index
   */
  static checkInitialized(params: { indexes: readonly Address[]; initializedIndexes: readonly Address[] }): void {
    const initialized = new Set(params.initializedIndexes.map((index) => index.toLowerCase()));
    const missing = params.indexes.find((index) => !initialized.has(index.toLowerCase()));
    if (missing !== undefined) throw new IndexNotInitializedError(missing);
  }

  /** `keccak256("<ROLE>_ROLE")` as in IndexManager.sol; `DEFAULT_ADMIN` is the zero hash (OpenZeppelin). */
  static roleHash(role: IndexManagerRole): Hex {
    return role === "DEFAULT_ADMIN" ? zeroHash : keccak256(stringToHex(`${role}_ROLE`));
  }

  static hasRoleRead(params: { indexManager: Address; role: IndexManagerRole; account: Address }) {
    return {
      address: params.indexManager,
      abi: indexManagerWithErrorsAbi,
      functionName: "hasRole",
      args: [IndexManagerCalls.roleHash(params.role), params.account],
    } as const;
  }

  static deployedIndexesRead(indexManager: Address) {
    return { address: indexManager, abi: indexManagerWithErrorsAbi, functionName: "getDeployedIndexes" } as const;
  }

  static initializedIndexesRead(indexManager: Address) {
    return { address: indexManager, abi: indexManagerWithErrorsAbi, functionName: "getInitializedIndexes" } as const;
  }

  static isIndexInitializedRead(params: SingleIndexParams) {
    return {
      address: params.indexManager,
      abi: indexManagerWithErrorsAbi,
      functionName: "checkIsIndexInitialized",
      args: [params.index],
    } as const;
  }

  /** The zero address when no Index exists for the pair; the order of the assets does not matter. */
  static indexByAssetsRead(params: { indexManager: Address; assetA: Address; assetB: Address }) {
    return {
      address: params.indexManager,
      abi: indexManagerWithErrorsAbi,
      functionName: "getIndexByAssetsAddresses",
      args: [params.assetA, params.assetB],
    } as const;
  }
}
