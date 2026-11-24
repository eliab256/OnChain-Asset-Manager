// Checkpoint: the last block fully written for a chain, where the indexer resumes after a stop.
import type { Db } from "./db.js";

/** The last processed block of a chain. Hash in lowercase. */
export type CheckpointPosition = {
  blockNumber: bigint;
  blockHash: string;
};

/**
 * Reads the checkpoint of a chain.
 * @returns The last processed block, or null if the indexer never wrote a block of this chain.
 */
export async function getCheckpoint(db: Db, chainId: number): Promise<CheckpointPosition | null> {
  const row = await db.checkpoint.findUnique({ where: { chainId } });
  return row === null ? null : { blockNumber: row.lastBlockNumber, blockHash: row.lastBlockHash };
}

/**
 * Moves the checkpoint of a chain to a block. Called as the last write of a block's transaction,
 * so it never points past a block that is not fully written.
 * @param position Number and hash (lowercase) of the block just written.
 */
export async function setCheckpoint(db: Db, chainId: number, position: CheckpointPosition): Promise<void> {
  const data = { lastBlockNumber: position.blockNumber, lastBlockHash: position.blockHash.toLowerCase() };
  await db.checkpoint.upsert({ where: { chainId }, create: { chainId, ...data }, update: data });
}
