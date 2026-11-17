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
  const httpClient = createPublicClient({ chain, transport: http(config.rpcUrl) });
  const wsClient =
    config.rpcWsUrl !== undefined
      ? createPublicClient({ chain, transport: webSocket(config.rpcWsUrl, { reconnect: true }) })
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
