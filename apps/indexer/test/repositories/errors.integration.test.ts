import { describe, expect, it } from "vitest";
import { recordIndexerError } from "../../src/repositories/errors.js";
import { useTestDatabase } from "../helpers/db.js";

describe("errors repository", () => {
  const db = useTestDatabase();

  it("writes an error with block and context", async () => {
    await recordIndexerError(db(), { chainId: 31337, blockNumber: 7n, context: "unknownLog 0xab:3", message: "boom" });
    const [row] = await db().indexerError.findMany();
    expect(row).toMatchObject({ chainId: 31337, blockNumber: 7n, context: "unknownLog 0xab:3", message: "boom" });
  });

  it("writes null for a missing block and context", async () => {
    await recordIndexerError(db(), { chainId: 31337, message: "no block" });
    const [row] = await db().indexerError.findMany();
    expect(row).toMatchObject({ blockNumber: null, context: null });
  });

  it("is rolled back with the transaction it was written in", async () => {
    await expect(
      db().$transaction(async (tx) => {
        await recordIndexerError(tx, { chainId: 31337, blockNumber: 1n, message: "inside" });
        throw new Error("block failed");
      }),
    ).rejects.toThrow("block failed");
    expect(await db().indexerError.count()).toBe(0);
  });
});
