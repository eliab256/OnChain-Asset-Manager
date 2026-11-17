// Contract reads at a given block. `blockNumber` is required by the types: a handler reads the state
// of the block it is processing, never `latest`, so reprocessing a block gives the same result
// (apps/indexer/indexer.md §3).
import type {
  Abi,
  Chain,
  ContractFunctionArgs,
  ContractFunctionName,
  MulticallParameters,
  MulticallReturnType,
  PublicClient,
  ReadContractParameters,
  ReadContractReturnType,
  Transport,
} from "viem";

type AtBlock = { blockNumber: bigint; blockTag?: never };

/**
 * `readContract` pinned to a block.
 * @param parameters viem readContract parameters with a mandatory blockNumber.
 */
export function readContractAt<
  const abi extends Abi | readonly unknown[],
  functionName extends ContractFunctionName<abi, "pure" | "view">,
  const args extends ContractFunctionArgs<abi, "pure" | "view", functionName>,
>(
  client: PublicClient<Transport, Chain>,
  parameters: ReadContractParameters<abi, functionName, args> & AtBlock,
): Promise<ReadContractReturnType<abi, functionName, args>> {
  // tsc cannot see that the intersection still satisfies viem's conditional parameter type; the type-aware
  // linter can, hence the disable.
  // oxlint-disable-next-line typescript/no-unnecessary-type-assertion
  return client.readContract(parameters as ReadContractParameters<abi, functionName, args>);
}

/**
 * `multicall` pinned to a block. Always deployless: the aggregator bytecode is sent inside the eth_call,
 * so it works on pure anvil (no Multicall3 deployed) and at any block of the fork.
 * Failures stay per call (`allowFailure` defaults to true), so one reverting feed does not hide the others.
 * @param parameters viem multicall parameters with a mandatory blockNumber.
 */
export function multicallAt<const contracts extends readonly unknown[], allowFailure extends boolean = true>(
  client: PublicClient<Transport, Chain>,
  parameters: Omit<MulticallParameters<contracts, allowFailure>, "deployless" | "multicallAddress"> & AtBlock,
): Promise<MulticallReturnType<contracts, allowFailure>> {
  return client.multicall({ ...parameters, deployless: true });
}
