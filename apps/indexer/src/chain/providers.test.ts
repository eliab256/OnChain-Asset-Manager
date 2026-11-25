// checkProviders without a node: providers whose transport answers or fails as a test decides. The paths where
// every check passes (a real deployless multicall, a real read at startBlock) are in
// test/fallback.integration.test.ts, against anvil.
import { createPublicClient, custom, HttpRequestError, RpcRequestError, type EIP1193RequestFn } from "viem";
import { describe, expect, it } from "vitest";
import type { ProviderClient } from "./clients.js";
import { NoProviderReachableError, ProviderCheckError, checkProviders, type ProviderProbe } from "./providers.js";

const probe: ProviderProbe = {
  chainId: 31337,
  indexManager: "0x00000000000000000000000000000000000000e1",
  indexFactory: "0x00000000000000000000000000000000000000f1",
  startBlock: 0n,
};

type Answer = (method: string) => unknown;

/** A provider whose every request is answered by `answer` (a value, or a thrown/rejected error). */
function provider(url: string, answer: Answer): ProviderClient {
  const request: EIP1193RequestFn = ({ method }) => {
    try {
      return Promise.resolve(answer(method) as never);
    } catch (error) {
      return Promise.reject(error instanceof Error ? error : new Error(String(error)));
    }
  };
  // The type of ProviderClient is a client over http; for the checks only the requests matter.
  return { url, client: createPublicClient({ transport: custom({ request }, { retryCount: 0 }) }) as unknown as ProviderClient["client"] };
}

const down = (url: string) =>
  provider(url, () => {
    throw new HttpRequestError({ url, cause: new TypeError("fetch failed") });
  });

const onChain = (chainId: number, then: Answer = (method) => { throw new Error(`unexpected ${method}`); }) =>
  (method: string) => (method === "eth_chainId" ? `0x${chainId.toString(16)}` : method === "eth_blockNumber" ? "0x2a" : then(method));

describe("checkProviders", () => {
  it("stops on a provider that serves another chain, naming it with the masked URL", async () => {
    const error = await checkProviders([provider("https://rpc.example/v2/SuperSecretKey0123456", onChain(1))], probe).catch((e: unknown) => e);

    expect(error).toBeInstanceOf(ProviderCheckError);
    expect(error).toMatchObject({ check: "chainId", url: "https://rpc.example/***" });
    expect((error as Error).message).not.toContain("SuperSecretKey0123456");
  });

  it("stops on a backup provider with another chain id even when RPC_URL is down", async () => {
    await expect(checkProviders([down("http://127.0.0.1:1"), provider("http://backup:8545", onChain(31338))], probe)).rejects.toMatchObject({
      check: "chainId",
      url: "http://backup:8545",
    });
  });

  it("stops when the deployless multicall is refused for a reason other than a busy provider", async () => {
    const refuses = provider(
      "http://no-deployless:8545",
      onChain(31337, () => {
        throw new RpcRequestError({ body: {}, url: "http://no-deployless:8545", error: { code: -32602, message: "missing to" } });
      }),
    );
    await expect(checkProviders([refuses], probe)).rejects.toMatchObject({ check: "deployment" });
  });

  it("stops with NoProviderReachableError when no provider answers, a rate-limited one included", async () => {
    // The second provider answers the chain id but fails its multicall with a rate limit: transient, so
    // unreachable too. One provider down and the other fine is in test/fallback.integration.test.ts.
    const busy = provider(
      "http://busy:8545",
      onChain(31337, () => {
        throw new HttpRequestError({ url: "http://busy:8545", status: 429 });
      }),
    );
    const error = await checkProviders([down("http://127.0.0.1:1"), busy], probe).catch((e: unknown) => e);

    expect(error).toBeInstanceOf(NoProviderReachableError);
    expect((error as NoProviderReachableError).urls).toEqual(["http://127.0.0.1:1", "http://busy:8545"]);
  });

  it("passes on a non-RPC error as it is, without calling it unreachable", async () => {
    const broken = provider("http://broken:8545", () => {
      throw new RpcRequestError({ body: {}, url: "http://broken:8545", error: { code: -32601, message: "method not found" } });
    });
    const error = await checkProviders([broken], probe).catch((e: unknown) => e);

    expect(error).not.toBeInstanceOf(NoProviderReachableError);
    expect(error).not.toBeInstanceOf(ProviderCheckError);
  });
});
