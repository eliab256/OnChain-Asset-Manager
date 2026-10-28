import {
  indexAbi,
  indexFactoryAbi,
  indexManagerAbi,
  multiSigWalletAbi,
  priceFeedManagerAbi,
  routerAbi,
  swapManagerAbi,
  timelockControllerAbi,
} from "@oam/abi";
import { toFunctionSelector, type Abi } from "viem";
import { describe, expect, it } from "vitest";
import {
  aggregatorV3Abi,
  indexManagerWithErrorsAbi,
  indexWithErrorsAbi,
  permitTokenAbi,
  protocolErrorsAbi,
  routerWithErrorsAbi,
} from "./fragments.js";

const protocolAbis = {
  routerAbi,
  indexAbi,
  indexManagerAbi,
  indexFactoryAbi,
  priceFeedManagerAbi,
  swapManagerAbi,
  multiSigWalletAbi,
  timelockControllerAbi,
} as const;

type AbiError = Extract<Abi[number], { type: "error" }>;

/** Canonical `Name(type,...)`: protocol errors have no tuple parameters, so the types are flat. */
function toSignature(item: AbiError): string {
  return `${item.name}(${item.inputs.map((input) => input.type).join(",")})`;
}

function errorSignatures(abi: Abi): Set<string> {
  return new Set(abi.filter((item): item is AbiError => item.type === "error").map((item) => toSignature(item)));
}

describe("protocolErrorsAbi", () => {
  it("contains only errors", () => {
    expect(protocolErrorsAbi.length).toBeGreaterThan(0);
    expect(protocolErrorsAbi.every((item) => item.type === "error")).toBe(true);
  });

  it.each(Object.entries(protocolAbis))("contains every error of %s", (_name, abi) => {
    const all = errorSignatures(protocolErrorsAbi);
    for (const signature of errorSignatures(abi)) expect(all).toContain(signature);
  });

  it("contains nothing that is not in a protocol ABI", () => {
    const union = new Set(Object.values(protocolAbis).flatMap((abi) => [...errorSignatures(abi)]));
    expect(errorSignatures(protocolErrorsAbi)).toEqual(union);
  });

  // An error name reused with different parameters would make decoding by name ambiguous.
  it("no error name maps to two different signatures", () => {
    const byName = new Map<string, string>();
    for (const item of protocolErrorsAbi) {
      const signature = toSignature(item);
      expect(byName.get(item.name) ?? signature).toBe(signature);
      byName.set(item.name, signature);
    }
  });

  it("includes the errors a Router call can hit inside the Index and the PriceFeedManager", () => {
    const names = new Set(protocolErrorsAbi.map((item) => item.name));
    for (const name of [
      "Router__InvalidTolerance",
      "Router__InvalidAmounts",
      "Router__InsufficientUsdcBalance",
      "Index__ToleranceExceeded",
      "Index__NotInitialized",
      "PriceFeedManager__PriceIsStale",
      "ERC2612ExpiredSignature",
      "ERC2612InvalidSigner",
      "ERC20InsufficientAllowance",
    ]) {
      expect(names).toContain(name);
    }
  });
});

describe("ABIs merged with the protocol errors", () => {
  const merged = [
    ["routerWithErrorsAbi", routerWithErrorsAbi, routerAbi],
    ["indexManagerWithErrorsAbi", indexManagerWithErrorsAbi, indexManagerAbi],
    ["indexWithErrorsAbi", indexWithErrorsAbi, indexAbi],
  ] as const;

  it.each(merged)("%s keeps every item of the contract ABI and adds every protocol error", (_name, full, base) => {
    const signatures = new Set((full as Abi).map((item) => JSON.stringify(item)));
    for (const item of base) expect(signatures).toContain(JSON.stringify(item));
    expect(errorSignatures(full as Abi)).toEqual(errorSignatures(protocolErrorsAbi));
  });

  it.each(merged)("%s adds no function, event or constructor", (_name, full, base) => {
    const nonErrors = (abi: Abi) => abi.filter((item) => item.type !== "error").map((item) => JSON.stringify(item));
    expect(nonErrors(full as Abi)).toEqual(nonErrors(base as Abi));
  });
});

describe("hand-written fragments", () => {
  // Selectors from the standards (Chainlink AggregatorV3Interface, EIP-2612, ERC-5267).
  it("latestRoundData has the Chainlink selector and five outputs", () => {
    const [item] = aggregatorV3Abi;
    expect(toFunctionSelector(item)).toBe("0xfeaf968c");
    expect(item.outputs.map((output) => output.type)).toEqual(["uint80", "int256", "uint256", "uint256", "uint80"]);
  });

  it("permit token reads: nonces(address), version(), eip712Domain()", () => {
    const selectors = Object.fromEntries(permitTokenAbi.map((item) => [item.name, toFunctionSelector(item)]));
    expect(selectors).toEqual({ nonces: "0x7ecebe00", version: "0x54fd4d50", eip712Domain: "0x84b0196e" });
    expect(permitTokenAbi.every((item) => item.stateMutability === "view")).toBe(true);
  });
});
