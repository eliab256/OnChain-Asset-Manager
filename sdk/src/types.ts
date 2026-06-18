import type { PublicClient, Address, Hex } from "viem";

export interface RouterConfig {
  publicClient: PublicClient;
  routerAddress: Address;
  indexManagerAddress: Address;
  usdcAddress: Address;
}

/**
 * Struct: IndexAsset
 */
export type IndexAsset = {
  asset: Address;
  weightPercentage: bigint;
  priceFeed: Address;
};

/**
 * Enum: AssetAvailable
 */
export type AssetAvailable = "WETH" | "WBTC" | "LINK" | "COMP";

/**
 * Struct: Transaction
 */
export type Transaction = {
  target: Address;
  value: bigint;
  data: Hex;
  executed: boolean;
  confirmations: bigint;
};
