// The parts of the runner that read the DB and the head (indexer-roadmap.md step 5, part 4): one catch-up round
// (catchUpRound) and the tolerance of backfill for a head a few blocks below the checkpoint. Fake node and test DB.
// The rules of createCatchUp itself (one round at a time, retries, stop) are unit-tested in src/runner.test.ts.
import type { Address } from "viem";
import { describe, expect, it } from "vitest";
import { setCheckpoint } from "../src/repositories/checkpoint.js";
import { insertIndexContract } from "../src/repositories/contracts.js";
import { CheckpointAheadOfHeadError, MAX_HEAD_BEHIND_CHECKPOINT, backfill, catchUpRound } from "../src/runner.js";
import type { RangeDeps } from "../src/pipeline.js";
import { useTestDatabase } from "./helpers/db.js";
import { FakeChain, hash, transferLog } from "./helpers/fakeChain.js";

const CHAIN = 31337;
const INDEX: Address = "0x00000000000000000000000000000000000000a1";
const ALICE: Address = "0x00000000000000000000000000000000000000c3";
const ZERO: Address = "0x0000000000000000000000000000000000000000";

/** Blocks 1..`last` with a Transfer of INDEX in every block. */
function chain(last: bigint): FakeChain {
  const fake = new FakeChain();
  for (let n = 1n; n <= last; n++) fake.addBlock(n, n.toString(16).padStart(2, "0"));
  fake.logs = [...fake.blocks.keys()].map((n) =>
    transferLog(INDEX, { blockNumber: n, blockHash: fake.blocks.get(n)?.hash ?? hash("00"), txHash: hash(`a${n.toString(16)}`), logIndex: 0 }, ZERO, ALICE, n),
  );
  return fake;
}

describe("catchUpRound", () => {
  const db = useTestDatabase();
  const deps = (fake: FakeChain): Omit<RangeDeps, "signal"> => ({
    prisma: db(),
    client: fake.client(),
    chainId: CHAIN,
    handlers: {},
    batchSize: 10,
    mismatchRetryDelayMs: 0,
  });
  const live = () => new AbortController().signal;
  const blocks = async () => (await db().block.findMany({ orderBy: { number: "asc" } })).map((block) => block.number);

  it("processes from the block after the checkpoint to the head", async () => {
    const fake = chain(5n);
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    await catchUpRound(deps(fake), 1n)(live());
    fake.addBlock(6n, "06");
    fake.addBlock(7n, "07");

    await catchUpRound(deps(fake), 1n)(live());

    expect(await blocks()).toEqual([1n, 2n, 3n, 4n, 5n, 6n, 7n]);
    expect(await db().checkpoint.findUnique({ where: { chainId: CHAIN } })).toMatchObject({ lastBlockNumber: 7n });
  });

  it("starts from startBlock on a chain with no checkpoint yet", async () => {
    const fake = chain(5n);
    await insertIndexContract(db(), CHAIN, INDEX, 3n);
    await catchUpRound(deps(fake), 3n)(live());

    expect(await blocks()).toEqual([3n, 4n, 5n]);
  });

  it("does nothing, and asks no logs, when there is no new block", async () => {
    const fake = chain(5n);
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    await catchUpRound(deps(fake), 1n)(live());
    const getLogsBefore = fake.count("eth_getLogs");

    await catchUpRound(deps(fake), 1n)(live());

    expect(fake.count("eth_getLogs")).toBe(getLogsBefore);
  });

  it("waits without an error when the provider is behind the checkpoint, however far", async () => {
    const fake = chain(5n);
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    await catchUpRound(deps(fake), 1n)(live());
    // A backup provider that is 200 blocks behind: in the live loop this only waits for the next signal.
    await setCheckpoint(db(), CHAIN, { blockNumber: 205n, blockHash: hash("cd") });

    await expect(catchUpRound(deps(fake), 1n)(live())).resolves.toBeUndefined();
    expect(fake.count("eth_getLogs")).toBe(1);
  });

  it("stops between two blocks when the runner's signal is aborted", async () => {
    const fake = chain(5n);
    await insertIndexContract(db(), CHAIN, INDEX, 1n);
    const controller = new AbortController();
    fake.onRequest = (method, params) => {
      if (method === "eth_getBlockByNumber" && params[0] === "0x2") controller.abort();
    };

    await catchUpRound(deps(fake), 1n)(controller.signal);

    expect(await blocks()).toEqual([1n, 2n]);
  });
});

describe("backfill with the head below the checkpoint", () => {
  const db = useTestDatabase();
  const fixed = {
    indexManager: "0x00000000000000000000000000000000000000e1",
    router: "0x00000000000000000000000000000000000000e2",
    priceFeedManager: "0x00000000000000000000000000000000000000e3",
    swapManager: "0x00000000000000000000000000000000000000e4",
    multiSigWallet: "0x00000000000000000000000000000000000000e5",
    timelock: "0x00000000000000000000000000000000000000e6",
    startBlock: 1n,
  };
  const deps = (fake: FakeChain): RangeDeps => ({ prisma: db(), client: fake.client(), chainId: CHAIN, handlers: {}, batchSize: 10, mismatchRetryDelayMs: 0 });

  it(`starts and processes nothing when the head is up to ${MAX_HEAD_BEHIND_CHECKPOINT} blocks behind`, async () => {
    const fake = chain(5n);
    await setCheckpoint(db(), CHAIN, { blockNumber: 5n + MAX_HEAD_BEHIND_CHECKPOINT, blockHash: hash("cd") });

    const result = await backfill(deps(fake), fixed);

    expect(result.range).toMatchObject({ lastBlock: null, blocksProcessed: 0 });
    expect(await db().block.count()).toBe(0);
  });

  it(`refuses to start when the head is more than ${MAX_HEAD_BEHIND_CHECKPOINT} blocks behind`, async () => {
    const fake = chain(5n);
    await setCheckpoint(db(), CHAIN, { blockNumber: 5n + MAX_HEAD_BEHIND_CHECKPOINT + 1n, blockHash: hash("cd") });

    await expect(backfill(deps(fake), fixed)).rejects.toBeInstanceOf(CheckpointAheadOfHeadError);
  });
});
