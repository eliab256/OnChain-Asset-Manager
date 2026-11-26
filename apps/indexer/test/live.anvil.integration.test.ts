// Part 6 of step 5 of localHelpers/indexer-roadmap.md: the whole indexer, as `npm start` runs it, against anvil. The
// indexer is a child process (src/index.ts), so the live loop, SIGINT and the exit code are the real ones. A mint
// made with the SDK while it runs must reach RawEvent at once via WebSocket and, without RPC_WS_URL, within
// POLL_INTERVAL_MS; Ctrl-C and a restart must resume from the checkpoint with no gap and no duplicate.
// Needs anvil with the deployment of deployments/31337.json (make dev, or anvil --load-state .anvil/31337.json).
// The transactions are reverted at the end with evm_snapshot / evm_revert.
import { protocolAddresses } from "@oam/abi";
import { createTestClient, http, numberToHex, type Hex, type PublicClient, type TransactionReceipt } from "viem";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { ANVIL_CHAIN_ID, probeAnvil, testRpcUrl } from "./helpers/anvil.js";
import { useTestDatabase } from "./helpers/db.js";
import { testDatabaseUrl } from "./helpers/env.js";
import { startIndexer, type IndexerProcess } from "./helpers/indexerProcess.js";
import { prepareMint, type Minter } from "./helpers/mint.js";

const probe = await probeAnvil();
const fixed = protocolAddresses[ANVIL_CHAIN_ID];
const rpcUrl = testRpcUrl();
const wsUrl = rpcUrl.replace(/^http/, "ws");
/** 1 000 USDC (6 decimals). */
const USDC_AMOUNT = 1_000n * 10n ** 6n;
/** A guard far longer than the test timeout: whatever arrives before it came from the WebSocket. */
const GUARD_NEVER_MS = 600_000;
/** The guard of the run without WebSocket. */
const GUARD_SHORT_MS = 1_000;

type RpcLog = { transactionHash: Hex; logIndex: Hex };

/** The indexer being tested, for the message of a timeout. */
let current: IndexerProcess | undefined;
const lastLines = (): string =>
  (current?.lines ?? [])
    .slice(-8)
    .map((line) => JSON.stringify(line))
    .join(" | ");

/** Polls `check` every 25 ms until it returns true; throws after `timeoutMs`. */
async function waitUntil(check: () => Promise<boolean>, timeoutMs: number, what: string): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!(await check())) {
    if (Date.now() > deadline) throw new Error(`timed out after ${timeoutMs} ms waiting for ${what}; indexer: ${lastLines()}`);
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}

describe.skipIf(probe.client === undefined)(`live indexer against anvil${probe.reason === undefined ? "" : ` (skipped: ${probe.reason})`}`, () => {
  const db = useTestDatabase();
  const client = probe.client as PublicClient;
  const testClient = createTestClient({ mode: "anvil", transport: http(rpcUrl, { retryCount: 0 }) });
  let snapshotId: Hex;
  let minter: Minter;
  let running: IndexerProcess | undefined;

  beforeAll(async () => {
    snapshotId = await testClient.snapshot();
    minter = await prepareMint(rpcUrl);
  });
  // Waits for the exit, not only for the signal: an indexer still writing after the next test's TRUNCATE would leave
  // it a checkpoint and blocks of another run.
  afterEach(async () => {
    const process = running;
    running = undefined;
    if (process === undefined) return;
    try {
      await process.stop("SIGTERM", 10_000);
    } catch {
      await process.stop("SIGKILL", 5_000);
    }
  });
  afterAll(async () => {
    await testClient.revert({ id: snapshotId });
  });

  /**
   * Starts the indexer on the test DB and waits for its "live" line, and with the WebSocket for "websocket subscribed".
   * The fallback list is emptied on purpose.
   */
  async function start(options: { websocket: boolean; guardMs: number }): Promise<IndexerProcess> {
    running = startIndexer({
      DATABASE_URL: testDatabaseUrl(),
      RPC_URL: rpcUrl,
      RPC_FALLBACK_URLS: "",
      RPC_WS_URL: options.websocket ? wsUrl : "",
      CHAIN_ID: String(ANVIL_CHAIN_ID),
      POLL_INTERVAL_MS: String(options.guardMs),
    });
    current = running;
    const live = await running.waitFor("live", 30_000);
    expect(live).toMatchObject({ websocket: options.websocket, guardMs: options.guardMs });
    // "live" comes before the node confirms the subscription; blocks mined in between are caught by the round that
    // onSubscribed asks for, but a test that measures the WebSocket must start after it.
    if (options.websocket) await running.waitFor("websocket subscribed", 10_000);
    return running;
  }

  const head = () => client.getBlockNumber({ cacheTime: 0 });
  async function checkpoint(): Promise<bigint | undefined> {
    const row = await db().checkpoint.findUnique({ where: { chainId: ANVIL_CHAIN_ID } });
    return row?.lastBlockNumber;
  }
  /** Waits until the checkpoint is on the current head: the indexer has nothing left to do. */
  async function synced(timeoutMs = 10_000): Promise<void> {
    await waitUntil(async () => (await checkpoint()) === (await head()), timeoutMs, "checkpoint on the head");
  }
  /** Milliseconds from now until the SharesMinted of `receipt` is in RawEvent. */
  async function msUntilIndexed(receipt: TransactionReceipt, timeoutMs: number): Promise<number> {
    const startedAt = Date.now();
    await waitUntil(
      async () => (await db().rawEvent.count({ where: { chainId: ANVIL_CHAIN_ID, txHash: receipt.transactionHash, eventName: "SharesMinted" } })) === 1,
      timeoutMs,
      `SharesMinted of ${receipt.transactionHash} in RawEvent`,
    );
    return Date.now() - startedAt;
  }

  it("a mint reaches RawEvent at once via WebSocket, with a guard that cannot fire during the test", async () => {
    await start({ websocket: true, guardMs: GUARD_NEVER_MS });
    await synced();

    const receipt = await minter.mint(USDC_AMOUNT);
    const elapsed = await msUntilIndexed(receipt, 5_000);

    // With the guard at 10 minutes only the WebSocket can have asked for the round.
    expect(elapsed).toBeLessThan(5_000);
    const event = await db().rawEvent.findFirstOrThrow({ where: { chainId: ANVIL_CHAIN_ID, txHash: receipt.transactionHash, eventName: "SharesMinted" } });
    expect(event).toMatchObject({ blockNumber: receipt.blockNumber, blockHash: receipt.blockHash, address: minter.index.toLowerCase() });
  }, 60_000);

  it("without RPC_WS_URL a mint reaches RawEvent within POLL_INTERVAL_MS, through the guard timer", async () => {
    await start({ websocket: false, guardMs: GUARD_SHORT_MS });
    await synced();

    const receipt = await minter.mint(USDC_AMOUNT);
    const elapsed = await msUntilIndexed(receipt, GUARD_SHORT_MS * 5);

    // Measured from the receipt: one guard interval at most, plus the round that writes the blocks.
    expect(elapsed).toBeLessThan(GUARD_SHORT_MS + 1_500);
  }, 60_000);

  it("Ctrl-C stops cleanly, and a restart resumes from the checkpoint with no gap and no duplicate", async () => {
    const first = await start({ websocket: true, guardMs: GUARD_NEVER_MS });
    await minter.mint(USDC_AMOUNT);
    await synced();
    const stoppedAt = await checkpoint();

    expect(await first.stop("SIGINT")).toBe(0);
    expect(first.lines.map((line) => line.message)).toEqual(expect.arrayContaining(["stop requested: finishing the block in progress", "indexer stopped cleanly"]));
    expect(first.lines.filter((line) => line.level === "error" || line.level === "warn")).toEqual([]);

    // Blocks the indexer never saw: a mint and two empty blocks while it is stopped.
    const missed = await minter.mint(USDC_AMOUNT);
    await testClient.mine({ blocks: 2 });
    expect(await checkpoint()).toBe(stoppedAt);

    const second = await start({ websocket: true, guardMs: GUARD_NEVER_MS });
    const backfill = second.lines.find((line) => line.message === "backfill done");
    expect(backfill).toMatchObject({ fromBlock: String((stoppedAt ?? 0n) + 1n), insertedContracts: 0 });
    await synced();
    expect(await msUntilIndexed(missed, 1_000)).toBeLessThan(1_000);

    // No gap: one Block row per block from startBlock to the head.
    const last = await head();
    const blocks = await db().block.findMany({ where: { chainId: ANVIL_CHAIN_ID }, orderBy: { number: "asc" }, select: { number: true } });
    expect(blocks.map((block) => block.number)).toEqual(Array.from({ length: Number(last - fixed.startBlock + 1n) }, (_, i) => fixed.startBlock + BigInt(i)));

    // No duplicate and nothing missing: RawEvent holds exactly the logs of the indexed contracts, read with a plain
    // eth_getLogs. The unique key (chainId, txHash, logIndex) already forbids two equal rows; the count against the
    // reference catches a log written twice under another key or skipped.
    const contracts = await db().contract.findMany({ where: { chainId: ANVIL_CHAIN_ID }, select: { address: true } });
    const reference = (await client.request({
      method: "eth_getLogs",
      params: [{ address: contracts.map((c) => c.address as Hex), fromBlock: numberToHex(fixed.startBlock), toBlock: numberToHex(last) }],
    })) as RpcLog[];
    const events = await db().rawEvent.findMany({ where: { chainId: ANVIL_CHAIN_ID }, select: { txHash: true, logIndex: true } });
    const key = (txHash: string, logIndex: number | bigint) => `${txHash.toLowerCase()}:${BigInt(logIndex)}`;
    expect(events.map((e) => key(e.txHash, e.logIndex)).sort()).toEqual(reference.map((log) => key(log.transactionHash, BigInt(log.logIndex))).sort());

    expect(await second.stop("SIGTERM")).toBe(0);
  }, 90_000);
});
