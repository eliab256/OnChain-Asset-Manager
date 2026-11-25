import { createPublicClient, custom, numberToHex, type PublicClient } from "viem";
import { describe, expect, it } from "vitest";
import { IncompleteBlockError, fetchBlockHeader } from "./blocks.js";

const HASH = `0x${"AB".repeat(32)}`;
const PARENT = `0x${"CD".repeat(32)}`;

function clientReturning(block: Record<string, unknown>, calls: unknown[][] = []): PublicClient {
  return createPublicClient({
    transport: custom({
      request: ({ method, params }: { method: string; params: unknown[] }) => {
        calls.push([method, ...params]);
        if (method === "eth_getBlockByNumber") return Promise.resolve(block);
        return Promise.reject(new Error(`unexpected ${method}`));
      },
    }),
  });
}

describe("fetchBlockHeader", () => {
  it("returns number, lowercase hashes and the header timestamp as a Date", async () => {
    const calls: unknown[][] = [];
    const client = clientReturning(
      { number: numberToHex(42), hash: HASH, parentHash: PARENT, timestamp: numberToHex(1_700_000_000), transactions: [] },
      calls,
    );
    expect(await fetchBlockHeader(client, 42n)).toEqual({
      number: 42n,
      hash: HASH.toLowerCase(),
      parentHash: PARENT.toLowerCase(),
      timestamp: new Date(1_700_000_000_000),
    });
    expect(calls).toEqual([["eth_getBlockByNumber", numberToHex(42), false]]);
  });

  it("rejects a pending block without hash", async () => {
    const client = clientReturning({ number: null, hash: null, parentHash: PARENT, timestamp: "0x0", transactions: [] });
    await expect(fetchBlockHeader(client, 42n)).rejects.toThrow(IncompleteBlockError);
  });
});
