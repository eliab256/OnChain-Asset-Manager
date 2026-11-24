// Contract: the addresses the indexer listens to, with their kind (indexer.md §3, "Dispatch degli handler").
import { ContractKind } from "@oam/db";
import type { Db } from "./db.js";

/**
 * The fixed contracts of a deployment, as `protocolAddresses[chainId]` of @oam/abi gives them.
 * IndexFactory (no events) and USDC (not a protocol contract) are left out on purpose.
 */
export type FixedContracts = {
  indexManager: string;
  router: string;
  priceFeedManager: string;
  swapManager: string;
  multiSigWallet: string;
  timelock: string;
  startBlock: bigint;
};

const FIXED_KINDS = {
  indexManager: ContractKind.INDEX_MANAGER,
  router: ContractKind.ROUTER,
  priceFeedManager: ContractKind.PRICE_FEED_MANAGER,
  swapManager: ContractKind.SWAP_MANAGER,
  multiSigWallet: ContractKind.MULTISIG_WALLET,
  timelock: ContractKind.TIMELOCK,
} as const satisfies Record<Exclude<keyof FixedContracts, "startBlock">, ContractKind>;

/**
 * Inserts the fixed contracts of a chain (bootstrap, indexer.md §4), all with the deployment's startBlock.
 * Rows that already exist are left as they are, so the bootstrap can run at every start.
 * @returns How many rows were inserted (0 from the second start on).
 */
export async function insertFixedContracts(db: Db, chainId: number, fixed: FixedContracts): Promise<number> {
  const data = Object.entries(FIXED_KINDS).map(([key, kind]) => ({
    chainId,
    address: fixed[key as keyof typeof FIXED_KINDS].toLowerCase(),
    kind,
    startBlock: fixed.startBlock,
  }));
  const { count } = await db.contract.createMany({ data, skipDuplicates: true });
  return count;
}

/**
 * Inserts an Index discovered through IndexCreated.
 * @param startBlock The block of IndexCreated.
 * @returns true if the row was inserted, false if the Index was already known.
 */
export async function insertIndexContract(db: Db, chainId: number, address: string, startBlock: bigint): Promise<boolean> {
  const { count } = await db.contract.createMany({
    data: [{ chainId, address: address.toLowerCase(), kind: ContractKind.INDEX, startBlock }],
    skipDuplicates: true,
  });
  return count === 1;
}

/**
 * Reads every contract of a chain: the addresses to pass to getLogs and the kind of each emitter.
 * @returns Lowercase address → kind.
 */
export async function loadContractKinds(db: Db, chainId: number): Promise<Map<string, ContractKind>> {
  const rows = await db.contract.findMany({ where: { chainId }, select: { address: true, kind: true } });
  return new Map(rows.map((row) => [row.address, row.kind]));
}
