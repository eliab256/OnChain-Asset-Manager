// Backfill of the anvil snapshot (indexer-roadmap.md step 3): bootstrap + processRange from startBlock to
// the head against a real node. Needs anvil with the deployment of deployments/31337.json (make dev, or
// anvil --load-state .anvil/31337.json). Sends no transactions: the chain stays as the snapshot left it.
import { readFileSync } from "node:fs";
import { protocolAddresses } from "@oam/abi";
import type { PrismaClient } from "@oam/db";
import { numberToHex, type Hex, type PublicClient } from "viem";
import { describe, expect, it } from "vitest";
import { processRange, type RangeDeps } from "../src/pipeline.js";
import { setCheckpoint } from "../src/repositories/checkpoint.js";
import { CheckpointAheadOfHeadError, backfill, bootstrap } from "../src/runner.js";
import { ANVIL_CHAIN_ID, probeAnvil } from "./helpers/anvil.js";
import { useTestDatabase } from "./helpers/db.js";

const probe = await probeAnvil();
const fixed = protocolAddresses[ANVIL_CHAIN_ID];
/** The six contracts with events, as the bootstrap registers them (no IndexFactory, no USDC). */
const fixedAddresses = [fixed.indexManager, fixed.router, fixed.priceFeedManager, fixed.swapManager, fixed.multiSigWallet, fixed.timelock];

type RpcLog = { address: Hex; blockNumber: Hex; blockHash: Hex; transactionHash: Hex; logIndex: Hex };

/** Logs of the fixed contracts read with a plain eth_getLogs, not through chain/logs.ts: the reference the DB is checked against. */
async function expectedLogs(client: PublicClient, to: bigint): Promise<string[]> {
  const logs = (await client.request({
    method: "eth_getLogs",
    params: [{ address: fixedAddresses, fromBlock: numberToHex(fixed.startBlock), toBlock: numberToHex(to) }],
  })) as RpcLog[];
  return logs
    .map((log) => `${BigInt(log.blockNumber)} ${log.blockHash} ${log.transactionHash}:${BigInt(log.logIndex)} ${log.address}`.toLowerCase())
    .sort();
}

/** Block and RawEvent of the chain without service columns (id), ordered: two runs that index the same chain give the same dump. */
async function dump(prisma: PrismaClient) {
  const blocks = await prisma.block.findMany({ where: { chainId: ANVIL_CHAIN_ID }, orderBy: { number: "asc" } });
  const events = await prisma.rawEvent.findMany({ where: { chainId: ANVIL_CHAIN_ID }, orderBy: [{ blockNumber: "asc" }, { logIndex: "asc" }], omit: { id: true } });
  const checkpoint = await prisma.checkpoint.findUnique({ where: { chainId: ANVIL_CHAIN_ID }, omit: { updatedAt: true } });
  return { blocks, events, checkpoint };
}

describe.skipIf(probe.client === undefined)(`backfill of the anvil snapshot${probe.reason === undefined ? "" : ` (skipped: ${probe.reason})`}`, () => {
  const db = useTestDatabase();
  const client = probe.client as PublicClient;
  const deps = (batchSize = 2000): RangeDeps => ({ prisma: db(), client, chainId: ANVIL_CHAIN_ID, handlers: {}, batchSize });

  it("writes Block contiguous from startBlock to the head, with the chain's hashes, and the checkpoint on the head", async () => {
    const result = await backfill(deps(), fixed);
    const head = await client.getBlockNumber({ cacheTime: 0 });

    expect(result.head).toBe(head);
    expect(result.bootstrap).toEqual({ fromBlock: fixed.startBlock, checkpoint: null, insertedContracts: 6 });
    expect(result.range).toEqual({ lastBlock: head, blocksProcessed: Number(head - fixed.startBlock + 1n), addedContracts: [] });

    const blocks = await db().block.findMany({ where: { chainId: ANVIL_CHAIN_ID }, orderBy: { number: "asc" } });
    expect(blocks.map((block) => block.number)).toEqual(Array.from({ length: Number(head - fixed.startBlock + 1n) }, (_, i) => fixed.startBlock + BigInt(i)));
    for (const block of blocks) {
      const onChain = await client.getBlock({ blockNumber: block.number });
      expect({ hash: block.hash, parentHash: block.parentHash }).toEqual({ hash: onChain.hash, parentHash: onChain.parentHash });
      expect(block.timestamp.getTime()).toBe(Number(onChain.timestamp) * 1000);
    }
    const last = blocks.at(-1);
    expect(await db().checkpoint.findUnique({ where: { chainId: ANVIL_CHAIN_ID } })).toMatchObject({ lastBlockNumber: head, lastBlockHash: last?.hash });
  });

  it("stores in RawEvent exactly the logs of the fixed contracts, all decoded, the deploy's IndexCreated included", async () => {
    const { head } = await backfill(deps(), fixed);
    const events = await db().rawEvent.findMany({ where: { chainId: ANVIL_CHAIN_ID } });

    const stored = events.map((event) => `${event.blockNumber} ${event.blockHash} ${event.txHash}:${event.logIndex} ${event.address}`).sort();
    expect(stored).toEqual(await expectedLogs(client, head));
    expect(stored.length).toBeGreaterThan(0);
    // Every log decoded: an unknown one would be an IndexerError row instead of a RawEvent.
    expect(await db().indexerError.count()).toBe(0);

    const created = events.filter((event) => event.eventName === "IndexCreated");
    const deployment = JSON.parse(readFileSync(new URL("../../../deployments/31337.json", import.meta.url), "utf8")) as { indexes: Record<string, unknown> };
    const deployedIndexes = Object.keys(deployment.indexes);
    expect(created.map((event) => (event.args as { indexAddress: string }).indexAddress).sort()).toEqual(deployedIndexes.map((a) => a.toLowerCase()).sort());
  });

  it("writes nothing on a second run: it resumes after the checkpoint and finds no new block", async () => {
    const first = await backfill(deps(), fixed);
    const before = await dump(db());

    const second = await backfill(deps(), fixed);
    expect(second.bootstrap).toEqual({ fromBlock: first.head + 1n, checkpoint: { blockNumber: first.head, blockHash: before.checkpoint?.lastBlockHash }, insertedContracts: 0 });
    expect(second.range).toEqual({ lastBlock: null, blocksProcessed: 0, addedContracts: [] });
    expect(await dump(db())).toEqual(before);
  });

  it("gives the same rows when stopped halfway and resumed, with chunks of another size", async () => {
    const straight = await backfill(deps(), fixed);
    const reference = await dump(db());
    await db().$executeRawUnsafe(`TRUNCATE TABLE "Block", "RawEvent", "Checkpoint", "Contract" RESTART IDENTITY CASCADE`);

    // First half by hand, as if the process had stopped after block `half`, then a backfill with batchSize 7.
    const half = (fixed.startBlock + straight.head) / 2n;
    const start = await bootstrap(db(), ANVIL_CHAIN_ID, fixed);
    await processRange(deps(5), start.fromBlock, half);
    const resumed = await backfill(deps(7), fixed);

    expect(resumed.bootstrap.fromBlock).toBe(half + 1n);
    expect(await dump(db())).toEqual(reference);
  });

  it("stops when the checkpoint is past the head (anvil restarted under the same chain id) and writes nothing", async () => {
    const head = await client.getBlockNumber({ cacheTime: 0 });
    await setCheckpoint(db(), ANVIL_CHAIN_ID, { blockNumber: head + 100n, blockHash: `0x${"ab".repeat(32)}` });

    await expect(backfill(deps(), fixed)).rejects.toBeInstanceOf(CheckpointAheadOfHeadError);
    expect(await db().block.count()).toBe(0);
  });
});
