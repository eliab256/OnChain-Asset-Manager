// isTransientRpcError on the errors as viem really throws them: produced by a client whose transport fails,
// so the wrapping (RpcRequestError inside an action error, cause chains) is viem's own and not guessed.
import { createPublicClient, custom, http, HttpRequestError, RpcRequestError, TimeoutError, type EIP1193RequestFn } from "viem";
import { describe, expect, it } from "vitest";
import { LogBlockMismatchError } from "./consistency.js";
import { isTransientRpcError } from "./errors.js";

const URL = "http://127.0.0.1:8545";

/** A client whose every request fails with `error`, without viem's retries (the test must not wait). */
function failingClient(error: Error) {
  const request: EIP1193RequestFn = () => Promise.reject(error);
  return createPublicClient({ transport: custom({ request }, { retryCount: 0 }) });
}

/** What the indexer catches when a read fails with `error`: here getBlockNumber and an eth_call. */
async function thrownBy(error: Error): Promise<unknown[]> {
  const client = failingClient(error);
  const errors: unknown[] = [];
  await client.getBlockNumber({ cacheTime: 0 }).catch((e: unknown) => errors.push(e));
  await client.call({ to: "0x0000000000000000000000000000000000000001", data: "0x" }).catch((e: unknown) => errors.push(e));
  expect(errors).toHaveLength(2);
  return errors;
}

const rpcError = (code: number, message = "error") => new RpcRequestError({ body: {}, url: URL, error: { code, message } });

describe("isTransientRpcError", () => {
  it.each([
    ["timeout", new TimeoutError({ body: {}, url: URL })],
    ["HTTP 408", new HttpRequestError({ url: URL, status: 408 })],
    ["HTTP 429", new HttpRequestError({ url: URL, status: 429 })],
    ["HTTP 500", new HttpRequestError({ url: URL, status: 500 })],
    ["HTTP 502", new HttpRequestError({ url: URL, status: 502 })],
    ["HTTP 503", new HttpRequestError({ url: URL, status: 503 })],
    ["HTTP 504", new HttpRequestError({ url: URL, status: 504 })],
    ["no HTTP response", new HttpRequestError({ url: URL, cause: new TypeError("fetch failed") })],
    ["JSON-RPC -32005 limit exceeded", rpcError(-32005)],
    ["JSON-RPC 429 in a 200 response", rpcError(429)],
    ["JSON-RPC -32007 (QuickNode)", rpcError(-32007)],
  ])("is transient: %s", async (_, error) => {
    for (const thrown of await thrownBy(error)) expect(isTransientRpcError(thrown)).toBe(true);
  });

  it.each([
    ["HTTP 400", new HttpRequestError({ url: URL, status: 400 })],
    ["HTTP 403 (refused key)", new HttpRequestError({ url: URL, status: 403 })],
    ["HTTP 413 (request too large)", new HttpRequestError({ url: URL, status: 413 })],
    ["JSON-RPC -32603 internal error", rpcError(-32603)],
    ["JSON-RPC -32602 invalid params", rpcError(-32602)],
    ["JSON-RPC 3 execution reverted", rpcError(3, "execution reverted")],
  ])("is permanent: %s", async (_, error) => {
    for (const thrown of await thrownBy(error)) expect(isTransientRpcError(thrown)).toBe(false);
  });

  it("is transient for a node that does not listen, as viem's http transport reports it", async () => {
    // Port 1 is closed on any developer machine: the request fails before any HTTP response.
    const client = createPublicClient({ transport: http("http://127.0.0.1:1", { retryCount: 0, timeout: 2_000 }) });
    const error = await client.getBlockNumber({ cacheTime: 0 }).catch((e: unknown) => e);
    expect(isTransientRpcError(error)).toBe(true);
  });

  it("is permanent for the indexer's own errors and for errors that are not viem's", () => {
    const hash = (byte: string) => `0x${byte.repeat(32)}` as const;
    const location = { address: "0x00000000000000000000000000000000000000a1", blockNumber: 5n, blockHash: hash("aa"), txHash: hash("cc"), logIndex: 0 } as const;
    expect(isTransientRpcError(new LogBlockMismatchError({ number: 5n, hash: hash("bb") }, location))).toBe(false);
    expect(isTransientRpcError(new Error("Can't reach database server"))).toBe(false);
    expect(isTransientRpcError("a string")).toBe(false);
    expect(isTransientRpcError(undefined)).toBe(false);
  });

  it("finds a transient cause wrapped in a plain Error, and stops on a cause cycle", () => {
    expect(isTransientRpcError(new Error("catch-up failed", { cause: new TimeoutError({ body: {}, url: URL }) }))).toBe(true);
    const a = new Error("a");
    const b = new Error("b", { cause: a });
    Object.assign(a, { cause: b });
    expect(isTransientRpcError(a)).toBe(false);
  });
});
