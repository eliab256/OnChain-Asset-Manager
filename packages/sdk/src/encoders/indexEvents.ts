import { indexAbi, indexManagerAbi } from "@oam/abi";
import {
  decodeEventLog,
  encodeAbiParameters,
  encodeEventTopics,
  isAddressEqual,
  parseEventLogs,
  size,
  slice,
  type Address,
  type Hex,
  type Log,
} from "viem";
import { INDEX_ACTIONS, type IndexAction } from "../constants/public.js";
import { EventNotFoundError, UnknownIndexActionError } from "../errors.js";
import { decodeProtocolError } from "./revertData.js";

export type SharesMintedEvent = {
  user: Address;
  /** 18 decimals. */
  sharesMinted: bigint;
  /** Token decimals of each asset. */
  asset0Amount: bigint;
  asset1Amount: bigint;
  /** USDC decimals. */
  usdcAmountIn: bigint;
  feeAmount: bigint;
};

export type SharesBurnedEvent = {
  user: Address;
  sharesBurned: bigint;
  asset0Amount: bigint;
  asset1Amount: bigint;
  usdcAmountOut: bigint;
  feeAmount: bigint;
};

/** The IndexManager does not revert when an action on an Index fails: it emits `IndexActionFailed`. */
export type IndexActionFailure = {
  index: Address;
  caller: Address;
  action: IndexAction;
  reasonData: Hex;
  /** Decoded custom error, when it belongs to the protocol ABIs. */
  errorName: string | undefined;
  args: readonly unknown[];
};

/** A log as found in `receipt.logs`; only address, topics and data are read. */
type ReceiptLog = Log<bigint, number, boolean>;

/** `encodeEventTopics` types a topic as possibly null or a list; every argument encoded here is a scalar. */
function toLog(address: Address, topics: readonly (Hex | Hex[] | null)[], data: Hex): ReceiptLog {
  const [signature, ...indexed] = topics.filter((topic): topic is Hex => typeof topic === "string");
  return {
    address,
    topics: signature ? [signature, ...indexed] : [],
    data,
    blockHash: null,
    blockNumber: null,
    logIndex: null,
    transactionHash: null,
    transactionIndex: null,
    removed: false,
  };
}

/** @throws {EventNotFoundError} the logs contain no `SharesMinted` from `index` */
export function parseSharesMinted(logs: readonly ReceiptLog[], index: Address): SharesMintedEvent {
  const event = parseEventLogs({ abi: indexAbi, eventName: "SharesMinted", logs: [...logs] }).find((log) =>
    isAddressEqual(log.address, index),
  );
  if (!event) throw new EventNotFoundError("SharesMinted", index);
  return { ...event.args };
}

/** @throws {EventNotFoundError} the logs contain no `SharesBurned` from `index` */
export function parseSharesBurned(logs: readonly ReceiptLog[], index: Address): SharesBurnedEvent {
  const event = parseEventLogs({ abi: indexAbi, eventName: "SharesBurned", logs: [...logs] }).find((log) =>
    isAddressEqual(log.address, index),
  );
  if (!event) throw new EventNotFoundError("SharesBurned", index);
  return { ...event.args };
}

/**
 * `undefined` when the action on `index` succeeded (no `IndexActionFailed` for it in the logs).
 * Only logs emitted by `indexManager` count: any contract touched in the same transaction (a token
 * during a swap, for example) could emit an event with the same signature.
 * @throws {UnknownIndexActionError} the action id is not in `INDEX_ACTIONS`
 */
export function parseIndexActionFailure(
  logs: readonly ReceiptLog[],
  params: { indexManager: Address; index: Address },
): IndexActionFailure | undefined {
  const event = parseEventLogs({ abi: indexManagerAbi, eventName: "IndexActionFailed", logs: [...logs] }).find(
    (log) => isAddressEqual(log.address, params.indexManager) && isAddressEqual(log.args.indexAddress, params.index),
  );
  if (!event) return undefined;
  const action = INDEX_ACTIONS[event.args.action];
  if (!action) throw new UnknownIndexActionError(event.args.action);
  const decoded = decodeProtocolError(event.args.reasonData);
  return {
    index: event.args.indexAddress,
    caller: event.args.caller,
    action,
    reasonData: event.args.reasonData,
    errorName: decoded?.errorName,
    args: decoded?.args ?? [],
  };
}

export type IndexCreatedEvent = {
  index: Address;
  /** The lower of the two asset addresses. */
  asset0: Address;
  asset1: Address;
  /** Weight units (1_000_000 = 100%). */
  asset0Weight: bigint;
  asset1Weight: bigint;
  /** 1e6 scale (10_000 = 1%). */
  feePercentage: number;
  /** The caller of `createIndex`: the MultiSig when the Index is created through a proposal. */
  assetManager: Address;
};

/**
 * The Index of a `createIndex` receipt (also inside the receipt of the MultiSig `executeTransaction`).
 * Only logs emitted by `indexManager` count.
 * @throws {EventNotFoundError}
 */
export function parseIndexCreated(logs: readonly ReceiptLog[], indexManager: Address): IndexCreatedEvent {
  const event = parseEventLogs({ abi: indexManagerAbi, eventName: "IndexCreated", logs: [...logs] }).find((log) =>
    isAddressEqual(log.address, indexManager),
  );
  if (!event) throw new EventNotFoundError("IndexCreated", indexManager);
  const { indexAddress, ...rest } = event.args;
  return { index: indexAddress, ...rest };
}

/** Inverse of `parseIndexCreated`. */
export function encodeIndexCreatedLog(indexManager: Address, event: IndexCreatedEvent): ReceiptLog {
  const topics = encodeEventTopics({
    abi: indexManagerAbi,
    eventName: "IndexCreated",
    args: { indexAddress: event.index, asset0: event.asset0, asset1: event.asset1 },
  });
  const data = encodeAbiParameters(
    [{ type: "uint128" }, { type: "uint128" }, { type: "uint32" }, { type: "address" }],
    [event.asset0Weight, event.asset1Weight, event.feePercentage, event.assetManager],
  );
  return toLog(indexManager, topics, data);
}

/** Inverse of `parseSharesMinted`: the log an Index at `index` emits. */
export function encodeSharesMintedLog(index: Address, event: SharesMintedEvent): ReceiptLog {
  const topics = encodeEventTopics({ abi: indexAbi, eventName: "SharesMinted", args: { user: event.user } });
  const data = encodeAbiParameters(
    [{ type: "uint256" }, { type: "uint256" }, { type: "uint256" }, { type: "uint256" }, { type: "uint256" }],
    [event.sharesMinted, event.asset0Amount, event.asset1Amount, event.usdcAmountIn, event.feeAmount],
  );
  return toLog(index, topics, data);
}

/** Inverse of `parseSharesBurned`. */
export function encodeSharesBurnedLog(index: Address, event: SharesBurnedEvent): ReceiptLog {
  const topics = encodeEventTopics({ abi: indexAbi, eventName: "SharesBurned", args: { user: event.user } });
  const data = encodeAbiParameters(
    [{ type: "uint256" }, { type: "uint256" }, { type: "uint256" }, { type: "uint256" }, { type: "uint256" }],
    [event.sharesBurned, event.asset0Amount, event.asset1Amount, event.usdcAmountOut, event.feeAmount],
  );
  return toLog(index, topics, data);
}

/** Inverse of `parseIndexActionFailure`: the log the IndexManager at `indexManager` emits. */
export function encodeIndexActionFailedLog(
  indexManager: Address,
  failure: Pick<IndexActionFailure, "index" | "caller" | "action" | "reasonData">,
): ReceiptLog {
  const topics = encodeEventTopics({
    abi: indexManagerAbi,
    eventName: "IndexActionFailed",
    args: { indexAddress: failure.index, caller: failure.caller, action: INDEX_ACTIONS.indexOf(failure.action) },
  });
  const data = encodeAbiParameters([{ type: "bytes" }], [failure.reasonData]);
  return toLog(indexManager, topics, data);
}

/**
 * Why an action on an Index reverted, from the raw revert data:
 * - `protocol`: a custom error of the protocol ABIs, decoded;
 * - `unknownCustomError`: at least 4 bytes but not in the protocol ABIs (e.g. an error of the swap router);
 * - `errorString` / `panic`: `Error(string)` and `Panic(uint256)`;
 * - `empty`: less than 4 bytes, typically out of gas or a bare `revert()`. In a batch this usually means the gas
 *   limit was too low: retry with a higher one.
 */
export type FailureReason =
  | { kind: "protocol"; errorName: string; args: readonly unknown[] }
  | { kind: "unknownCustomError"; selector: Hex }
  | { kind: "errorString"; message: string }
  | { kind: "panic"; code: bigint }
  | { kind: "empty" };

/** An Index whose action reverted inside a batch. The IndexManager emitted `IndexActionFailed` and went on. */
export type BatchActionFailure = {
  index: Address;
  reasonData: Hex;
  reason: FailureReason;
};

/** Reserves of `IndexRebalanced`, in the token decimals of each asset. */
export type RebalanceReserves = {
  asset0ReserveBefore: bigint;
  asset1ReserveBefore: bigint;
  asset0ReserveAfter: bigint;
  asset1ReserveAfter: bigint;
};

export type RebalanceBatchResult = {
  rebalanced: ({ index: Address } & RebalanceReserves)[];
  /** Already within the rebalance threshold (`Index__RebalanceNotNeeded`). */
  notNeeded: { index: Address }[];
  failed: BatchActionFailure[];
};

/** Outcome of the rebalance an Index attempts right after applying new weights. */
export type WeightUpdateRebalance =
  | ({ status: "rebalanced" } & RebalanceReserves)
  | { status: "skipped" }
  | { status: "failed"; reasonData: Hex; reason: FailureReason };

export type WeightUpdateBatchResult = {
  /** Weights applied, in weight units (1_000_000 = 100%). */
  updated: { index: Address; asset0Weight: bigint; asset1Weight: bigint; rebalance: WeightUpdateRebalance }[];
  /** Weights not applied: the proposal is still pending. */
  failed: BatchActionFailure[];
};

export type CollectFeesBatchResult = {
  /** USDC decimals. */
  collected: { index: Address; feeAmount: bigint }[];
  /** No fees accrued (`Index__NoFeesToCollect`). */
  noFees: { index: Address }[];
  failed: BatchActionFailure[];
};

type BatchParams = {
  indexManager: Address;
  /** The list passed to the batch call, in the same order. */
  indexes: readonly Address[];
};

type IndexEventLog = ReturnType<typeof decodeEventLog<typeof indexAbi>>;

/** One entry per element of `indexes`: the IndexManager outcome and the Index events emitted for it. */
type BatchEntry =
  | { index: Address; success: true; indexEvents: IndexEventLog[] }
  | { index: Address; success: false; reasonData: Hex };

/** Classifies raw revert data. */
export function failureReasonOf(reasonData: Hex): FailureReason {
  if (size(reasonData) < 4) return { kind: "empty" };
  const decoded = decodeProtocolError(reasonData);
  if (!decoded) return { kind: "unknownCustomError", selector: slice(reasonData, 0, 4) };
  if (decoded.errorName === "Error") return { kind: "errorString", message: decoded.args[0] as string };
  if (decoded.errorName === "Panic") return { kind: "panic", code: decoded.args[0] as bigint };
  return { kind: "protocol", errorName: decoded.errorName, args: decoded.args };
}

function decodeOrUndefined<const abi extends typeof indexAbi | typeof indexManagerAbi>(abi: abi, log: ReceiptLog) {
  try {
    return decodeEventLog({ abi, data: log.data, topics: log.topics });
  } catch {
    return undefined;
  }
}

/**
 * Walks the logs in order. The Index events emitted by X since the previous outcome for X belong to the next
 * `IndexActionTriggered` / `IndexActionFailed` for X, so an Index listed twice is handled too. Only IndexManager
 * events for `action` count; the outcomes must match `indexes` one to one, in order.
 * @throws {EventNotFoundError} the logs do not hold one outcome per element of `indexes`
 */
function parseBatch(logs: readonly ReceiptLog[], params: BatchParams, action: IndexAction): BatchEntry[] {
  const actionId = INDEX_ACTIONS.indexOf(action);
  const pending = new Map<string, IndexEventLog[]>();
  const entries: BatchEntry[] = [];

  for (const log of logs) {
    if (isAddressEqual(log.address, params.indexManager)) {
      const event = decodeOrUndefined(indexManagerAbi, log);
      if (!event || event.args === undefined) continue;
      if (event.eventName !== "IndexActionTriggered" && event.eventName !== "IndexActionFailed") continue;
      if (event.args.action !== actionId) continue;
      const index = event.args.indexAddress;
      const key = index.toLowerCase();
      if (event.eventName === "IndexActionTriggered") {
        entries.push({ index, success: true, indexEvents: pending.get(key) ?? [] });
      } else {
        entries.push({ index, success: false, reasonData: event.args.reasonData });
      }
      pending.delete(key);
    } else if (params.indexes.some((index) => isAddressEqual(index, log.address))) {
      const event = decodeOrUndefined(indexAbi, log);
      if (!event) continue;
      const key = log.address.toLowerCase();
      pending.set(key, [...(pending.get(key) ?? []), event]);
    }
  }

  const outcomeEvents = "IndexActionTriggered/IndexActionFailed";
  params.indexes.forEach((index, i) => {
    const entry = entries[i];
    if (!entry || !isAddressEqual(entry.index, index)) {
      throw new EventNotFoundError(`${outcomeEvents} (${action}) for ${index}`, params.indexManager);
    }
  });
  if (entries.length > params.indexes.length) {
    throw new EventNotFoundError(`${outcomeEvents} (${action}) for only the ${params.indexes.length} indexes given`, params.indexManager);
  }
  return entries;
}

function failureOf(entry: { index: Address; reasonData: Hex }): BatchActionFailure {
  return { index: entry.index, reasonData: entry.reasonData, reason: failureReasonOf(entry.reasonData) };
}

function isProtocolError(reason: FailureReason, errorName: string): boolean {
  return reason.kind === "protocol" && reason.errorName === errorName;
}

/** The last event named `eventName` in the group, i.e. the one closest to the outcome. */
function findIndexEvent<const name extends IndexEventLog["eventName"]>(
  events: IndexEventLog[],
  eventName: name,
): Extract<IndexEventLog, { eventName: name }> | undefined {
  for (let i = events.length - 1; i >= 0; i--) {
    const event = events[i];
    if (event?.eventName === eventName) return event as Extract<IndexEventLog, { eventName: name }>;
  }
  return undefined;
}

function reservesOf(event: Extract<IndexEventLog, { eventName: "IndexRebalanced" }>): RebalanceReserves {
  const { asset0ReserveBefore, asset1ReserveBefore, asset0ReserveAfter, asset1ReserveAfter } = event.args;
  return { asset0ReserveBefore, asset1ReserveBefore, asset0ReserveAfter, asset1ReserveAfter };
}

/**
 * Outcome of `rebalanceMultipleIndexes` for each Index, from the receipt logs. A reverted transaction has no
 * logs: pass its error to `toSdkError` instead.
 * @throws {EventNotFoundError} the logs are not those of this batch, or a rebalanced Index has no `IndexRebalanced`
 */
export function parseRebalanceBatch(logs: readonly ReceiptLog[], params: BatchParams): RebalanceBatchResult {
  const result: RebalanceBatchResult = { rebalanced: [], notNeeded: [], failed: [] };
  for (const entry of parseBatch(logs, params, "REBALANCE")) {
    if (entry.success) {
      const rebalanced = findIndexEvent(entry.indexEvents, "IndexRebalanced");
      if (!rebalanced) throw new EventNotFoundError("IndexRebalanced", entry.index);
      result.rebalanced.push({ index: entry.index, ...reservesOf(rebalanced) });
      continue;
    }
    const failure = failureOf(entry);
    if (isProtocolError(failure.reason, "Index__RebalanceNotNeeded")) result.notNeeded.push({ index: entry.index });
    else result.failed.push(failure);
  }
  return result;
}

/**
 * Outcome of `executeWeightUpdateForMultipleIndexes` for each Index, from the receipt logs.
 * @throws {EventNotFoundError} the logs are not those of this batch, or an updated Index lacks its Index events
 */
export function parseWeightUpdateBatch(logs: readonly ReceiptLog[], params: BatchParams): WeightUpdateBatchResult {
  const result: WeightUpdateBatchResult = { updated: [], failed: [] };
  for (const entry of parseBatch(logs, params, "EXECUTE_WEIGHTS")) {
    if (!entry.success) {
      result.failed.push(failureOf(entry));
      continue;
    }
    const weights = findIndexEvent(entry.indexEvents, "WeightsUpdated");
    if (!weights) throw new EventNotFoundError("WeightsUpdated", entry.index);
    const weightsAt = entry.indexEvents.lastIndexOf(weights);
    // The inner rebalance outcome is emitted after WeightsUpdated, by executeWeightUpdate itself.
    const afterWeights = entry.indexEvents.slice(weightsAt + 1);
    const rebalanced = findIndexEvent(afterWeights, "IndexRebalanced");
    const rebalanceFailed = findIndexEvent(afterWeights, "WeightsUpdateRebalanceFailed");
    let rebalance: WeightUpdateRebalance;
    if (rebalanced) rebalance = { status: "rebalanced", ...reservesOf(rebalanced) };
    else if (findIndexEvent(afterWeights, "WeightsUpdateRebalanceSkipped")) rebalance = { status: "skipped" };
    else if (rebalanceFailed) {
      const { reasonData } = rebalanceFailed.args;
      rebalance = { status: "failed", reasonData, reason: failureReasonOf(reasonData) };
    } else {
      throw new EventNotFoundError("IndexRebalanced/WeightsUpdateRebalanceSkipped/WeightsUpdateRebalanceFailed", entry.index);
    }
    result.updated.push({
      index: entry.index,
      asset0Weight: weights.args.asset0Weight,
      asset1Weight: weights.args.asset1Weight,
      rebalance,
    });
  }
  return result;
}

/**
 * Outcome of `collectFeesFromMultipleIndexes` for each Index, from the receipt logs.
 * @throws {EventNotFoundError} the logs are not those of this batch, or a collected Index has no `FeesCollected`
 */
export function parseCollectFeesBatch(logs: readonly ReceiptLog[], params: BatchParams): CollectFeesBatchResult {
  const result: CollectFeesBatchResult = { collected: [], noFees: [], failed: [] };
  for (const entry of parseBatch(logs, params, "COLLECT_FEES")) {
    if (entry.success) {
      const fees = findIndexEvent(entry.indexEvents, "FeesCollected");
      if (!fees) throw new EventNotFoundError("FeesCollected", entry.index);
      result.collected.push({ index: entry.index, feeAmount: fees.args.feeAmount });
      continue;
    }
    const failure = failureOf(entry);
    if (isProtocolError(failure.reason, "Index__NoFeesToCollect")) result.noFees.push({ index: entry.index });
    else result.failed.push(failure);
  }
  return result;
}
