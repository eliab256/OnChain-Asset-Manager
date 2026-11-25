// Runner: decides when the indexer works (indexer.md §3 and §4). Bootstrap and backfill up to the head, then
// catch-up rounds run one at a time (createCatchUp). The signals that trigger them (WebSocket, polling) and
// SIGINT / SIGTERM arrive with part 5 of step 5 of localHelpers/indexer-roadmap.md.
import { isTransientRpcError } from "./chain/errors.js";
import { errorFields, logger } from "./logger.js";
import { processRange, type ProcessRangeResult, type RangeDeps } from "./pipeline.js";
import { getCheckpoint, type CheckpointPosition } from "./repositories/checkpoint.js";
import { insertFixedContracts, type FixedContracts } from "./repositories/contracts.js";
import type { Db } from "./repositories/db.js";

/** Where the indexer resumes on a chain. */
export type BootstrapResult = {
  /** First block to process: startBlock on a chain never indexed, otherwise checkpoint + 1. */
  fromBlock: bigint;
  /**
   * The last block fully written, or null on a chain never indexed. Its hash is what the parentHash of
   * fromBlock must match: a reorg that happened while the indexer was stopped shows up there.
   */
  checkpoint: CheckpointPosition | null;
  /** Fixed contracts inserted by this start: 6 the first time, 0 from the second start on. */
  insertedContracts: number;
};

/**
 * Prepares a chain for processing (indexer.md §4, "Bootstrap"): inserts the fixed contracts, so that
 * getLogs has addresses to listen to, then reads the checkpoint to decide where to start.
 * Safe to run at every start: existing contracts and the checkpoint are left as they are.
 * @param fixed The fixed contracts and startBlock of the deployment, i.e. protocolAddresses[chainId].
 */
export async function bootstrap(db: Db, chainId: number, fixed: FixedContracts): Promise<BootstrapResult> {
  const insertedContracts = await insertFixedContracts(db, chainId, fixed);
  const checkpoint = await getCheckpoint(db, chainId);
  const fromBlock = checkpoint === null ? fixed.startBlock : checkpoint.blockNumber + 1n;
  return { fromBlock, checkpoint, insertedContracts };
}

/**
 * How far the head may be below the checkpoint at startup before the indexer refuses to start. A few blocks
 * are normal with backup providers: the one answering may be a little behind the one that wrote the checkpoint
 * (indexer.md §2, "RPC di riserva"). Far more means another chain under the same chain id, typically an anvil
 * restarted from scratch. 64 is two epochs of Ethereum: no healthy node lags that much.
 */
export const MAX_HEAD_BEHIND_CHECKPOINT = 64n;

/**
 * Thrown when the checkpoint is more than MAX_HEAD_BEHIND_CHECKPOINT blocks past the head of the chain: the node
 * is not the chain the DB was written from, typically an anvil restarted from scratch under the same chain id
 * (indexer.md §4, "Bootstrap"). Processing would wait for blocks that, once they exist, have other hashes.
 */
export class CheckpointAheadOfHeadError extends Error {
  constructor(
    readonly chainId: number,
    readonly checkpointBlock: bigint,
    readonly head: bigint,
  ) {
    super(
      `Checkpoint of chain ${chainId} is at block ${checkpointBlock}, but the chain head is ${head}: the node was ` +
        `restarted or serves another chain. Delete the rows of chain ${chainId} before restarting the indexer`,
    );
    this.name = "CheckpointAheadOfHeadError";
  }
}

export type BackfillResult = {
  bootstrap: BootstrapResult;
  /** Head read once at the start: blocks produced during the backfill are left to the next call. */
  head: bigint;
  range: ProcessRangeResult;
};

/**
 * Bootstrap, then every block from the resume point to the current head (indexer.md §4). Running it again
 * processes only the blocks after the checkpoint; with nothing new it writes nothing. A head a few blocks below
 * the checkpoint (a provider behind) processes nothing and leaves the blocks to the live loop.
 * @param fixed protocolAddresses[chainId].
 * @throws CheckpointAheadOfHeadError when the head is more than MAX_HEAD_BEHIND_CHECKPOINT blocks below the
 *   checkpoint, or whatever processRange throws (blocks before the failing one stay written).
 */
export async function backfill(deps: RangeDeps, fixed: FixedContracts): Promise<BackfillResult> {
  const start = await bootstrap(deps.prisma, deps.chainId, fixed);
  // cacheTime 0: viem caches the block number for a few seconds, and the head must be the current one.
  const head = await deps.client.getBlockNumber({ cacheTime: 0 });
  if (start.checkpoint !== null && start.checkpoint.blockNumber > head) {
    if (start.checkpoint.blockNumber - head > MAX_HEAD_BEHIND_CHECKPOINT) {
      throw new CheckpointAheadOfHeadError(deps.chainId, start.checkpoint.blockNumber, head);
    }
    logger.warn("chain head is below the checkpoint: the provider is behind, nothing to backfill", {
      chainId: deps.chainId,
      checkpoint: start.checkpoint.blockNumber,
      head,
    });
  }
  const range = await processRange(deps, start.fromBlock, head);
  return { bootstrap: start, head, range };
}

// ─── Catch-up ────────────────────────────────────────────────────────────────────────────────────────────────

/** One catch-up round: processes what is new and returns. Receives the signal of the runner's stop. */
export type CatchUpRound = (signal: AbortSignal) => Promise<void>;

/**
 * The round of the live loop (indexer.md §4, "Live"): reads the checkpoint from the DB and the head via HTTP,
 * then processRange(checkpoint + 1, head) with the stop signal. Nothing new, nothing done. A head below the
 * checkpoint is a provider behind (a backup one, indexer.md §2): no error, the next signal tries again.
 * @param startBlock Where to start when the chain has no checkpoint yet (a backfill that found no block).
 */
export function catchUpRound(deps: Omit<RangeDeps, "signal">, startBlock: bigint): CatchUpRound {
  return async (signal) => {
    const checkpoint = await getCheckpoint(deps.prisma, deps.chainId);
    const from = checkpoint === null ? startBlock : checkpoint.blockNumber + 1n;
    const head = await deps.client.getBlockNumber({ cacheTime: 0 });
    if (head < from - 1n) {
      logger.info("chain head is below the checkpoint: the provider is behind, waiting", { chainId: deps.chainId, checkpoint: from - 1n, head });
      return;
    }
    if (head < from) return;
    await processRange({ ...deps, signal }, from, head);
  };
}

/** First pause after a failed round with a transient RPC error. */
export const CATCH_UP_RETRY_INITIAL_MS = 1_000;
/** Ceiling of the pause: it doubles at every failure in a row and never exceeds this. */
export const CATCH_UP_RETRY_MAX_MS = 30_000;

export type CatchUpOptions = {
  /** Called once, with the error, when a round fails with a permanent error. The runner accepts no round after it. */
  onFatal: (error: unknown) => void;
  /** Pauses between retries; tests pass shorter ones. */
  retryInitialMs?: number;
  retryMaxMs?: number;
  /** Waits `ms` or until `signal` aborts, whichever comes first. Tests replace it to avoid real waits. */
  sleep?: (ms: number, signal: AbortSignal) => Promise<void>;
};

export type CatchUp = {
  /**
   * Asks for a round (a new block was announced, or the poll fired). With no round running one starts; with one
   * running, one more is scheduled after it, however many triggers arrive meanwhile. Ignored after stop or a fatal error.
   */
  trigger: () => void;
  /** Stops: no new round, the one running is told to stop between two blocks. Resolves when it has ended. */
  stop: () => Promise<void>;
  /** Resolves when no round is running or waiting to retry (for tests and for stop). */
  idle: () => Promise<void>;
};

function abortableSleep(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    if (signal.aborted) return resolve();
    const timer = setTimeout(done, ms);
    function done(): void {
      clearTimeout(timer);
      signal.removeEventListener("abort", done);
      resolve();
    }
    signal.addEventListener("abort", done);
  });
}

/**
 * Runs catch-up rounds one at a time (indexer.md §4, "Live"). The WebSocket and the poll both call trigger(), and
 * nothing guarantees they do not fire together: two processRange at once would write the same blocks in parallel.
 * Here a trigger during a round only sets a flag, and one more round runs after the current one.
 *
 * Errors of a round: a transient RPC error (chain/errors.ts) waits and tries again, with a pause that starts at
 * retryInitialMs, doubles at every failure in a row up to retryMaxMs, and goes back to the start after a round that
 * succeeds. Any other error (reorg, DB, a permanent RPC error) is handed to onFatal and the runner stops.
 */
export function createCatchUp(round: CatchUpRound, options: CatchUpOptions): CatchUp {
  const initialMs = options.retryInitialMs ?? CATCH_UP_RETRY_INITIAL_MS;
  const maxMs = options.retryMaxMs ?? CATCH_UP_RETRY_MAX_MS;
  const sleep = options.sleep ?? abortableSleep;
  const controller = new AbortController();
  let pending = false;
  let finished = false;
  let running: Promise<void> | undefined;

  /** Pause after `failures` failed rounds in a row: initialMs, then doubled each time, never above maxMs. */
  function retryDelay(failures: number): number {
    return Math.min(initialMs * 2 ** (failures - 1), maxMs);
  }

  async function loop(): Promise<void> {
    let failures = 0;
    while (pending && !finished && !controller.signal.aborted) {
      pending = false;
      try {
        await round(controller.signal);
        failures = 0;
      } catch (error) {
        // A stop never makes processRange throw (it returns with stopped: true), so a permanent error is reported
        // even while stopping. A transient one is not retried when the runner is stopping.
        if (!isTransientRpcError(error)) {
          finished = true;
          options.onFatal(error);
          return;
        }
        if (controller.signal.aborted) return;
        failures++;
        const delay = retryDelay(failures);
        logger.warn("catch-up failed on a transient RPC error, retrying", { failures, retryInMs: delay, ...errorFields(error) });
        await sleep(delay, controller.signal);
        // The failed round still has to be done: it counts as a pending trigger.
        pending = true;
      }
    }
  }

  function trigger(): void {
    if (finished || controller.signal.aborted) return;
    pending = true;
    if (running !== undefined) return;
    running = loop().finally(() => {
      running = undefined;
    });
  }

  function idle(): Promise<void> {
    return running ?? Promise.resolve();
  }

  async function stop(): Promise<void> {
    controller.abort();
    await idle();
  }

  return { trigger, stop, idle };
}
