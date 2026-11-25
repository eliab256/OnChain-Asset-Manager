// Handlers of the IndexManager events (indexer.md §5). For now only the minimal IndexCreated of roadmap
// step 4: the Contract row that makes the indexer listen to the new Index. Index and Token rows come with step 6.
import { ContractKind } from "@oam/db";
import { insertIndexContract } from "../repositories/contracts.js";
import type { Handler } from "./types.js";

/**
 * IndexCreated: registers the new Index in Contract (kind INDEX, startBlock = block of creation) and returns it
 * in addedContracts, so the pipeline dispatches its events from the same block on. Its logs of the current chunk
 * are already requested by processRange, which reads indexAddress from this same event (indexer.md §4).
 * Processing the block again inserts nothing and returns the same contract.
 */
export const indexCreated: Handler<"IndexCreated"> = {
  kinds: [ContractKind.INDEX_MANAGER],
  async handle({ db, chainId, block, log }) {
    await insertIndexContract(db, chainId, log.args.indexAddress, block.number);
    return { addedContracts: [{ address: log.args.indexAddress, kind: ContractKind.INDEX }] };
  },
};
