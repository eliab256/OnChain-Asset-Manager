// Union of the events emitted by the protocol contracts the indexer listens to.
// IndexFactory and SwapManager emit nothing of their own (SwapManager only the proxy events, which are here
// through the other UUPS proxies). Upgraded and Initialized of the ERC1967 proxies come with the UUPS ABIs.
import {
  indexAbi,
  indexManagerAbi,
  multiSigWalletAbi,
  priceFeedManagerAbi,
  routerAbi,
  swapManagerAbi,
  timelockControllerAbi,
} from "@oam/abi";
import { toEventSelector, type Hex } from "viem";

/** The ABIs merged into protocolEventsAbi. Exported for the test that checks the duplicates. */
export const sourceAbis = [
  indexAbi,
  indexManagerAbi,
  routerAbi,
  priceFeedManagerAbi,
  swapManagerAbi,
  multiSigWalletAbi,
  timelockControllerAbi,
] as const;

type SourceItem = (typeof sourceAbis)[number][number];

/** Every event of the protocol ABIs, as a viem-typed union discriminated by `name`. */
export type ProtocolEventAbiItem = Extract<SourceItem, { type: "event" }>;

function isEvent(item: SourceItem): item is ProtocolEventAbiItem {
  return item.type === "event";
}

/**
 * Event-only ABI, deduplicated by topic0. The same event appears in several ABIs with the same
 * signature (RoleGranted in IndexManager and Timelock, Upgraded and Initialized in every proxy):
 * the first copy is enough to decode it.
 */
export const protocolEventsAbi: readonly ProtocolEventAbiItem[] = (() => {
  const seen = new Set<string>();
  const events: ProtocolEventAbiItem[] = [];
  for (const abi of sourceAbis) {
    for (const item of abi) {
      if (!isEvent(item)) continue;
      const selector = toEventSelector(item);
      if (seen.has(selector)) continue;
      seen.add(selector);
      events.push(item);
    }
  }
  return events;
})();

/** The same events keyed by topic0, to find the definition of a decoded log (its inputs and their types). */
export const protocolEventsByTopic0: ReadonlyMap<Hex, ProtocolEventAbiItem> = new Map(
  protocolEventsAbi.map((event) => [toEventSelector(event), event]),
);
