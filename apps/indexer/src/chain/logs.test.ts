import {
  createPublicClient,
  custom,
  encodeAbiParameters,
  encodeEventTopics,
  getAddress,
  numberToHex,
  toEventSelector,
  type AbiEvent,
  type AbiParameter,
  type Address,
  type Hex,
  type Log,
} from "viem";
import { describe, expect, it } from "vitest";
import { protocolEventsAbi } from "./abi.js";
import {
  compareLogs,
  decodeLog,
  fetchLogs,
  IncompleteLogError,
  InvalidAddressFilterError,
  normalizeArgs,
  type ChainLog,
} from "./logs.js";

const CHECKSUMMED: Address = getAddress("0xabcdef0123456789abcdef0123456789abcdef01");
const BLOCK_HASH = "0xAA00000000000000000000000000000000000000000000000000000000000001" as Hex;
const TX_HASH = "0xBB00000000000000000000000000000000000000000000000000000000000002" as Hex;

/** A deterministic, valid value for an ABI parameter. Addresses are checksummed on purpose. */
function sampleValue(param: AbiParameter, seed: number): unknown {
  const arrayMatch = /^(.*)\[(\d*)\]$/.exec(param.type);
  if (arrayMatch !== null) {
    const inner: AbiParameter = { ...param, type: arrayMatch[1] ?? "" };
    const length = arrayMatch[2] === "" ? 2 : Number(arrayMatch[2]);
    return Array.from({ length }, (_, i) => sampleValue(inner, seed + i + 1));
  }
  if (param.type === "tuple") {
    const components = (param as { components: readonly AbiParameter[] }).components;
    return Object.fromEntries(components.map((c, i) => [c.name ?? String(i), sampleValue(c, seed + i + 1)]));
  }
  if (param.type === "address") return CHECKSUMMED;
  if (param.type === "bool") return seed % 2 === 0;
  if (param.type === "string") return `value-${seed}`;
  if (param.type === "bytes") return "0xdeadbeef";
  if (param.type.startsWith("bytes")) {
    const size = Number(param.type.slice(5));
    return numberToHex(seed + 1, { size });
  }
  // viem decodes integers up to 48 bits as number, wider ones as bigint.
  const intMatch = /^(u?)int(\d*)$/.exec(param.type);
  if (intMatch !== null) {
    const bits = intMatch[2] === "" ? 256 : Number(intMatch[2]);
    const signed = intMatch[1] === "";
    if (bits <= 48) return signed ? -(seed + 1) : seed + 1;
    return signed ? -BigInt(seed + 1) : BigInt(seed + 1) * 1_000_000_000_000n;
  }
  throw new Error(`no sample for ABI type ${param.type}`);
}

/** Encodes a raw log for `event` with sample args, as eth_getLogs would return it. */
function rawLog(event: AbiEvent, overrides: Partial<Log> = {}): { log: Log; args: Record<string, unknown> } {
  const args = Object.fromEntries(event.inputs.map((input, i) => [input.name ?? String(i), sampleValue(input, i)]));
  const indexed = event.inputs.filter((i) => i.indexed === true);
  const notIndexed = event.inputs.filter((i) => i.indexed !== true);
  const topicArgs: Record<string, unknown> = Object.fromEntries(
    indexed.map((i): [string, unknown] => [i.name ?? "", args[i.name ?? ""]]),
  );
  const topics = encodeEventTopics({ abi: [event], eventName: event.name, args: topicArgs });
  const data = encodeAbiParameters(
    notIndexed,
    notIndexed.map((i): unknown => args[i.name ?? ""]),
  );
  const log = {
    address: CHECKSUMMED,
    topics: topics as [Hex, ...Hex[]],
    data,
    blockNumber: 42n,
    blockHash: BLOCK_HASH,
    transactionHash: TX_HASH,
    transactionIndex: 0,
    logIndex: 7,
    removed: false,
    ...overrides,
  } as Log;
  return { log, args };
}

function lowercaseDeep(value: unknown): unknown {
  if (typeof value === "string") return /^0x[0-9a-fA-F]{40}$/.test(value) ? value.toLowerCase() : value;
  if (Array.isArray(value)) return value.map(lowercaseDeep);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, lowercaseDeep(v)]));
  }
  return value;
}

describe("protocolEventsAbi", () => {
  it("has one entry per topic0", () => {
    const selectors = protocolEventsAbi.map((e) => toEventSelector(e as AbiEvent));
    expect(new Set(selectors).size).toBe(selectors.length);
  });

  it("covers the events the indexer handles", () => {
    const names = new Set<string>(protocolEventsAbi.map((e) => e.name));
    for (const name of [
      "IndexCreated",
      "IndexActionTriggered",
      "IndexActionFailed",
      "SharesMinted",
      "SharesBurned",
      "Transfer",
      "Approval",
      "PriceFeedRegistered",
      "TransactionSubmitted",
      "CallScheduled",
      "RoleGranted",
      "Upgraded",
    ]) {
      expect(names.has(name), name).toBe(true);
    }
  });
});

describe("decodeLog", () => {
  it.each(protocolEventsAbi.map((e) => [e.name, e] as const))("decodes %s", (_name, event) => {
    const { log, args } = rawLog(event);
    const decoded = decodeLog(log);

    expect(decoded.kind).toBe("decoded");
    if (decoded.kind !== "decoded") return;
    expect(decoded.eventName).toBe(event.name);
    // viem returns undefined args for an event without inputs (EIP712DomainChanged).
    expect(decoded.args).toEqual(event.inputs.length === 0 ? undefined : lowercaseDeep(args));
  });

  it("normalizes the position of the log", () => {
    const { log } = rawLog(protocolEventsAbi[0] as AbiEvent);
    const decoded = decodeLog(log);

    expect(decoded).toMatchObject({
      address: CHECKSUMMED.toLowerCase(),
      blockNumber: 42n,
      blockHash: BLOCK_HASH.toLowerCase(),
      txHash: TX_HASH.toLowerCase(),
      logIndex: 7,
    });
  });

  it("lowercases indexed and non-indexed addresses (SharesMinted, IndexCreated)", () => {
    for (const name of ["SharesMinted", "IndexCreated"]) {
      const event = protocolEventsAbi.find((e) => e.name === name) as AbiEvent;
      const decoded = decodeLog(rawLog(event).log);
      const addresses = JSON.stringify(decoded, (_k, v: unknown) => (typeof v === "bigint" ? v.toString() : v)).match(
        /0x[0-9a-fA-F]{40}(?![0-9a-fA-F])/g,
      );
      expect(addresses?.length ?? 0).toBeGreaterThan(0);
      for (const address of addresses ?? []) expect(address).toBe(address.toLowerCase());
    }
  });

  it("returns an unknown log for a topic0 outside the protocol ABIs", () => {
    const log = {
      ...rawLog(protocolEventsAbi[0] as AbiEvent).log,
      topics: [toEventSelector("NotAProtocolEvent(uint256)")] as [Hex],
      data: "0x" as Hex,
    } as Log;
    const decoded = decodeLog(log);

    expect(decoded.kind).toBe("unknown");
    if (decoded.kind !== "unknown") return;
    expect(decoded.topics).toEqual(log.topics);
    expect(decoded.data).toBe("0x");
    expect(decoded.reason).toBe("AbiEventSignatureNotFoundError");
    expect(decoded.detail).toContain("0x");
    expect(decoded.blockNumber).toBe(42n);
  });

  it("returns an unknown log when the data does not match the event", () => {
    const transfer = protocolEventsAbi.find((e) => e.name === "Transfer") as AbiEvent;
    const log = { ...rawLog(transfer).log, data: "0x1234" as Hex } as Log;
    const decoded = decodeLog(log);

    expect(decoded.kind).toBe("unknown");
    if (decoded.kind !== "unknown") return;
    // The detail says what did not match, not only which error class.
    expect(decoded.detail).not.toBe("");
    expect(decoded.detail).not.toBe(decoded.reason);
  });

  it("throws on a log without position", () => {
    const log = { ...rawLog(protocolEventsAbi[0] as AbiEvent).log, blockNumber: null } as unknown as Log;

    expect(() => decodeLog(log)).toThrow(IncompleteLogError);
  });
});

describe("normalizeArgs", () => {
  const MIXED = "0xAbCdEf0123456789aBcDeF0123456789AbCdEf01";

  it("lowercases address, address[] and addresses inside tuples", () => {
    const inputs: AbiParameter[] = [
      { name: "owner", type: "address" },
      { name: "owners", type: "address[]" },
      { name: "pair", type: "tuple", components: [{ name: "token", type: "address" }, { name: "amount", type: "uint256" }] },
    ];

    expect(normalizeArgs(inputs, { owner: MIXED, owners: [MIXED, MIXED], pair: { token: MIXED, amount: 1n } })).toEqual({
      owner: MIXED.toLowerCase(),
      owners: [MIXED.toLowerCase(), MIXED.toLowerCase()],
      pair: { token: MIXED.toLowerCase(), amount: 1n },
    });
  });

  it("leaves a string that looks like an address untouched", () => {
    const inputs: AbiParameter[] = [{ name: "note", type: "string" }, { name: "who", type: "address" }];

    expect(normalizeArgs(inputs, { note: MIXED, who: MIXED })).toEqual({ note: MIXED, who: MIXED.toLowerCase() });
  });

  it("handles unnamed arguments, which viem returns as an array", () => {
    const inputs: AbiParameter[] = [{ type: "address" }, { type: "uint256" }];

    expect(normalizeArgs(inputs, [MIXED, 5n])).toEqual([MIXED.toLowerCase(), 5n]);
  });
});

describe("compareLogs", () => {
  it("orders by block, then by logIndex", () => {
    const at = (blockNumber: bigint, logIndex: number) =>
      ({ blockNumber, logIndex }) as Pick<ChainLog, "blockNumber" | "logIndex">;
    const sorted = [at(2n, 0), at(1n, 5), at(1n, 1), at(3n, 0)].sort((a, b) =>
      compareLogs(a as ChainLog, b as ChainLog),
    );

    expect(sorted).toEqual([at(1n, 1), at(1n, 5), at(2n, 0), at(3n, 0)]);
  });
});

describe("fetchLogs", () => {
  function clientReturning(logs: Log[]) {
    const calls: { method: string; params: unknown }[] = [];
    const client = createPublicClient({
      transport: custom({
        request: ({ method, params }: { method: string; params: unknown }) => {
          calls.push({ method, params });
          if (method === "eth_getLogs") {
            return Promise.resolve(
              logs.map((l) => ({
                ...l,
                blockNumber: numberToHex(l.blockNumber ?? 0n),
                logIndex: numberToHex(l.logIndex ?? 0),
                transactionIndex: numberToHex(l.transactionIndex ?? 0),
              })),
            );
          }
          return Promise.reject(new Error(`unexpected ${method}`));
        },
      }),
    });
    return { client, calls };
  }

  it("makes one eth_getLogs call on the given addresses and range, and sorts the result", async () => {
    const transfer = protocolEventsAbi.find((e) => e.name === "Transfer") as AbiEvent;
    const { client, calls } = clientReturning([
      rawLog(transfer, { blockNumber: 11n, logIndex: 0 }).log,
      rawLog(transfer, { blockNumber: 10n, logIndex: 3 }).log,
      rawLog(transfer, { blockNumber: 10n, logIndex: 1 }).log,
    ]);
    const addresses = ["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002"] as const;

    const logs = await fetchLogs(client, addresses, 10n, 12n);

    expect(calls).toHaveLength(1);
    expect(calls[0]?.method).toBe("eth_getLogs");
    expect(calls[0]?.params).toMatchObject([{ address: [...addresses], fromBlock: "0xa", toBlock: "0xc" }]);
    expect(logs.map((l) => [l.blockNumber, l.logIndex])).toEqual([
      [10n, 1],
      [10n, 3],
      [11n, 0],
    ]);
  });

  it("refuses an address list with a hole instead of fetching every contract's logs", async () => {
    const { client, calls } = clientReturning([]);
    const addresses = ["0x0000000000000000000000000000000000000001", undefined] as unknown as Address[];

    await expect(fetchLogs(client, addresses, 1n, 10n)).rejects.toBeInstanceOf(InvalidAddressFilterError);
    await expect(fetchLogs(client, ["0x1234"], 1n, 10n)).rejects.toBeInstanceOf(InvalidAddressFilterError);
    expect(calls).toHaveLength(0);
  });

  it("does not call the node with no addresses or an empty range", async () => {
    const { client, calls } = clientReturning([]);

    expect(await fetchLogs(client, [], 1n, 10n)).toEqual([]);
    expect(await fetchLogs(client, ["0x0000000000000000000000000000000000000001"], 10n, 9n)).toEqual([]);
    expect(calls).toHaveLength(0);
  });
});
