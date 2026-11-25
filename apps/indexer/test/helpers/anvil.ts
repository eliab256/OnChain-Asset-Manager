// The anvil node of the integration tests (indexer.md §3, "Test d'integrazione"): started from outside
// (make dev, or anvil --load-state .anvil/31337.json), never by the test. The suites that need it skip
// with a title that says why when no node with the deployment of deployments/31337.json answers.
import { fileURLToPath } from "node:url";
import { protocolAddresses } from "@oam/abi";
import { config as loadDotenv } from "dotenv";
import { createPublicClient, http, type PublicClient } from "viem";

export const ANVIL_CHAIN_ID = 31337;

/** TEST_RPC_URL from apps/indexer/.env, or anvil's default port. Not RPC_URL: that one may point at a fork. */
export function testRpcUrl(): string {
  loadDotenv({ path: fileURLToPath(new URL("../../.env", import.meta.url)), quiet: true });
  const url = process.env["TEST_RPC_URL"];
  return url === undefined || url.trim() === "" ? "http://127.0.0.1:8545" : url.trim();
}

export type AnvilProbe = { client: PublicClient; reason: undefined } | { client: undefined; reason: string };

/**
 * Connects to the test node and checks that it is anvil (31337) with the IndexManager of deployments/31337.json.
 * @returns The client, or the reason the anvil suites are skipped.
 */
export async function probeAnvil(): Promise<AnvilProbe> {
  const url = testRpcUrl();
  const client = createPublicClient({ transport: http(url, { retryCount: 0, timeout: 5_000 }) });
  let chainId: number;
  try {
    chainId = await client.getChainId();
  } catch {
    return { client: undefined, reason: `no node at ${url}` };
  }
  if (chainId !== ANVIL_CHAIN_ID) return { client: undefined, reason: `node at ${url} has chain id ${chainId}, not ${ANVIL_CHAIN_ID}` };
  const code = await client.getCode({ address: protocolAddresses[ANVIL_CHAIN_ID].indexManager });
  if (code === undefined || code === "0x") return { client: undefined, reason: `no deployment of deployments/31337.json at ${url}` };
  return { client, reason: undefined };
}
