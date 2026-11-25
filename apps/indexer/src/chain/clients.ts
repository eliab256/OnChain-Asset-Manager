// viem clients of the indexer. Every read goes through the HTTP client, which tries RPC_URL first and the
// backup providers after it (indexer.md §2, "RPC di riserva"); the WebSocket client only announces new blocks
// (indexer.md §4, "Live"). Nothing here touches the network: the startup checks are in providers.ts.
import {
  createPublicClient,
  defineChain,
  fallback,
  http,
  webSocket,
  type Chain,
  type FallbackTransport,
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

/** One HTTP provider on its own, without fallback: what the startup checks talk to. */
export type ProviderClient = { url: string; client: PublicClient<HttpTransport, Chain> };

export type ChainClients = {
  /** RPC_URL, then RPC_FALLBACK_URLS in order: the client every read of the indexer goes through. */
  http: PublicClient<FallbackTransport<readonly HttpTransport[]>, Chain>;
  /** The same providers one by one, in the same order, for checkProviders. */
  providers: readonly ProviderClient[];
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
function indexedChain(chainId: number, rpcUrls: readonly string[], rpcWsUrl: string | undefined): Chain {
  return defineChain({
    id: chainId,
    name: `chain-${chainId}`,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [...rpcUrls], ...(rpcWsUrl !== undefined ? { webSocket: [rpcWsUrl] } : {}) } },
  });
}

/**
 * Creates the clients without touching the network.
 *
 * The HTTP client uses viem's fallback transport over RPC_URL and RPC_FALLBACK_URLS, in that order and without
 * `rank`: every request goes to the first provider and moves to the next only when it fails, so the indexer
 * changes node only when it has to (two nodes can disagree on head and reorgs). viem's fallback starts again from
 * the first provider at every request: while RPC_URL is down, each request first waits for its error (immediate
 * for a refused connection, up to RPC_TIMEOUT_MS for a provider that does not answer). The retries are the
 * fallback's: it calls each provider once per attempt and repeats the whole list RPC_RETRY_COUNT times.
 * With no RPC_FALLBACK_URLS the list has one provider and behaves like a plain http transport.
 */
export function createChainClients(config: Pick<Config, "chainId" | "rpcUrl" | "rpcFallbackUrls" | "rpcWsUrl">): ChainClients {
  const urls = [config.rpcUrl, ...config.rpcFallbackUrls];
  const chain = indexedChain(config.chainId, urls, config.rpcWsUrl);
  const httpClient = createPublicClient({
    chain,
    transport: fallback(
      urls.map((url) => http(url, { timeout: RPC_TIMEOUT_MS })),
      { retryCount: RPC_RETRY_COUNT, retryDelay: RPC_RETRY_DELAY_MS },
    ),
  });
  const providers = urls.map((url) => ({ url, client: createPublicClient({ chain, transport: http(url, retry) }) }));
  const wsClient =
    config.rpcWsUrl !== undefined
      ? createPublicClient({ chain, transport: webSocket(config.rpcWsUrl, { reconnect: true, ...retry }) })
      : undefined;
  return { http: httpClient, providers, ws: wsClient };
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
