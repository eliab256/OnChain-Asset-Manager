// Live loop of the indexer (indexer.md §4, "Live"): decides when a catch-up round is asked for. Two signals, both
// calling the same trigger(): the WebSocket announcing a new block, and a guard timer that fires only when the
// WebSocket has been silent for guardMs. The rounds themselves, one at a time, are createCatchUp's (runner.ts).
import type { Chain, PublicClient, WebSocketTransport } from "viem";
import { errorFields, logger } from "./logger.js";

/** Callbacks of a block subscription. */
export type BlockWatchCallbacks = {
  /** A new block was announced. */
  onBlock: () => void;
  /** The subscription or its socket failed. */
  onError: (error: unknown) => void;
  /** The node confirmed the subscription: from now on every new block is announced. */
  onSubscribed: () => void;
};

/** What the live loop needs from a block subscription: start it with the callbacks, get back the function that ends it. */
export type BlockWatch = (callbacks: BlockWatchCallbacks) => () => void;

/**
 * BlockWatch over the WebSocket transport: eth_subscribe to newHeads, no polling. The block number is not passed
 * on: the round reads the head again via HTTP (indexer.md §4, "Live").
 *
 * It calls transport.subscribe, the same call viem's watchBlockNumber makes inside, because that one does not say
 * when the subscription is active: a block mined between the last round and the node's confirmation would be
 * announced to nobody (indexer.md §4, "Live", 2026-11-26). The promise of subscribe resolves on the confirmation,
 * and there onSubscribed is called. viem still subscribes again by itself after a reconnect.
 */
export function wsBlockWatch(client: PublicClient<WebSocketTransport, Chain>): BlockWatch {
  return ({ onBlock, onError, onSubscribed }) => {
    // False after unwatch: callbacks of a subscription being closed are dropped.
    let active = true;
    let unsubscribe: (() => Promise<unknown>) | undefined;
    client.transport
      .subscribe({
        params: ["newHeads"],
        onData: () => {
          if (active) onBlock();
        },
        onError: (error: unknown) => {
          if (active) onError(error);
        },
      })
      .then((subscription) => {
        // Closed before the node confirmed: end it now that its id is known.
        if (!active) return void subscription.unsubscribe();
        unsubscribe = subscription.unsubscribe;
        onSubscribed();
      })
      .catch((error: unknown) => {
        // No socket at all (node down): viem rejects without calling onError.
        if (active) onError(error);
      });
    return () => {
      active = false;
      // Not awaited: on a closed socket the eth_unsubscribe never gets an answer, and there is nothing to wait for.
      void unsubscribe?.();
    };
  };
}

export type LiveOptions = {
  /** Asks for a catch-up round: CatchUp.trigger. */
  trigger: () => void;
  /** The WebSocket subscription; undefined without RPC_WS_URL, and then the guard timer is the only signal. */
  watch: BlockWatch | undefined;
  /** POLL_INTERVAL_MS: how long the WebSocket may stay silent before a round is asked for via HTTP. */
  guardMs: number;
};

export type Live = {
  /** Ends the subscription and the timer. Rounds already asked for are createCatchUp's to stop. */
  stop: () => void;
};

/**
 * Starts the live loop. Every block announced by the WebSocket asks for a round and resets the guard timer; when
 * the timer expires (no announcement for guardMs) it asks for a round itself and starts again. With a healthy
 * WebSocket there are no periodic HTTP requests; a WebSocket open but mute is still covered, because the timer
 * watches the absence of announcements, not the errors.
 *
 * A WebSocket error writes one warning line, not one per error: viem reports both the error and the close of the
 * socket, and again at each failed reconnect. viem reconnects on its own (5 attempts, 2 s apart) and subscribes
 * again; after the last failed attempt it drops the subscription for good. So when the guard timer expires after
 * an error and no block has arrived since, the subscription is started again, which opens a new socket. A block
 * announced after an error means viem has recovered, and nothing is restarted.
 *
 * Every subscription that becomes active asks for one round (onSubscribed): blocks mined while it was being set up
 * were announced to nobody, and without that round they would wait for the next block or for the guard timer.
 */
export function startLive(options: LiveOptions): Live {
  let stopped = false;
  let failed = false;
  let unwatch: (() => void) | undefined;
  let timer: NodeJS.Timeout | undefined;

  function subscribe(): void {
    if (options.watch === undefined) return;
    unwatch = options.watch({ onBlock, onError, onSubscribed });
  }

  function unsubscribe(): void {
    // The unsubscribe of a dead socket must not stop the loop: viem already swallows its error, this is a guard.
    try {
      unwatch?.();
    } catch (error) {
      logger.debug("websocket unsubscribe failed", errorFields(error));
    }
    unwatch = undefined;
  }

  function armGuard(): void {
    clearTimeout(timer);
    timer = setTimeout(onGuard, options.guardMs);
  }

  function onBlock(): void {
    if (stopped) return;
    if (failed) logger.info("websocket is announcing blocks again");
    failed = false;
    armGuard();
    options.trigger();
  }

  function onError(error: unknown): void {
    if (stopped || failed) return;
    failed = true;
    logger.warn("websocket error: the guard timer asks for rounds via HTTP until it recovers", {
      guardMs: options.guardMs,
      ...errorFields(error),
    });
  }

  /**
   * The subscription is active. A round now covers the blocks mined before it: the round that index.ts asks for after
   * the backfill, or the last one before a new subscription, may have read the head before them.
   */
  function onSubscribed(): void {
    if (stopped) return;
    logger.info("websocket subscribed");
    options.trigger();
  }

  function onGuard(): void {
    if (stopped) return;
    if (failed) {
      logger.info("websocket still silent after an error: subscribing again");
      unsubscribe();
      // Cleared before subscribing: a new failure must log again, once.
      failed = false;
      subscribe();
    }
    armGuard();
    options.trigger();
  }

  subscribe();
  armGuard();

  return {
    stop: () => {
      if (stopped) return;
      stopped = true;
      clearTimeout(timer);
      unsubscribe();
    },
  };
}
