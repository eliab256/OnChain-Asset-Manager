// wsBlockWatch against a real anvil WebSocket (indexer.md §4, "Live"): onSubscribed comes with the node's
// confirmation, blocks are announced after it, a subscription closed before the confirmation stays silent, and a
// node that does not answer ends in onError without an unhandled rejection. Needs anvil (make dev, or
// anvil --load-state .anvil/31337.json); the blocks mined here are reverted with evm_snapshot / evm_revert.
import { createPublicClient, createTestClient, http, webSocket, type Chain, type Hex, type PublicClient, type WebSocketTransport } from "viem";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { wsBlockWatch, type BlockWatchCallbacks } from "../src/live.js";
import { probeAnvil, testRpcUrl } from "./helpers/anvil.js";
import { closedPortUrl } from "./helpers/rpcServer.js";

const probe = await probeAnvil();
const rpcUrl = testRpcUrl();
const toWs = (url: string) => url.replace(/^http/, "ws");

/** Callbacks that record what they receive. */
function recorder() {
  const events: string[] = [];
  const errors: unknown[] = [];
  let subscribed: () => void = () => {};
  const subscribedOnce = new Promise<void>((resolve) => (subscribed = resolve));
  const callbacks: BlockWatchCallbacks = {
    onBlock: () => events.push("block"),
    onError: (error) => {
      events.push("error");
      errors.push(error);
    },
    onSubscribed: () => {
      events.push("subscribed");
      subscribed();
    },
  };
  return { events, errors, callbacks, subscribedOnce };
}

/** Polls until `check` is true, at most `timeoutMs`. */
async function eventually(check: () => boolean, timeoutMs = 3_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!check()) {
    if (Date.now() > deadline) throw new Error(`condition not met within ${timeoutMs} ms`);
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

function wsClient(url: string): PublicClient<WebSocketTransport, Chain> {
  // reconnect: false, so that the node-down case ends at once instead of after viem's 5 attempts.
  return createPublicClient({ transport: webSocket(url, { reconnect: false, retryCount: 0 }) }) as PublicClient<WebSocketTransport, Chain>;
}

async function close(client: PublicClient<WebSocketTransport, Chain>): Promise<void> {
  try {
    (await client.transport.getRpcClient()).close();
  } catch {
    // never connected
  }
}

describe.skipIf(probe.client === undefined)(`wsBlockWatch against anvil${probe.reason === undefined ? "" : ` (skipped: ${probe.reason})`}`, () => {
  const testClient = createTestClient({ mode: "anvil", transport: http(rpcUrl, { retryCount: 0 }) });
  let snapshotId: Hex;
  beforeAll(async () => {
    snapshotId = await testClient.snapshot();
  });
  afterAll(async () => {
    await testClient.revert({ id: snapshotId });
  });

  it("calls onSubscribed on the node's confirmation, then onBlock for every block mined after it", async () => {
    const client = wsClient(toWs(rpcUrl));
    const r = recorder();
    const unwatch = wsBlockWatch(client)(r.callbacks);
    try {
      await r.subscribedOnce;
      expect(r.events).toEqual(["subscribed"]);
      await testClient.mine({ blocks: 1 });
      await testClient.mine({ blocks: 1 });
      await eventually(() => r.events.length === 3);
      expect(r.events).toEqual(["subscribed", "block", "block"]);
    } finally {
      unwatch();
      await close(client);
    }
  });

  it("stays silent when closed before the confirmation, and after it", async () => {
    const client = wsClient(toWs(rpcUrl));
    const r = recorder();
    // Closed in the same tick: the eth_subscribe has not even been sent yet.
    wsBlockWatch(client)(r.callbacks)();
    // A second watch on the same socket tells when the first one would have been confirmed.
    const witness = recorder();
    const unwatchWitness = wsBlockWatch(client)(witness.callbacks);
    try {
      await witness.subscribedOnce;
      await testClient.mine({ blocks: 1 });
      await eventually(() => witness.events.includes("block"));
      expect(r.events).toEqual([]);
    } finally {
      unwatchWitness();
      await close(client);
    }
  });

  it("ends in onError when no node answers, without onSubscribed", async () => {
    const client = wsClient(toWs(await closedPortUrl()));
    const r = recorder();
    const unwatch = wsBlockWatch(client)(r.callbacks);
    try {
      await eventually(() => r.errors.length > 0);
      expect(r.events).not.toContain("subscribed");
    } finally {
      unwatch();
      await close(client);
    }
  });
});
