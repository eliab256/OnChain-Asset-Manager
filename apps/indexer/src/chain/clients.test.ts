import { createPublicClient, custom } from "viem";
import { describe, expect, it } from "vitest";
import { assertChainId, ChainIdMismatchError, createChainClients } from "./clients.js";

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
    const base = { chainId: 31337, rpcUrl: "http://127.0.0.1:8545" } as const;

    expect(createChainClients({ ...base, rpcWsUrl: undefined }).ws).toBeUndefined();
    const clients = createChainClients({ ...base, rpcWsUrl: "ws://127.0.0.1:8545" });
    expect(clients.ws).toBeDefined();
    expect(clients.http.chain.id).toBe(31337);
  });
});
