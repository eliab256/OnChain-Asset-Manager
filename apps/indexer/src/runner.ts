// Runner: decides when the indexer works (indexer.md §3 and §4). For now only the bootstrap;
// backfill and live loop arrive with steps 3 and 5 of localHelpers/indexer-roadmap.md.
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
