// Stopping a range between two blocks (indexer-roadmap.md step 5, part 3): with its AbortSignal aborted,
// processRange finishes the block in progress and returns before the next one. Fake node and test database.
import { ContractKind } from "@oam/db";
import type { Address } from "viem";
import { describe, expect, it } from "vitest";
import { processRange, type HandlerMap, type RangeDeps } from "../src/pipeline.js";
import { getCheckpoint } from "../src/repositories/checkpoint.js";
import { insertIndexContract } from "../src/repositories/contracts.js";
import { useTestDatabase } from "./helpers/db.js";
import { FakeChain, hash, transferLog } from "./helpers/fakeChain.js";

const CHAIN = 31337;
const INDEX: Address = "0x00000000000000000000000000000000000000a1";
const ALICE: Address = "0x00000000000000000000000000000000000000c3";
const ZERO: Address = "0x0000000000000000000000000000000000000000";

/** Blocks 1..5 with a Transfer of INDEX in every block. */
function chain(): FakeChain {
  const fake = new FakeChain();
  for (let n = 1n; n <= 5n; n++) fake.addBlock(n, `${n}${n}`);
  fake.logs = [1n, 2n, 3n, 4n, 5n].map((n) =>
    transferLog(INDEX, { blockNumber: n, blockHash: fake.blocks.get(n)?.hash ?? hash("00"), txHash: hash(`a${n}`), logIndex: 0 }, ZERO, ALICE, n),
  );
  return fake;
}

/** A Transfer handler that aborts the signal while block `at` is being written, inside its transaction. */
function abortingIn(at: bigint, controller: AbortController): HandlerMap {
  return {
    Transfer: {
      kinds: [ContractKind.INDEX],
      handle: ({ block }) => {
        if (block.number === at) controller.abort();
        return Promise.resolve(undefined);
      },
    },
  };
}

describe("processRange stopped by its signal", () => {
  const db = useTestDatabase();

  function deps(fake: FakeChain, options: { batchSize?: number; handlers?: HandlerMap; signal?: AbortSignal } = {}): RangeDeps {
    return {
      prisma: db(),
      client: fake.client(),
      chainId: CHAIN,
      handlers: options.handlers ?? {},
      batchSize: options.batchSize ?? 10,
      mismatchRetryDelayMs: 0,
      ...(options.signal === undefined ? {} : { signal: options.signal }),
    };
  }

  async function writtenBlocks(): Promise<bigint[]> {
    return (await db().block.findMany({ orderBy: { number: "asc" } })).map((block) => block.number);
  }

  it("does nothing when the signal is already aborted: no RPC call, no row", async () => {
    const fake = chain();
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    const controller = new AbortController();
    controller.abort();

    const result = await processRange(deps(fake, { signal: controller.signal }), 1n, 5n);

    expect(result).toEqual({ lastBlock: null, blocksProcessed: 0, addedContracts: [], stopped: true });
    expect(fake.calls).toEqual([]);
    expect(await writtenBlocks()).toEqual([]);
  });

  it("finishes the block whose handler sees the stop, then returns before the next one", async () => {
    const fake = chain();
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    const controller = new AbortController();

    const result = await processRange(deps(fake, { handlers: abortingIn(2n, controller), signal: controller.signal }), 1n, 5n);

    expect(result).toEqual({ lastBlock: 2n, blocksProcessed: 2, addedContracts: [], stopped: true });
    // Block 2 is written whole (Block, RawEvent, Checkpoint in one transaction), block 3 not at all.
    expect(await writtenBlocks()).toEqual([1n, 2n]);
    expect(await db().rawEvent.count()).toBe(2);
    expect(await getCheckpoint(db(), CHAIN)).toEqual({ blockNumber: 2n, blockHash: hash("22") });
  });

  it("finishes a block whose RPC read is in flight when the stop arrives", async () => {
    const fake = chain();
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    const controller = new AbortController();
    fake.onRequest = (method, params) => {
      if (method === "eth_getBlockByNumber" && params[0] === "0x3") controller.abort();
    };

    const result = await processRange(deps(fake, { signal: controller.signal }), 1n, 5n);

    expect(result).toMatchObject({ lastBlock: 3n, blocksProcessed: 3, stopped: true });
    expect(await writtenBlocks()).toEqual([1n, 2n, 3n]);
  });

  it("processes no block of a chunk whose getLogs was in flight when the stop arrived", async () => {
    const fake = chain();
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    const controller = new AbortController();
    let getLogs = 0;
    fake.onRequest = (method) => {
      if (method === "eth_getLogs" && ++getLogs === 2) controller.abort();
    };

    const result = await processRange(deps(fake, { batchSize: 2, signal: controller.signal }), 1n, 5n);

    // Chunk [1, 2] written; the getLogs of [3, 4] answered, but none of its blocks was started.
    expect(result).toMatchObject({ lastBlock: 2n, blocksProcessed: 2, stopped: true });
    expect(await writtenBlocks()).toEqual([1n, 2n]);
    expect(fake.count("eth_getLogs")).toBe(2);
  });

  it("resumes from the checkpoint after a stop, with the same rows as a run that never stopped", async () => {
    const fake = chain();
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    const controller = new AbortController();
    await processRange(deps(fake, { handlers: abortingIn(2n, controller), signal: controller.signal }), 1n, 5n);

    const checkpoint = await getCheckpoint(db(), CHAIN);
    const resumed = await processRange(deps(fake), (checkpoint?.blockNumber ?? 0n) + 1n, 5n);

    expect(resumed).toMatchObject({ lastBlock: 5n, blocksProcessed: 3, stopped: false });
    expect(await writtenBlocks()).toEqual([1n, 2n, 3n, 4n, 5n]);
    const events = await db().rawEvent.findMany({ orderBy: { blockNumber: "asc" } });
    expect(events.map((event) => event.blockNumber)).toEqual([1n, 2n, 3n, 4n, 5n]);
  });
});
