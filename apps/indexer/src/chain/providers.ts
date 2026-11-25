// Startup checks of every HTTP provider (indexer.md §2, "RPC di riserva"). A backup provider is used only when
// RPC_URL fails, which may happen in the middle of a backfill: a provider that cannot serve the indexer must be
// found here, at startup, and not then. Each provider is checked on its own, never through the fallback client.
import { indexManagerAbi } from "@oam/abi";
import type { Address } from "viem";
import { maskUrl } from "../secrets.js";
import type { ProviderClient } from "./clients.js";
import { isTransientRpcError } from "./errors.js";
import { multicallAt } from "./reads.js";

/** What the checks compare against: the deployment of the chain being indexed (protocolAddresses[chainId]). */
export type ProviderProbe = {
  chainId: number;
  indexManager: Address;
  indexFactory: Address;
  /** Deployment block: a provider must serve state at it, i.e. be an archive node for old blocks. */
  startBlock: bigint;
};

export type ProviderCheck = "chainId" | "deployment" | "archive";

/** Thrown when a provider answers, but cannot serve the indexer. The URL in the message is masked. */
export class ProviderCheckError extends Error {
  constructor(
    readonly url: string,
    readonly check: ProviderCheck,
    detail: string,
    options?: ErrorOptions,
  ) {
    super(`RPC provider ${url} failed the ${check} check: ${detail}`, options);
    this.name = "ProviderCheckError";
  }
}

/** Thrown when no provider answers at all at startup: there is nothing to index from. */
export class NoProviderReachableError extends Error {
  constructor(readonly urls: readonly string[], options?: ErrorOptions) {
    super(`No RPC provider answers: ${urls.join(", ")}. Check RPC_URL and RPC_FALLBACK_URLS`, options);
    this.name = "NoProviderReachableError";
  }
}

export type ProviderStatus =
  | { url: string; status: "ok" }
  /** Did not answer (transient error): not checked, the fallback skips it until it answers again. */
  | { url: string; status: "unreachable"; error: unknown };

/** viem's one-line summary of an error, without the request body and URL that its full message carries. */
function shortMessage(error: unknown): string {
  if (error instanceof Error) return "shortMessage" in error && typeof error.shortMessage === "string" ? error.shortMessage : error.message;
  return String(error);
}

/** The three checks of one provider; throws ProviderCheckError, or the RPC error itself when it does not answer. */
async function checkOne({ url, client }: ProviderClient, probe: ProviderProbe): Promise<void> {
  const masked = maskUrl(url);

  const chainId = await client.getChainId();
  if (chainId !== probe.chainId) throw new ProviderCheckError(masked, "chainId", `it serves chain ${chainId}, but CHAIN_ID is ${probe.chainId}`);

  // A deployless multicall (the one the indexer uses for every read) at the head, of a value the deployment
  // file also knows: it proves both that the provider accepts an eth_call without `to` (some limit the size of
  // eth_call) and that the deployment file describes this chain.
  const head = await client.getBlockNumber({ cacheTime: 0 });
  let factory: Address;
  try {
    [factory] = await multicallAt(client, {
      contracts: [{ address: probe.indexManager, abi: indexManagerAbi, functionName: "getIndexFactory" }],
      allowFailure: false,
      blockNumber: head,
    });
  } catch (error) {
    if (isTransientRpcError(error)) throw error;
    throw new ProviderCheckError(masked, "deployment", `deployless multicall of getIndexFactory() at block ${head} failed: ${shortMessage(error)}`, {
      cause: error,
    });
  }
  if (factory.toLowerCase() !== probe.indexFactory.toLowerCase()) {
    throw new ProviderCheckError(
      masked,
      "deployment",
      `the IndexManager returns IndexFactory ${factory}, the deployment file says ${probe.indexFactory}: wrong deployment file for this chain`,
    );
  }

  // State at the deployment block: a node that keeps only recent state (not archive) refuses it, and the indexer
  // reads at old blocks during a backfill.
  try {
    await client.getBalance({ address: probe.indexManager, blockNumber: probe.startBlock });
  } catch (error) {
    if (isTransientRpcError(error)) throw error;
    throw new ProviderCheckError(masked, "archive", `it cannot read state at the deployment block ${probe.startBlock}: ${shortMessage(error)}`, {
      cause: error,
    });
  }
}

/**
 * Checks every provider in order (indexer.md §2, "RPC di riserva"): chain id, a deployless multicall that
 * matches the deployment file, a read at startBlock. A provider that answers but fails a check stops the start
 * (ProviderCheckError, naming it with the masked URL). One that does not answer (transient error, e.g. connection
 * refused) is reported as unreachable and the start goes on: the fallback client skips it while it is down.
 * @returns The status of every provider, in the order of the list.
 * @throws ProviderCheckError, or NoProviderReachableError when no provider answers.
 */
export async function checkProviders(providers: readonly ProviderClient[], probe: ProviderProbe): Promise<ProviderStatus[]> {
  const statuses: ProviderStatus[] = [];
  let lastError: unknown;
  for (const provider of providers) {
    try {
      await checkOne(provider, probe);
      statuses.push({ url: maskUrl(provider.url), status: "ok" });
    } catch (error) {
      if (error instanceof ProviderCheckError || !isTransientRpcError(error)) throw error;
      statuses.push({ url: maskUrl(provider.url), status: "unreachable", error });
      lastError = error;
    }
  }
  if (statuses.every((status) => status.status === "unreachable")) {
    throw new NoProviderReachableError(
      statuses.map((status) => status.url),
      { cause: lastError },
    );
  }
  return statuses;
}
