// processRange against the test database and the fake node: chunking, grouping by block, empty blocks,
// addresses read from Contract and contracts added during the range.
import { ContractKind } from "@oam/db";
import type { Address } from "viem";
import { describe, expect, it } from "vitest";
import { ParentHashMismatchError, StoredBlockMismatchError, processRange, type HandlerMap, type RangeDeps } from "../src/pipeline.js";
import { insertBlock } from "../src/repositories/blocks.js";
import { getCheckpoint } from "../src/repositories/checkpoint.js";
import { insertIndexContract } from "../src/repositories/contracts.js";
import { useTestDatabase } from "./helpers/db.js";
import { FakeChain, hash, transferLog, type LogFilter } from "./helpers/fakeChain.js";

const CHAIN = 31337;
const INDEX: Address = "0x00000000000000000000000000000000000000a1";
const NEW_INDEX: Address = "0x00000000000000000000000000000000000000a2";
const ALICE: Address = "0x00000000000000000000000000000000000000c3";
const ZERO: Address = "0x0000000000000000000000000000000000000000";

/** Blocks 1..5 with a Transfer of INDEX in blocks 2 and 4, and one of NEW_INDEX in block 5. */
function chain(): FakeChain {
  const fake = new FakeChain();
  for (let n = 1n; n <= 5n; n++) fake.addBlock(n, `${n}${n}`);
  const at = (n: bigint, tx: string) => ({ blockNumber: n, blockHash: fake.blocks.get(n)?.hash ?? hash("00"), txHash: hash(tx), logIndex: 0 });
  fake.logs = [
    transferLog(INDEX, at(2n, "a2"), ZERO, ALICE, 1n),
    transferLog(INDEX, at(4n, "a4"), ZERO, ALICE, 2n),
    transferLog(NEW_INDEX, at(5n, "a5"), ZERO, ALICE, 3n),
  ];
  return fake;
}

function getLogsRanges(fake: FakeChain): [bigint, bigint, string[]][] {
  return fake.calls
    .filter((call) => call.method === "eth_getLogs")
    .map((call) => {
      const filter = call.params[0] as LogFilter;
      const addresses = filter.address === undefined ? [] : Array.isArray(filter.address) ? filter.address : [filter.address];
      return [BigInt(filter.fromBlock), BigInt(filter.toBlock), addresses.map((a) => a.toLowerCase())];
    });
}

describe("processRange", () => {
  const db = useTestDatabase();

  function deps(fake: FakeChain, batchSize: number, handlers: HandlerMap = {}): RangeDeps {
    return { prisma: db(), client: fake.client(), chainId: CHAIN, handlers, batchSize, mismatchRetryDelayMs: 0 };
  }

  it("processes every block of the range in chunks of batchSize, empty blocks included", async () => {
    const fake = chain();
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    const result = await processRange(deps(fake, 2), 1n, 5n);

    expect(result).toEqual({ lastBlock: 5n, blocksProcessed: 5, addedContracts: [], stopped: false });
    expect(getLogsRanges(fake).map(([from, to]) => [from, to])).toEqual([
      [1n, 2n],
      [3n, 4n],
      [5n, 5n],
    ]);
    const blocks = await db().block.findMany({ orderBy: { number: "asc" } });
    expect(blocks.map((b) => b.number)).toEqual([1n, 2n, 3n, 4n, 5n]);
    const events = await db().rawEvent.findMany({ orderBy: { blockNumber: "asc" } });
    expect(events.map((e) => e.blockNumber)).toEqual([2n, 4n]);
    expect(await getCheckpoint(db(), CHAIN)).toEqual({ blockNumber: 5n, blockHash: hash("55") });
  });

  it("asks only for the logs of the contracts in Contract", async () => {
    const fake = chain();
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    await processRange(deps(fake, 10), 1n, 5n);
    expect(getLogsRanges(fake)).toEqual([[1n, 5n, [INDEX]]]);
    expect(await db().rawEvent.count()).toBe(2);
  });

  it("adds a contract returned by a handler to the filter of the next chunk", async () => {
    const fake = chain();
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    // The Transfer of block 2 stands in for IndexCreated: its handler registers NEW_INDEX.
    const handlers: HandlerMap = {
      Transfer: {
        kinds: [ContractKind.INDEX],
        handle: ({ block }) =>
          Promise.resolve(block.number === 2n ? { addedContracts: [{ address: NEW_INDEX, kind: ContractKind.INDEX }] } : undefined),
      },
    };
    const result = await processRange(deps(fake, 2, handlers), 1n, 5n);

    expect(result.addedContracts).toEqual([{ address: NEW_INDEX, kind: ContractKind.INDEX }]);
    const ranges = getLogsRanges(fake);
    expect(ranges[0]?.[2]).toEqual([INDEX]);
    expect(ranges[1]?.[2]).toEqual([INDEX, NEW_INDEX]);
    const events = await db().rawEvent.findMany({ orderBy: { blockNumber: "asc" } });
    expect(events.map((e) => [e.blockNumber, e.address])).toEqual([
      [2n, INDEX],
      [4n, INDEX],
      [5n, NEW_INDEX],
    ]);
  });

  it("processes the blocks even when Contract is empty, without asking for logs", async () => {
    const fake = chain();
    const result = await processRange(deps(fake, 2), 1n, 3n);
    expect(result.blocksProcessed).toBe(3);
    expect(fake.count("eth_getLogs")).toBe(0);
    expect(await db().block.count()).toBe(3);
  });

  it("does nothing on an empty range", async () => {
    const fake = chain();
    expect(await processRange(deps(fake, 2), 4n, 3n)).toEqual({ lastBlock: null, blocksProcessed: 0, addedContracts: [], stopped: false });
    expect(fake.calls).toEqual([]);
  });

  it("rejects a batchSize that is not a positive integer", async () => {
    await expect(processRange(deps(chain(), 0), 1n, 5n)).rejects.toThrow(RangeError);
  });

  it("keeps the blocks before a failure and leaves the checkpoint on the last of them", async () => {
    const fake = chain();
    // Block 3 is stored with a hash the chain does not have: the rerun stops on block 3 itself.
    await insertBlock(db(), CHAIN, { number: 3n, hash: hash("99"), parentHash: hash("22"), timestamp: new Date(0) });
    await expect(processRange(deps(fake, 10), 1n, 5n)).rejects.toThrow(StoredBlockMismatchError);
    expect(await getCheckpoint(db(), CHAIN)).toEqual({ blockNumber: 2n, blockHash: hash("22") });
    const blocks = await db().block.findMany({ orderBy: { number: "asc" } });
    expect(blocks.map((b) => [b.number, b.hash])).toEqual([
      [1n, hash("11")],
      [2n, hash("22")],
      [3n, hash("99")],
    ]);
  });

  it("stops on a parentHash that does not follow the stored chain", async () => {
    const fake = chain();
    await insertBlock(db(), CHAIN, { number: 2n, hash: hash("98"), parentHash: hash("11"), timestamp: new Date(0) });
    await expect(processRange(deps(fake, 10), 3n, 5n)).rejects.toThrow(ParentHashMismatchError);
    expect(await getCheckpoint(db(), CHAIN)).toBeNull();
  });
});
