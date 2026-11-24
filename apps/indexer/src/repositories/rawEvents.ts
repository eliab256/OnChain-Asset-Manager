// RawEvent: every decoded protocol event, unique on (chainId, txHash, logIndex).
// Undecodable logs never come here: they become IndexerError rows (indexer.md §5).
import type { Db } from "./db.js";
import { toJsonArgs } from "./json.js";

/**
 * A decoded event to store. The decoded logs of chain/ have this shape, but the repository does not
 * import their type: this layer does not know the chain (indexer.md §3).
 */
export type RawEventInput = {
  address: string;
  eventName: string;
  args: unknown;
  blockNumber: bigint;
  blockHash: string;
  txHash: string;
  logIndex: number;
};

/**
 * Inserts the decoded events of a block, skipping the ones already stored (same chainId, txHash, logIndex).
 * @param timestamp Timestamp of the block header, never the server clock.
 * @returns How many rows were inserted: less than events.length only when the block is processed again.
 */
export async function insertRawEvents(db: Db, chainId: number, timestamp: Date, events: readonly RawEventInput[]): Promise<number> {
  if (events.length === 0) return 0;
  const data = events.map((event) => ({
    chainId,
    blockNumber: event.blockNumber,
    blockHash: event.blockHash.toLowerCase(),
    txHash: event.txHash.toLowerCase(),
    logIndex: event.logIndex,
    timestamp,
    address: event.address.toLowerCase(),
    eventName: event.eventName,
    args: toJsonArgs(event.args),
  }));
  const { count } = await db.rawEvent.createMany({ data, skipDuplicates: true });
  return count;
}
