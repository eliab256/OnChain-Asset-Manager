// Backup RPC providers against anvil (indexer-roadmap.md step 5, part 2; indexer.md §2 "RPC di riserva"):
// startup checks on real answers and a backfill that goes through the second provider when the first is down.
// The wrong providers are a local proxy in front of anvil that changes one answer (test/helpers/rpcServer.ts).
import { protocolAddresses } from "@oam/abi";
import type { Address } from "viem";
import { afterEach, describe, expect, it } from "vitest";
import { createChainClients } from "../src/chain/clients.js";
import { ProviderCheckError, checkProviders, type ProviderProbe } from "../src/chain/providers.js";
import { handlers } from "../src/handlers/index.js";
import { backfill } from "../src/runner.js";
import { ANVIL_CHAIN_ID, probeAnvil, testRpcUrl } from "./helpers/anvil.js";
import { useTestDatabase } from "./helpers/db.js";
import { closedPortUrl, startRpcProxy, type Override, type RpcProxy, type RpcRequest } from "./helpers/rpcServer.js";

const anvil = await probeAnvil();
const fixed = protocolAddresses[ANVIL_CHAIN_ID];
const probe: ProviderProbe = { chainId: ANVIL_CHAIN_ID, ...fixed };
const KEY = "FakeApiKey0123456789abcdef";

function clients(rpcUrl: string, fallbacks: string[]) {
  return createChainClients({ chainId: ANVIL_CHAIN_ID, rpcUrl, rpcFallbackUrls: fallbacks, rpcWsUrl: undefined });
}

describe.skipIf(anvil.client === undefined)(`backup RPC providers${anvil.reason === undefined ? "" : ` (skipped: ${anvil.reason})`}`, () => {
  const db = useTestDatabase();
  const proxies: RpcProxy[] = [];
  afterEach(async () => {
    await Promise.all(proxies.splice(0).map((proxy) => proxy.close()));
  });

  async function proxy(override: (request: RpcRequest) => Override): Promise<RpcProxy> {
    const started = await startRpcProxy(testRpcUrl(), override);
    proxies.push(started);
    return started;
  }

  it("passes the checks on anvil, and reports a provider on a closed port as unreachable", async () => {
    const closed = await closedPortUrl();
    const statuses = await checkProviders(clients(closed, [testRpcUrl()]).providers, probe);

    expect(statuses.map((status) => [status.url, status.status])).toEqual([
      [closed, "unreachable"],
      [testRpcUrl(), "ok"],
    ]);
  });

  it("backfills through the backup provider when RPC_URL is a closed port", async () => {
    const closed = await closedPortUrl();
    const backup = await proxy(() => undefined);
    const { http } = clients(closed, [backup.url]);

    const result = await backfill({ prisma: db(), client: http, chainId: ANVIL_CHAIN_ID, handlers, batchSize: 2000 }, fixed);

    expect(result.range.lastBlock).toBe(result.head);
    expect(await db().block.count()).toBe(Number(result.head - fixed.startBlock + 1n));
    expect(await db().rawEvent.count()).toBeGreaterThan(0);
    // Every read went to the backup once RPC_URL refused it.
    expect(backup.methods).toContain("eth_getLogs");
  });

  it("stops on a backup provider that serves another chain, naming it without its API key", async () => {
    const wrongChain = await proxy((request) => (request.method === "eth_chainId" ? { result: "0x1" } : undefined));
    const error = await checkProviders(clients(testRpcUrl(), [`${wrongChain.url}/v2/${KEY}`]).providers, probe).catch((e: unknown) => e);

    expect(error).toBeInstanceOf(ProviderCheckError);
    expect(error).toMatchObject({ check: "chainId", url: `${wrongChain.url}/***` });
    expect((error as Error).message).not.toContain(KEY);
  });

  it("stops on a provider that refuses an eth_call without `to` (no deployless multicall)", async () => {
    const noDeployless = await proxy((request) => {
      const call = request.params?.[0] as { to?: string } | undefined;
      return request.method === "eth_call" && call?.to === undefined ? { error: { code: -32602, message: "missing to" } } : undefined;
    });
    await expect(checkProviders(clients(noDeployless.url, []).providers, probe)).rejects.toMatchObject({ check: "deployment" });
  });

  it("stops when the deployment file does not describe the chain the provider serves", async () => {
    const otherFactory: Address = "0x00000000000000000000000000000000000000f1";
    await expect(checkProviders(clients(testRpcUrl(), []).providers, { ...probe, indexFactory: otherFactory })).rejects.toMatchObject({
      check: "deployment",
    });
  });

  it("stops on a provider that cannot read state at the deployment block (not an archive node)", async () => {
    const notArchive = await proxy((request) =>
      request.method === "eth_getBalance" && request.params?.[1] !== "latest" ? { error: { code: -32000, message: "missing trie node" } } : undefined,
    );
    await expect(checkProviders(clients(notArchive.url, []).providers, probe)).rejects.toMatchObject({ check: "archive" });
  });
});
