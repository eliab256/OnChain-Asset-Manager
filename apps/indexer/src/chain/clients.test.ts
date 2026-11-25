import { createPublicClient, custom } from "viem";
import { describe, expect, it } from "vitest";
import { assertChainId, ChainIdMismatchError, createChainClients, RPC_RETRY_COUNT, RPC_RETRY_DELAY_MS, RPC_TIMEOUT_MS } from "./clients.js";

function clientWithChainId(chainId: number) {
  return createPublicClient({
    transport: custom({
      request: ({ method }: { method: string }) =>
        method === "eth_chainId" ? Promise.resolve(`0x${chainId.toString(16)}`) : Promise.reject(new Error(method)),
    }),
  });
}

describe("assertChainId", () => {
  it("passes when the node serves the configured chain", async () => {
    await expect(assertChainId(clientWithChainId(31337), 31337)).resolves.toBeUndefined();
  });

  it("stops on a different chain", async () => {
    await expect(assertChainId(clientWithChainId(31338), 31337)).rejects.toBeInstanceOf(ChainIdMismatchError);
  });
});

describe("createChainClients", () => {
  it("creates the WebSocket client only when RPC_WS_URL is set", () => {
    const base = { chainId: 31337, rpcUrl: "http://127.0.0.1:8545", rpcFallbackUrls: [] } as const;

    expect(createChainClients({ ...base, rpcWsUrl: undefined }).ws).toBeUndefined();
    const clients = createChainClients({ ...base, rpcWsUrl: "ws://127.0.0.1:8545" });
    expect(clients.ws).toBeDefined();
    expect(clients.http.chain.id).toBe(31337);
  });

  it("sets viem's retries and timeout explicitly, the same on HTTP and WebSocket", () => {
    const clients = createChainClients({ chainId: 31337, rpcUrl: "http://127.0.0.1:8545", rpcFallbackUrls: [], rpcWsUrl: "ws://127.0.0.1:8545" });
    const expected = { retryCount: RPC_RETRY_COUNT, retryDelay: RPC_RETRY_DELAY_MS, timeout: RPC_TIMEOUT_MS };

    // The fallback repeats the whole list RPC_RETRY_COUNT times; every provider gets the request timeout.
    expect(clients.http.transport).toMatchObject({ retryCount: RPC_RETRY_COUNT, retryDelay: RPC_RETRY_DELAY_MS });
    for (const transport of clients.http.transport.transports) expect(transport.config.timeout).toBe(RPC_TIMEOUT_MS);
    for (const provider of clients.providers) expect(provider.client.transport).toMatchObject(expected);
    expect(clients.ws?.transport).toMatchObject(expected);
  });

  it("puts RPC_URL first and the backup providers after it, in order, on a fallback transport", () => {
    const urls = ["http://127.0.0.1:8545", "http://127.0.0.1:8546", "http://127.0.0.1:8547"];
    const clients = createChainClients({ chainId: 31337, rpcUrl: urls[0] ?? "", rpcFallbackUrls: urls.slice(1), rpcWsUrl: undefined });

    expect(clients.http.transport.type).toBe("fallback");
    expect(clients.http.transport.transports.map((transport) => transport.value?.url)).toEqual(urls);
    expect(clients.providers.map((provider) => provider.url)).toEqual(urls);
    expect(clients.http.chain.rpcUrls.default.http).toEqual(urls);
  });
});
