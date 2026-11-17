// Fetches the logs of the protocol contracts and turns them into normalized, decoded events.
// This layer does not know the database: a log that cannot be decoded is returned as "unknown"
// and the pipeline decides what to write (an IndexerError row).
import {
  BaseError,
  decodeEventLog,
  isAddress,
  type AbiParameter,
  type Address,
  type DecodeEventLogReturnType,
  type Hex,
  type Log,
  type PublicClient,
} from "viem";
import { protocolEventsAbi, protocolEventsByTopic0 } from "./abi.js";

/** Position of a log on the chain. Addresses and hashes are lowercase. */
export type LogLocation = {
  address: Address;
  blockNumber: bigint;
  blockHash: Hex;
  txHash: Hex;
  logIndex: number;
};

type DecodedProtocolEvent = DecodeEventLogReturnType<typeof protocolEventsAbi>;

/**
 * A decoded protocol event, discriminated by `eventName`. `args` keeps the viem types
 * (uint/int as bigint), with every address in lowercase.
 */
export type DecodedLog = LogLocation & {
  kind: "decoded";
} & { [E in DecodedProtocolEvent as E["eventName"]]: { eventName: E["eventName"]; args: E["args"] } }[DecodedProtocolEvent["eventName"]];

/** A log from a protocol address that matches no event of the protocol ABIs. Raw data kept for IndexerError. */
export type UnknownLog = LogLocation & {
  kind: "unknown";
  topics: readonly Hex[];
  data: Hex;
  /** Why decoding failed: the viem error name, e.g. AbiEventSignatureNotFoundError. */
  reason: string;
  /** What did not match, from viem's short message (e.g. the expected data size). */
  detail: string;
};

export type ChainLog = DecodedLog | UnknownLog;

/** Thrown when the node returns a log without its position (pending log): getLogs on a mined range never should. */
export class IncompleteLogError extends Error {
  constructor(log: Log) {
    super(`Log without block or transaction position from ${log.address}`);
    this.name = "IncompleteLogError";
  }
}

/**
 * Lowercases a decoded value according to its ABI type: `address`, arrays of addresses and addresses
 * inside tuples. Any other type is returned as it is, even a string that looks like an address.
 */
function normalizeValue(param: AbiParameter, value: unknown): unknown {
  const array = /^(.*)\[\d*\]$/.exec(param.type);
  if (array !== null) {
    if (!Array.isArray(value)) return value;
    const element: AbiParameter = { ...param, type: array[1] ?? "" };
    return value.map((inner) => normalizeValue(element, inner));
  }
  if (param.type === "address") return typeof value === "string" ? value.toLowerCase() : value;
  if (param.type === "tuple" && "components" in param) {
    return normalizeArgs(param.components, value);
  }
  return value;
}

/**
 * Lowercases the addresses of decoded arguments, guided by the ABI inputs. viem returns named
 * arguments as an object and unnamed ones as an array (by position): both shapes are handled.
 * @param inputs The ABI inputs of the event (or the components of a tuple).
 * @param args The arguments as decoded by viem.
 */
export function normalizeArgs(inputs: readonly AbiParameter[], args: unknown): unknown {
  if (Array.isArray(args)) {
    const positional: readonly unknown[] = args;
    return positional.map((value, i) => (inputs[i] === undefined ? value : normalizeValue(inputs[i], value)));
  }
  if (args === null || typeof args !== "object") return args;
  const named = args as Record<string, unknown>;
  return Object.fromEntries(
    Object.entries(named).map(([key, value]) => {
      const input = inputs.find((candidate) => candidate.name === key);
      return [key, input === undefined ? value : normalizeValue(input, value)];
    }),
  );
}

function locate(log: Log): LogLocation {
  if (log.blockNumber === null || log.blockHash === null || log.transactionHash === null || log.logIndex === null) {
    throw new IncompleteLogError(log);
  }
  return {
    address: log.address.toLowerCase() as Address,
    blockNumber: log.blockNumber,
    blockHash: log.blockHash.toLowerCase() as Hex,
    txHash: log.transactionHash.toLowerCase() as Hex,
    logIndex: log.logIndex,
  };
}

/**
 * Decodes one raw log against the protocol ABIs. Never throws on unknown data: a log that does not
 * decode comes back with `kind: "unknown"`.
 */
export function decodeLog(log: Log): ChainLog {
  const location = locate(log);
  try {
    const decoded = decodeEventLog({ abi: protocolEventsAbi, topics: log.topics, data: log.data, strict: true });
    // decodeEventLog matched topic0, so the definition is in the map: it gives the type of each argument.
    const event = log.topics[0] === undefined ? undefined : protocolEventsByTopic0.get(log.topics[0]);
    return {
      ...location,
      kind: "decoded",
      eventName: decoded.eventName,
      args: event === undefined ? decoded.args : normalizeArgs(event.inputs, decoded.args),
    } as DecodedLog;
  } catch (error) {
    return {
      ...location,
      kind: "unknown",
      topics: log.topics,
      data: log.data,
      reason: error instanceof Error ? error.name : String(error),
      detail: error instanceof BaseError ? error.shortMessage : error instanceof Error ? error.message : String(error),
    };
  }
}

/** Thrown before calling the node when the address filter contains something that is not an address. */
export class InvalidAddressFilterError extends Error {
  constructor(readonly value: unknown) {
    super(`Invalid address in the getLogs filter: ${String(value)}`);
    this.name = "InvalidAddressFilterError";
  }
}

/** Orders logs as the chain does: by block, then by position in the block. */
export function compareLogs(a: LogLocation, b: LogLocation): number {
  if (a.blockNumber !== b.blockNumber) return a.blockNumber < b.blockNumber ? -1 : 1;
  return a.logIndex - b.logIndex;
}

/**
 * Logs emitted by `addresses` in [fromBlock, toBlock], decoded and sorted by (block, logIndex).
 * The caller chooses the range size (BATCH_SIZE): this function makes exactly one eth_getLogs call.
 * @param addresses Contracts to listen to; an empty list returns no logs without calling the node.
 * @throws InvalidAddressFilterError if an entry is not an address. viem drops an undefined entry and the node
 *   then returns the logs of every contract (mock token Transfers included), so the list is checked here.
 */
export async function fetchLogs(
  client: PublicClient,
  addresses: readonly Address[],
  fromBlock: bigint,
  toBlock: bigint,
): Promise<ChainLog[]> {
  for (const address of addresses as readonly unknown[]) {
    if (typeof address !== "string" || !isAddress(address, { strict: false })) throw new InvalidAddressFilterError(address);
  }
  if (addresses.length === 0 || fromBlock > toBlock) return [];
  const logs = await client.getLogs({ address: [...addresses], fromBlock, toBlock });
  return logs.map(decodeLog).sort(compareLogs);
}
