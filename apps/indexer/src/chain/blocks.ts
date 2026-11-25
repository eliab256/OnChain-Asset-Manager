// Block headers as the pipeline needs them: number, hashes in lowercase, timestamp as a Date.
import type { Hex, PublicClient } from "viem";

/** The part of a block the indexer stores and checks. */
export type BlockHeader = {
  number: bigint;
  hash: Hex;
  parentHash: Hex;
  /** From the block header (seconds since epoch), never the server clock. */
  timestamp: Date;
};

/** Thrown when the node returns a block without hash or number, i.e. a pending block. */
export class IncompleteBlockError extends Error {
  constructor(readonly blockNumber: bigint) {
    super(`Block ${blockNumber} came back without hash or number (pending?)`);
    this.name = "IncompleteBlockError";
  }
}

/**
 * Reads the header of a mined block (eth_getBlockByNumber without transactions).
 * @throws IncompleteBlockError if the node answers with a pending block.
 */
export async function fetchBlockHeader(client: PublicClient, blockNumber: bigint): Promise<BlockHeader> {
  const block = await client.getBlock({ blockNumber, includeTransactions: false });
  if (block.hash === null || block.number === null) throw new IncompleteBlockError(blockNumber);
  return {
    number: block.number,
    hash: block.hash.toLowerCase() as Hex,
    parentHash: block.parentHash.toLowerCase() as Hex,
    timestamp: new Date(Number(block.timestamp) * 1000),
  };
}
