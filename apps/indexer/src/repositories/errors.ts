// IndexerError: the log of problems the indexer met and went past (or stopped on).
// Rows are never deleted, not even by a reorg (db.md, "Reorg", point 6).
import type { Db } from "./db.js";

export type IndexerErrorInput = {
  chainId: number;
  /** Block being processed, when the error belongs to one. */
  blockNumber?: bigint;
  /** Where it happened, e.g. "unknownLog 0x…:3 at 0x…". */
  context?: string;
  message: string;
};

/**
 * Writes an IndexerError row. Inside a block's transaction the row is rolled back with the block,
 * so a retried block does not leave duplicates.
 */
export async function recordIndexerError(db: Db, input: IndexerErrorInput): Promise<void> {
  await db.indexerError.create({
    data: {
      chainId: input.chainId,
      blockNumber: input.blockNumber ?? null,
      context: input.context ?? null,
      message: input.message,
    },
  });
}
