// Every handler of the indexer, by event name. An event missing here is only stored in RawEvent.
import { indexCreated } from "./indexManager.js";
import type { HandlerMap } from "./types.js";

export const handlers: HandlerMap = {
  IndexCreated: indexCreated,
};
