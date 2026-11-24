import { describe, expect, it } from "vitest";
import { getCheckpoint, setCheckpoint } from "../../src/repositories/checkpoint.js";
import { useTestDatabase } from "../helpers/db.js";

const hash = (byte: string): string => `0x${byte.repeat(32)}`;

describe("checkpoint repository", () => {
  const db = useTestDatabase();

  it("returns null for a chain that was never indexed", async () => {
    expect(await getCheckpoint(db(), 31337)).toBeNull();
  });

  it("creates the checkpoint, then moves it", async () => {
    await setCheckpoint(db(), 31337, { blockNumber: 10n, blockHash: hash("aa") });
    await setCheckpoint(db(), 31337, { blockNumber: 11n, blockHash: hash("bb") });
    expect(await getCheckpoint(db(), 31337)).toEqual({ blockNumber: 11n, blockHash: hash("bb") });
    expect(await db().checkpoint.count()).toBe(1);
  });

  it("keeps one checkpoint per chain", async () => {
    await setCheckpoint(db(), 31337, { blockNumber: 5n, blockHash: hash("aa") });
    await setCheckpoint(db(), 31338, { blockNumber: 26_178_000n, blockHash: hash("cc") });
    expect((await getCheckpoint(db(), 31337))?.blockNumber).toBe(5n);
    expect((await getCheckpoint(db(), 31338))?.blockNumber).toBe(26_178_000n);
  });

  it("stores the hash in lowercase", async () => {
    await setCheckpoint(db(), 31337, { blockNumber: 1n, blockHash: hash("AB") });
    expect((await getCheckpoint(db(), 31337))?.blockHash).toBe(hash("ab"));
  });
});
