import { toEventSelector, type AbiEvent } from "viem";
import { describe, expect, it } from "vitest";
import { protocolEventsAbi, sourceAbis } from "./abi.js";

/** Every copy of every event in the source ABIs, grouped by topic0. */
function copiesByTopic0(): Map<string, AbiEvent[]> {
  const groups = new Map<string, AbiEvent[]>();
  for (const abi of sourceAbis) {
    for (const item of abi) {
      if (item.type !== "event") continue;
      const selector = toEventSelector(item);
      groups.set(selector, [...(groups.get(selector) ?? []), item]);
    }
  }
  return groups;
}

/** What the decoder depends on beyond topic0: which inputs are indexed, and their names. */
function layout(event: AbiEvent): string {
  return JSON.stringify(event.inputs.map((input) => [input.name, input.type, input.indexed === true]));
}

describe("protocolEventsAbi deduplication", () => {
  it("drops only true duplicates: same topic0 means same indexed layout and names", () => {
    // topic0 hashes name and types but not `indexed`: ERC-20 and ERC-721 Transfer share it.
    // Keeping only the first copy is safe only if every copy decodes the same way.
    for (const [selector, copies] of copiesByTopic0()) {
      const layouts = new Set(copies.map(layout));
      expect(layouts.size, `${copies[0]?.name ?? selector} has copies with different indexed inputs or names`).toBe(1);
    }
  });

  it("keeps one entry for each distinct topic0 of the source ABIs", () => {
    expect(protocolEventsAbi).toHaveLength(copiesByTopic0().size);
  });

  it("catches a copy with different indexed inputs", () => {
    const erc20Transfer = {
      type: "event",
      name: "Transfer",
      inputs: [
        { name: "from", type: "address", indexed: true },
        { name: "to", type: "address", indexed: true },
        { name: "value", type: "uint256", indexed: false },
      ],
    } as const satisfies AbiEvent;
    const erc721Transfer = {
      ...erc20Transfer,
      inputs: [erc20Transfer.inputs[0], erc20Transfer.inputs[1], { name: "value", type: "uint256", indexed: true }],
    } as const satisfies AbiEvent;

    expect(toEventSelector(erc20Transfer)).toBe(toEventSelector(erc721Transfer));
    expect(layout(erc20Transfer)).not.toBe(layout(erc721Transfer));
  });
});
