import { describe, expect, it } from "vitest";
import { anvil, ANVIL_CHAIN_ID, MAINNET_FORK_CHAIN_ID, mainnetFork, supportedChains } from "./chains.js";

describe("chains", () => {
  it("anvil is 31337 and the mainnet fork 31338 (FORK_CHAIN_ID in the Makefile), never 1", () => {
    expect(ANVIL_CHAIN_ID).toBe(31337);
    expect(MAINNET_FORK_CHAIN_ID).toBe(31338);
    expect(anvil.id).toBe(ANVIL_CHAIN_ID);
    expect(mainnetFork.id).toBe(MAINNET_FORK_CHAIN_ID);
  });

  it("the fork definition uses ETH with 18 decimals and the local RPC", () => {
    expect(mainnetFork.nativeCurrency).toEqual({ name: "Ether", symbol: "ETH", decimals: 18 });
    expect(mainnetFork.rpcUrls.default.http).toEqual(["http://127.0.0.1:8545"]);
  });

  it("supportedChains lists exactly anvil and the fork", () => {
    expect(supportedChains.map((chain) => chain.id)).toEqual([31337, 31338]);
  });
});
