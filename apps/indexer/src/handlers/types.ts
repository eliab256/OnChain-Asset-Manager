// Types shared by the handlers and the pipeline that calls them (indexer.md §3, "Dispatch degli handler").
// They live here, under the pipeline, so that a handler never imports pipeline.ts (layers only look down).
import type { ContractKind } from "@oam/db";
import type { PublicClient } from "viem";
import type { BlockHeader } from "../chain/blocks.js";
import type { ChainLog, DecodedLog } from "../chain/logs.js";
import type { Db } from "../repositories/db.js";

export type EventName = DecodedLog["eventName"];
export type LogOf<E extends EventName> = Extract<DecodedLog, { eventName: E }>;

/** A contract a handler added to Contract while processing the block (today only an Index from IndexCreated). */
export type AddedContract = { address: string; kind: ContractKind };

/** What a handler receives: the block's transaction, the event and the context of the block. */
export type HandlerContext<E extends EventName> = {
  /** The transaction of the block: every write of the handler goes through it. */
  db: Db;
  chainId: number;
  /** For reads of contract state, always at block.number (chain/reads.ts). */
  client: PublicClient;
  block: BlockHeader;
  log: LogOf<E>;
  /** Every log of the same transaction, in logIndex order, this one included. */
  txLogs: readonly ChainLog[];
};

export type HandlerResult = { addedContracts?: readonly AddedContract[] } | undefined;

/** The handler of one event. */
export type Handler<E extends EventName> = {
  /** Contract kinds the event is expected from. From any other emitter the handler is not called. */
  kinds: readonly ContractKind[];
  handle: (context: HandlerContext<E>) => Promise<HandlerResult>;
};

/** Handlers by event name. An event without a handler is only stored in RawEvent. */
export type HandlerMap = { [E in EventName]?: Handler<E> };
