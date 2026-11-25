// processBlock against the real test database and a fake node (no anvil): the cases that are hard to get
// from a real chain (reorg, logs from another block version, undecodable logs, wrong emitter).
import { ContractKind } from "@oam/db";
import type { Address } from "viem";
import { describe, expect, it } from "vitest";
import { LogBlockMismatchError } from "../src/chain/consistency.js";
import { decodeLog, type ChainLog } from "../src/chain/logs.js";
import { ParentHashMismatchError, StoredBlockMismatchError, processBlock, type HandlerMap, type PipelineDeps } from "../src/pipeline.js";
import { getCheckpoint, setCheckpoint } from "../src/repositories/checkpoint.js";
import { insertBlock } from "../src/repositories/blocks.js";
import { useTestDatabase } from "./helpers/db.js";
import { FakeChain, hash, strangerLog, transferLog } from "./helpers/fakeChain.js";

const CHAIN = 31337;
const INDEX: Address = "0x00000000000000000000000000000000000000a1";
const ROUTER: Address = "0x00000000000000000000000000000000000000b2";
const ALICE: Address = "0x00000000000000000000000000000000000000c3";
const BOB: Address = "0x00000000000000000000000000000000000000d4";
const ZERO: Address = "0x0000000000000000000000000000000000000000";

const kinds = new Map<string, ContractKind>([
  [INDEX, ContractKind.INDEX],
  [ROUTER, ContractKind.ROUTER],
]);

type Call = { blockNumber: bigint; logIndex: number; txLogs: number };

/** A Transfer handler that records its calls, so tests can see when it ran (and when it did not). */
function recordingHandlers(calls: Call[], options: { throwOnCall?: boolean } = {}): HandlerMap {
  return {
    Transfer: {
      kinds: [ContractKind.INDEX],
      handle: ({ block, log, txLogs }) => {
        if (options.throwOnCall === true) return Promise.reject(new Error("handler failed"));
        calls.push({ blockNumber: block.number, logIndex: log.logIndex, txLogs: txLogs.length });
        return Promise.resolve(undefined);
      },
    },
  };
}

describe("processBlock", () => {
  const db = useTestDatabase();

  function deps(chain: FakeChain, handlers: HandlerMap = {}): PipelineDeps {
    return { prisma: db(), client: chain.client(), chainId: CHAIN, handlers, contractKinds: kinds, mismatchRetryDelayMs: 0 };
  }

  /** Block 5 with a mint (zero → alice) and a transfer (alice → bob) in the same tx. */
  function chainWithTransfers(): { chain: FakeChain; logs: ChainLog[] } {
    const chain = new FakeChain();
    chain.addBlock(4n, "44");
    const block = chain.addBlock(5n, "55");
    const at = { blockNumber: 5n, blockHash: block.hash, txHash: hash("77") };
    chain.logs = [transferLog(INDEX, { ...at, logIndex: 0 }, ZERO, ALICE, 10n), transferLog(INDEX, { ...at, logIndex: 1 }, ALICE, BOB, 4n)];
    return { chain, logs: chain.logs.map(decodeLog) };
  }

  it("writes Block, RawEvent and Checkpoint, and calls the handler of each event in logIndex order", async () => {
    const { chain, logs } = chainWithTransfers();
    const calls: Call[] = [];
    const result = await processBlock(deps(chain, recordingHandlers(calls)), 5n, [...logs].reverse());

    expect(result).toMatchObject({ blockInserted: true, rawEventsInserted: 2, addedContracts: [] });
    expect(await db().block.count()).toBe(1);
    const events = await db().rawEvent.findMany({ orderBy: { logIndex: "asc" } });
    expect(events.map((e) => [e.eventName, e.logIndex])).toEqual([["Transfer", 0], ["Transfer", 1]]);
    expect(events[1]?.args).toEqual({ from: ALICE, to: BOB, value: "4" });
    expect(await getCheckpoint(db(), CHAIN)).toEqual({ blockNumber: 5n, blockHash: hash("55") });
    expect(calls).toEqual([
      { blockNumber: 5n, logIndex: 0, txLogs: 2 },
      { blockNumber: 5n, logIndex: 1, txLogs: 2 },
    ]);
  });

  it("writes a block without logs: Block and Checkpoint, no RawEvent", async () => {
    const chain = new FakeChain();
    chain.addBlock(1n, "11");
    await processBlock(deps(chain), 1n, []);
    expect(await db().block.count()).toBe(1);
    expect(await db().rawEvent.count()).toBe(0);
    expect((await getCheckpoint(db(), CHAIN))?.blockNumber).toBe(1n);
  });

  it("writes nothing new when the same block is processed twice", async () => {
    const { chain, logs } = chainWithTransfers();
    await processBlock(deps(chain), 5n, logs);
    const again = await processBlock(deps(chain), 5n, logs);
    expect(again).toMatchObject({ blockInserted: false, rawEventsInserted: 0 });
    expect(await db().block.count()).toBe(1);
    expect(await db().rawEvent.count()).toBe(2);
  });

  it("keeps an undecodable log out of RawEvent, records an IndexerError and moves the checkpoint", async () => {
    const chain = new FakeChain();
    const block = chain.addBlock(3n, "33");
    chain.logs = [strangerLog(INDEX, { blockNumber: 3n, blockHash: block.hash, txHash: hash("78"), logIndex: 0 })];
    await processBlock(deps(chain), 3n, chain.logs.map(decodeLog));

    expect(await db().rawEvent.count()).toBe(0);
    const [error] = await db().indexerError.findMany();
    expect(error).toMatchObject({ blockNumber: 3n, context: `unknownLog ${INDEX} ${hash("78")}:0` });
    expect(error?.message).toContain(`topics=[${hash("ee")}]`);
    expect((await getCheckpoint(db(), CHAIN))?.blockNumber).toBe(3n);
  });

  it("does not call a handler for an event from an unexpected contract kind, but keeps the event in RawEvent", async () => {
    const chain = new FakeChain();
    const block = chain.addBlock(3n, "33");
    chain.logs = [transferLog(ROUTER, { blockNumber: 3n, blockHash: block.hash, txHash: hash("79"), logIndex: 0 }, ZERO, ALICE, 1n)];
    const calls: Call[] = [];
    await processBlock(deps(chain, recordingHandlers(calls)), 3n, chain.logs.map(decodeLog));

    expect(calls).toEqual([]);
    expect(await db().rawEvent.count()).toBe(1);
    const [error] = await db().indexerError.findMany();
    expect(error?.context).toBe(`unexpectedEmitter ${ROUTER} ${hash("79")}:0`);
    expect(error?.message).toContain("from a ROUTER");
  });

  it("writes nothing of a block whose handler fails", async () => {
    const { chain, logs } = chainWithTransfers();
    await expect(processBlock(deps(chain, recordingHandlers([], { throwOnCall: true })), 5n, logs)).rejects.toThrow("handler failed");
    expect(await db().block.count()).toBe(0);
    expect(await db().rawEvent.count()).toBe(0);
    expect(await getCheckpoint(db(), CHAIN)).toBeNull();
  });

  it("returns the contracts a handler added", async () => {
    const { chain, logs } = chainWithTransfers();
    const handlers: HandlerMap = {
      Transfer: { kinds: [ContractKind.INDEX], handle: () => Promise.resolve({ addedContracts: [{ address: BOB, kind: ContractKind.INDEX }] }) },
    };
    const result = await processBlock(deps(chain, handlers), 5n, logs);
    expect(result.addedContracts).toEqual([
      { address: BOB, kind: ContractKind.INDEX },
      { address: BOB, kind: ContractKind.INDEX },
    ]);
  });

  describe("parentHash", () => {
    it("stops on a reorg: IndexerError kept, nothing of the block written, checkpoint unchanged", async () => {
      const { chain, logs } = chainWithTransfers();
      await insertBlock(db(), CHAIN, { number: 4n, hash: hash("99"), parentHash: hash("00"), timestamp: new Date(0) });
      await setCheckpoint(db(), CHAIN, { blockNumber: 4n, blockHash: hash("99") });

      await expect(processBlock(deps(chain), 5n, logs)).rejects.toThrow(ParentHashMismatchError);
      expect(await db().block.count()).toBe(1);
      expect(await db().rawEvent.count()).toBe(0);
      expect((await getCheckpoint(db(), CHAIN))?.blockNumber).toBe(4n);
      const [error] = await db().indexerError.findMany();
      expect(error).toMatchObject({ blockNumber: 5n, context: "parentHashMismatch" });
    });

    it("stops when the block itself is already stored with another hash", async () => {
      const { chain, logs } = chainWithTransfers();
      await insertBlock(db(), CHAIN, { number: 5n, hash: hash("59"), parentHash: hash("44"), timestamp: new Date(0) });
      await expect(processBlock(deps(chain), 5n, logs)).rejects.toThrow(StoredBlockMismatchError);
      expect(await db().rawEvent.count()).toBe(0);
      expect(await getCheckpoint(db(), CHAIN)).toBeNull();
      const [error] = await db().indexerError.findMany();
      expect(error).toMatchObject({ blockNumber: 5n, context: "storedBlockMismatch" });
    });

    it("accepts a block that follows the stored one", async () => {
      const { chain, logs } = chainWithTransfers();
      await insertBlock(db(), CHAIN, { number: 4n, hash: hash("44"), parentHash: hash("00"), timestamp: new Date(0) });
      await processBlock(deps(chain), 5n, logs);
      expect(await db().block.count()).toBe(2);
    });
  });

  describe("logs that do not belong to the block", () => {
    it("reads the block again and writes the logs of the version it reads", async () => {
      const { chain } = chainWithTransfers();
      // The range's getLogs saw block 5 before a reorg: same logs, old block hash.
      const stale = chain.logs.map((log) => decodeLog({ ...log, blockHash: hash("50") }));
      await processBlock(deps(chain), 5n, stale);

      expect(chain.count("eth_getBlockByNumber")).toBe(2);
      expect(chain.count("eth_getLogs")).toBe(1);
      const events = await db().rawEvent.findMany();
      expect(events.every((e) => e.blockHash === hash("55"))).toBe(true);
      expect(await db().indexerError.count()).toBe(0);
    });

    it("gives up after 3 reads: IndexerError kept and nothing of the block written", async () => {
      const { chain } = chainWithTransfers();
      // The node keeps serving logs of another version of block 5.
      chain.logs = chain.logs.map((log) => ({ ...log, blockHash: hash("50") }));
      await expect(processBlock(deps(chain), 5n, chain.logs.map(decodeLog))).rejects.toThrow(LogBlockMismatchError);

      expect(chain.count("eth_getBlockByNumber")).toBe(3);
      expect(chain.count("eth_getLogs")).toBe(2);
      expect(await db().block.count()).toBe(0);
      expect(await db().rawEvent.count()).toBe(0);
      const [error] = await db().indexerError.findMany();
      expect(error?.context).toMatch(/^logBlockMismatch /);
    });
  });
});
