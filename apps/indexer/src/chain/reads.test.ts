import { indexAbi } from "@oam/abi";
import { createPublicClient, custom, decodeFunctionData, encodeFunctionResult, type Hex } from "viem";
import { foundry } from "viem/chains";
import { describe, expect, it } from "vitest";
import { multicallAt, readContractAt } from "./reads.js";

const INDEX = "0x0000000000000000000000000000000000000abc" as const;

function recordingClient(respond: (method: string, params: unknown[]) => unknown) {
  const calls: { method: string; params: unknown[] }[] = [];
  const client = createPublicClient({
    chain: foundry,
    transport: custom({
      request: ({ method, params }: { method: string; params: unknown[] }) => {
        calls.push({ method, params });
        return Promise.resolve(respond(method, params));
      },
    }),
  });
  return { client, calls };
}

describe("readContractAt", () => {
  it("sends eth_call at the given block, not latest", async () => {
    const { client, calls } = recordingClient(() =>
      encodeFunctionResult({ abi: indexAbi, functionName: "totalSupply", result: 5n }),
    );

    const supply = await readContractAt(client, {
      address: INDEX,
      abi: indexAbi,
      functionName: "totalSupply",
      blockNumber: 100n,
    });

    expect(supply).toBe(5n);
    expect(calls).toHaveLength(1);
    expect(calls[0]?.method).toBe("eth_call");
    expect(calls[0]?.params[1]).toBe("0x64");
  });
});

describe("multicallAt", () => {
  it("sends one deployless eth_call at the given block", async () => {
    const { client, calls } = recordingClient(() => "0x");

    // The aggregator answer is not decoded here: only the shape of the request matters.
    await multicallAt(client, {
      contracts: [
        { address: INDEX, abi: indexAbi, functionName: "totalSupply" },
        { address: INDEX, abi: indexAbi, functionName: "decimals" },
      ],
      blockNumber: 100n,
    }).catch(() => undefined);

    expect(calls).toHaveLength(1);
    const call = calls[0];
    if (call === undefined) throw new Error("no call recorded");
    const [request, block] = call.params as [{ to?: Hex; data: Hex }, Hex];
    expect(call.method).toBe("eth_call");
    expect(block).toBe("0x64");
    // Deployless: no target contract, the aggregator bytecode travels in `data`.
    expect(request.to).toBeUndefined();
    expect(() => decodeFunctionData({ abi: indexAbi, data: request.data })).toThrow();
  });

  it("rejects a call without blockNumber at compile time", () => {
    const { client } = recordingClient(() => "0x");
    // @ts-expect-error blockNumber is mandatory
    void readContractAt(client, { address: INDEX, abi: indexAbi, functionName: "totalSupply" }).catch(() => undefined);
    // @ts-expect-error blockTag is not allowed
    void readContractAt(client, { address: INDEX, abi: indexAbi, functionName: "totalSupply", blockNumber: 1n, blockTag: "latest" }).catch(() => undefined);
  });
});
