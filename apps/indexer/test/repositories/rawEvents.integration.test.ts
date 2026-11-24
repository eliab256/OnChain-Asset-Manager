import { describe, expect, it } from "vitest";
import { insertRawEvents, type RawEventInput } from "../../src/repositories/rawEvents.js";
import { useTestDatabase } from "../helpers/db.js";

const hash = (byte: string): string => `0x${byte.repeat(32)}`;
const timestamp = new Date("2026-11-22T12:00:00Z");

function event(logIndex: number, overrides: Partial<RawEventInput> = {}): RawEventInput {
  return {
    address: "0x00000000000000000000000000000000000000aa",
    eventName: "SharesMinted",
    args: { user: "0x00000000000000000000000000000000000000bb", shares: 2n ** 200n, fee: 0n },
    blockNumber: 5n,
    blockHash: hash("55"),
    txHash: hash("77"),
    logIndex,
    ...overrides,
  };
}

describe("rawEvents repository", () => {
  const db = useTestDatabase();

  it("inserts the events of a block with the block timestamp", async () => {
    expect(await insertRawEvents(db(), 31337, timestamp, [event(0), event(1)])).toBe(2);
    const rows = await db().rawEvent.findMany({ orderBy: { logIndex: "asc" } });
    expect(rows.map((row) => row.logIndex)).toEqual([0, 1]);
    expect(rows[0]).toMatchObject({ chainId: 31337, blockNumber: 5n, eventName: "SharesMinted", timestamp });
  });

  it("stores bigint args as decimal strings, beyond the precision of a JS number", async () => {
    await insertRawEvents(db(), 31337, timestamp, [event(0)]);
    const row = await db().rawEvent.findFirstOrThrow();
    expect(row.args).toEqual({
      user: "0x00000000000000000000000000000000000000bb",
      shares: (2n ** 200n).toString(),
      fee: "0",
    });
  });

  it("counts only the rows really inserted when the same block is processed again", async () => {
    await insertRawEvents(db(), 31337, timestamp, [event(0), event(1)]);
    expect(await insertRawEvents(db(), 31337, timestamp, [event(0), event(1), event(2)])).toBe(1);
    expect(await db().rawEvent.count()).toBe(3);
  });

  it("keeps the same txHash and logIndex apart on two chains", async () => {
    await insertRawEvents(db(), 31337, timestamp, [event(0)]);
    expect(await insertRawEvents(db(), 31338, timestamp, [event(0)])).toBe(1);
  });

  it("does not query the database for an empty block", async () => {
    expect(await insertRawEvents(db(), 31337, timestamp, [])).toBe(0);
  });

  it("stores address and hashes in lowercase", async () => {
    await insertRawEvents(db(), 31337, timestamp, [
      event(0, { address: "0x00000000000000000000000000000000000000AA", txHash: hash("AB"), blockHash: hash("CD") }),
    ]);
    const row = await db().rawEvent.findFirstOrThrow();
    expect(row).toMatchObject({
      address: "0x00000000000000000000000000000000000000aa",
      txHash: hash("ab"),
      blockHash: hash("cd"),
    });
  });
});
