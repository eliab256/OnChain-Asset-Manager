import type { Hex } from "viem";
import { describe, expect, it } from "vitest";
import { LogBlockMismatchError, assertLogsBelongToBlock, type BlockIdentity } from "./consistency.js";
import type { LogLocation } from "./logs.js";

const hash = (byte: string): Hex => `0x${byte.repeat(32)}`;
const block: BlockIdentity = { number: 10n, hash: hash("aa") };

function log(overrides: Partial<LogLocation> = {}): LogLocation {
  return {
    address: "0x00000000000000000000000000000000000000ab",
    blockNumber: 10n,
    blockHash: hash("aa"),
    txHash: hash("77"),
    logIndex: 0,
    ...overrides,
  };
}

describe("assertLogsBelongToBlock", () => {
  it("accepts logs with the number and hash of the block", () => {
    expect(() => assertLogsBelongToBlock(block, [log(), log({ logIndex: 1 })])).not.toThrow();
  });

  it("accepts a block without logs", () => {
    expect(() => assertLogsBelongToBlock(block, [])).not.toThrow();
  });

  it("compares hashes ignoring case", () => {
    expect(() => assertLogsBelongToBlock({ number: 10n, hash: hash("AA") }, [log()])).not.toThrow();
  });

  it("rejects a log from another version of the same block (reorg)", () => {
    expect(() => assertLogsBelongToBlock(block, [log(), log({ logIndex: 1, blockHash: hash("bb") })])).toThrow(LogBlockMismatchError);
  });

  it("rejects a log from another block number", () => {
    expect(() => assertLogsBelongToBlock(block, [log({ blockNumber: 11n })])).toThrow(LogBlockMismatchError);
  });

  it("reports the block and the first log that does not belong to it", () => {
    const stray = log({ logIndex: 2, blockHash: hash("bb") });
    let caught: unknown;
    try {
      assertLogsBelongToBlock(block, [log(), stray, log({ logIndex: 3, blockHash: hash("cc") })]);
    } catch (error) {
      caught = error;
    }
    expect(caught).toBeInstanceOf(LogBlockMismatchError);
    expect(caught).toMatchObject({ block, log: stray });
    expect((caught as Error).message).toContain(`${hash("77")}:2`);
  });
});
