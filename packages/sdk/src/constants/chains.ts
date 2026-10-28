import { ANVIL_CHAIN_ID, MAINNET_FORK_CHAIN_ID } from "@oam/abi";
import { defineChain } from "viem";
import { anvil } from "viem/chains";

export { ANVIL_CHAIN_ID, MAINNET_FORK_CHAIN_ID, anvil };

// `make anvil-fork` runs the mainnet fork with its own chain id, so wallets never mistake it for mainnet.
export const mainnetFork = defineChain({
  id: MAINNET_FORK_CHAIN_ID,
  name: "Mainnet fork",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["http://127.0.0.1:8545"] } },
});

export const supportedChains = [anvil, mainnetFork] as const;
