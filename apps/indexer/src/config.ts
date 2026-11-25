// Environment of the indexer, read once at startup. Variables are documented in apps/indexer/indexer.md §2.
import { isSupportedChainId, type SupportedChainId } from "@oam/abi";
import { maskUrl, urlSecrets } from "./secrets.js";

export type Config = {
  /** HTTP RPC of the chain: every read (blocks, logs, contract calls) goes through it. */
  rpcUrl: string;
  /**
   * Backup HTTP RPCs of the same chain, tried in this order when rpcUrl fails (indexer.md §2, "RPC di riserva").
   * Empty when RPC_FALLBACK_URLS is not set.
   */
  rpcFallbackUrls: readonly string[];
  /** WebSocket RPC of the same chain, used only to be told about new blocks. Undefined = polling only. */
  rpcWsUrl: string | undefined;
  /** 31337 (anvil) or 31338 (mainnet fork). Checked against eth_chainId at startup. */
  chainId: SupportedChainId;
  /** Postgres connection string, the same database as packages/db/.env. */
  databaseUrl: string;
  /** Blocks per getLogs call during the backfill. */
  batchSize: number;
  /** Interval of the HTTP head polling in milliseconds. */
  pollIntervalMs: number;
};

export const DEFAULT_BATCH_SIZE = 2000;
export const DEFAULT_POLL_INTERVAL_MS = 30_000;

/** Thrown when the environment is incomplete or malformed; the message lists every problem at once. */
export class ConfigError extends Error {
  constructor(readonly problems: readonly string[]) {
    super(`Invalid indexer configuration:\n${problems.map((p) => `  - ${p}`).join("\n")}`);
    this.name = "ConfigError";
  }
}

/**
 * Reads and validates the configuration from an environment object.
 * Collects every problem before throwing, so a fresh setup is fixed in one pass.
 * @param env Usually process.env, after dotenv has loaded apps/indexer/.env.
 */
export function loadConfig(env: NodeJS.ProcessEnv): Config {
  const problems: string[] = [];

  const rpcUrl = readUrl(env, "RPC_URL", ["http:", "https:"], problems);
  const rpcFallbackUrls = readUrlList(env, "RPC_FALLBACK_URLS", ["http:", "https:"], problems);
  if (rpcUrl !== undefined && rpcFallbackUrls.includes(rpcUrl)) problems.push("RPC_FALLBACK_URLS repeats RPC_URL");
  const rpcWsUrl = isSet(env.RPC_WS_URL) ? readUrl(env, "RPC_WS_URL", ["ws:", "wss:"], problems) : undefined;
  const databaseUrl = readUrl(env, "DATABASE_URL", ["postgresql:", "postgres:"], problems);

  let chainId: SupportedChainId | undefined;
  const rawChainId = readPositiveInt(env, "CHAIN_ID", undefined, problems);
  if (rawChainId !== undefined) {
    if (isSupportedChainId(rawChainId)) chainId = rawChainId;
    else problems.push(`CHAIN_ID=${rawChainId} is not supported (expected 31337 or 31338)`);
  }

  const batchSize = readPositiveInt(env, "BATCH_SIZE", DEFAULT_BATCH_SIZE, problems);
  const pollIntervalMs = readPositiveInt(env, "POLL_INTERVAL_MS", DEFAULT_POLL_INTERVAL_MS, problems);

  if (
    problems.length > 0 ||
    rpcUrl === undefined ||
    databaseUrl === undefined ||
    chainId === undefined ||
    batchSize === undefined ||
    pollIntervalMs === undefined
  ) {
    throw new ConfigError(problems);
  }
  return { rpcUrl, rpcFallbackUrls, rpcWsUrl, chainId, databaseUrl, batchSize, pollIntervalMs };
}

/**
 * The configuration as it can be logged: only protocol and host of each URL, because RPC providers put
 * the API key in the path or in the query string, and the database URL carries a password.
 */
export function describeConfig(config: Config): Record<string, string | number | null> {
  return {
    rpcUrl: maskUrl(config.rpcUrl),
    rpcFallbackUrls: config.rpcFallbackUrls.length === 0 ? null : config.rpcFallbackUrls.map((url) => maskUrl(url)).join(", "),
    rpcWsUrl: config.rpcWsUrl === undefined ? null : maskUrl(config.rpcWsUrl),
    chainId: config.chainId,
    databaseUrl: maskUrl(config.databaseUrl, "database"),
    batchSize: config.batchSize,
    pollIntervalMs: config.pollIntervalMs,
  };
}

function isSet(value: string | undefined): value is string {
  return value !== undefined && value.trim() !== "";
}

function readUrl(
  env: NodeJS.ProcessEnv,
  name: string,
  protocols: readonly string[],
  problems: string[],
): string | undefined {
  const value = env[name];
  if (!isSet(value)) {
    problems.push(`${name} is missing`);
    return undefined;
  }
  return checkUrl(value.trim(), name, protocols, problems);
}

/** Validates one URL; `label` names it in the problem (the variable, or the variable and the position in a list). */
function checkUrl(value: string, label: string, protocols: readonly string[], problems: string[]): string | undefined {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    problems.push(`${label} is not a valid URL`);
    return undefined;
  }
  if (!protocols.includes(url.protocol)) {
    problems.push(`${label} must start with ${protocols.map((p) => `${p}//`).join(" or ")}`);
    return undefined;
  }
  return value;
}

/**
 * Reads an optional comma-separated list of URLs. Empty items (a trailing comma) are skipped; a repeated
 * URL is a problem, because the same provider twice in the fallback list only doubles the wait when it is down.
 */
function readUrlList(env: NodeJS.ProcessEnv, name: string, protocols: readonly string[], problems: string[]): string[] {
  const value = env[name];
  if (!isSet(value)) return [];
  const items = value.split(",").map((item) => item.trim()).filter((item) => item !== "");
  const urls: string[] = [];
  items.forEach((item, position) => {
    const url = checkUrl(item, `${name}[${position}]`, protocols, problems);
    if (url === undefined) return;
    if (urls.includes(url)) problems.push(`${name}[${position}] repeats an earlier URL of the list`);
    else urls.push(url);
  });
  return urls;
}

function readPositiveInt(
  env: NodeJS.ProcessEnv,
  name: string,
  fallback: number | undefined,
  problems: string[],
): number | undefined {
  const value = env[name];
  if (!isSet(value)) {
    if (fallback === undefined) problems.push(`${name} is missing`);
    return fallback;
  }
  if (!/^\d+$/.test(value.trim()) || Number(value) <= 0 || !Number.isSafeInteger(Number(value))) {
    problems.push(`${name}=${value} must be a positive integer`);
    return undefined;
  }
  return Number(value);
}

/** Every secret carried by the configured URLs, to register with logger.redact at startup. */
export function configSecrets(config: Config): string[] {
  return [
    ...urlSecrets(config.rpcUrl),
    ...config.rpcFallbackUrls.flatMap((url) => urlSecrets(url)),
    ...(config.rpcWsUrl === undefined ? [] : urlSecrets(config.rpcWsUrl)),
    ...urlSecrets(config.databaseUrl, "database"),
  ];
}
