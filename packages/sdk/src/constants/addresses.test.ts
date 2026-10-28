import { getAddress, isAddress } from "viem";
import { describe, expect, it } from "vitest";
import anvilDeployment from "../../../../deployments/31337.json" with { type: "json" };
import forkDeployment from "../../../../deployments/31338.json" with { type: "json" };
import { UnsupportedChainError } from "../errors.js";
import { getProtocolAddresses } from "./addresses.js";

// The deployment files are the single source of truth: the expected values are read from them
// here, independently of the mapping done in @oam/abi.
const deployments = [
  [31337, anvilDeployment],
  [31338, forkDeployment],
] as const;

describe("getProtocolAddresses", () => {
  it.each(deployments)("chain %i returns the proxies of deployments/<chainId>.json", (chainId, file) => {
    expect(file.chainId).toBe(chainId);
    expect(getProtocolAddresses(chainId)).toEqual({
      indexManager: getAddress(file.indexManager),
      indexFactory: getAddress(file.indexFactory),
      router: getAddress(file.router.proxy),
      priceFeedManager: getAddress(file.priceFeedManager.proxy),
      swapManager: getAddress(file.swapManager.proxy),
      usdc: getAddress(file.config.usdc),
      multiSigWallet: getAddress(file.multiSigWallet.address),
      timelock: getAddress(file.timelock),
      startBlock: BigInt(file.startBlock),
    });
  });

  it.each(deployments)("chain %i never returns an implementation address (only proxies are callable)", (chainId, file) => {
    const values = Object.values(getProtocolAddresses(chainId));
    expect(values).not.toContain(getAddress(file.router.implementation));
    expect(values).not.toContain(getAddress(file.priceFeedManager.implementation));
    expect(values).not.toContain(getAddress(file.swapManager.implementation));
  });

  it.each(deployments)("chain %i returns checksummed, non-zero addresses", (chainId) => {
    const { startBlock, ...addresses } = getProtocolAddresses(chainId);
    expect(startBlock >= 0n).toBe(true);
    for (const address of Object.values(addresses)) {
      expect(isAddress(address, { strict: true })).toBe(true);
      expect(address).not.toBe("0x0000000000000000000000000000000000000000");
    }
  });

  it("the mainnet fork uses mainnet USDC, not a mock", () => {
    expect(getProtocolAddresses(31338).usdc).toBe("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
  });

  // Chain id 1 is the dangerous one: the fork runs on 31338 precisely so that mainnet is never
  // mistaken for it, and no mainnet deployment exists.
  it.each([1, 0, -1, 31336, 31339, 11155111, Number.NaN])("chain %s throws UnsupportedChainError", (chainId) => {
    expect(() => getProtocolAddresses(chainId)).toThrow(UnsupportedChainError);
  });

  it("the error carries the requested chain id", () => {
    try {
      getProtocolAddresses(1);
      expect.unreachable();
    } catch (error) {
      expect(error).toBeInstanceOf(UnsupportedChainError);
      expect((error as UnsupportedChainError).chainId).toBe(1);
    }
  });
});
