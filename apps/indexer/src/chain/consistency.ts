// Consistency checks between data read with different RPC calls (indexer.md §4, "Controllo del blockHash dei log").
// The logs of a range come from one getLogs, made before the getBlock of each of its blocks: a reorg in
// between, or two calls served by different nodes, can pair a block with the logs of another version of it.
import type { Hex } from "viem";
import type { LogLocation } from "./logs.js";

/** The block a group of logs is about to be written with. */
export type BlockIdentity = {
  number: bigint;
  hash: Hex;
};

/** Thrown when a log does not belong to the block it is grouped with. The block must not be written. */
export class LogBlockMismatchError extends Error {
  constructor(
    readonly block: BlockIdentity,
    readonly log: LogLocation,
  ) {
    super(
      `Log ${log.txHash}:${log.logIndex} of ${log.address} is at block ${log.blockNumber} (${log.blockHash}), ` +
        `but it was grouped with block ${block.number} (${block.hash}): reorg or inconsistent RPC, read the block again`,
    );
    this.name = "LogBlockMismatchError";
  }
}

/**
 * Checks that every log has the number and the hash of the block just read. Hashes are compared
 * case-insensitively, so a block hash in mixed case from a provider does not raise a false alarm.
 * An empty list passes: a block without logs has nothing to compare.
 * @param block Number and hash from getBlock(n).
 * @param logs The logs grouped under block n.
 * @throws LogBlockMismatchError on the first log that belongs to another block.
 */
export function assertLogsBelongToBlock(block: BlockIdentity, logs: readonly LogLocation[]): void {
  const hash = block.hash.toLowerCase();
  for (const log of logs) {
    if (log.blockNumber !== block.number || log.blockHash.toLowerCase() !== hash) {
      throw new LogBlockMismatchError(block, log);
    }
  }
}
