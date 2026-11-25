import { protocolAddresses } from "@oam/abi";
import { describe, expect, it } from "vitest";
import { setCheckpoint } from "../src/repositories/checkpoint.js";
import { loadContractKinds } from "../src/repositories/contracts.js";
import { bootstrap } from "../src/runner.js";
import { useTestDatabase } from "./helpers/db.js";

const fixed = protocolAddresses[31337];
const hash = (byte: string): string => `0x${byte.repeat(32)}`;

describe("bootstrap", () => {
  const db = useTestDatabase();

  it("starts a chain never indexed from the deployment's startBlock", async () => {
    const result = await bootstrap(db(), 31337, fixed);
    expect(result).toEqual({ fromBlock: fixed.startBlock, checkpoint: null, insertedContracts: 6 });
  });

  it("registers the fixed contracts, so getLogs has addresses to listen to", async () => {
    await bootstrap(db(), 31337, fixed);
    expect((await loadContractKinds(db(), 31337)).size).toBe(6);
  });

  it("resumes from the block after the checkpoint and returns it", async () => {
    await bootstrap(db(), 31337, fixed);
    await setCheckpoint(db(), 31337, { blockNumber: 42n, blockHash: hash("ab") });
    const result = await bootstrap(db(), 31337, fixed);
    expect(result).toEqual({ fromBlock: 43n, checkpoint: { blockNumber: 42n, blockHash: hash("ab") }, insertedContracts: 0 });
  });

  it("adds no contract and moves nothing on a second start", async () => {
    await bootstrap(db(), 31337, fixed);
    await bootstrap(db(), 31337, fixed);
    expect(await db().contract.count()).toBe(6);
    expect(await db().checkpoint.count()).toBe(0);
  });

  it("keeps the two chains apart: a checkpoint on 31338 does not move 31337", async () => {
    await setCheckpoint(db(), 31338, { blockNumber: 26_178_100n, blockHash: hash("cd") });
    const result = await bootstrap(db(), 31337, fixed);
    expect(result.fromBlock).toBe(fixed.startBlock);
  });
});
