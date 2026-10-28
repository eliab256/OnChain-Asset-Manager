import { fc, test } from "@fast-check/vitest";
import { indexAbi, indexManagerAbi } from "@oam/abi";
import {
  bytesToHex,
  concat,
  encodeAbiParameters,
  encodeEventTopics,
  erc20Abi,
  getAddress,
  toFunctionSelector,
  type Address,
  type Hex,
  type Log,
} from "viem";
import { describe, expect, it } from "vitest";
import { INDEX_ACTIONS, MAX_WEIGHT, MIN_WEIGHT, type IndexAction } from "../constants/public.js";
import { EventNotFoundError, UnknownIndexActionError } from "../errors.js";
import {
  encodeIndexActionFailedLog,
  encodeIndexCreatedLog,
  parseIndexCreated,
  type IndexCreatedEvent,
  encodeSharesBurnedLog,
  encodeSharesMintedLog,
  failureReasonOf,
  parseCollectFeesBatch,
  parseIndexActionFailure,
  parseRebalanceBatch,
  parseSharesBurned,
  parseSharesMinted,
  parseWeightUpdateBatch,
  type CollectFeesBatchResult,
  type FailureReason,
  type RebalanceBatchResult,
  type RebalanceReserves,
  type SharesBurnedEvent,
  type SharesMintedEvent,
  type WeightUpdateBatchResult,
  type WeightUpdateRebalance,
} from "./indexEvents.js";
import { protocolErrorsAbi } from "../abis/fragments.js";
import { encodeProtocolError } from "./revertData.js";

const INDEX = getAddress("0x2d2DF19A06b90e886EDcf42f0D9bB0147076084d");
const OTHER_INDEX = getAddress("0xBfD11c3C4B3C6870b4D54053a1B4bE5710e732A6");
const INDEX_MANAGER = getAddress("0x68B1D87F95878fE05B998F19b66F4baba5De1aed");
// A token or pool touched in the same transaction, able to emit an event with the same signature.
const ATTACKER = getAddress("0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0");
const USER = getAddress("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
const KEEPER = getAddress("0x3a5AAA255B8BFf32A00603077671B6406fAb90a9");

const address = fc.uint8Array({ minLength: 20, maxLength: 20 }).map((bytes) => getAddress(bytesToHex(bytes)));
// Event fields are uint256 on-chain; encodeAbiParameters rejects anything outside that range.
const uint256 = fc.bigInt({ min: 0n, max: 2n ** 256n - 1n });
const bytes = fc.uint8Array({ maxLength: 200 }).map((value) => bytesToHex(value));
const action = fc.constantFrom(...INDEX_ACTIONS);

const mintedArb = fc.record({
  user: address,
  sharesMinted: uint256,
  asset0Amount: uint256,
  asset1Amount: uint256,
  usdcAmountIn: uint256,
  feeAmount: uint256,
});
const burnedArb = fc.record({
  user: address,
  sharesBurned: uint256,
  asset0Amount: uint256,
  asset1Amount: uint256,
  usdcAmountOut: uint256,
  feeAmount: uint256,
});

const minted: SharesMintedEvent = {
  user: USER,
  sharesMinted: 65_340_000_000_000_000_000n,
  asset0Amount: 165_000n,
  asset1Amount: 24_750_000_000_000_000n,
  usdcAmountIn: 100_000_000n,
  feeAmount: 1_000_000n,
};
const burned: SharesBurnedEvent = {
  user: USER,
  sharesBurned: 65_340_000_000_000_000_000n,
  asset0Amount: 163_350n,
  asset1Amount: 24_502_500_000_000_000n,
  usdcAmountOut: 97_029_900n,
  feeAmount: 980_100n,
};

/** The same log re-addressed, as if another contract emitted it. */
function from<T extends { address: Hex }>(emitter: Hex, log: T): T {
  return { ...log, address: emitter };
}

describe("SharesMinted", () => {
  test.prop([address, mintedArb], { numRuns: 200 })("parse(encode(x)) equals x", (index, event) => {
    expect(parseSharesMinted([encodeSharesMintedLog(index, event)], index)).toEqual(event);
  });

  it("encodes the topics viem expects: signature then the indexed user", () => {
    const log = encodeSharesMintedLog(INDEX, minted);
    expect(log.address).toBe(INDEX);
    expect(log.topics).toHaveLength(2);
    expect(log.topics[1]?.toLowerCase()).toBe(`0x${"0".repeat(24)}${USER.slice(2).toLowerCase()}`);
  });

  it("matches the emitter case-insensitively, as receipts may not be checksummed", () => {
    const log = from(INDEX.toLowerCase() as Hex, encodeSharesMintedLog(INDEX, minted));
    expect(parseSharesMinted([log], INDEX)).toEqual(minted);
  });

  it("security: ignores a SharesMinted spoofed by another contract in the same transaction", () => {
    const spoofed = encodeSharesMintedLog(ATTACKER, { ...minted, sharesMinted: 10n ** 30n });
    const genuine = encodeSharesMintedLog(INDEX, minted);
    expect(parseSharesMinted([spoofed, genuine], INDEX)).toEqual(minted);
  });

  it("security: only a spoofed log -> EventNotFoundError", () => {
    expect(() => parseSharesMinted([encodeSharesMintedLog(ATTACKER, minted)], INDEX)).toThrow(EventNotFoundError);
  });

  it("ignores the SharesMinted of another Index in the same transaction", () => {
    expect(() => parseSharesMinted([encodeSharesMintedLog(OTHER_INDEX, minted)], INDEX)).toThrow(EventNotFoundError);
  });

  it("EventNotFoundError on empty logs, or when the Index emitted only SharesBurned", () => {
    expect(() => parseSharesMinted([], INDEX)).toThrow(EventNotFoundError);
    expect(() => parseSharesMinted([encodeSharesBurnedLog(INDEX, burned)], INDEX)).toThrow(EventNotFoundError);
  });

  it("skips unrelated and undecodable logs instead of throwing", () => {
    const junk = { ...encodeSharesMintedLog(INDEX, minted), topics: [`0x${"ab".repeat(32)}`] as [Hex], data: "0x" as Hex };
    expect(parseSharesMinted([junk, encodeSharesMintedLog(INDEX, minted)], INDEX)).toEqual(minted);
  });

  it("does not mutate the logs it receives", () => {
    const logs = Object.freeze([Object.freeze(encodeSharesMintedLog(INDEX, minted))]);
    expect(() => parseSharesMinted(logs, INDEX)).not.toThrow();
  });
});

describe("SharesBurned", () => {
  test.prop([address, burnedArb], { numRuns: 200 })("parse(encode(x)) equals x", (index, event) => {
    expect(parseSharesBurned([encodeSharesBurnedLog(index, event)], index)).toEqual(event);
  });

  it("security: ignores a SharesBurned spoofed by another contract", () => {
    const spoofed = encodeSharesBurnedLog(ATTACKER, { ...burned, usdcAmountOut: 10n ** 30n });
    expect(parseSharesBurned([spoofed, encodeSharesBurnedLog(INDEX, burned)], INDEX)).toEqual(burned);
    expect(() => parseSharesBurned([spoofed], INDEX)).toThrow(EventNotFoundError);
  });

  it("EventNotFoundError when the Index emitted only SharesMinted", () => {
    expect(() => parseSharesBurned([encodeSharesMintedLog(INDEX, minted)], INDEX)).toThrow(EventNotFoundError);
  });

  it("the error names the event and the expected emitter", () => {
    try {
      parseSharesBurned([], INDEX);
      expect.unreachable();
    } catch (error) {
      expect(error).toBeInstanceOf(EventNotFoundError);
      expect(error).toMatchObject({ eventName: "SharesBurned", emitter: INDEX });
    }
  });
});

describe("IndexActionFailed", () => {
  test.prop([address, address, address, action, bytes], { numRuns: 200 })(
    "parse(encode(x)) equals x",
    (indexManager, index, caller, failedAction, reasonData) => {
      const log = encodeIndexActionFailedLog(indexManager, { index, caller, action: failedAction, reasonData });
      const parsed = parseIndexActionFailure([log], { indexManager, index });
      expect(parsed).toMatchObject({ index, caller, action: failedAction, reasonData });
    },
  );

  it("decodes a protocol revert in reasonData", () => {
    const reasonData = encodeProtocolError({ errorName: "Index__RebalanceNotNeeded" });
    const log = encodeIndexActionFailedLog(INDEX_MANAGER, { index: INDEX, caller: KEEPER, action: "REBALANCE", reasonData });
    expect(parseIndexActionFailure([log], { indexManager: INDEX_MANAGER, index: INDEX })).toEqual({
      index: INDEX,
      caller: KEEPER,
      action: "REBALANCE",
      reasonData,
      errorName: "Index__RebalanceNotNeeded",
      args: [],
    });
  });

  it("decodes arguments of a protocol revert", () => {
    const reasonData = encodeProtocolError({ errorName: "ERC20InsufficientBalance", args: [INDEX, 1n, 2n] });
    const log = encodeIndexActionFailedLog(INDEX_MANAGER, { index: INDEX, caller: KEEPER, action: "COLLECT_FEES", reasonData });
    const failure = parseIndexActionFailure([log], { indexManager: INDEX_MANAGER, index: INDEX });
    expect(failure?.errorName).toBe("ERC20InsufficientBalance");
    expect(failure?.args).toEqual([INDEX, 1n, 2n]);
  });

  it("an empty or foreign revert keeps the raw data with no error name", () => {
    for (const reasonData of ["0x", "0xdeadbeef"] as const) {
      const log = encodeIndexActionFailedLog(INDEX_MANAGER, { index: INDEX, caller: KEEPER, action: "REBALANCE", reasonData });
      expect(parseIndexActionFailure([log], { indexManager: INDEX_MANAGER, index: INDEX })).toMatchObject({
        reasonData,
        errorName: undefined,
        args: [],
      });
    }
  });

  it("undefined when the action succeeded (no IndexActionFailed in the logs)", () => {
    expect(parseIndexActionFailure([], { indexManager: INDEX_MANAGER, index: INDEX })).toBeUndefined();
    expect(parseIndexActionFailure([encodeSharesMintedLog(INDEX, minted)], { indexManager: INDEX_MANAGER, index: INDEX })).toBeUndefined();
  });

  // A swap during a rebalance touches pools and tokens: any of them can emit a fake failure to
  // make a keeper believe the action failed (or hide a real failure behind a fake one).
  it("security: ignores an IndexActionFailed spoofed by another contract", () => {
    const spoofed = encodeIndexActionFailedLog(ATTACKER, { index: INDEX, caller: KEEPER, action: "REBALANCE", reasonData: "0x" });
    expect(parseIndexActionFailure([spoofed], { indexManager: INDEX_MANAGER, index: INDEX })).toBeUndefined();
  });

  it("security: the genuine failure wins over a spoofed one placed before it", () => {
    const spoofed = encodeIndexActionFailedLog(ATTACKER, { index: INDEX, caller: ATTACKER, action: "INITIALIZE", reasonData: "0x" });
    const genuine = encodeIndexActionFailedLog(INDEX_MANAGER, { index: INDEX, caller: KEEPER, action: "REBALANCE", reasonData: "0x" });
    expect(parseIndexActionFailure([spoofed, genuine], { indexManager: INDEX_MANAGER, index: INDEX })).toMatchObject({
      caller: KEEPER,
      action: "REBALANCE",
    });
  });

  it("in a batch, returns only the failure of the requested Index", () => {
    const other = encodeIndexActionFailedLog(INDEX_MANAGER, { index: OTHER_INDEX, caller: KEEPER, action: "REBALANCE", reasonData: "0x" });
    expect(parseIndexActionFailure([other], { indexManager: INDEX_MANAGER, index: INDEX })).toBeUndefined();
    expect(parseIndexActionFailure([other], { indexManager: INDEX_MANAGER, index: OTHER_INDEX })?.index).toBe(OTHER_INDEX);
  });

  it("an action id outside INDEX_ACTIONS throws UnknownIndexActionError", () => {
    // Built by hand: the SDK encoder only accepts known actions. Simulates a contract upgrade
    // that appends an enum value the SDK does not know yet.
    const topics = encodeEventTopics({
      abi: indexManagerAbi,
      eventName: "IndexActionFailed",
      args: { indexAddress: INDEX, caller: KEEPER, action: INDEX_ACTIONS.length },
    }) as Hex[];
    const log = {
      ...encodeIndexActionFailedLog(INDEX_MANAGER, { index: INDEX, caller: KEEPER, action: "REBALANCE", reasonData: "0x" }),
      topics: topics as [Hex, ...Hex[]],
      data: encodeAbiParameters([{ type: "bytes" }], ["0x"]),
    } satisfies Log<bigint, number, boolean>;
    expect(() => parseIndexActionFailure([log], { indexManager: INDEX_MANAGER, index: INDEX })).toThrow(UnknownIndexActionError);
  });

  it.each(INDEX_ACTIONS.map((name, id) => [name, id] as const))("action %s is encoded as enum value %i", (name, id) => {
    const log = encodeIndexActionFailedLog(INDEX_MANAGER, { index: INDEX, caller: KEEPER, action: name, reasonData: "0x" });
    expect(BigInt(log.topics[3] ?? "0x")).toBe(BigInt(id));
  });
});

// ─── Batch outcomes ───────────────────────────────────────────────────────────
//
// The SDK has no public encoder for the success event and the Index events of the batches, and
// must not get one for the tests: the logs are built here with viem, as the contracts emit them
// (src/events/*.sol), in the order of IndexManager._tryIndexAction and Index.executeWeightUpdate.

type ReceiptLog = Log<bigint, number, boolean>;

const THIRD_INDEX = getAddress("0x5FC8d32690cc91D4c39d9d3abcBD16989F875707");
// A registered Index that is not part of the batch being parsed.
const UNLISTED_INDEX = getAddress("0xa513E6E4b8f2a923D98304ec87F64353C4D5C853");
const USDC = getAddress("0x5FbDB2315678afecb367f032d93F642f64180aa3");
const POOL = getAddress("0x610178dA211FEF7D417bC0e6FeD39F05609AD788");
const LISTED = [INDEX, OTHER_INDEX, THIRD_INDEX] as const;

// Selectors of src/libraries/RevertData.sol, written out so the test does not depend on how viem decodes them.
const ERROR_STRING_SELECTOR = "0x08c379a0";
const PANIC_SELECTOR = "0x4e487b71";

function rawLog(address: Address, topics: readonly (Hex | Hex[] | null)[], data: Hex): ReceiptLog {
  const flat = topics.filter((topic): topic is Hex => typeof topic === "string");
  return {
    address,
    topics: flat as [Hex, ...Hex[]],
    data,
    blockHash: null,
    blockNumber: null,
    logIndex: null,
    transactionHash: null,
    transactionIndex: null,
    removed: false,
  };
}

function triggeredLog(emitter: Address, index: Address, action: IndexAction): ReceiptLog {
  const topics = encodeEventTopics({
    abi: indexManagerAbi,
    eventName: "IndexActionTriggered",
    args: { indexAddress: index, caller: KEEPER, action: INDEX_ACTIONS.indexOf(action) },
  });
  return rawLog(emitter, topics, "0x");
}

function failedLog(emitter: Address, index: Address, action: IndexAction, reasonData: Hex): ReceiptLog {
  return encodeIndexActionFailedLog(emitter, { index, caller: KEEPER, action, reasonData });
}

function rebalancedLog(emitter: Address, reserves: RebalanceReserves): ReceiptLog {
  return rawLog(
    emitter,
    encodeEventTopics({ abi: indexAbi, eventName: "IndexRebalanced" }),
    encodeAbiParameters(
      [{ type: "uint256" }, { type: "uint256" }, { type: "uint256" }, { type: "uint256" }],
      [reserves.asset0ReserveBefore, reserves.asset1ReserveBefore, reserves.asset0ReserveAfter, reserves.asset1ReserveAfter],
    ),
  );
}

function weightsUpdatedLog(emitter: Address, weight0: bigint): ReceiptLog {
  return rawLog(
    emitter,
    encodeEventTopics({ abi: indexAbi, eventName: "WeightsUpdated" }),
    encodeAbiParameters([{ type: "uint128" }, { type: "uint128" }], [weight0, MAX_WEIGHT - weight0]),
  );
}

function skippedLog(emitter: Address): ReceiptLog {
  return rawLog(emitter, encodeEventTopics({ abi: indexAbi, eventName: "WeightsUpdateRebalanceSkipped" }), "0x");
}

function rebalanceFailedLog(emitter: Address, reasonData: Hex): ReceiptLog {
  return rawLog(
    emitter,
    encodeEventTopics({ abi: indexAbi, eventName: "WeightsUpdateRebalanceFailed" }),
    encodeAbiParameters([{ type: "bytes" }], [reasonData]),
  );
}

function feesCollectedLog(emitter: Address, feeAmount: bigint): ReceiptLog {
  return rawLog(
    emitter,
    encodeEventTopics({ abi: indexAbi, eventName: "FeesCollected", args: { feeCollector: KEEPER } }),
    encodeAbiParameters([{ type: "uint256" }], [feeAmount]),
  );
}

function transferLog(token: Address, from: Address, to: Address, value: bigint): ReceiptLog {
  return rawLog(
    token,
    encodeEventTopics({ abi: erc20Abi, eventName: "Transfer", args: { from, to } }),
    encodeAbiParameters([{ type: "uint256" }], [value]),
  );
}

function junkLog(emitter: Address): ReceiptLog {
  return rawLog(emitter, [`0x${"ab".repeat(32)}`], "0x1234");
}

type ReasonCase = { reasonData: Hex; reason: FailureReason };

const NOT_NEEDED = encodeProtocolError({ errorName: "Index__RebalanceNotNeeded" });
const NO_FEES = encodeProtocolError({ errorName: "Index__NoFeesToCollect" });

// Protocol errors other than the two the parsers route to a dedicated list.
const protocolReasons: ReasonCase[] = [
  {
    reasonData: encodeProtocolError({ errorName: "Index__RebalanceSlippageTooHigh" }),
    reason: { kind: "protocol", errorName: "Index__RebalanceSlippageTooHigh", args: [] },
  },
  {
    reasonData: encodeProtocolError({ errorName: "PriceFeedManager__PriceIsStale" }),
    reason: { kind: "protocol", errorName: "PriceFeedManager__PriceIsStale", args: [] },
  },
  {
    reasonData: encodeProtocolError({ errorName: "Index__NotPendingWeightUpdate" }),
    reason: { kind: "protocol", errorName: "Index__NotPendingWeightUpdate", args: [] },
  },
  {
    reasonData: encodeProtocolError({ errorName: "ERC20InsufficientBalance", args: [INDEX, 1n, 2n] }),
    reason: { kind: "protocol", errorName: "ERC20InsufficientBalance", args: [INDEX, 1n, 2n] },
  },
];

// Not selectors of any protocol error: checked against protocolErrorsAbi below, so the generator
// can never draw data the SDK is right to decode.
const FOREIGN_SELECTORS = ["0xdeadbeef", "0x39d35496", "0xcafebabe"] as const;

const emptyReason = fc
  .uint8Array({ maxLength: 3 })
  .map((raw): ReasonCase => ({ reasonData: bytesToHex(raw), reason: { kind: "empty" } }));
const errorStringReason = fc.string({ maxLength: 40 }).map(
  (message): ReasonCase => ({
    reasonData: concat([ERROR_STRING_SELECTOR, encodeAbiParameters([{ type: "string" }], [message])]),
    reason: { kind: "errorString", message },
  }),
);
const panicReason = uint256.map(
  (code): ReasonCase => ({
    reasonData: concat([PANIC_SELECTOR, encodeAbiParameters([{ type: "uint256" }], [code])]),
    reason: { kind: "panic", code },
  }),
);
const foreignReason = fc.tuple(fc.constantFrom(...FOREIGN_SELECTORS), fc.uint8Array({ maxLength: 96 })).map(
  ([selector, tail]): ReasonCase => ({
    reasonData: concat([selector, bytesToHex(tail)]),
    reason: { kind: "unknownCustomError", selector },
  }),
);
const protocolReason = fc.constantFrom(...protocolReasons);
const anyReason = fc.oneof(emptyReason, errorStringReason, panicReason, foreignReason, protocolReason);
// What Index.executeWeightUpdate puts in WeightsUpdateRebalanceFailed: a custom error, never a common one.
const customReason = fc.oneof(foreignReason, protocolReason);

const listedIndex = fc.constantFrom(...LISTED);
const reservesArb = fc.record({
  asset0ReserveBefore: uint256,
  asset1ReserveBefore: uint256,
  asset0ReserveAfter: uint256,
  asset1ReserveAfter: uint256,
});
// Index.proposeUpdateWeights requires MIN_WEIGHT < weight0 < MAX_WEIGHT; weight1 is the complement.
const weight0Arb = fc.bigInt({ min: MIN_WEIGHT + 1n, max: MAX_WEIGHT - 1n });
// s_totalFees is a uint128 and collectFees reverts with Index__NoFeesToCollect when it is zero.
const feeArb = fc.bigInt({ min: 1n, max: 2n ** 128n - 1n });

/**
 * Logs another contract, or the IndexManager for another action, can put in the same receipt.
 * None of them is an Index event of a listed Index, so none may change the outcome of the batch.
 */
function noiseFor(action: IndexAction) {
  const otherAction = fc.constantFrom(...INDEX_ACTIONS.filter((name) => name !== action));
  const anyIndex = fc.constantFrom(...LISTED, UNLISTED_INDEX);
  return fc.oneof(
    fc.tuple(anyIndex, fc.constantFrom(...INDEX_ACTIONS)).map(([index, name]) => triggeredLog(ATTACKER, index, name)),
    fc.tuple(anyIndex, fc.constantFrom(...INDEX_ACTIONS), anyReason).map(([index, name, r]) => failedLog(ATTACKER, index, name, r.reasonData)),
    fc.tuple(listedIndex, otherAction).map(([index, name]) => triggeredLog(INDEX_MANAGER, index, name)),
    fc.tuple(listedIndex, otherAction, anyReason).map(([index, name, r]) => failedLog(INDEX_MANAGER, index, name, r.reasonData)),
    fc.tuple(fc.constantFrom(ATTACKER, UNLISTED_INDEX), reservesArb).map(([emitter, r]) => rebalancedLog(emitter, r)),
    fc.tuple(fc.constantFrom(ATTACKER, UNLISTED_INDEX), weight0Arb).map(([emitter, w]) => weightsUpdatedLog(emitter, w)),
    fc.constantFrom(ATTACKER, UNLISTED_INDEX).map((emitter) => skippedLog(emitter)),
    fc.tuple(fc.constantFrom(ATTACKER, UNLISTED_INDEX), customReason).map(([emitter, r]) => rebalanceFailedLog(emitter, r.reasonData)),
    fc.tuple(fc.constantFrom(ATTACKER, UNLISTED_INDEX, USDC), feeArb).map(([emitter, fee]) => feesCollectedLog(emitter, fee)),
    // Share transfers are Index events too (the Index is an ERC20), but not outcome events.
    fc.tuple(fc.constantFrom(...LISTED, USDC), uint256).map(([token, value]) => transferLog(token, USER, POOL, value)),
    fc.constantFrom(INDEX_MANAGER, ...LISTED).map((emitter) => junkLog(emitter)),
  );
}

type Placed = { at: number; log: ReceiptLog };
const placedNoise = (action: IndexAction) =>
  fc.array(fc.record({ at: fc.nat(), log: noiseFor(action) }), { maxLength: 8 });

function interleave(core: readonly ReceiptLog[], noise: readonly Placed[]): ReceiptLog[] {
  const out = [...core];
  for (const { at, log } of noise) out.splice(at % (out.length + 1), 0, log);
  return out;
}

// ── models: one outcome per element of `indexes`, the logs the contracts emit for it, the expected result

type RebalanceOutcome = { index: Address } & (
  | { kind: "rebalanced"; reserves: RebalanceReserves }
  | { kind: "notNeeded" }
  | { kind: "failed"; failure: ReasonCase }
);

const rebalanceOutcome: fc.Arbitrary<RebalanceOutcome> = fc.oneof(
  fc.record({ index: listedIndex, kind: fc.constant("rebalanced" as const), reserves: reservesArb }),
  fc.record({ index: listedIndex, kind: fc.constant("notNeeded" as const) }),
  fc.record({ index: listedIndex, kind: fc.constant("failed" as const), failure: anyReason }),
);

/** Logs of one outcome; the IndexManager event is always the last one. A reverted Index call leaves no Index event. */
function rebalanceGroup(outcome: RebalanceOutcome): ReceiptLog[] {
  switch (outcome.kind) {
    case "rebalanced":
      return [
        transferLog(USDC, outcome.index, POOL, 1n),
        rebalancedLog(outcome.index, outcome.reserves),
        triggeredLog(INDEX_MANAGER, outcome.index, "REBALANCE"),
      ];
    case "notNeeded":
      return [failedLog(INDEX_MANAGER, outcome.index, "REBALANCE", NOT_NEEDED)];
    case "failed":
      return [failedLog(INDEX_MANAGER, outcome.index, "REBALANCE", outcome.failure.reasonData)];
  }
}

function expectedRebalance(outcomes: readonly RebalanceOutcome[]): RebalanceBatchResult {
  const result: RebalanceBatchResult = { rebalanced: [], notNeeded: [], failed: [] };
  for (const outcome of outcomes) {
    if (outcome.kind === "rebalanced") result.rebalanced.push({ index: outcome.index, ...outcome.reserves });
    else if (outcome.kind === "notNeeded") result.notNeeded.push({ index: outcome.index });
    else result.failed.push({ index: outcome.index, ...outcome.failure });
  }
  return result;
}

type InnerRebalance =
  | { status: "rebalanced"; reserves: RebalanceReserves }
  | { status: "skipped" }
  | { status: "failed"; failure: ReasonCase };

type WeightOutcome = { index: Address } & (
  | { kind: "updated"; weight0: bigint; inner: InnerRebalance }
  | { kind: "failed"; failure: ReasonCase }
);

const innerRebalance: fc.Arbitrary<InnerRebalance> = fc.oneof(
  fc.record({ status: fc.constant("rebalanced" as const), reserves: reservesArb }),
  fc.record({ status: fc.constant("skipped" as const) }),
  fc.record({ status: fc.constant("failed" as const), failure: customReason }),
);

const weightOutcome: fc.Arbitrary<WeightOutcome> = fc.oneof(
  fc.record({ index: listedIndex, kind: fc.constant("updated" as const), weight0: weight0Arb, inner: innerRebalance }),
  fc.record({ index: listedIndex, kind: fc.constant("failed" as const), failure: anyReason }),
);

function weightGroup(outcome: WeightOutcome): ReceiptLog[] {
  if (outcome.kind === "failed") return [failedLog(INDEX_MANAGER, outcome.index, "EXECUTE_WEIGHTS", outcome.failure.reasonData)];
  // Index.executeWeightUpdate: WeightsUpdated first, then the outcome of the inner rebalance.
  const inner =
    outcome.inner.status === "rebalanced"
      ? [transferLog(USDC, outcome.index, POOL, 1n), rebalancedLog(outcome.index, outcome.inner.reserves)]
      : outcome.inner.status === "skipped"
        ? [skippedLog(outcome.index)]
        : [rebalanceFailedLog(outcome.index, outcome.inner.failure.reasonData)];
  return [weightsUpdatedLog(outcome.index, outcome.weight0), ...inner, triggeredLog(INDEX_MANAGER, outcome.index, "EXECUTE_WEIGHTS")];
}

function expectedWeights(outcomes: readonly WeightOutcome[]): WeightUpdateBatchResult {
  const result: WeightUpdateBatchResult = { updated: [], failed: [] };
  for (const outcome of outcomes) {
    if (outcome.kind === "failed") {
      result.failed.push({ index: outcome.index, ...outcome.failure });
      continue;
    }
    const rebalance: WeightUpdateRebalance =
      outcome.inner.status === "rebalanced"
        ? { status: "rebalanced", ...outcome.inner.reserves }
        : outcome.inner.status === "skipped"
          ? { status: "skipped" }
          : { status: "failed", ...outcome.inner.failure };
    result.updated.push({
      index: outcome.index,
      asset0Weight: outcome.weight0,
      asset1Weight: MAX_WEIGHT - outcome.weight0,
      rebalance,
    });
  }
  return result;
}

type FeesOutcome = { index: Address } & (
  | { kind: "collected"; fee: bigint }
  | { kind: "noFees" }
  | { kind: "failed"; failure: ReasonCase }
);

const feesOutcome: fc.Arbitrary<FeesOutcome> = fc.oneof(
  fc.record({ index: listedIndex, kind: fc.constant("collected" as const), fee: feeArb }),
  fc.record({ index: listedIndex, kind: fc.constant("noFees" as const) }),
  fc.record({ index: listedIndex, kind: fc.constant("failed" as const), failure: anyReason }),
);

function feesGroup(outcome: FeesOutcome): ReceiptLog[] {
  switch (outcome.kind) {
    case "collected":
      return [
        transferLog(USDC, outcome.index, KEEPER, outcome.fee),
        feesCollectedLog(outcome.index, outcome.fee),
        triggeredLog(INDEX_MANAGER, outcome.index, "COLLECT_FEES"),
      ];
    case "noFees":
      return [failedLog(INDEX_MANAGER, outcome.index, "COLLECT_FEES", NO_FEES)];
    case "failed":
      return [failedLog(INDEX_MANAGER, outcome.index, "COLLECT_FEES", outcome.failure.reasonData)];
  }
}

function expectedFees(outcomes: readonly FeesOutcome[]): CollectFeesBatchResult {
  const result: CollectFeesBatchResult = { collected: [], noFees: [], failed: [] };
  for (const outcome of outcomes) {
    if (outcome.kind === "collected") result.collected.push({ index: outcome.index, feeAmount: outcome.fee });
    else if (outcome.kind === "noFees") result.noFees.push({ index: outcome.index });
    else result.failed.push({ index: outcome.index, ...outcome.failure });
  }
  return result;
}

const batch = (indexes: readonly Address[]) => ({ indexManager: INDEX_MANAGER, indexes });
const indexesOf = (outcomes: readonly { index: Address }[]) => outcomes.map((outcome) => outcome.index);
// Up to 6 entries drawn from 3 Indexes: duplicates are frequent, as in a keeper that lists an Index twice.
const outcomesOf = <T>(arb: fc.Arbitrary<T>) => fc.array(arb, { minLength: 1, maxLength: 6 });

describe("failureReasonOf", () => {
  it("generator invariant: the foreign selectors are not protocol errors", () => {
    // An error selector is computed like a function selector: name and input types only.
    const protocolSelectors = new Set(
      protocolErrorsAbi.map((item) =>
        toFunctionSelector({ ...item, type: "function", outputs: [], stateMutability: "nonpayable" }),
      ),
    );
    for (const selector of FOREIGN_SELECTORS) expect(protocolSelectors.has(selector)).toBe(false);
  });

  it.each(["0x", "0x00", "0x0000", "0x08c379"] as const)("less than 4 bytes (%s) is empty: out of gas or a bare revert()", (data) => {
    expect(failureReasonOf(data)).toEqual({ kind: "empty" });
  });

  it("Error(string) gives the message", () => {
    const data = concat([ERROR_STRING_SELECTOR, encodeAbiParameters([{ type: "string" }], ["ERC20: transfer amount exceeds balance"])]);
    expect(failureReasonOf(data)).toEqual({ kind: "errorString", message: "ERC20: transfer amount exceeds balance" });
  });

  it("Panic(uint256) gives the code", () => {
    const data = concat([PANIC_SELECTOR, encodeAbiParameters([{ type: "uint256" }], [0x11n])]);
    expect(failureReasonOf(data)).toEqual({ kind: "panic", code: 0x11n });
  });

  it("a protocol custom error is decoded, with and without arguments", () => {
    expect(failureReasonOf(NOT_NEEDED)).toEqual({ kind: "protocol", errorName: "Index__RebalanceNotNeeded", args: [] });
    expect(failureReasonOf(NO_FEES)).toEqual({ kind: "protocol", errorName: "Index__NoFeesToCollect", args: [] });
    const withArgs = encodeProtocolError({ errorName: "ERC20InsufficientBalance", args: [INDEX, 5n, 7n] });
    expect(failureReasonOf(withArgs)).toEqual({ kind: "protocol", errorName: "ERC20InsufficientBalance", args: [INDEX, 5n, 7n] });
  });

  it("exactly 4 unknown bytes, or 4 unknown bytes with arguments: unknownCustomError with the 4-byte selector", () => {
    expect(failureReasonOf("0xdeadbeef")).toEqual({ kind: "unknownCustomError", selector: "0xdeadbeef" });
    expect(failureReasonOf(`0xdeadbeef${"00".repeat(64)}`)).toEqual({ kind: "unknownCustomError", selector: "0xdeadbeef" });
  });

  it("a known selector with undecodable arguments is an unknownCustomError, not a throw", () => {
    expect(failureReasonOf(`${ERROR_STRING_SELECTOR}0102`)).toEqual({ kind: "unknownCustomError", selector: ERROR_STRING_SELECTOR });
    const truncated = encodeProtocolError({ errorName: "ERC20InsufficientBalance", args: [INDEX, 5n, 7n] }).slice(0, 2 + 8 + 64);
    expect(failureReasonOf(truncated as Hex)).toMatchObject({ kind: "unknownCustomError" });
  });

  test.prop([anyReason], { numRuns: 200 })("classifies every kind of revert data", ({ reasonData, reason }) => {
    expect(failureReasonOf(reasonData)).toEqual(reason);
  });

  test.prop([bytes], { numRuns: 200 })("never throws on arbitrary bytes; below 4 bytes always empty", (data) => {
    const reason = failureReasonOf(data);
    if (data.length < 2 + 8) expect(reason).toEqual({ kind: "empty" });
    else expect(reason.kind).not.toBe("empty");
  });
});

describe("parseRebalanceBatch", () => {
  test.prop([outcomesOf(rebalanceOutcome), placedNoise("REBALANCE")], { numRuns: 200 })(
    "one entry per listed Index, in the right list and in order, whatever the noise",
    (outcomes, noise) => {
      const logs = interleave(outcomes.flatMap(rebalanceGroup), noise);
      expect(parseRebalanceBatch(logs, batch(indexesOf(outcomes)))).toEqual(expectedRebalance(outcomes));
    },
  );

  test.prop([outcomesOf(rebalanceOutcome), fc.nat()], { numRuns: 200 })(
    "a missing outcome -> EventNotFoundError",
    (outcomes, pick) => {
      const groups = outcomes.map(rebalanceGroup);
      const dropped = pick % groups.length;
      // Keep the Index events of the dropped outcome: only the IndexManager event disappears.
      const logs = groups.flatMap((group, i) => (i === dropped ? group.slice(0, -1) : group));
      expect(() => parseRebalanceBatch(logs, batch(indexesOf(outcomes)))).toThrow(EventNotFoundError);
    },
  );

  test.prop([outcomesOf(rebalanceOutcome)], { numRuns: 200 })(
    "fewer or more indexes than outcomes -> EventNotFoundError",
    (outcomes) => {
      const logs = outcomes.flatMap(rebalanceGroup);
      const indexes = indexesOf(outcomes);
      expect(() => parseRebalanceBatch(logs, batch(indexes.slice(0, -1)))).toThrow(EventNotFoundError);
      expect(() => parseRebalanceBatch(logs, batch([...indexes, INDEX]))).toThrow(EventNotFoundError);
    },
  );

  it("one Index per list: rebalanced with the reserves of IndexRebalanced, not needed, failed with the reason", () => {
    const reserves = { asset0ReserveBefore: 10n, asset1ReserveBefore: 20n, asset0ReserveAfter: 8n, asset1ReserveAfter: 25n };
    const stale = encodeProtocolError({ errorName: "PriceFeedManager__PriceIsStale" });
    const logs = [
      failedLog(INDEX_MANAGER, OTHER_INDEX, "REBALANCE", stale),
      rebalancedLog(INDEX, reserves),
      triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE"),
      failedLog(INDEX_MANAGER, THIRD_INDEX, "REBALANCE", NOT_NEEDED),
    ];
    expect(parseRebalanceBatch(logs, batch([OTHER_INDEX, INDEX, THIRD_INDEX]))).toEqual({
      rebalanced: [{ index: INDEX, ...reserves }],
      notNeeded: [{ index: THIRD_INDEX }],
      failed: [
        {
          index: OTHER_INDEX,
          reasonData: stale,
          reason: { kind: "protocol", errorName: "PriceFeedManager__PriceIsStale", args: [] },
        },
      ],
    });
  });

  it("an Index listed twice: each outcome gets its own IndexRebalanced", () => {
    const first = { asset0ReserveBefore: 1n, asset1ReserveBefore: 2n, asset0ReserveAfter: 3n, asset1ReserveAfter: 4n };
    const second = { asset0ReserveBefore: 5n, asset1ReserveBefore: 6n, asset0ReserveAfter: 7n, asset1ReserveAfter: 8n };
    const logs = [
      rebalancedLog(INDEX, first),
      triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE"),
      rebalancedLog(INDEX, second),
      triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE"),
      failedLog(INDEX_MANAGER, INDEX, "REBALANCE", NOT_NEEDED),
    ];
    expect(parseRebalanceBatch(logs, batch([INDEX, INDEX, INDEX]))).toEqual({
      rebalanced: [
        { index: INDEX, ...first },
        { index: INDEX, ...second },
      ],
      notNeeded: [{ index: INDEX }],
      failed: [],
    });
  });

  it("the IndexRebalanced of an earlier outcome is not reused: a second success without its own event -> EventNotFoundError", () => {
    const reserves = { asset0ReserveBefore: 1n, asset1ReserveBefore: 2n, asset0ReserveAfter: 3n, asset1ReserveAfter: 4n };
    const logs = [
      rebalancedLog(INDEX, reserves),
      triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE"),
      triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE"),
    ];
    expect(() => parseRebalanceBatch(logs, batch([INDEX, INDEX]))).toThrow(EventNotFoundError);
  });

  it("Index events before a failed outcome belong to that outcome, not to the next success of the same Index", () => {
    const reserves = { asset0ReserveBefore: 1n, asset1ReserveBefore: 2n, asset0ReserveAfter: 3n, asset1ReserveAfter: 4n };
    const logs = [
      rebalancedLog(INDEX, reserves),
      failedLog(INDEX_MANAGER, INDEX, "REBALANCE", "0x"),
      triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE"),
    ];
    expect(() => parseRebalanceBatch(logs, batch([INDEX, INDEX]))).toThrow(EventNotFoundError);
  });

  it("an IndexRebalanced emitted after the outcome belongs to the next outcome, so the success lacks it", () => {
    const reserves = { asset0ReserveBefore: 1n, asset1ReserveBefore: 2n, asset0ReserveAfter: 3n, asset1ReserveAfter: 4n };
    const logs = [triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE"), rebalancedLog(INDEX, reserves)];
    expect(() => parseRebalanceBatch(logs, batch([INDEX]))).toThrow(EventNotFoundError);
  });

  // A contract holding both roles runs executeSingleWeightUpdate(X) (its inner rebalance emits
  // IndexRebalanced, its EXECUTE_WEIGHTS outcome is ignored here) and then the batch on X in the same
  // tx: both IndexRebalanced are grouped with the batch outcome, the reserves are those of the last one.
  it("an earlier IndexRebalanced of another action: the reserves come from the one just before the batch outcome", () => {
    const earlier = { asset0ReserveBefore: 1n, asset1ReserveBefore: 2n, asset0ReserveAfter: 3n, asset1ReserveAfter: 4n };
    const batched = { asset0ReserveBefore: 3n, asset1ReserveBefore: 4n, asset0ReserveAfter: 5n, asset1ReserveAfter: 6n };
    const logs = [
      weightsUpdatedLog(INDEX, 600_000n),
      rebalancedLog(INDEX, earlier),
      triggeredLog(INDEX_MANAGER, INDEX, "EXECUTE_WEIGHTS"),
      rebalancedLog(INDEX, batched),
      triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE"),
    ];
    expect(parseRebalanceBatch(logs, batch([INDEX]))).toEqual({ rebalanced: [{ index: INDEX, ...batched }], notNeeded: [], failed: [] });
  });

  // rebalanceSingleIndex emits the same IndexActionTriggered(REBALANCE) as a batch entry: in one tx
  // with a batch it is one more outcome, so the outcomes no longer match `indexes` one to one.
  it("a single rebalance of X in the same tx as the batch is an extra REBALANCE outcome -> EventNotFoundError", () => {
    const single = { asset0ReserveBefore: 1n, asset1ReserveBefore: 2n, asset0ReserveAfter: 3n, asset1ReserveAfter: 4n };
    const logs = [
      rebalancedLog(INDEX, single),
      triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE"),
      failedLog(INDEX_MANAGER, INDEX, "REBALANCE", NOT_NEEDED),
    ];
    expect(() => parseRebalanceBatch(logs, batch([INDEX]))).toThrow(EventNotFoundError);
  });

  it("success without IndexRebalanced -> EventNotFoundError", () => {
    expect(() => parseRebalanceBatch([triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE")], batch([INDEX]))).toThrow(EventNotFoundError);
  });

  it("security: an IndexRebalanced from another contract, or from another listed Index, does not complete a success", () => {
    const reserves = { asset0ReserveBefore: 1n, asset1ReserveBefore: 2n, asset0ReserveAfter: 3n, asset1ReserveAfter: 4n };
    for (const emitter of [ATTACKER, OTHER_INDEX, INDEX_MANAGER]) {
      const logs = [rebalancedLog(emitter, reserves), triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE")];
      expect(() => parseRebalanceBatch(logs, batch([INDEX])), emitter).toThrow(EventNotFoundError);
    }
  });

  it("security: outcomes emitted by another contract are ignored (wrong emitter)", () => {
    const reserves = { asset0ReserveBefore: 1n, asset1ReserveBefore: 2n, asset0ReserveAfter: 3n, asset1ReserveAfter: 4n };
    const spoofedOnly = [rebalancedLog(INDEX, reserves), triggeredLog(ATTACKER, INDEX, "REBALANCE")];
    expect(() => parseRebalanceBatch(spoofedOnly, batch([INDEX]))).toThrow(EventNotFoundError);

    // A fake failure placed first must not hide the genuine success, nor count as an outcome.
    const logs = [
      failedLog(ATTACKER, INDEX, "REBALANCE", "0x"),
      rebalancedLog(INDEX, reserves),
      triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE"),
    ];
    expect(parseRebalanceBatch(logs, batch([INDEX]))).toEqual({ rebalanced: [{ index: INDEX, ...reserves }], notNeeded: [], failed: [] });
  });

  it("outcomes of another action are not outcomes of this batch", () => {
    const logs = [
      triggeredLog(INDEX_MANAGER, INDEX, "EXECUTE_WEIGHTS"),
      failedLog(INDEX_MANAGER, INDEX, "COLLECT_FEES", NO_FEES),
    ];
    expect(() => parseRebalanceBatch(logs, batch([INDEX]))).toThrow(EventNotFoundError);
    expect(
      parseRebalanceBatch([...logs, failedLog(INDEX_MANAGER, INDEX, "REBALANCE", NOT_NEEDED)], batch([INDEX])),
    ).toEqual({ rebalanced: [], notNeeded: [{ index: INDEX }], failed: [] });
  });

  it("outcomes in another order than `indexes` -> EventNotFoundError", () => {
    const logs = [failedLog(INDEX_MANAGER, INDEX, "REBALANCE", NOT_NEEDED), failedLog(INDEX_MANAGER, OTHER_INDEX, "REBALANCE", NOT_NEEDED)];
    expect(() => parseRebalanceBatch(logs, batch([OTHER_INDEX, INDEX]))).toThrow(EventNotFoundError);
  });

  it("an outcome for an Index that is not listed -> EventNotFoundError", () => {
    const logs = [failedLog(INDEX_MANAGER, INDEX, "REBALANCE", NOT_NEEDED), failedLog(INDEX_MANAGER, UNLISTED_INDEX, "REBALANCE", NOT_NEEDED)];
    expect(() => parseRebalanceBatch(logs, batch([INDEX]))).toThrow(EventNotFoundError);
    expect(() => parseRebalanceBatch(logs, batch([INDEX, OTHER_INDEX]))).toThrow(EventNotFoundError);
  });

  it("no logs (a reverted tx, or the wrong receipt) -> EventNotFoundError", () => {
    expect(() => parseRebalanceBatch([], batch([INDEX]))).toThrow(EventNotFoundError);
  });

  it("the logs of another batch kind are rejected", () => {
    const feeLogs = feesGroup({ index: INDEX, kind: "collected", fee: 5n });
    expect(() => parseRebalanceBatch(feeLogs, batch([INDEX]))).toThrow(EventNotFoundError);
    expect(() => parseWeightUpdateBatch(feeLogs, batch([INDEX]))).toThrow(EventNotFoundError);
  });

  it("matches IndexManager and Index addresses case-insensitively", () => {
    const logs = [failedLog(INDEX_MANAGER, INDEX, "REBALANCE", NOT_NEEDED)].map((log) => ({
      ...log,
      address: log.address.toLowerCase() as Address,
    }));
    const params = { indexManager: INDEX_MANAGER.toLowerCase() as Address, indexes: [INDEX.toLowerCase() as Address] };
    expect(parseRebalanceBatch(logs, params).notNeeded).toHaveLength(1);
  });

  it("does not mutate the logs or the indexes it receives", () => {
    const logs = Object.freeze(rebalanceGroup({ index: INDEX, kind: "notNeeded" }).map((log) => Object.freeze(log)));
    const indexes = Object.freeze([INDEX]);
    expect(() => parseRebalanceBatch(logs, { indexManager: INDEX_MANAGER, indexes })).not.toThrow();
  });
});

describe("parseWeightUpdateBatch", () => {
  test.prop([outcomesOf(weightOutcome), placedNoise("EXECUTE_WEIGHTS")], { numRuns: 200 })(
    "one entry per listed Index with the applied weights and the inner rebalance outcome, whatever the noise",
    (outcomes, noise) => {
      const logs = interleave(outcomes.flatMap(weightGroup), noise);
      expect(parseWeightUpdateBatch(logs, batch(indexesOf(outcomes)))).toEqual(expectedWeights(outcomes));
    },
  );

  test.prop([outcomesOf(weightOutcome), fc.nat()], { numRuns: 200 })("a missing outcome -> EventNotFoundError", (outcomes, pick) => {
    const groups = outcomes.map(weightGroup);
    const dropped = pick % groups.length;
    const logs = groups.flatMap((group, i) => (i === dropped ? group.slice(0, -1) : group));
    expect(() => parseWeightUpdateBatch(logs, batch(indexesOf(outcomes)))).toThrow(EventNotFoundError);
  });

  it("every rebalance status, and a failed execution, in one batch", () => {
    const reserves = { asset0ReserveBefore: 10n, asset1ReserveBefore: 20n, asset0ReserveAfter: 12n, asset1ReserveAfter: 18n };
    const stale = encodeProtocolError({ errorName: "PriceFeedManager__PriceIsStale" });
    const notPending = encodeProtocolError({ errorName: "Index__NotPendingWeightUpdate" });
    const outcomes: WeightOutcome[] = [
      { index: INDEX, kind: "updated", weight0: 600_000n, inner: { status: "rebalanced", reserves } },
      { index: OTHER_INDEX, kind: "updated", weight0: 510_000n, inner: { status: "skipped" } },
      {
        index: THIRD_INDEX,
        kind: "updated",
        weight0: 400_000n,
        inner: { status: "failed", failure: { reasonData: stale, reason: { kind: "protocol", errorName: "PriceFeedManager__PriceIsStale", args: [] } } },
      },
      { index: INDEX, kind: "failed", failure: { reasonData: notPending, reason: { kind: "protocol", errorName: "Index__NotPendingWeightUpdate", args: [] } } },
    ];
    expect(parseWeightUpdateBatch(outcomes.flatMap(weightGroup), batch(indexesOf(outcomes)))).toEqual({
      updated: [
        { index: INDEX, asset0Weight: 600_000n, asset1Weight: 400_000n, rebalance: { status: "rebalanced", ...reserves } },
        { index: OTHER_INDEX, asset0Weight: 510_000n, asset1Weight: 490_000n, rebalance: { status: "skipped" } },
        {
          index: THIRD_INDEX,
          asset0Weight: 400_000n,
          asset1Weight: 600_000n,
          rebalance: { status: "failed", reasonData: stale, reason: { kind: "protocol", errorName: "PriceFeedManager__PriceIsStale", args: [] } },
        },
      ],
      failed: [{ index: INDEX, reasonData: notPending, reason: { kind: "protocol", errorName: "Index__NotPendingWeightUpdate", args: [] } }],
    });
  });

  it("success without WeightsUpdated -> EventNotFoundError", () => {
    const logs = [skippedLog(INDEX), triggeredLog(INDEX_MANAGER, INDEX, "EXECUTE_WEIGHTS")];
    expect(() => parseWeightUpdateBatch(logs, batch([INDEX]))).toThrow(EventNotFoundError);
  });

  it("success with WeightsUpdated but no rebalance outcome event -> EventNotFoundError", () => {
    const logs = [weightsUpdatedLog(INDEX, 600_000n), triggeredLog(INDEX_MANAGER, INDEX, "EXECUTE_WEIGHTS")];
    expect(() => parseWeightUpdateBatch(logs, batch([INDEX]))).toThrow(EventNotFoundError);
  });

  it("security: WeightsUpdated and the rebalance outcome are only taken from the Index itself", () => {
    for (const emitter of [ATTACKER, OTHER_INDEX]) {
      const spoofedWeights = [weightsUpdatedLog(emitter, 600_000n), skippedLog(INDEX), triggeredLog(INDEX_MANAGER, INDEX, "EXECUTE_WEIGHTS")];
      expect(() => parseWeightUpdateBatch(spoofedWeights, batch([INDEX])), emitter).toThrow(EventNotFoundError);
      const spoofedOutcome = [weightsUpdatedLog(INDEX, 600_000n), skippedLog(emitter), triggeredLog(INDEX_MANAGER, INDEX, "EXECUTE_WEIGHTS")];
      expect(() => parseWeightUpdateBatch(spoofedOutcome, batch([INDEX])), emitter).toThrow(EventNotFoundError);
    }
  });

  it("security: a success emitted by another contract does not mark the weights as applied", () => {
    const logs = weightGroup({ index: INDEX, kind: "updated", weight0: 600_000n, inner: { status: "skipped" } }).map((log) =>
      log.address === INDEX_MANAGER ? { ...log, address: ATTACKER } : log,
    );
    expect(() => parseWeightUpdateBatch(logs, batch([INDEX]))).toThrow(EventNotFoundError);
  });

  // Index.executeWeightUpdate emits WeightsUpdated and only then the outcome of its own rebalance.
  // An IndexRebalanced emitted by the same Index earlier in the transaction (a rebalanceSingleIndex
  // run by the same contract before the batch: its REBALANCE outcome is ignored by this parser) is
  // grouped with this outcome too, but it precedes WeightsUpdated, so it cannot be the inner rebalance.
  it("the rebalance outcome is the event that follows WeightsUpdated, not an earlier IndexRebalanced of the same Index", () => {
    const earlier = { asset0ReserveBefore: 1n, asset1ReserveBefore: 2n, asset0ReserveAfter: 3n, asset1ReserveAfter: 4n };
    const logs = [
      rebalancedLog(INDEX, earlier),
      triggeredLog(INDEX_MANAGER, INDEX, "REBALANCE"),
      weightsUpdatedLog(INDEX, 510_000n),
      skippedLog(INDEX),
      triggeredLog(INDEX_MANAGER, INDEX, "EXECUTE_WEIGHTS"),
    ];
    expect(parseWeightUpdateBatch(logs, batch([INDEX])).updated[0]?.rebalance).toEqual({ status: "skipped" });
  });
});

describe("parseCollectFeesBatch", () => {
  test.prop([outcomesOf(feesOutcome), placedNoise("COLLECT_FEES")], { numRuns: 200 })(
    "one entry per listed Index, in the right list and in order, whatever the noise",
    (outcomes, noise) => {
      const logs = interleave(outcomes.flatMap(feesGroup), noise);
      expect(parseCollectFeesBatch(logs, batch(indexesOf(outcomes)))).toEqual(expectedFees(outcomes));
    },
  );

  test.prop([outcomesOf(feesOutcome), fc.nat()], { numRuns: 200 })("a missing outcome -> EventNotFoundError", (outcomes, pick) => {
    const groups = outcomes.map(feesGroup);
    const dropped = pick % groups.length;
    const logs = groups.flatMap((group, i) => (i === dropped ? group.slice(0, -1) : group));
    expect(() => parseCollectFeesBatch(logs, batch(indexesOf(outcomes)))).toThrow(EventNotFoundError);
  });

  it("collected with the amount of FeesCollected, no fees, failed", () => {
    const insufficient = encodeProtocolError({ errorName: "ERC20InsufficientBalance", args: [THIRD_INDEX, 0n, 9n] });
    const logs = [
      transferLog(USDC, INDEX, KEEPER, 4_000_000n),
      feesCollectedLog(INDEX, 4_000_000n),
      triggeredLog(INDEX_MANAGER, INDEX, "COLLECT_FEES"),
      failedLog(INDEX_MANAGER, OTHER_INDEX, "COLLECT_FEES", NO_FEES),
      failedLog(INDEX_MANAGER, THIRD_INDEX, "COLLECT_FEES", insufficient),
    ];
    expect(parseCollectFeesBatch(logs, batch([INDEX, OTHER_INDEX, THIRD_INDEX]))).toEqual({
      collected: [{ index: INDEX, feeAmount: 4_000_000n }],
      noFees: [{ index: OTHER_INDEX }],
      failed: [
        {
          index: THIRD_INDEX,
          reasonData: insufficient,
          reason: { kind: "protocol", errorName: "ERC20InsufficientBalance", args: [THIRD_INDEX, 0n, 9n] },
        },
      ],
    });
  });

  it("success without FeesCollected -> EventNotFoundError, even with the USDC Transfer", () => {
    const logs = [transferLog(USDC, INDEX, KEEPER, 4_000_000n), triggeredLog(INDEX_MANAGER, INDEX, "COLLECT_FEES")];
    expect(() => parseCollectFeesBatch(logs, batch([INDEX]))).toThrow(EventNotFoundError);
  });

  it("security: the fee amount comes from the Index, never from a FeesCollected of another contract", () => {
    const logs = [feesCollectedLog(USDC, 10n ** 30n), feesCollectedLog(INDEX, 7n), triggeredLog(INDEX_MANAGER, INDEX, "COLLECT_FEES")];
    expect(parseCollectFeesBatch(logs, batch([INDEX])).collected).toEqual([{ index: INDEX, feeAmount: 7n }]);
    expect(() =>
      parseCollectFeesBatch([feesCollectedLog(ATTACKER, 7n), triggeredLog(INDEX_MANAGER, INDEX, "COLLECT_FEES")], batch([INDEX])),
    ).toThrow(EventNotFoundError);
  });

  it("Index__NoFeesToCollect from another action is not a noFees of this batch", () => {
    expect(() => parseCollectFeesBatch([failedLog(INDEX_MANAGER, INDEX, "REBALANCE", NO_FEES)], batch([INDEX]))).toThrow(
      EventNotFoundError,
    );
  });
});

describe("IndexCreated", () => {
  // IndexCreated(address indexed indexAddress, address indexed asset0, address indexed asset1,
  //              uint128 asset0Weight, uint128 asset1Weight, uint32 feePercentage, address assetManager)
  const uint128 = fc.bigInt({ min: 0n, max: 2n ** 128n - 1n });
  const uint32 = fc.integer({ min: 0, max: 2 ** 32 - 1 });
  const createdArb = fc.record({
    index: address,
    asset0: address,
    asset1: address,
    asset0Weight: uint128,
    asset1Weight: uint128,
    feePercentage: uint32,
    assetManager: address,
  });
  const created: IndexCreatedEvent = {
    index: INDEX,
    asset0: getAddress("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"),
    asset1: getAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
    asset0Weight: 500_000n,
    asset1Weight: 500_000n,
    feePercentage: 10_000,
    assetManager: KEEPER,
  };

  test.prop([address, createdArb], { numRuns: 200 })("parseIndexCreated(encodeIndexCreatedLog(x)) equals x", (indexManager, event) => {
    expect(parseIndexCreated([encodeIndexCreatedLog(indexManager, event)], indexManager)).toEqual(event);
  });

  it("the encoded log matches the IndexManager ABI (topics from viem, data as abi.encode of the non-indexed fields)", () => {
    const log = encodeIndexCreatedLog(INDEX_MANAGER, created);
    const topics = encodeEventTopics({
      abi: indexManagerAbi,
      eventName: "IndexCreated",
      args: { indexAddress: created.index, asset0: created.asset0, asset1: created.asset1 },
    });
    expect(log.topics).toEqual(topics);
    expect(log.data).toBe(
      encodeAbiParameters(
        [{ type: "uint128" }, { type: "uint128" }, { type: "uint32" }, { type: "address" }],
        [500_000n, 500_000n, 10_000, KEEPER],
      ),
    );
    expect(log.address).toBe(INDEX_MANAGER);
  });

  it("security: an IndexCreated from another emitter is ignored", () => {
    expect(() => parseIndexCreated([encodeIndexCreatedLog(ATTACKER, created)], INDEX_MANAGER)).toThrow(EventNotFoundError);
  });

  it("security: a spoofed IndexCreated before the real one does not win", () => {
    const spoofed = encodeIndexCreatedLog(ATTACKER, { ...created, index: OTHER_INDEX });
    expect(parseIndexCreated([spoofed, encodeIndexCreatedLog(INDEX_MANAGER, created)], INDEX_MANAGER)).toEqual(created);
  });

  it("no IndexCreated in the logs -> EventNotFoundError", () => {
    expect(() => parseIndexCreated([], INDEX_MANAGER)).toThrow(EventNotFoundError);
    const other = encodeIndexActionFailedLog(INDEX_MANAGER, { index: INDEX, caller: KEEPER, action: "REBALANCE", reasonData: "0x" });
    expect(() => parseIndexCreated([other], INDEX_MANAGER)).toThrow(EventNotFoundError);
  });

  it("emitter comparison is case-insensitive", () => {
    const log = encodeIndexCreatedLog(INDEX_MANAGER, created);
    expect(parseIndexCreated([log], INDEX_MANAGER.toLowerCase() as Address)).toEqual(created);
  });
});
