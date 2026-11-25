// A fake node for the pipeline tests: blocks and logs kept in memory, served through a viem custom
// transport (eth_getBlockByNumber, eth_getLogs). Tests change it between calls to simulate reorgs.
import { indexAbi, indexManagerAbi } from "@oam/abi";
import {
  createPublicClient,
  custom,
  encodeAbiParameters,
  encodeEventTopics,
  hexToBigInt,
  numberToHex,
  type Address,
  type Hex,
  type Log,
  type PublicClient,
} from "viem";

export const hash = (byte: string): Hex => `0x${byte.repeat(32)}`;

export type FakeBlock = { hash: Hex; parentHash: Hex; timestamp: bigint };

/** The eth_getLogs filter as viem sends it. */
export type LogFilter = { fromBlock: Hex; toBlock: Hex; address?: Address | Address[] };

export class FakeChain {
  readonly blocks = new Map<bigint, FakeBlock>();
  logs: Log[] = [];
  readonly calls: { method: string; params: unknown[] }[] = [];

  /** Adds block n with the given hash byte; its parent is block n − 1 if present, else a fixed hash. */
  addBlock(number: bigint, hashByte: string, timestamp = 1_700_000_000n + number * 12n): FakeBlock {
    const parent = this.blocks.get(number - 1n);
    const block = { hash: hash(hashByte), parentHash: parent?.hash ?? hash("00"), timestamp };
    this.blocks.set(number, block);
    return block;
  }

  client(): PublicClient {
    return createPublicClient({
      transport: custom({
        request: ({ method, params }: { method: string; params: unknown[] }) => {
          this.calls.push({ method, params });
          if (method === "eth_getBlockByNumber") return Promise.resolve(this.rpcBlock(hexToBigInt(params[0] as Hex)));
          if (method === "eth_getLogs") return Promise.resolve(this.rpcLogs(params[0] as LogFilter));
          return Promise.reject(new Error(`FakeChain: unexpected ${method}`));
        },
      }),
    });
  }

  count(method: string): number {
    return this.calls.filter((call) => call.method === method).length;
  }

  private rpcBlock(number: bigint): Record<string, unknown> | null {
    const block = this.blocks.get(number);
    if (block === undefined) return null;
    return { number: numberToHex(number), hash: block.hash, parentHash: block.parentHash, timestamp: numberToHex(block.timestamp), transactions: [] };
  }

  /** Like a real node: logs of the requested range, and only from the requested addresses when a filter is given. */
  private rpcLogs(filter: LogFilter): Record<string, unknown>[] {
    const from = hexToBigInt(filter.fromBlock);
    const to = hexToBigInt(filter.toBlock);
    const addresses =
      filter.address === undefined ? undefined : new Set((Array.isArray(filter.address) ? filter.address : [filter.address]).map((a) => a.toLowerCase()));
    return this.logs
      .filter((log) => log.blockNumber !== null && log.blockNumber >= from && log.blockNumber <= to)
      .filter((log) => addresses === undefined || addresses.has(log.address.toLowerCase()))
      .map((log) => ({
        address: log.address,
        topics: log.topics,
        data: log.data,
        blockNumber: numberToHex(log.blockNumber ?? 0n),
        blockHash: log.blockHash,
        transactionHash: log.transactionHash,
        transactionIndex: numberToHex(log.transactionIndex ?? 0),
        logIndex: numberToHex(log.logIndex ?? 0),
        removed: false,
      }));
  }
}

type LogPosition = { blockNumber: bigint; blockHash: Hex; txHash: Hex; logIndex: number };

/** A raw ERC-20 Transfer of Index shares, as viem returns it from getLogs. */
export function transferLog(address: Address, at: LogPosition, from: Address, to: Address, value: bigint): Log {
  return {
    address,
    topics: encodeEventTopics({ abi: indexAbi, eventName: "Transfer", args: { from, to } }) as [Hex, ...Hex[]],
    data: encodeAbiParameters([{ type: "uint256" }], [value]),
    blockNumber: at.blockNumber,
    blockHash: at.blockHash,
    transactionHash: at.txHash,
    transactionIndex: 0,
    logIndex: at.logIndex,
    removed: false,
  };
}

export type IndexCreatedArgs = {
  indexAddress: Address;
  asset0: Address;
  asset1: Address;
  asset0Weight: bigint;
  asset1Weight: bigint;
  feePercentage: bigint;
  assetManager: Address;
};

/** A raw IndexCreated of the IndexManager: indexed parameters in the topics, the others ABI-encoded in data. */
export function indexCreatedLog(indexManager: Address, at: LogPosition, args: IndexCreatedArgs): Log {
  const event = indexManagerAbi.find((item) => item.type === "event" && item.name === "IndexCreated");
  if (event === undefined || event.type !== "event") throw new Error("IndexCreated missing from indexManagerAbi");
  const nonIndexed = event.inputs.filter((input) => !input.indexed);
  const values = nonIndexed.map((input) => args[input.name as keyof IndexCreatedArgs]);
  return {
    address: indexManager,
    topics: encodeEventTopics({ abi: indexManagerAbi, eventName: "IndexCreated", args }) as [Hex, ...Hex[]],
    data: encodeAbiParameters(nonIndexed, values),
    blockNumber: at.blockNumber,
    blockHash: at.blockHash,
    transactionHash: at.txHash,
    transactionIndex: 0,
    logIndex: at.logIndex,
    removed: false,
  };
}

/** A raw log whose topic0 matches no protocol event. */
export function strangerLog(address: Address, at: LogPosition): Log {
  return {
    address,
    topics: [hash("ee")],
    data: "0x",
    blockNumber: at.blockNumber,
    blockHash: at.blockHash,
    transactionHash: at.txHash,
    transactionIndex: 0,
    logIndex: at.logIndex,
    removed: false,
  };
}
