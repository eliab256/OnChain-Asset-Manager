// Block: one row per processed block, with the hash and parentHash used to detect reorgs.
import type { Db } from "./db.js";

/** A block as stored. Hashes in lowercase, timestamp from the block header. */
export type StoredBlock = {
  number: bigint;
  hash: string;
  parentHash: string;
  timestamp: Date;
};

/**
 * Inserts a block row, skipping it if the chain already has a row with that number.
 * @returns true if the row was inserted, false if it was already there.
 */
export async function insertBlock(db: Db, chainId: number, block: StoredBlock): Promise<boolean> {
  const data = { chainId, ...block, hash: block.hash.toLowerCase(), parentHash: block.parentHash.toLowerCase() };
  const { count } = await db.block.createMany({ data: [data], skipDuplicates: true });
  return count === 1;
}

/**
 * Reads a stored block, e.g. block n − 1 to compare its hash with the parentHash of block n.
 * @returns The block, or null if it was never written.
 */
export async function getStoredBlock(db: Db, chainId: number, number: bigint): Promise<StoredBlock | null> {
  const row = await db.block.findUnique({ where: { chainId_number: { chainId, number } } });
  return row === null ? null : { number: row.number, hash: row.hash, parentHash: row.parentHash, timestamp: row.timestamp };
}
