// Runner: decides when the indexer works (indexer.md §3 and §4). Bootstrap and backfill up to the head;
// the live loop arrives with step 5 of localHelpers/indexer-roadmap.md.
import { processRange, type ProcessRangeResult, type RangeDeps } from "./pipeline.js";
import { getCheckpoint, type CheckpointPosition } from "./repositories/checkpoint.js";
import { insertFixedContracts, type FixedContracts } from "./repositories/contracts.js";
import type { Db } from "./repositories/db.js";

/** Where the indexer resumes on a chain. */
export type BootstrapResult = {
  /** First block to process: startBlock on a chain never indexed, otherwise checkpoint + 1. */
  fromBlock: bigint;
  /**
   * The last block fully written, or null on a chain never indexed. Its hash is what the parentHash of
   * fromBlock must match: a reorg that happened while the indexer was stopped shows up there.
   */
  checkpoint: CheckpointPosition | null;
  /** Fixed contracts inserted by this start: 6 the first time, 0 from the second start on. */
  insertedContracts: number;
};

/**
 * Prepares a chain for processing (indexer.md §4, "Bootstrap"): inserts the fixed contracts, so that
 * getLogs has addresses to listen to, then reads the checkpoint to decide where to start.
 * Safe to run at every start: existing contracts and the checkpoint are left as they are.
 * @param fixed The fixed contracts and startBlock of the deployment, i.e. protocolAddresses[chainId].
 */
export async function bootstrap(db: Db, chainId: number, fixed: FixedContracts): Promise<BootstrapResult> {
  const insertedContracts = await insertFixedContracts(db, chainId, fixed);
  const checkpoint = await getCheckpoint(db, chainId);
  const fromBlock = checkpoint === null ? fixed.startBlock : checkpoint.blockNumber + 1n;
  return { fromBlock, checkpoint, insertedContracts };
}

/**
 * Thrown when the checkpoint is past the head of the chain: the node is not the chain the DB was written
 * from, typically an anvil restarted from scratch under the same chain id (indexer.md §4, "Bootstrap").
 * Processing would wait for blocks that, once they exist, have other hashes.
 */
export class CheckpointAheadOfHeadError extends Error {
  constructor(
    readonly chainId: number,
    readonly checkpointBlock: bigint,
    readonly head: bigint,
  ) {
    super(
      `Checkpoint of chain ${chainId} is at block ${checkpointBlock}, but the chain head is ${head}: the node was ` +
        `restarted or serves another chain. Delete the rows of chain ${chainId} before restarting the indexer`,
    );
    this.name = "CheckpointAheadOfHeadError";
  }
}

export type BackfillResult = {
  bootstrap: BootstrapResult;
  /** Head read once at the start: blocks produced during the backfill are left to the next call. */
  head: bigint;
  range: ProcessRangeResult;
};

/**
 * Bootstrap, then every block from the resume point to the current head (indexer.md §4). Running it again
 * processes only the blocks after the checkpoint; with nothing new it writes nothing.
 * @param fixed protocolAddresses[chainId].
 * @throws CheckpointAheadOfHeadError, or whatever processRange throws (blocks before the failing one stay written).
 */
export async function backfill(deps: RangeDeps, fixed: FixedContracts): Promise<BackfillResult> {
  const start = await bootstrap(deps.prisma, deps.chainId, fixed);
  // cacheTime 0: viem caches the block number for a few seconds, and the head must be the current one.
  const head = await deps.client.getBlockNumber({ cacheTime: 0 });
  if (start.checkpoint !== null && start.checkpoint.blockNumber > head) {
    throw new CheckpointAheadOfHeadError(deps.chainId, start.checkpoint.blockNumber, head);
  }
  const range = await processRange(deps, start.fromBlock, head);
  return { bootstrap: start, head, range };
}
