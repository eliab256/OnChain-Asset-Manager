// startLive without a chain: a fake subscription the test drives (announce a block, report an error) and vitest's
// fake timers for the guard timer, so every rule of indexer.md §4 "Live" is checked on its own.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { startLive, type BlockWatch, type BlockWatchCallbacks } from "./live.js";
import { logger } from "./logger.js";

const GUARD_MS = 30_000;

/** A BlockWatch that records each subscription and lets the test call its callbacks. */
function fakeWatch() {
  const subscriptions: (BlockWatchCallbacks & { unwatched: boolean })[] = [];
  const watch: BlockWatch = (callbacks) => {
    const subscription = { ...callbacks, unwatched: false };
    subscriptions.push(subscription);
    return () => {
      subscription.unwatched = true;
    };
  };
  const current = () => {
    const subscription = subscriptions.at(-1);
    if (subscription === undefined) throw new Error("no subscription");
    return subscription;
  };
  return { watch, subscriptions, current };
}

describe("startLive", () => {
  let triggers: number;
  const trigger = () => {
    triggers++;
  };

  beforeEach(() => {
    vi.useFakeTimers();
    triggers = 0;
    vi.spyOn(logger, "warn").mockImplementation(() => {});
    vi.spyOn(logger, "info").mockImplementation(() => {});
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it("asks for a round at every announced block, and none in between", () => {
    const ws = fakeWatch();
    const live = startLive({ trigger, watch: ws.watch, guardMs: GUARD_MS });
    expect(ws.subscriptions).toHaveLength(1);
    expect(triggers).toBe(0);
    ws.current().onBlock();
    ws.current().onBlock();
    expect(triggers).toBe(2);
    live.stop();
  });

  it("asks for one round when the subscription becomes active, for the blocks mined while it was set up", () => {
    const ws = fakeWatch();
    const live = startLive({ trigger, watch: ws.watch, guardMs: GUARD_MS });
    expect(triggers).toBe(0);
    ws.current().onSubscribed();
    expect(triggers).toBe(1);
    expect(logger.info).toHaveBeenCalledWith("websocket subscribed");
    live.stop();
  });

  it("a subscription started again by the guard asks for its round too", () => {
    const ws = fakeWatch();
    const live = startLive({ trigger, watch: ws.watch, guardMs: GUARD_MS });
    ws.current().onSubscribed();
    ws.current().onError(new Error("socket closed"));
    vi.advanceTimersByTime(GUARD_MS);
    // One round from the first subscription, one from the guard.
    expect(triggers).toBe(2);
    ws.current().onSubscribed();
    expect(triggers).toBe(3);
    live.stop();
  });

  it("makes no round via the guard while blocks keep arriving within guardMs", () => {
    const ws = fakeWatch();
    const live = startLive({ trigger, watch: ws.watch, guardMs: GUARD_MS });
    for (let i = 0; i < 5; i++) {
      vi.advanceTimersByTime(GUARD_MS - 1);
      ws.current().onBlock();
    }
    // 5 rounds, all from the WebSocket: the timer never expired.
    expect(triggers).toBe(5);
    live.stop();
  });

  it("asks for a round when the WebSocket stays silent for guardMs, then again every guardMs", () => {
    const ws = fakeWatch();
    const live = startLive({ trigger, watch: ws.watch, guardMs: GUARD_MS });
    vi.advanceTimersByTime(GUARD_MS - 1);
    expect(triggers).toBe(0);
    vi.advanceTimersByTime(1);
    expect(triggers).toBe(1);
    vi.advanceTimersByTime(GUARD_MS);
    expect(triggers).toBe(2);
    live.stop();
  });

  it("restarts the guard from a block: the next expiry is guardMs after the block", () => {
    const ws = fakeWatch();
    const live = startLive({ trigger, watch: ws.watch, guardMs: GUARD_MS });
    vi.advanceTimersByTime(20_000);
    ws.current().onBlock();
    vi.advanceTimersByTime(GUARD_MS - 1);
    expect(triggers).toBe(1);
    vi.advanceTimersByTime(1);
    expect(triggers).toBe(2);
    live.stop();
  });

  it("without a WebSocket the guard is the only signal and fires every guardMs", () => {
    const live = startLive({ trigger, watch: undefined, guardMs: 1_000 });
    vi.advanceTimersByTime(3_500);
    expect(triggers).toBe(3);
    live.stop();
  });

  it("logs one warning for a burst of errors and keeps the guard running", () => {
    const ws = fakeWatch();
    const live = startLive({ trigger, watch: ws.watch, guardMs: GUARD_MS });
    ws.current().onError(new Error("socket closed"));
    ws.current().onError(new Error("socket error"));
    ws.current().onError(new Error("reconnect failed"));
    expect(logger.warn).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(GUARD_MS);
    expect(triggers).toBe(1);
    live.stop();
  });

  it("subscribes again at the guard expiry after an error with no block since", () => {
    const ws = fakeWatch();
    const live = startLive({ trigger, watch: ws.watch, guardMs: GUARD_MS });
    const first = ws.current();
    first.onError(new Error("socket closed"));
    vi.advanceTimersByTime(GUARD_MS);
    expect(first.unwatched).toBe(true);
    expect(ws.subscriptions).toHaveLength(2);
    // The new subscription failing too logs again, once.
    ws.current().onError(new Error("still down"));
    expect(logger.warn).toHaveBeenCalledTimes(2);
    vi.advanceTimersByTime(GUARD_MS);
    expect(ws.subscriptions).toHaveLength(3);
    live.stop();
  });

  it("does not subscribe again when a block arrived after the error (viem reconnected)", () => {
    const ws = fakeWatch();
    const live = startLive({ trigger, watch: ws.watch, guardMs: GUARD_MS });
    ws.current().onError(new Error("socket closed"));
    ws.current().onBlock();
    vi.advanceTimersByTime(GUARD_MS);
    expect(ws.subscriptions).toHaveLength(1);
    // A later error is a new outage and logs again.
    ws.current().onError(new Error("socket closed"));
    expect(logger.warn).toHaveBeenCalledTimes(2);
    live.stop();
  });

  it("does not subscribe again at the guard of a healthy but quiet WebSocket", () => {
    const ws = fakeWatch();
    const live = startLive({ trigger, watch: ws.watch, guardMs: GUARD_MS });
    vi.advanceTimersByTime(GUARD_MS * 4);
    expect(ws.subscriptions).toHaveLength(1);
    expect(triggers).toBe(4);
    live.stop();
  });

  it("stop ends the subscription and the timer, and ignores later callbacks", () => {
    const ws = fakeWatch();
    const live = startLive({ trigger, watch: ws.watch, guardMs: GUARD_MS });
    live.stop();
    expect(ws.current().unwatched).toBe(true);
    ws.current().onBlock();
    ws.current().onSubscribed();
    ws.current().onError(new Error("late"));
    vi.advanceTimersByTime(GUARD_MS * 3);
    expect(triggers).toBe(0);
    expect(logger.warn).not.toHaveBeenCalled();
    expect(vi.getTimerCount()).toBe(0);
    live.stop();
  });
});
