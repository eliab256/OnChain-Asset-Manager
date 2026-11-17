import { describe, expect, it } from "vitest";
import { maskUrl, redact, urlSecrets } from "./secrets.js";

const KEY = "AbCdEf0123456789xyz";

describe("maskUrl", () => {
  it.each([
    ["key in the path (Alchemy)", `https://eth-mainnet.g.alchemy.com/v2/${KEY}`, "https://eth-mainnet.g.alchemy.com/***"],
    ["key in the path (Infura)", `wss://mainnet.infura.io/ws/v3/${KEY}`, "wss://mainnet.infura.io/***"],
    ["key in the query", `https://rpc.example.com/?apikey=${KEY}`, "https://rpc.example.com/***"],
    ["key as password", `https://user:${KEY}@rpc.example.com`, "https://user:***@rpc.example.com"],
  ])("hides the secret: %s", (_case, raw, masked) => {
    expect(maskUrl(raw)).toBe(masked);
    expect(maskUrl(raw)).not.toContain(KEY);
  });

  it("masks only the password of a database URL", () => {
    expect(maskUrl(`postgresql://oam:${KEY}@localhost:5434/oam`, "database")).toBe("postgresql://oam:***@localhost:5434/oam");
    expect(urlSecrets(`postgresql://oam:${KEY}@localhost:5434/oam`, "database")).toEqual([KEY]);
  });

  it("leaves a URL without secrets unchanged", () => {
    expect(maskUrl("http://127.0.0.1:8545")).toBe("http://127.0.0.1:8545");
    expect(maskUrl("ws://127.0.0.1:8545")).toBe("ws://127.0.0.1:8545");
  });
});

describe("urlSecrets", () => {
  it("returns nothing for a local URL", () => {
    expect(urlSecrets("http://127.0.0.1:8545")).toEqual([]);
  });

  it("returns the path and the key-like segment", () => {
    expect(urlSecrets(`https://eth-mainnet.g.alchemy.com/v2/${KEY}`)).toEqual([`/v2/${KEY}`, KEY]);
  });

  it("returns the query and the password", () => {
    expect(urlSecrets(`https://u:pw@rpc.example.com/?apikey=${KEY}`)).toEqual(["pw", `?apikey=${KEY}`]);
  });
});

describe("redact", () => {
  it("removes the key from a viem HTTP error message", () => {
    const viemMessage = `HTTP request failed.\n\nURL: https://eth-mainnet.g.alchemy.com/v2/${KEY}\nRequest body: {"method":"eth_chainId"}`;
    const secrets = urlSecrets(`https://eth-mainnet.g.alchemy.com/v2/${KEY}`);

    const safe = redact(viemMessage, secrets);

    expect(safe).not.toContain(KEY);
    expect(safe).toContain("URL: https://eth-mainnet.g.alchemy.com***");
  });

  it("removes the key when it appears alone", () => {
    expect(redact(`invalid api key ${KEY}`, urlSecrets(`https://x.example.com/v2/${KEY}`))).toBe("invalid api key ***");
  });
});
