import { getAddress, type Address } from "viem";
import anvilDeployment from "../../../deployments/31337.json" with { type: "json" };
import forkDeployment from "../../../deployments/31338.json" with { type: "json" };

// Addresses come from deployments/<chainId>.json, written by the Foundry deploy scripts.
// Redeploy with `make deploy-anvil` / `make deploy-fork` instead of editing them here.

export const ANVIL_CHAIN_ID = 31337;
export const MAINNET_FORK_CHAIN_ID = 31338;

export const supportedChainIds = [ANVIL_CHAIN_ID, MAINNET_FORK_CHAIN_ID] as const;
export type SupportedChainId = (typeof supportedChainIds)[number];

/** Proxy addresses only: an implementation behind a proxy has no storage and must never be called. */
export type ProtocolAddresses = {
  indexManager: Address;
  indexFactory: Address;
  router: Address;
  priceFeedManager: Address;
  swapManager: Address;
  usdc: Address;
  multiSigWallet: Address;
  timelock: Address;
  /** Block of the deployment, where an indexer starts reading logs. */
  startBlock: bigint;
};

/** The subset of the deployment file the packages rely on. */
type DeploymentFile = {
  startBlock: number;
  indexManager: string;
  indexFactory: string;
  timelock: string;
  router: { proxy: string };
  priceFeedManager: { proxy: string };
  swapManager: { proxy: string };
  multiSigWallet: { address: string };
  config: { usdc: string };
};

function toProtocolAddresses(deployment: DeploymentFile): ProtocolAddresses {
  return {
    indexManager: getAddress(deployment.indexManager),
    indexFactory: getAddress(deployment.indexFactory),
    router: getAddress(deployment.router.proxy),
    priceFeedManager: getAddress(deployment.priceFeedManager.proxy),
    swapManager: getAddress(deployment.swapManager.proxy),
    usdc: getAddress(deployment.config.usdc),
    multiSigWallet: getAddress(deployment.multiSigWallet.address),
    timelock: getAddress(deployment.timelock),
    startBlock: BigInt(deployment.startBlock),
  };
}

export const protocolAddresses: Readonly<Record<SupportedChainId, ProtocolAddresses>> = {
  [ANVIL_CHAIN_ID]: toProtocolAddresses(anvilDeployment),
  [MAINNET_FORK_CHAIN_ID]: toProtocolAddresses(forkDeployment),
};

export function isSupportedChainId(chainId: number): chainId is SupportedChainId {
  return (supportedChainIds as readonly number[]).includes(chainId);
}
