// createCatchUp without a DB or a chain: the round is a fake that the test ends (or fails) when it wants, so the
// concurrency rules are checked on their own: one round at a time, one more after triggers that arrive meanwhile,
// retries with a growing pause, stop that waits for the round in progress.
import { HttpRequestError, TimeoutError } from "viem";
import { describe, expect, it } from "vitest";
import { CATCH_UP_RETRY_INITIAL_MS, CATCH_UP_RETRY_MAX_MS, createCatchUp, type CatchUpOptions } from "./runner.js";

/** Lets pending promise callbacks run (the loop of createCatchUp is async). */
const tick = () => new Promise<void>((resolve) => setImmediate(resolve));

type Call = { signal: AbortSignal; finish: () => void; fail: (error: unknown) => void };

/** A round that records each call and stays pending until the test finishes or fails it. */
function controllableRound() {
  const calls: Call[] = [];
  const round = (signal: AbortSignal) =>
    new Promise<void>((resolve, reject) => {
      calls.push({ signal, finish: resolve, fail: reject });
    });
  const last = (): Call => {
    const call = calls.at(-1);
    if (call === undefined) throw new Error("no round started");
    return call;
  };
  return { calls, round, last };
}

const transient = () => new TimeoutError({ body: {}, url: "http://127.0.0.1:8545" });

/** Options with a sleep that records the pauses and returns at once. */
function options(overrides: Partial<CatchUpOptions> = {}) {
  const fatal: unknown[] = [];
  const pauses: number[] = [];
  const opts: CatchUpOptions = {
    onFatal: (error) => fatal.push(error),
    sleep: (ms) => {
      pauses.push(ms);
      return Promise.resolve();
    },
    ...overrides,
  };
  return { opts, fatal, pauses };
}

describe("createCatchUp", () => {
  it("starts a round on a trigger, and a new one on a trigger after it has ended", async () => {
    const { calls, round, last } = controllableRound();
    const catchUp = createCatchUp(round, options().opts);

    catchUp.trigger();
    expect(calls).toHaveLength(1);
    last().finish();
    await catchUp.idle();

    catchUp.trigger();
    expect(calls).toHaveLength(2);
  });

  it("runs exactly one more round after the current one, however many triggers arrive meanwhile", async () => {
    const { calls, round, last } = controllableRound();
    const catchUp = createCatchUp(round, options().opts);

    catchUp.trigger();
    catchUp.trigger();
    catchUp.trigger();
    catchUp.trigger();
    expect(calls).toHaveLength(1);

    last().finish();
    await tick();
    expect(calls).toHaveLength(2);
    last().finish();
    await catchUp.idle();
    expect(calls).toHaveLength(2);
  });

  it("never runs two rounds at the same time", async () => {
    let active = 0;
    let maxActive = 0;
    const round = async () => {
      active++;
      maxActive = Math.max(maxActive, active);
      await tick();
      active--;
    };
    const catchUp = createCatchUp(round, options().opts);
    for (let i = 0; i < 20; i++) {
      catchUp.trigger();
      if (i % 3 === 0) await tick();
    }
    await catchUp.idle();
    expect(maxActive).toBe(1);
  });

  it("retries a transient RPC error with a pause that doubles up to the ceiling, and starts again after a success", async () => {
    const { calls, round, last } = controllableRound();
    const { opts, pauses, fatal } = options();
    const catchUp = createCatchUp(round, opts);

    catchUp.trigger();
    for (let i = 0; i < 7; i++) {
      last().fail(transient());
      await tick();
    }
    // A trigger during the round that succeeds keeps the same loop going: the failure that follows in it must
    // start again from the first pause, not continue from the ceiling.
    catchUp.trigger();
    last().finish();
    await tick();
    last().fail(new HttpRequestError({ url: "http://127.0.0.1:8545", status: 503 }));
    await tick();
    last().finish();
    await catchUp.idle();

    expect(CATCH_UP_RETRY_INITIAL_MS).toBe(1_000);
    expect(CATCH_UP_RETRY_MAX_MS).toBe(30_000);
    expect(pauses).toEqual([1_000, 2_000, 4_000, 8_000, 16_000, 30_000, 30_000, 1_000]);
    expect(calls).toHaveLength(10);
    expect(fatal).toEqual([]);
  });

  it("hands a permanent error to onFatal once, and accepts no round after it", async () => {
    const { calls, round, last } = controllableRound();
    const { opts, fatal, pauses } = options();
    const catchUp = createCatchUp(round, opts);
    const reorg = new Error("Reorg at block 5");

    catchUp.trigger();
    catchUp.trigger();
    last().fail(reorg);
    await catchUp.idle();
    catchUp.trigger();

    expect(fatal).toEqual([reorg]);
    expect(pauses).toEqual([]);
    // Neither the pending trigger nor the one after the error started a round.
    expect(calls).toHaveLength(1);
  });

  it("stop tells the running round to stop, waits for it, and skips the pending round", async () => {
    const { calls, round, last } = controllableRound();
    const catchUp = createCatchUp(round, options().opts);

    catchUp.trigger();
    catchUp.trigger();
    let stopped = false;
    const stopping = catchUp.stop().then(() => {
      stopped = true;
    });
    await tick();

    expect(last().signal.aborted).toBe(true);
    // The round has not ended yet: neither has stop.
    expect(stopped).toBe(false);
    last().finish();
    await stopping;

    catchUp.trigger();
    expect(calls).toHaveLength(1);
  });

  it("stop during the retry pause ends the pause at once and retries nothing", async () => {
    const { calls, round, last } = controllableRound();
    // The real abortable sleep, with a pause far longer than the test timeout.
    const catchUp = createCatchUp(round, { onFatal: () => undefined, retryInitialMs: 600_000 });

    catchUp.trigger();
    last().fail(transient());
    await tick();
    await catchUp.stop();

    expect(calls).toHaveLength(1);
  });

  it("reports a permanent error that arrives while stopping, instead of losing it", async () => {
    const { round, last } = controllableRound();
    const { opts, fatal } = options();
    const catchUp = createCatchUp(round, opts);
    const dbDown = new Error("Can't reach database server");

    catchUp.trigger();
    const stopping = catchUp.stop();
    last().fail(dbDown);
    await stopping;

    expect(fatal).toEqual([dbDown]);
  });
});
