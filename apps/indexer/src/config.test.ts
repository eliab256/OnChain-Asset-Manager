import { describe, expect, it } from "vitest";
import {
  ConfigError,
  configSecrets,
  DEFAULT_BATCH_SIZE,
  DEFAULT_POLL_INTERVAL_MS,
  describeConfig,
  loadConfig,
} from "./config.js";

const valid = {
  RPC_URL: "http://127.0.0.1:8545",
  RPC_WS_URL: "ws://127.0.0.1:8545",
  CHAIN_ID: "31337",
  DATABASE_URL: "postgresql://oam:secret@localhost:5434/oam",
  BATCH_SIZE: "500",
  POLL_INTERVAL_MS: "1000",
};

function problemsOf(env: NodeJS.ProcessEnv): readonly string[] {
  try {
    loadConfig(env);
  } catch (error) {
    if (error instanceof ConfigError) return error.problems;
    throw error;
  }
  throw new Error("expected a ConfigError");
}

describe("loadConfig", () => {
  it("reads a complete environment", () => {
    expect(loadConfig(valid)).toEqual({
      rpcUrl: "http://127.0.0.1:8545",
      rpcWsUrl: "ws://127.0.0.1:8545",
      chainId: 31337,
      databaseUrl: "postgresql://oam:secret@localhost:5434/oam",
      batchSize: 500,
      pollIntervalMs: 1000,
    });
  });

  it("applies the defaults and treats an empty RPC_WS_URL as absent", () => {
    const config = loadConfig({ ...valid, RPC_WS_URL: "", BATCH_SIZE: undefined, POLL_INTERVAL_MS: " " });

    expect(config.rpcWsUrl).toBeUndefined();
    expect(config.batchSize).toBe(DEFAULT_BATCH_SIZE);
    expect(config.pollIntervalMs).toBe(DEFAULT_POLL_INTERVAL_MS);
  });

  it("accepts the fork chain id", () => {
    expect(loadConfig({ ...valid, CHAIN_ID: "31338" }).chainId).toBe(31338);
  });

  it("lists every problem at once", () => {
    expect(problemsOf({})).toEqual(["RPC_URL is missing", "DATABASE_URL is missing", "CHAIN_ID is missing"]);
  });

  it("rejects an unsupported chain id", () => {
    expect(problemsOf({ ...valid, CHAIN_ID: "1" })).toEqual(["CHAIN_ID=1 is not supported (expected 31337 or 31338)"]);
  });

  it("rejects malformed numbers", () => {
    expect(problemsOf({ ...valid, BATCH_SIZE: "0", POLL_INTERVAL_MS: "1.5" })).toEqual([
      "BATCH_SIZE=0 must be a positive integer",
      "POLL_INTERVAL_MS=1.5 must be a positive integer",
    ]);
  });

  it("rejects a URL with the wrong protocol", () => {
    expect(problemsOf({ ...valid, RPC_URL: "ws://127.0.0.1:8545", RPC_WS_URL: "http://127.0.0.1:8545" })).toEqual([
      "RPC_URL must start with http:// or https://",
      "RPC_WS_URL must start with ws:// or wss://",
    ]);
  });

  it("rejects something that is not a URL", () => {
    expect(problemsOf({ ...valid, DATABASE_URL: "localhost" })).toEqual(["DATABASE_URL is not a valid URL"]);
  });
});

describe("describeConfig", () => {
  it("masks the database password and keeps the database name", () => {
    expect(describeConfig(loadConfig(valid)).databaseUrl).toBe("postgresql://oam:***@localhost:5434/oam");
  });

  it("hides the API key of a provider URL", () => {
    const config = loadConfig({
      ...valid,
      RPC_URL: "https://eth-mainnet.g.alchemy.com/v2/AbCdEf0123456789xyz",
      RPC_WS_URL: "wss://eth-mainnet.g.alchemy.com/v2/AbCdEf0123456789xyz",
    });
    const described = JSON.stringify(describeConfig(config));

    expect(described).not.toContain("AbCdEf0123456789xyz");
    expect(describeConfig(config).rpcUrl).toBe("https://eth-mainnet.g.alchemy.com/***");
    expect(describeConfig(config).rpcWsUrl).toBe("wss://eth-mainnet.g.alchemy.com/***");
  });

  it("leaves a local URL readable", () => {
    expect(describeConfig(loadConfig(valid)).rpcUrl).toBe("http://127.0.0.1:8545");
  });
});

describe("configSecrets", () => {
  it("collects the secrets of every URL", () => {
    const secrets = configSecrets(
      loadConfig({ ...valid, RPC_URL: "https://mainnet.infura.io/v3/0123456789abcdef0123456789abcdef" }),
    );

    expect(secrets).toContain("0123456789abcdef0123456789abcdef");
    expect(secrets).toContain("secret");
    // The database name is not a secret: redacting "/oam" would mangle unrelated lines.
    expect(secrets).not.toContain("/oam");
  });
});
