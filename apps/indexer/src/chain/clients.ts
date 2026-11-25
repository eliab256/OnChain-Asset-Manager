// viem clients of the indexer. Every read goes through the HTTP client; the WebSocket client only
// announces new blocks (apps/indexer/indexer.md §4, "Live").
import {
  createPublicClient,
  defineChain,
  http,
  webSocket,
  type Chain,
  type HttpTransport,
  type PublicClient,
  type WebSocketTransport,
} from "viem";
import type { Config } from "../config.js";

/**
 * Retries of a single request inside viem, before the error reaches the indexer (indexer.md §4, "Live").
 * viem waits `RPC_RETRY_DELAY_MS * 2^attempt` between them (150, 300, 600 ms): it absorbs a blip of the provider.
 * A longer outage is the runner's job, which waits with a growing pause between two catch-ups. These are viem's
 * defaults, written here so that a viem upgrade cannot change them unseen.
 */
export const RPC_RETRY_COUNT = 3;
/** Base pause of viem's retries, doubled at every attempt. */
export const RPC_RETRY_DELAY_MS = 150;
/** Time limit of one request; past it viem throws TimeoutError, which counts as transient (chain/errors.ts). */
export const RPC_TIMEOUT_MS = 10_000;

const retry = { retryCount: RPC_RETRY_COUNT, retryDelay: RPC_RETRY_DELAY_MS, timeout: RPC_TIMEOUT_MS } as const;

export type ChainClients = {
  http: PublicClient<HttpTransport, Chain>;
  /** Present only when RPC_WS_URL is set. */
  ws: PublicClient<WebSocketTransport, Chain> | undefined;
};

/** Thrown when the RPC serves a different chain than CHAIN_ID. */
export class ChainIdMismatchError extends Error {
  constructor(
    readonly expected: number,
    readonly actual: number,
  ) {
    super(`RPC chain id is ${actual}, but CHAIN_ID is ${expected}: check RPC_URL and CHAIN_ID`);
    this.name = "ChainIdMismatchError";
  }
}

/**
 * Minimal chain definition for the chain being indexed. Nothing in it is specific to anvil: the same
 * definition works for the fork or for a public network. No multicall3 address on purpose: reads use
 * deployless multicall (see reads.ts), so pure anvil, which has no Multicall3, behaves like any other chain.
 */
function indexedChain(chainId: number, rpcUrl: string, rpcWsUrl: string | undefined): Chain {
  return defineChain({
    id: chainId,
    name: `chain-${chainId}`,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [rpcUrl], ...(rpcWsUrl !== undefined ? { webSocket: [rpcWsUrl] } : {}) } },
  });
}

/** Creates the clients without touching the network. */
export function createChainClients(config: Pick<Config, "chainId" | "rpcUrl" | "rpcWsUrl">): ChainClients {
  const chain = indexedChain(config.chainId, config.rpcUrl, config.rpcWsUrl);
  const httpClient = createPublicClient({ chain, transport: http(config.rpcUrl, retry) });
  const wsClient =
    config.rpcWsUrl !== undefined
      ? createPublicClient({ chain, transport: webSocket(config.rpcWsUrl, { reconnect: true, ...retry }) })
      : undefined;
  return { http: httpClient, ws: wsClient };
}

/**
 * Asks the node for eth_chainId and stops the process if it is not the configured one,
 * so a fork indexer never writes anvil data under 31338 (and the other way round).
 */
export async function assertChainId(client: PublicClient, expected: number): Promise<void> {
  const actual = await client.getChainId();
  if (actual !== expected) throw new ChainIdMismatchError(expected, actual);
}

/**
 * Closes the WebSocket connection, if any. The HTTP transport holds no connection to close.
 * Uses the viem RPC client's close(), not the raw socket's: closing the socket alone makes viem
 * reconnect (reconnect: true) and its keep-alive timer would keep the process running.
 */
export async function closeChainClients(clients: ChainClients): Promise<void> {
  if (clients.ws === undefined) return;
  try {
    const rpcClient = await clients.ws.transport.getRpcClient();
    rpcClient.close();
  } catch {
    // The socket never connected (node down): there is nothing to close, and this error must not
    // hide the one that stopped the process.
  }
}
