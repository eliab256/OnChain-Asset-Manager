import { describe, expect, it } from "vitest";
import { getStoredBlock, insertBlock, type StoredBlock } from "../../src/repositories/blocks.js";
import { useTestDatabase } from "../helpers/db.js";

const hash = (byte: string): string => `0x${byte.repeat(32)}`;

function block(number: bigint, hashByte: string, parentByte: string): StoredBlock {
  return { number, hash: hash(hashByte), parentHash: hash(parentByte), timestamp: new Date(Number(number) * 12_000) };
}

describe("blocks repository", () => {
  const db = useTestDatabase();

  it("inserts a block and reads it back", async () => {
    expect(await insertBlock(db(), 31337, block(1n, "11", "00"))).toBe(true);
    expect(await getStoredBlock(db(), 31337, 1n)).toEqual(block(1n, "11", "00"));
  });

  it("returns null for a block never written", async () => {
    expect(await getStoredBlock(db(), 31337, 99n)).toBeNull();
  });

  it("skips a block number already stored and keeps the first row", async () => {
    await insertBlock(db(), 31337, block(1n, "11", "00"));
    expect(await insertBlock(db(), 31337, block(1n, "22", "00"))).toBe(false);
    expect((await getStoredBlock(db(), 31337, 1n))?.hash).toBe(hash("11"));
  });

  it("keeps the same block number apart on two chains", async () => {
    await insertBlock(db(), 31337, block(1n, "11", "00"));
    expect(await insertBlock(db(), 31338, block(1n, "22", "00"))).toBe(true);
    expect((await getStoredBlock(db(), 31338, 1n))?.hash).toBe(hash("22"));
  });

  it("stores hashes in lowercase", async () => {
    await insertBlock(db(), 31337, block(1n, "AB", "CD"));
    expect(await getStoredBlock(db(), 31337, 1n)).toMatchObject({ hash: hash("ab"), parentHash: hash("cd") });
  });
});
