// Index discovered during a range (indexer-roadmap.md step 4, indexer.md §4 "Index creati a metà range"):
// the IndexCreated handler registers the Index and processRange requests its logs of the same chunk,
// before processing it. Fake node and test database, no anvil.
import { ContractKind } from "@oam/db";
import type { Address } from "viem";
import { describe, expect, it } from "vitest";
import { decodeLog } from "../src/chain/logs.js";
import { handlers } from "../src/handlers/index.js";
import { processBlock, processRange, type HandlerMap, type RangeDeps } from "../src/pipeline.js";
import { useTestDatabase } from "./helpers/db.js";
import { FakeChain, hash, indexCreatedLog, transferLog, type LogFilter } from "./helpers/fakeChain.js";

const CHAIN = 31337;
const MANAGER: Address = "0x00000000000000000000000000000000000000e1";
const ROUTER: Address = "0x00000000000000000000000000000000000000b2";
const INDEX: Address = "0x00000000000000000000000000000000000000a1";
const ALICE: Address = "0x00000000000000000000000000000000000000c3";
const ZERO: Address = "0x0000000000000000000000000000000000000000";

function created(index: Address) {
  return {
    indexAddress: index,
    asset0: "0x00000000000000000000000000000000000000f0" as Address,
    asset1: "0x00000000000000000000000000000000000000f1" as Address,
    asset0Weight: 500_000n,
    asset1Weight: 500_000n,
    feePercentage: 10_000n,
    assetManager: ALICE,
  };
}

/** Blocks 1..6; IndexCreated in block 2 (logIndex 1), then the Index's own Transfers in blocks 2 (logIndex 2), 4 and 6. */
function chainWithNewIndex(emitter: Address = MANAGER): FakeChain {
  const fake = new FakeChain();
  for (let n = 1n; n <= 6n; n++) fake.addBlock(n, `${n}${n}`);
  const at = (n: bigint, tx: string, logIndex: number) => ({ blockNumber: n, blockHash: fake.blocks.get(n)?.hash ?? hash("00"), txHash: hash(tx), logIndex });
  fake.logs = [
    indexCreatedLog(emitter, at(2n, "a2", 1), created(INDEX)),
    transferLog(INDEX, at(2n, "b2", 2), ZERO, ALICE, 1n),
    transferLog(INDEX, at(4n, "a4", 0), ZERO, ALICE, 2n),
    transferLog(INDEX, at(6n, "a6", 0), ZERO, ALICE, 3n),
  ];
  return fake;
}

function getLogsCalls(fake: FakeChain): [bigint, bigint, string[]][] {
  return fake.calls
    .filter((call) => call.method === "eth_getLogs")
    .map((call) => {
      const filter = call.params[0] as LogFilter;
      const addresses = filter.address === undefined ? [] : Array.isArray(filter.address) ? filter.address : [filter.address];
      return [BigInt(filter.fromBlock), BigInt(filter.toBlock), addresses.map((a) => a.toLowerCase())];
    });
}

describe("Index discovered during a range", () => {
  const db = useTestDatabase();

  async function register(address: Address, kind: ContractKind): Promise<void> {
    await db().contract.create({ data: { chainId: CHAIN, address, kind, startBlock: 1n } });
  }

  function deps(fake: FakeChain, batchSize: number, map: HandlerMap = handlers): RangeDeps {
    return { prisma: db(), client: fake.client(), chainId: CHAIN, handlers: map, batchSize, mismatchRetryDelayMs: 0 };
  }

  async function storedEvents(): Promise<string[]> {
    const events = await db().rawEvent.findMany({ orderBy: [{ blockNumber: "asc" }, { logIndex: "asc" }] });
    return events.map((event) => `${event.blockNumber}:${event.logIndex} ${event.eventName} ${event.address}`);
  }

  it("registers the Index and stores its logs of the same chunk, from the block of creation on", async () => {
    const fake = chainWithNewIndex();
    await register(MANAGER, ContractKind.INDEX_MANAGER);
    const result = await processRange(deps(fake, 10), 1n, 6n);

    expect(result.addedContracts).toEqual([{ address: INDEX, kind: ContractKind.INDEX }]);
    expect(await db().contract.findUnique({ where: { chainId_address: { chainId: CHAIN, address: INDEX } } })).toMatchObject({
      kind: ContractKind.INDEX,
      startBlock: 2n,
    });
    expect(await storedEvents()).toEqual([
      `2:1 IndexCreated ${MANAGER}`,
      `2:2 Transfer ${INDEX}`,
      `4:0 Transfer ${INDEX}`,
      `6:0 Transfer ${INDEX}`,
    ]);
    // One getLogs of the known contracts, one of the new Index from its creation block to the end of the chunk.
    expect(getLogsCalls(fake)).toEqual([
      [1n, 6n, [MANAGER]],
      [2n, 6n, [INDEX]],
    ]);
    expect(await db().indexerError.count()).toBe(0);
  });

  it("dispatches the Index's events of the creation block to their handler, after IndexCreated", async () => {
    const fake = chainWithNewIndex();
    await register(MANAGER, ContractKind.INDEX_MANAGER);
    const seen: string[] = [];
    const map: HandlerMap = {
      ...handlers,
      Transfer: {
        kinds: [ContractKind.INDEX],
        handle: ({ block, log }) => {
          seen.push(`${block.number}:${log.logIndex}`);
          return Promise.resolve(undefined);
        },
      },
    };
    await processRange(deps(fake, 10, map), 1n, 6n);

    expect(seen).toEqual(["2:2", "4:0", "6:0"]);
    expect(await db().indexerError.count()).toBe(0);
  });

  it("keeps out the Index's logs of the creation block that come before IndexCreated", async () => {
    const fake = chainWithNewIndex();
    const block2 = fake.blocks.get(2n)?.hash ?? hash("00");
    fake.logs.push(transferLog(INDEX, { blockNumber: 2n, blockHash: block2, txHash: hash("c2"), logIndex: 0 }, ZERO, ALICE, 9n));
    await register(MANAGER, ContractKind.INDEX_MANAGER);
    await processRange(deps(fake, 10), 1n, 6n);

    expect(await storedEvents()).not.toContain(`2:0 Transfer ${INDEX}`);
    expect(await db().rawEvent.count()).toBe(4);
  });

  it("finds the logs in the next chunk when the Index is created on the last block of a chunk", async () => {
    const fake = chainWithNewIndex();
    await register(MANAGER, ContractKind.INDEX_MANAGER);
    await processRange(deps(fake, 2), 1n, 6n);

    expect(await db().rawEvent.count()).toBe(4);
    // Chunk [1, 2]: the new Index's getLogs covers only block 2. From chunk [3, 4] on it is in the filter.
    expect(getLogsCalls(fake)).toEqual([
      [1n, 2n, [MANAGER]],
      [2n, 2n, [INDEX]],
      [3n, 4n, [MANAGER, INDEX]],
      [5n, 6n, [MANAGER, INDEX]],
    ]);
  });

  it("does not request the logs of an Index already in Contract a second time", async () => {
    const fake = chainWithNewIndex();
    await register(MANAGER, ContractKind.INDEX_MANAGER);
    await register(INDEX, ContractKind.INDEX);
    await processRange(deps(fake, 10), 1n, 6n);

    expect(getLogsCalls(fake)).toEqual([[1n, 6n, [MANAGER, INDEX]]]);
    expect(await db().rawEvent.count()).toBe(4);
  });

  it("writes nothing twice when the range is processed again", async () => {
    const fake = chainWithNewIndex();
    await register(MANAGER, ContractKind.INDEX_MANAGER);
    await processRange(deps(fake, 10), 1n, 6n);
    const before = await storedEvents();
    await processRange(deps(fake, 10), 1n, 6n);

    expect(await storedEvents()).toEqual(before);
    expect(await db().contract.count()).toBe(2);
  });

  it("ignores an IndexCreated emitted by a contract that is not the IndexManager", async () => {
    const fake = chainWithNewIndex(ROUTER);
    await register(ROUTER, ContractKind.ROUTER);
    await processRange(deps(fake, 10), 1n, 6n);

    expect(getLogsCalls(fake)).toEqual([[1n, 6n, [ROUTER]]]);
    expect(await db().contract.count()).toBe(1);
    expect(await storedEvents()).toEqual([`2:1 IndexCreated ${ROUTER}`]);
    const [error] = await db().indexerError.findMany();
    expect(error?.context).toMatch(/^unexpectedEmitter /);
  });

  it("requests the new Index's logs again when the creation block is read again after a blockHash mismatch", async () => {
    const fake = chainWithNewIndex();
    await register(MANAGER, ContractKind.INDEX_MANAGER);
    // The range's getLogs saw block 2 before a reorg: IndexCreated with the old block hash, and no Index logs yet.
    const stale = fake.logs.slice(0, 1).map((log) => decodeLog({ ...log, blockHash: hash("20") }));
    const kinds = new Map<string, ContractKind>([[MANAGER, ContractKind.INDEX_MANAGER]]);
    await processBlock({ ...deps(fake, 10), contractKinds: kinds }, 2n, stale);

    expect(getLogsCalls(fake)).toEqual([
      [2n, 2n, [MANAGER]],
      [2n, 2n, [INDEX]],
    ]);
    expect(await storedEvents()).toEqual([`2:1 IndexCreated ${MANAGER}`, `2:2 Transfer ${INDEX}`]);
  });
});
