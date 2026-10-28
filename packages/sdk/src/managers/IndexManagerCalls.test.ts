import { fc, test } from "@fast-check/vitest";
import { indexManagerAbi } from "@oam/abi";
import {
  bytesToHex,
  decodeFunctionData,
  encodeFunctionData,
  getAddress,
  keccak256,
  maxUint256,
  toHex,
  zeroAddress,
  zeroHash,
  type Address,
  type Hex,
} from "viem";
import { describe, expect, it } from "vitest";
import { indexManagerWithErrorsAbi } from "../abis/fragments.js";
import { MAX_FEE_PERCENTAGE, MAX_WEIGHT, MIN_FEE_PERCENTAGE, MIN_WEIGHT } from "../constants/public.js";
import {
  EmptyIndexListError,
  IndexNotInitializedError,
  InvalidFeePercentageError,
  InvalidIndexAssetsError,
  InvalidSwapRouteError,
  InvalidWeightError,
  ValueOutOfRangeError,
  ZeroAddressError,
  ZeroAmountError,
} from "../errors.js";
import { POOL_VERSION, v3Route, v4Route, type SwapRoute } from "../utils/swapRoutes.js";
import { IndexManagerCalls, type IndexManagerRole } from "./IndexManagerCalls.js";

const INDEX_MANAGER = getAddress("0x68B1D87F95878fE05B998F19b66F4baba5De1aed");
const INDEX = getAddress("0x2d2DF19A06b90e886EDcf42f0D9bB0147076084d");
const OTHER_INDEX = getAddress("0xBfD11c3C4B3C6870b4D54053a1B4bE5710e732A6");
const KEEPER = getAddress("0x3a5AAA255B8BFf32A00603077671B6406fAb90a9");

const address = fc.uint8Array({ minLength: 20, maxLength: 20 }).map((bytes) => getAddress(bytesToHex(bytes)));
const addressList = fc.array(address, { minLength: 1, maxLength: 10 });

function decode(calldata: Hex) {
  return decodeFunctionData({ abi: indexManagerAbi, data: calldata });
}

// Static builders are wrapped in arrows: passing them bare would detach them from the class (unbound-method).
type SingleIndexParams = Parameters<typeof IndexManagerCalls.rebalanceCallParameters>[0];
type ManyIndexesParams = Parameters<typeof IndexManagerCalls.rebalanceManyCallParameters>[0];
type RoleParams = Parameters<typeof IndexManagerCalls.grantRoleCallParameters>[0];

const single = [
  ["rebalanceCallParameters", (p: SingleIndexParams) => IndexManagerCalls.rebalanceCallParameters(p), "rebalanceSingleIndex"],
  ["executeWeightUpdateCallParameters", (p: SingleIndexParams) => IndexManagerCalls.executeWeightUpdateCallParameters(p), "executeSingleWeightUpdate"],
  ["collectFeesCallParameters", (p: SingleIndexParams) => IndexManagerCalls.collectFeesCallParameters(p), "collectFeesFromSingleIndex"],
  ["cancelWeightUpdateCallParameters", (p: SingleIndexParams) => IndexManagerCalls.cancelWeightUpdateCallParameters(p), "cancelWeightUpdate"],
] as const;

const many = [
  ["rebalanceManyCallParameters", (p: ManyIndexesParams) => IndexManagerCalls.rebalanceManyCallParameters(p), "rebalanceMultipleIndexes"],
  ["executeWeightUpdateManyCallParameters", (p: ManyIndexesParams) => IndexManagerCalls.executeWeightUpdateManyCallParameters(p), "executeWeightUpdateForMultipleIndexes"],
  ["collectFeesManyCallParameters", (p: ManyIndexesParams) => IndexManagerCalls.collectFeesManyCallParameters(p), "collectFeesFromMultipleIndexes"],
] as const;

describe("single-Index calls", () => {
  it.each(single)("%s calls %s(index) on the IndexManager with no value", (_name, build, functionName) => {
    const call = build({ indexManager: INDEX_MANAGER, index: INDEX });
    expect(call.to).toBe(INDEX_MANAGER);
    expect(call.value).toBe(0n);
    expect(decode(call.calldata)).toEqual({ functionName, args: [INDEX] });
  });

  test.prop([fc.constantFrom(...single), address, address], { numRuns: 200 })(
    "decoded calldata equals the inputs",
    ([, build, functionName], indexManager, index) => {
      const call = build({ indexManager, index });
      expect(call.to).toBe(indexManager);
      expect(decode(call.calldata)).toEqual({ functionName, args: [index] });
    },
  );
});

describe("many-Index calls", () => {
  it.each(many)("%s calls %s(indexes) with the list in order", (_name, build, functionName) => {
    const call = build({ indexManager: INDEX_MANAGER, indexes: [INDEX, OTHER_INDEX] });
    expect(call.to).toBe(INDEX_MANAGER);
    expect(call.value).toBe(0n);
    expect(decode(call.calldata)).toEqual({ functionName, args: [[INDEX, OTHER_INDEX]] });
  });

  test.prop([fc.constantFrom(...many), addressList], { numRuns: 200 })("decoded calldata equals the inputs", ([, build, functionName], indexes) => {
    expect(decode(build({ indexManager: INDEX_MANAGER, indexes }).calldata)).toEqual({ functionName, args: [indexes] });
  });

  it.each(many)("%s rejects an empty list with EmptyIndexListError", (_name, build) => {
    expect(() => build({ indexManager: INDEX_MANAGER, indexes: [] })).toThrow(EmptyIndexListError);
  });

  it.each(many)("%s does not mutate the list", (_name, build) => {
    const indexes = Object.freeze([INDEX, OTHER_INDEX]);
    build({ indexManager: INDEX_MANAGER, indexes });
    expect(indexes).toEqual([INDEX, OTHER_INDEX]);
  });
});

describe("proposeNewWeightsCallParameters", () => {
  it("calls proposeNewWeights(index, newWeight0)", () => {
    const call = IndexManagerCalls.proposeNewWeightsCallParameters({ indexManager: INDEX_MANAGER, index: INDEX, newWeight0: 600_000n });
    expect(call.to).toBe(INDEX_MANAGER);
    expect(call.value).toBe(0n);
    expect(decode(call.calldata)).toEqual({ functionName: "proposeNewWeights", args: [INDEX, 600_000n] });
  });

  test.prop([address, fc.bigInt({ min: MIN_WEIGHT + 1n, max: MAX_WEIGHT - 1n })], { numRuns: 200 })(
    "decoded calldata equals the inputs for every valid weight",
    (index, newWeight0) => {
      const call = IndexManagerCalls.proposeNewWeightsCallParameters({ indexManager: INDEX_MANAGER, index, newWeight0 });
      expect(decode(call.calldata).args).toEqual([index, newWeight0]);
    },
  );

  // Index.proposeUpdateWeights reverts when newWeight0 >= MAX_WEIGHT or <= MIN_WEIGHT.
  it.each([MIN_WEIGHT, MAX_WEIGHT, 0n, -1n, MAX_WEIGHT + 1n, 2n ** 128n])("weight %s -> InvalidWeightError", (newWeight0) => {
    expect(() =>
      IndexManagerCalls.proposeNewWeightsCallParameters({ indexManager: INDEX_MANAGER, index: INDEX, newWeight0 }),
    ).toThrow(InvalidWeightError);
  });

  it.each([MIN_WEIGHT + 1n, MAX_WEIGHT - 1n])("weight at the bound %s is accepted", (newWeight0) => {
    expect(() =>
      IndexManagerCalls.proposeNewWeightsCallParameters({ indexManager: INDEX_MANAGER, index: INDEX, newWeight0 }),
    ).not.toThrow();
  });
});

describe("roles", () => {
  // From IndexManager.sol: keccak256("<NAME>_ROLE"); DEFAULT_ADMIN_ROLE is 0x00 in AccessControl.
  it.each([
    ["ASSET_MANAGER", keccak256(toHex("ASSET_MANAGER_ROLE"))],
    ["FEE_COLLECTOR", keccak256(toHex("FEE_COLLECTOR_ROLE"))],
    ["REBALANCER", keccak256(toHex("REBALANCER_ROLE"))],
    ["DEFAULT_ADMIN", zeroHash],
  ] as const)("roleHash(%s) equals the contract constant", (role, hash) => {
    expect(IndexManagerCalls.roleHash(role)).toBe(hash);
  });

  it.each(["ASSET_MANAGER", "FEE_COLLECTOR", "REBALANCER", "DEFAULT_ADMIN"] as const)(
    "the IndexManager ABI exposes %s_ROLE",
    (role) => {
      expect(indexManagerAbi.some((item) => item.type === "function" && item.name === `${role}_ROLE`)).toBe(true);
    },
  );

  it("hasRoleRead asks hasRole(roleHash, account) on the IndexManager", () => {
    const read = IndexManagerCalls.hasRoleRead({ indexManager: INDEX_MANAGER, role: "REBALANCER", account: KEEPER });
    expect(read).toEqual({
      address: INDEX_MANAGER,
      abi: indexManagerWithErrorsAbi,
      functionName: "hasRole",
      args: [keccak256(toHex("REBALANCER_ROLE")), KEEPER],
    });
  });

  it("every role has a distinct hash", () => {
    const roles: IndexManagerRole[] = ["DEFAULT_ADMIN", "ASSET_MANAGER", "REBALANCER", "FEE_COLLECTOR"];
    expect(new Set(roles.map((role) => IndexManagerCalls.roleHash(role))).size).toBe(roles.length);
  });
});

describe("read descriptors", () => {
  const reads = [
    ["deployedIndexesRead", IndexManagerCalls.deployedIndexesRead(INDEX_MANAGER), "getDeployedIndexes", undefined],
    ["initializedIndexesRead", IndexManagerCalls.initializedIndexesRead(INDEX_MANAGER), "getInitializedIndexes", undefined],
    [
      "isIndexInitializedRead",
      IndexManagerCalls.isIndexInitializedRead({ indexManager: INDEX_MANAGER, index: INDEX }),
      "checkIsIndexInitialized",
      [INDEX],
    ],
    [
      "indexByAssetsRead",
      IndexManagerCalls.indexByAssetsRead({ indexManager: INDEX_MANAGER, assetA: INDEX, assetB: OTHER_INDEX }),
      "getIndexByAssetsAddresses",
      [INDEX, OTHER_INDEX],
    ],
  ] as const;

  it.each(reads)("%s targets the IndexManager with the merged ABI", (_name, read, functionName, args) => {
    expect(read.address).toBe(INDEX_MANAGER);
    expect(read.abi).toBe(indexManagerWithErrorsAbi);
    expect(read.functionName).toBe(functionName);
    expect("args" in read ? read.args : undefined).toEqual(args);
  });

  it.each(reads)("%s encodes as a view function of the generated IndexManager ABI", (_name, read) => {
    const data = encodeFunctionData(read as Parameters<typeof encodeFunctionData>[0]);
    expect(decodeFunctionData({ abi: indexManagerAbi, data }).functionName).toBe(read.functionName);
    const item = indexManagerAbi.find((entry) => entry.type === "function" && entry.name === read.functionName);
    expect(item?.type === "function" ? item.stateMutability : undefined).toMatch(/^(view|pure)$/);
  });
});

describe("createIndexCallParameters", () => {
  const WBTC = getAddress("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599");
  const WETH = getAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
  const USDC = getAddress("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
  const base = {
    indexManager: INDEX_MANAGER,
    feePercentage: 10_000n,
    assetA: { asset: WETH, weight: 400_000n },
    assetB: { asset: WBTC, weight: 600_000n },
    usdc: USDC,
  };
  const build = (change: Partial<typeof base> = {}) => IndexManagerCalls.createIndexCallParameters({ ...base, ...change });

  it("calls createIndex(fee, assetA, assetB) in the order given: the contract sorts them", () => {
    const call = build();
    expect(call.to).toBe(INDEX_MANAGER);
    expect(call.value).toBe(0n);
    expect(decode(call.calldata)).toEqual({
      functionName: "createIndex",
      args: [10_000, { asset: WETH, weightPercentage: 400_000n }, { asset: WBTC, weightPercentage: 600_000n }],
    });
  });

  const nonZero = address.filter((value) => value !== zeroAddress);
  test.prop(
    [nonZero, nonZero, fc.bigInt({ min: MIN_WEIGHT + 1n, max: MAX_WEIGHT - MIN_WEIGHT - 1n }), fc.bigInt({ min: MIN_FEE_PERCENTAGE, max: MAX_FEE_PERCENTAGE })],
    { numRuns: 200 },
  )("decoded calldata equals the inputs for every valid configuration", (assetA, assetB, weightA, fee) => {
    fc.pre(assetA !== assetB);
    // weightB is derived after the draw so the pair always sums to MAX_WEIGHT, as the contract requires.
    const weightB = MAX_WEIGHT - weightA;
    const call = IndexManagerCalls.createIndexCallParameters({
      indexManager: INDEX_MANAGER,
      feePercentage: fee,
      assetA: { asset: assetA, weight: weightA },
      assetB: { asset: assetB, weight: weightB },
    });
    expect(decode(call.calldata).args).toEqual([Number(fee), { asset: assetA, weightPercentage: weightA }, { asset: assetB, weightPercentage: weightB }]);
  });

  it.each([
    ["assetA", { assetA: { asset: zeroAddress, weight: 400_000n } }],
    ["assetB", { assetB: { asset: zeroAddress, weight: 600_000n } }],
  ] as const)("zero %s -> ZeroAddressError", (_name, change) => {
    expect(() => build(change)).toThrow(ZeroAddressError);
  });

  it("the same asset twice -> InvalidIndexAssetsError (IndexManager__InvalidIndexAssetsAddress)", () => {
    expect(() => build({ assetB: { asset: WETH, weight: 600_000n } })).toThrow(InvalidIndexAssetsError);
  });

  it("the same asset with different checksum case -> InvalidIndexAssetsError", () => {
    expect(() => build({ assetB: { asset: WETH.toLowerCase() as Address, weight: 600_000n } })).toThrow(InvalidIndexAssetsError);
  });

  it.each(["assetA", "assetB"] as const)("USDC as %s -> InvalidIndexAssetsError (IndexManager__UsdcCannotBeIndexAsset)", (side) => {
    const weight = side === "assetA" ? 400_000n : 600_000n;
    expect(() => build({ [side]: { asset: USDC.toLowerCase() as Address, weight } })).toThrow(InvalidIndexAssetsError);
  });

  it("without the usdc option USDC is left to the contract", () => {
    const { indexManager, feePercentage, assetB } = base;
    expect(() => IndexManagerCalls.createIndexCallParameters({ indexManager, feePercentage, assetA: { asset: USDC, weight: 400_000n }, assetB })).not.toThrow();
  });

  // createIndex: each weight strictly between MIN_WEIGHT and MAX_WEIGHT, and their sum equal to MAX_WEIGHT.
  it.each([
    [MIN_WEIGHT, MAX_WEIGHT - MIN_WEIGHT],
    [MAX_WEIGHT - MIN_WEIGHT, MIN_WEIGHT],
    [0n, MAX_WEIGHT],
    [MAX_WEIGHT, 0n],
    [-1n, MAX_WEIGHT + 1n],
  ])("weights %s / %s -> InvalidWeightError", (weightA, weightB) => {
    expect(() => build({ assetA: { asset: WETH, weight: weightA }, assetB: { asset: WBTC, weight: weightB } })).toThrow(InvalidWeightError);
  });

  it.each([
    [400_000n, 599_999n],
    [400_000n, 600_001n],
    [MIN_WEIGHT + 1n, MIN_WEIGHT + 1n],
  ])("weights %s / %s that do not sum to MAX_WEIGHT -> InvalidIndexAssetsError", (weightA, weightB) => {
    expect(() => build({ assetA: { asset: WETH, weight: weightA }, assetB: { asset: WBTC, weight: weightB } })).toThrow(
      InvalidIndexAssetsError,
    );
  });

  it("accepts the extreme valid split MIN_WEIGHT + 1 / MAX_WEIGHT - MIN_WEIGHT - 1", () => {
    expect(() =>
      build({ assetA: { asset: WETH, weight: MIN_WEIGHT + 1n }, assetB: { asset: WBTC, weight: MAX_WEIGHT - MIN_WEIGHT - 1n } }),
    ).not.toThrow();
  });

  // MIN_FEES_PERCENTAGE and MAX_FEES_PERCENTAGE are both accepted on-chain (strict < and > in the revert).
  it.each([MIN_FEE_PERCENTAGE, MAX_FEE_PERCENTAGE])("fee %s at the bound is accepted", (feePercentage) => {
    expect(decode(build({ feePercentage }).calldata).args?.[0]).toBe(Number(feePercentage));
  });

  it.each([0n, MIN_FEE_PERCENTAGE - 1n, MAX_FEE_PERCENTAGE + 1n, -1n, 2n ** 32n])("fee %s -> InvalidFeePercentageError", (feePercentage) => {
    expect(() => build({ feePercentage })).toThrow(InvalidFeePercentageError);
  });
});

describe("initializeIndexCallParameters", () => {
  const WBTC = getAddress("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599");
  const WETH = getAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
  const USDC = getAddress("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
  const MULTISIG = getAddress("0xB7f8BC63BbcaD18155201308C8f3540b07f84F5e");
  const routes = {
    asset0Usdc: v3Route([WBTC, WETH, USDC], [3000, 500]),
    asset1Usdc: v3Route([USDC, WETH], [500]),
    asset0Asset1: v4Route({ currency0: WBTC, currency1: WETH, fee: 3000, tickSpacing: 60, hooks: zeroAddress }),
  };
  const tokens = { asset0: WBTC, asset1: WETH, usdc: USDC };
  const base = { indexManager: INDEX_MANAGER, depositor: MULTISIG, index: INDEX, amount0: 10n ** 8n, routes };
  const build = (change: Partial<typeof base> & { tokens?: typeof tokens } = {}) =>
    IndexManagerCalls.initializeIndexCallParameters({ ...base, ...change });

  it("calls initializeIndex(depositor, index, amount0, routes...) with the routes as built", () => {
    const call = build({ tokens });
    expect(call.to).toBe(INDEX_MANAGER);
    expect(call.value).toBe(0n);
    const decoded = decode(call.calldata);
    expect(decoded.functionName).toBe("initializeIndex");
    const [depositor, index, amount0, r0, r1, r01] = decoded.args as readonly [Address, Address, bigint, SwapRoute, SwapRoute, SwapRoute];
    expect([depositor, index, amount0]).toEqual([MULTISIG, INDEX, 10n ** 8n]);
    for (const [got, want] of [
      [r0, routes.asset0Usdc],
      [r1, routes.asset1Usdc],
      [r01, routes.asset0Asset1],
    ] as const) {
      expect(got.version).toBe(want.version);
      expect(got.v3Path.toLowerCase()).toBe(want.v3Path.toLowerCase());
      expect(got.poolKey).toEqual(want.poolKey);
    }
    expect(r01.version).toBe(POOL_VERSION.V4);
  });

  test.prop([fc.bigInt({ min: 1n, max: maxUint256 })], { numRuns: 200 })("amount0 round-trips over uint256", (amount0) => {
    expect(decode(build({ amount0 }).calldata).args?.[2]).toBe(amount0);
  });

  it.each([
    ["depositor", { depositor: zeroAddress }],
    ["index", { index: zeroAddress }],
  ] as const)("zero %s -> ZeroAddressError", (_name, change) => {
    expect(() => build(change)).toThrow(ZeroAddressError);
  });

  it("amount0 = 0 -> ZeroAmountError (IndexManager__InvalidIndexAssetsAmount)", () => {
    expect(() => build({ amount0: 0n })).toThrow(ZeroAmountError);
  });

  it.each([-1n, maxUint256 + 1n])("amount0 %s -> ValueOutOfRangeError", (amount0) => {
    expect(() => build({ amount0 })).toThrow(ValueOutOfRangeError);
  });

  it.each(["asset0Usdc", "asset1Usdc", "asset0Asset1"] as const)("a malformed %s V3 path -> InvalidSwapRouteError even without tokens", (name) => {
    const broken: SwapRoute = { ...routes.asset0Usdc, v3Path: "0x1234" };
    expect(() => build({ routes: { ...routes, [name]: broken } })).toThrow(InvalidSwapRouteError);
  });

  it("a V4 route with both currencies zero -> InvalidSwapRouteError", () => {
    const broken: SwapRoute = { ...routes.asset0Asset1, poolKey: { ...routes.asset0Asset1.poolKey, currency0: zeroAddress, currency1: zeroAddress } };
    expect(() => build({ routes: { ...routes, asset0Asset1: broken } })).toThrow(InvalidSwapRouteError);
  });

  // The Index stores the lower address as asset0; swapped tokens would make every route check run on the wrong pair.
  it.each([
    ["swapped (asset0 > asset1)", { asset0: WETH, asset1: WBTC, usdc: USDC }],
    ["equal", { asset0: WBTC, asset1: WBTC, usdc: USDC }],
    ["equal with different case", { asset0: WBTC, asset1: WBTC.toLowerCase() as Address, usdc: USDC }],
  ])("tokens %s -> InvalidIndexAssetsError", (_name, badTokens) => {
    const swappedRoutes = {
      asset0Usdc: v3Route([badTokens.asset0, USDC], [3000]),
      asset1Usdc: v3Route([badTokens.asset1, USDC], [3000]),
      asset0Asset1: v3Route([badTokens.asset0, badTokens.asset1], [3000]),
    };
    expect(() => build({ routes: swappedRoutes, tokens: badTokens })).toThrow(InvalidIndexAssetsError);
  });

  test.prop([address, address], { numRuns: 200 })("with tokens, accepted only when asset0 < asset1", (a, b) => {
    fc.pre(a !== zeroAddress && b !== zeroAddress && a !== USDC && b !== USDC);
    const t = { asset0: a, asset1: b, usdc: USDC };
    const r = { asset0Usdc: v3Route([a, USDC], [3000]), asset1Usdc: v3Route([b, USDC], [3000]), asset0Asset1: v3Route([a, b], [3000]) };
    if (BigInt(a) < BigInt(b)) expect(() => build({ routes: r, tokens: t })).not.toThrow();
    else expect(() => build({ routes: r, tokens: t })).toThrow(InvalidIndexAssetsError);
  });

  it("without tokens, a well-formed route of the wrong pair is left to the SwapManager", () => {
    expect(() => build({ routes: { ...routes, asset0Usdc: routes.asset1Usdc } })).not.toThrow();
  });

  // Each route must connect its own pair, as SwapManager._validateRoute checks per swap type.
  it.each([
    ["asset0Usdc swapped with asset1Usdc", { ...routes, asset0Usdc: routes.asset1Usdc }],
    ["asset1Usdc swapped with asset0Usdc", { ...routes, asset1Usdc: routes.asset0Usdc }],
    ["asset0Asset1 going to USDC", { ...routes, asset0Asset1: v3Route([WBTC, USDC], [3000]) }],
  ])("with tokens, %s -> InvalidSwapRouteError", (_name, badRoutes) => {
    expect(() => build({ routes: badRoutes, tokens })).toThrow(InvalidSwapRouteError);
  });
});

describe("grantRole / revokeRole", () => {
  const ACCOUNT = KEEPER;
  const roles: IndexManagerRole[] = ["DEFAULT_ADMIN", "ASSET_MANAGER", "REBALANCER", "FEE_COLLECTOR"];
  const builders = [
    ["grantRoleCallParameters", (p: RoleParams) => IndexManagerCalls.grantRoleCallParameters(p), "grantRole"],
    ["revokeRoleCallParameters", (p: RoleParams) => IndexManagerCalls.revokeRoleCallParameters(p), "revokeRole"],
  ] as const;

  it.each(builders.flatMap(([name, build, fn]) => roles.map((role) => [name, role, build, fn] as const)))(
    "%s(%s) calls the function with roleHash and the account",
    (_name, role, build, functionName) => {
      const call = build({ indexManager: INDEX_MANAGER, role, account: ACCOUNT });
      expect(call.to).toBe(INDEX_MANAGER);
      expect(call.value).toBe(0n);
      expect(decode(call.calldata)).toEqual({ functionName, args: [IndexManagerCalls.roleHash(role), ACCOUNT] });
    },
  );

  it.each(builders)("%s with the zero account -> ZeroAddressError", (_name, build) => {
    expect(() => build({ indexManager: INDEX_MANAGER, role: "REBALANCER", account: zeroAddress })).toThrow(ZeroAddressError);
  });
});

describe("checkInitialized", () => {
  const A = getAddress("0x1111111111111111111111111111111111111111");
  const B = getAddress("0x2222222222222222222222222222222222222222");
  const C = getAddress("0x3333333333333333333333333333333333333333");
  const D = getAddress("0x4444444444444444444444444444444444444444");

  /** The error thrown by checkInitialized, or undefined; fails the test if something else is thrown. */
  function thrown(indexes: readonly Address[], initializedIndexes: readonly Address[]): IndexNotInitializedError | undefined {
    try {
      IndexManagerCalls.checkInitialized({ indexes, initializedIndexes });
    } catch (err) {
      expect(err).toBeInstanceOf(IndexNotInitializedError);
      return err as IndexNotInitializedError;
    }
    return undefined;
  }

  it("passes when every Index is initialized, in any order", () => {
    expect(thrown([B, A], [A, B, C])).toBeUndefined();
    expect(thrown([C], [A, B, C])).toBeUndefined();
  });

  it("one missing -> IndexNotInitializedError with that address", () => {
    expect(thrown([A, D, B], [A, B, C])?.index).toBe(D);
  });

  // _areIndexesInitialized loops in order and reverts on the first address that is not initialized.
  it("several missing -> the first one in the order of indexes", () => {
    expect(thrown([A, D, B, C], [A, B])?.index).toBe(D);
    expect(thrown([C, D], [A])?.index).toBe(C);
  });

  it("matches checksum and lowercase addresses both ways", () => {
    expect(thrown([A.toLowerCase() as Address], [A])).toBeUndefined();
    expect(thrown([A], [A.toLowerCase() as Address])).toBeUndefined();
    const lower = D.toLowerCase() as Address;
    expect(thrown([A, lower], [A])?.index).toBe(lower);
  });

  it("duplicates in indexes: passes when initialized, reports the missing address once at its first position", () => {
    expect(thrown([A, A, A], [A])).toBeUndefined();
    expect(thrown([A, D, D], [A])?.index).toBe(D);
  });

  it("empty lists: no index to check passes; any index against an empty registry throws", () => {
    expect(thrown([], [])).toBeUndefined();
    expect(thrown([], [A])).toBeUndefined();
    expect(thrown([A], [])?.index).toBe(A);
  });

  it("does not mutate its inputs", () => {
    const indexes = Object.freeze([A, D]);
    const initializedIndexes = Object.freeze([A]);
    thrown(indexes, initializedIndexes);
    expect(indexes).toEqual([A, D]);
    expect(initializedIndexes).toEqual([A]);
  });

  // A small pool makes overlaps between the two lists frequent; the lowercase variant checks case-insensitivity.
  const pool = fc.array(address, { minLength: 1, maxLength: 6 });
  test.prop(
    [
      pool.chain((addresses) =>
        fc.tuple(
          fc.constant(addresses),
          fc.array(fc.tuple(fc.constantFrom(...addresses), fc.boolean()), { maxLength: 8 }),
          fc.array(fc.tuple(fc.constantFrom(...addresses), fc.boolean()), { maxLength: 8 }),
        ),
      ),
    ],
    { numRuns: 200 },
  )("throws iff some index is not initialized, reporting the first such index", ([, rawIndexes, rawInitialized]) => {
    const withCase = ([value, lower]: readonly [Address, boolean]) => (lower ? (value.toLowerCase() as Address) : value);
    const indexes = rawIndexes.map(withCase);
    const initializedIndexes = rawInitialized.map(withCase);
    const initializedSet = new Set(initializedIndexes.map((value) => value.toLowerCase()));
    const firstMissing = indexes.find((value) => !initializedSet.has(value.toLowerCase()));
    const error = thrown(indexes, initializedIndexes);
    if (firstMissing === undefined) expect(error).toBeUndefined();
    else expect(error?.index).toBe(firstMissing);
  });
});
