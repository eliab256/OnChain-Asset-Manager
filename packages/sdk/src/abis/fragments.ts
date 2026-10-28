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
import { parseAbi, type Abi } from "viem";

function errorsOf<const abi extends Abi>(abi: abi) {
  return abi.filter(
    (item): item is Extract<abi[number], { type: "error" }> => item.type === "error",
  );
}

/**
 * Every custom error of the protocol. A call to the Router can revert inside the Index or the
 * PriceFeedManager, and viem decodes a revert only if the error is in the ABI it was given.
 */
export const protocolErrorsAbi = [
  ...errorsOf(routerAbi),
  ...errorsOf(indexAbi),
  ...errorsOf(indexManagerAbi),
  ...errorsOf(indexFactoryAbi),
  ...errorsOf(priceFeedManagerAbi),
  ...errorsOf(swapManagerAbi),
  ...errorsOf(multiSigWalletAbi),
  ...errorsOf(timelockControllerAbi),
];

export const routerWithErrorsAbi = [...routerAbi, ...protocolErrorsAbi];
export const indexManagerWithErrorsAbi = [...indexManagerAbi, ...protocolErrorsAbi];
export const indexWithErrorsAbi = [...indexAbi, ...protocolErrorsAbi];
export const multiSigWalletWithErrorsAbi = [...multiSigWalletAbi, ...protocolErrorsAbi];
export const priceFeedManagerWithErrorsAbi = [...priceFeedManagerAbi, ...protocolErrorsAbi];

/** Chainlink feed, only what the SDK reads. */
export const aggregatorV3Abi = parseAbi([
  "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)",
]);

/** EIP-2612 and ERC-5267 reads of a permit token. Mainnet USDC has `version()` but no `eip712Domain()`. */
export const permitTokenAbi = parseAbi([
  "function nonces(address owner) view returns (uint256)",
  "function version() view returns (string)",
  "function eip712Domain() view returns (bytes1 fields, string name, string version, uint256 chainId, address verifyingContract, bytes32 salt, uint256[] extensions)",
]);
