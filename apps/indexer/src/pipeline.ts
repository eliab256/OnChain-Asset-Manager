// Pipeline: how a block is processed (indexer.md §4). One block is written entirely in one database
// transaction, or not at all. RPC reads of the block happen before the transaction opens.
import { ContractKind, type PrismaClient } from "@oam/db";
import type { Address, PublicClient } from "viem";
import { fetchBlockHeader, type BlockHeader } from "./chain/blocks.js";
import { LogBlockMismatchError, assertLogsBelongToBlock } from "./chain/consistency.js";
import { fetchLogs, type ChainLog, type DecodedLog, type LogLocation, type UnknownLog } from "./chain/logs.js";
import type { AddedContract, EventName, Handler, HandlerMap } from "./handlers/types.js";
import { logger, type LogFields } from "./logger.js";
import { getStoredBlock, insertBlock } from "./repositories/blocks.js";
import { setCheckpoint } from "./repositories/checkpoint.js";
import { recordIndexerError } from "./repositories/errors.js";
import { loadContractKinds } from "./repositories/contracts.js";
import { insertRawEvents } from "./repositories/rawEvents.js";

/**
 * Timeout of the block transaction. Prisma's default (5 s) is meant for database work only; the RPC reads
 * that handlers still make inside it (name(), symbol(), decimals) need room (indexer.md §4, "RPC e transazione").
 */
export const BLOCK_TX_TIMEOUT_MS = 30_000;
/** How long to wait for a pooled connection before the block transaction gives up. */
export const BLOCK_TX_MAX_WAIT_MS = 10_000;
/** Reads of block n (header and logs) before a blockHash mismatch is treated as permanent. */
export const BLOCK_READ_ATTEMPTS = 3;
/** Pause between two reads of the same block after a blockHash mismatch. */
export const DEFAULT_MISMATCH_RETRY_DELAY_MS = 1_000;

export type { AddedContract, Handler, HandlerContext, HandlerMap, HandlerResult } from "./handlers/types.js";

export type PipelineDeps = {
  prisma: PrismaClient;
  client: PublicClient;
  chainId: number;
  handlers: HandlerMap;
  /**
   * Lowercase address → kind of every contract of the chain (loadContractKinds), also the getLogs filter.
   * processRange passes its own map and adds the contracts of each block to it, so it is always current.
   */
  contractKinds: ReadonlyMap<string, ContractKind>;
  /** Pause between reads of the same block after a blockHash mismatch; tests pass 0. */
  mismatchRetryDelayMs?: number;
};

export type ProcessBlockResult = {
  block: BlockHeader;
  /** False when the block was already stored (block processed again). */
  blockInserted: boolean;
  rawEventsInserted: number;
  addedContracts: AddedContract[];
};

/**
 * Thrown when the parentHash of block n differs from the hash stored for n − 1: the chain the indexer
 * followed is no longer the real one. Until the rollback exists (roadmap step 7) the process stops here.
 */
export class ParentHashMismatchError extends Error {
  constructor(
    readonly blockNumber: bigint,
    readonly storedParentHash: string,
    readonly chainParentHash: string,
  ) {
    super(
      `Reorg at block ${blockNumber}: its parentHash is ${chainParentHash}, but block ${blockNumber - 1n} is stored ` +
        `with hash ${storedParentHash}. Rollback is not implemented yet (roadmap step 7): the indexer stops`,
    );
    this.name = "ParentHashMismatchError";
  }
}

/**
 * Thrown when block n is already stored with another hash: the block is processed again (a rerun over
 * written blocks) and the chain has changed under it. Writing it would keep the old Block row and move the
 * checkpoint to the new hash, so the process stops, as for a parentHash mismatch.
 */
export class StoredBlockMismatchError extends Error {
  constructor(
    readonly blockNumber: bigint,
    readonly storedHash: string,
    readonly chainHash: string,
  ) {
    super(
      `Reorg at block ${blockNumber}: it is stored with hash ${storedHash}, but the chain now has ${chainHash}. ` +
        `Rollback is not implemented yet (roadmap step 7): the indexer stops`,
    );
    this.name = "StoredBlockMismatchError";
  }
}

function sleep(ms: number): Promise<void> {
  return ms <= 0 ? Promise.resolve() : new Promise((resolve) => setTimeout(resolve, ms));
}

function where(log: LogLocation): string {
  return `${log.address} ${log.txHash}:${log.logIndex}`;
}

/**
 * Adds to `logs` (one getLogs of the known contracts over a range ending at `to`) the logs of every Index created in them
 * (indexer.md §4, "Index creati a metà range"). An IndexCreated from an INDEX_MANAGER names an address that
 * the getLogs filter did not have yet: its logs from the creation block to `to` are requested in one more
 * getLogs, and in the creation block only those after the IndexCreated (higher logIndex) are kept.
 * Done before any block of the range is processed, so every RPC call stays outside the block transactions.
 * @returns The logs sorted by (blockNumber, logIndex); `logs` itself when no new Index is created.
 */
export async function withDiscoveredIndexLogs(
  client: PublicClient,
  contractKinds: ReadonlyMap<string, ContractKind>,
  logs: readonly ChainLog[],
  to: bigint,
): Promise<readonly ChainLog[]> {
  const created = new Map<string, LogLocation>();
  for (const log of logs) {
    if (log.kind !== "decoded" || log.eventName !== "IndexCreated") continue;
    if (contractKinds.get(log.address) !== ContractKind.INDEX_MANAGER) continue;
    const index = log.args.indexAddress;
    if (!contractKinds.has(index) && !created.has(index)) created.set(index, log);
  }
  if (created.size === 0) return logs;

  let from = to;
  for (const at of created.values()) if (at.blockNumber < from) from = at.blockNumber;
  const indexLogs = await fetchLogs(client, [...created.keys()] as Address[], from, to);
  const after = indexLogs.filter((log) => {
    const at = created.get(log.address);
    return at !== undefined && (log.blockNumber > at.blockNumber || (log.blockNumber === at.blockNumber && log.logIndex > at.logIndex));
  });
  return [...logs, ...after].sort((a, b) => (a.blockNumber === b.blockNumber ? a.logIndex - b.logIndex : a.blockNumber < b.blockNumber ? -1 : 1));
}

/** One getLogs of the known contracts over [from, to], plus the logs of the Index created there. */
async function fetchRangeLogs(deps: PipelineDeps, from: bigint, to: bigint): Promise<readonly ChainLog[]> {
  const logs = await fetchLogs(deps.client, [...deps.contractKinds.keys()] as Address[], from, to);
  return withDiscoveredIndexLogs(deps.client, deps.contractKinds, logs, to);
}

/**
 * Reads the header of block n and checks that `logs` belong to it. On a mismatch it reads the header and
 * the logs of block n alone again, up to BLOCK_READ_ATTEMPTS reads in total.
 * @returns The header and the logs that belong to it (the re-read ones after a mismatch).
 * @throws LogBlockMismatchError if the last read still does not match; the IndexerError row is the caller's.
 */
async function readConsistentBlock(
  deps: PipelineDeps,
  blockNumber: bigint,
  logs: readonly ChainLog[],
): Promise<{ block: BlockHeader; logs: readonly ChainLog[] }> {
  let current = logs;
  for (let attempt = 1; ; attempt++) {
    const block = await fetchBlockHeader(deps.client, blockNumber);
    try {
      assertLogsBelongToBlock(block, current);
      return { block, logs: current };
    } catch (error) {
      if (!(error instanceof LogBlockMismatchError) || attempt >= BLOCK_READ_ATTEMPTS) throw error;
      logger.warn("logs do not belong to the block just read, reading the block again", {
        chainId: deps.chainId,
        blockNumber,
        attempt,
        error: error.message,
      });
      await sleep(deps.mismatchRetryDelayMs ?? DEFAULT_MISMATCH_RETRY_DELAY_MS);
      current = await fetchRangeLogs(deps, blockNumber, blockNumber);
    }
  }
}

/**
 * Processes block n (indexer.md §4, "processBlock"): reads the header, checks logs and parentHash, then in
 * one transaction writes Block, RawEvent, the handlers' rows and the Checkpoint. Processing the same block
 * again writes nothing new.
 * @param logs The logs of block n from the range's getLogs, decoded or unknown.
 * @throws ParentHashMismatchError or StoredBlockMismatchError on a reorg, LogBlockMismatchError if the logs never match the block:
 *   in both cases an IndexerError row is written outside the transaction and nothing of the block is.
 */
export async function processBlock(deps: PipelineDeps, blockNumber: bigint, logs: readonly ChainLog[]): Promise<ProcessBlockResult> {
  const { prisma, chainId } = deps;

  let block: BlockHeader;
  let blockLogs: ChainLog[];
  try {
    const read = await readConsistentBlock(deps, blockNumber, logs);
    block = read.block;
    blockLogs = [...read.logs].sort((a, b) => a.logIndex - b.logIndex);
  } catch (error) {
    if (error instanceof LogBlockMismatchError) {
      await recordIndexerError(prisma, { chainId, blockNumber, context: `logBlockMismatch ${where(error.log)}`, message: error.message });
    }
    throw error;
  }

  // Checked before the transaction: the IndexerError row must survive the stop that follows.
  const parent = await getStoredBlock(prisma, chainId, blockNumber - 1n);
  if (parent !== null && parent.hash !== block.parentHash) {
    const error = new ParentHashMismatchError(blockNumber, parent.hash, block.parentHash);
    await recordIndexerError(prisma, { chainId, blockNumber, context: "parentHashMismatch", message: error.message });
    throw error;
  }
  // A block processed again must be the same block: same rule, same place.
  const stored = await getStoredBlock(prisma, chainId, blockNumber);
  if (stored !== null && stored.hash !== block.hash) {
    const error = new StoredBlockMismatchError(blockNumber, stored.hash, block.hash);
    await recordIndexerError(prisma, { chainId, blockNumber, context: "storedBlockMismatch", message: error.message });
    throw error;
  }

  const decoded = blockLogs.filter((log): log is DecodedLog => log.kind === "decoded");
  const unknown = blockLogs.filter((log): log is UnknownLog => log.kind === "unknown");
  // Logged after the commit: a warning about a block that was then rolled back would describe nothing.
  const afterCommit: { level: "warn" | "error"; message: string; fields: LogFields }[] = [];

  const result = await prisma.$transaction(
    async (tx) => {
      const blockInserted = await insertBlock(tx, chainId, block);
      const rawEventsInserted = await insertRawEvents(tx, chainId, block.timestamp, decoded);

      for (const log of unknown) {
        await recordIndexerError(tx, {
          chainId,
          blockNumber,
          context: `unknownLog ${where(log)}`,
          message: `${log.reason}: ${log.detail}; topics=[${log.topics.join(",")}]; data=${log.data}`,
        });
        afterCommit.push({
          level: "error",
          message: "log from a protocol contract does not decode: update @oam/abi",
          fields: { chainId, blockNumber, address: log.address, txHash: log.txHash, logIndex: log.logIndex, reason: log.reason },
        });
      }

      const addedContracts: AddedContract[] = [];
      // A contract added by a handler emits its next events of this same block (an Index initialized in the
      // block of its creation): dispatch reads this copy, updated after every handler.
      const kinds = new Map(deps.contractKinds);
      for (const log of decoded) {
        const handler = deps.handlers[log.eventName] as Handler<EventName> | undefined;
        if (handler === undefined) continue;
        const kind = kinds.get(log.address);
        if (kind === undefined || !handler.kinds.includes(kind)) {
          const expected = handler.kinds.join("|");
          await recordIndexerError(tx, {
            chainId,
            blockNumber,
            context: `unexpectedEmitter ${where(log)}`,
            message: `${log.eventName} from a ${kind ?? "contract not in Contract"}, its handler expects ${expected}: handler not called`,
          });
          afterCommit.push({
            level: "warn",
            message: "event from an unexpected contract kind, handler skipped",
            fields: { chainId, blockNumber, eventName: log.eventName, address: log.address, kind: kind ?? null, expected },
          });
          continue;
        }
        const txLogs = blockLogs.filter((other) => other.txHash === log.txHash);
        const outcome = await handler.handle({ db: tx, chainId, client: deps.client, block, log, txLogs });
        for (const added of outcome?.addedContracts ?? []) {
          addedContracts.push(added);
          kinds.set(added.address.toLowerCase(), added.kind);
        }
      }

      // End-of-block steps (prices, NavSnapshot, expired proposals) go here, before the checkpoint.

      await setCheckpoint(tx, chainId, { blockNumber, blockHash: block.hash });
      return { block, blockInserted, rawEventsInserted, addedContracts };
    },
    { timeout: BLOCK_TX_TIMEOUT_MS, maxWait: BLOCK_TX_MAX_WAIT_MS },
  );

  for (const entry of afterCommit) logger[entry.level](entry.message, entry.fields);
  return result;
}

export type RangeDeps = Omit<PipelineDeps, "contractKinds"> & {
  /** Blocks per eth_getLogs call (BATCH_SIZE). */
  batchSize: number;
};

export type ProcessRangeResult = {
  /** Last block written, or null when the range was empty. */
  lastBlock: bigint | null;
  blocksProcessed: number;
  /** Every contract added to Contract while processing the range. */
  addedContracts: AddedContract[];
};

/**
 * Processes the blocks [from, to] in order (indexer.md §4, "processRange"): one eth_getLogs per chunk of
 * `batchSize` blocks on every contract of the chain, logs grouped by block, then processBlock for every
 * block of the chunk, empty ones included. Backfill and live use this same function.
 *
 * The addresses come from Contract, read once at the start of the range; contracts added by a block join
 * the filter of the next chunk. The logs of an Index created inside a chunk are requested before the chunk is
 * processed (withDiscoveredIndexLogs), so none of them is missed.
 * @throws whatever processBlock throws: the blocks before the failing one are already written and the
 *   checkpoint points at the last of them, so the next call resumes from there.
 */
export async function processRange(deps: RangeDeps, from: bigint, to: bigint): Promise<ProcessRangeResult> {
  if (!Number.isInteger(deps.batchSize) || deps.batchSize < 1) throw new RangeError(`batchSize must be a positive integer, got ${deps.batchSize}`);
  const result: ProcessRangeResult = { lastBlock: null, blocksProcessed: 0, addedContracts: [] };
  if (from > to) return result;

  const contractKinds = await loadContractKinds(deps.prisma, deps.chainId);
  const blockDeps: PipelineDeps = { ...deps, contractKinds };
  const batch = BigInt(deps.batchSize);

  for (let chunkStart = from; chunkStart <= to; chunkStart += batch) {
    const chunkEnd = chunkStart + batch - 1n < to ? chunkStart + batch - 1n : to;
    const logs = await fetchRangeLogs(blockDeps, chunkStart, chunkEnd);
    const byBlock = new Map<bigint, ChainLog[]>();
    for (const log of logs) {
      const group = byBlock.get(log.blockNumber);
      if (group === undefined) byBlock.set(log.blockNumber, [log]);
      else group.push(log);
    }

    for (let blockNumber = chunkStart; blockNumber <= chunkEnd; blockNumber++) {
      const processed = await processBlock(blockDeps, blockNumber, byBlock.get(blockNumber) ?? []);
      for (const added of processed.addedContracts) contractKinds.set(added.address.toLowerCase(), added.kind);
      result.addedContracts.push(...processed.addedContracts);
      result.lastBlock = blockNumber;
      result.blocksProcessed++;
    }
  }
  return result;
}
