import { fc, test } from "@fast-check/vitest";
import { multiSigWalletAbi } from "@oam/abi";
import {
  bytesToHex,
  concat,
  encodeAbiParameters,
  encodeFunctionData,
  erc20Abi,
  getAddress,
  hashTypedData,
  hexToBigInt,
  hexToNumber,
  keccak256,
  maxUint256,
  numberToHex,
  recoverTypedDataAddress,
  slice,
  toHex,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { describe, expect, it } from "vitest";
import type { ProtocolAddresses } from "../constants/addresses.js";
import { EventNotFoundError, InvalidSignatureError, UnknownProposalError } from "../errors.js";
import { IndexManagerCalls } from "../managers/IndexManagerCalls.js";
import { MultiSigCalls } from "../managers/MultiSigCalls.js";
import { PriceFeedManagerCalls } from "../managers/PriceFeedManagerCalls.js";
import { v3Route } from "../utils/swapRoutes.js";
import {
  assertConfirmSignature,
  buildConfirmTypedData,
  CONFIRM_TYPES,
  decodeProposal,
  encodeConfirmationRevokedLog,
  encodeTransactionConfirmedLog,
  encodeTransactionExecutedLog,
  encodeTransactionSubmittedLog,
  normalizeConfirmSignature,
  parseConfirmationRevoked,
  parseTransactionConfirmed,
  parseTransactionExecuted,
  parseTransactionSubmitted,
} from "./multiSig.js";
import type { PermitDomain } from "./permit.js";

// Anvil account 1, a MultiSig owner in deployments/*.json; well-known test key, signing is local.
const owner = privateKeyToAccount("0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d");
const MULTISIG = getAddress("0xB7f8BC63BbcaD18155201308C8f3540b07f84F5e");
// Any contract touched in the same transaction can emit an event with the same signature.
const ATTACKER = getAddress("0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0");
const INDEX_MANAGER = getAddress("0x68B1D87F95878fE05B998F19b66F4baba5De1aed");
const WBTC = getAddress("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599");
const WETH = getAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
const INDEX = getAddress("0x2d2DF19A06b90e886EDcf42f0D9bB0147076084d");
const FEED = getAddress("0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6");

const addresses: ProtocolAddresses = {
  indexManager: INDEX_MANAGER,
  indexFactory: getAddress("0x9A676e781A523b5d0C0e43731313A708CB607508"),
  router: getAddress("0x53839913417ebc7171723489F29B9B54F49b4EEA"),
  priceFeedManager: getAddress("0xa12fFA0B9f159BB4C54bce579611927Addc51610"),
  swapManager: getAddress("0x5E3d0fdE6f793B3115A9E7f5EBC195bbeeD35d6C"),
  usdc: getAddress("0x5FbDB2315678afecb367f032d93F642f64180aa3"),
  multiSigWallet: MULTISIG,
  timelock: getAddress("0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82"),
  startBlock: 0n,
};

// EIP712("MultiSigWallet", "2") in the MultiSigWallet constructor.
const domain: PermitDomain = { name: "MultiSigWallet", version: "2", chainId: 31337, verifyingContract: MULTISIG };

const address = fc.uint8Array({ minLength: 20, maxLength: 20 }).map((bytes) => getAddress(bytesToHex(bytes)));
const uint256 = fc.bigInt({ min: 0n, max: maxUint256 });
const bytes = fc.uint8Array({ maxLength: 200 }).map((value) => bytesToHex(value));

/** secp256k1 group order; OpenZeppelin ECDSA rejects s > n / 2 (EIP-2 malleability). */
const SECP256K1_N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

/** MultiSigWallet._getConfirmDigest rebuilt from the Solidity source, independently of viem's typed-data code. */
function confirmDigest(d: PermitDomain, m: { txId: bigint; target: Address; value: bigint; data: Hex; nonce: bigint }): Hex {
  const domainTypeHash = keccak256(toHex("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"));
  const domainSeparator = keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "bytes32" }, { type: "bytes32" }, { type: "uint256" }, { type: "address" }],
      [domainTypeHash, keccak256(toHex(d.name)), keccak256(toHex(d.version)), BigInt(d.chainId), d.verifyingContract],
    ),
  );
  const confirmTypeHash = keccak256(toHex("Confirm(uint256 txId,address target,uint256 value,bytes32 dataHash,uint256 nonce)"));
  const structHash = keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "uint256" }, { type: "address" }, { type: "uint256" }, { type: "bytes32" }, { type: "uint256" }],
      [confirmTypeHash, m.txId, m.target, m.value, keccak256(m.data), m.nonce],
    ),
  );
  return keccak256(concat(["0x1901", domainSeparator, structHash]));
}

const proposal = {
  txId: 3n,
  target: INDEX_MANAGER,
  value: 0n,
  data: "0xdeadbeef" as Hex,
  nonce: 1n,
};

describe("CONFIRM_TYPES", () => {
  it("matches CONFIRM_TYPEHASH of MultiSigWallet.sol field by field", () => {
    const encoded = `Confirm(${CONFIRM_TYPES.Confirm.map((f) => `${f.type} ${f.name}`).join(",")})`;
    expect(encoded).toBe("Confirm(uint256 txId,address target,uint256 value,bytes32 dataHash,uint256 nonce)");
  });
});

describe("buildConfirmTypedData", () => {
  it("hashes to the digest MultiSigWallet._getConfirmDigest computes", () => {
    const typed = buildConfirmTypedData({ domain, ...proposal });
    expect(hashTypedData(typed)).toBe(confirmDigest(domain, proposal));
  });

  it("signs data hash = keccak256(data), never the raw data", () => {
    expect(buildConfirmTypedData({ domain, ...proposal }).message.dataHash).toBe(keccak256(proposal.data));
  });

  it("a signature of the typed data recovers the signer", async () => {
    const typed = buildConfirmTypedData({ domain, ...proposal });
    const signature = await owner.signTypedData(typed);
    expect(await recoverTypedDataAddress({ ...typed, signature })).toBe(owner.address);
    expect(() => assertConfirmSignature(signature)).not.toThrow();
  });

  test.prop([uint256, address, uint256, bytes, uint256, fc.integer({ min: 1, max: 2 ** 31 }), address], { numRuns: 200 })(
    "digest equals the hand-built one for any transaction, nonce and domain",
    (txId, target, value, data, nonce, chainId, verifyingContract) => {
      const d = { ...domain, chainId, verifyingContract };
      const message = { txId, target, value, data, nonce };
      expect(hashTypedData(buildConfirmTypedData({ domain: d, ...message }))).toBe(confirmDigest(d, message));
    },
  );

  // Security: each bound field must change the digest, otherwise a signature collected for one
  // transaction (or before a revoke) would confirm another.
  it.each([
    ["txId", { txId: 4n }],
    ["target", { target: ATTACKER }],
    ["value", { value: 1n }],
    ["data", { data: "0xdeadbeee" as Hex }],
    ["nonce (bumped by revoke)", { nonce: 2n }],
  ] as const)("security: a different %s gives a different digest", (_name, change) => {
    const base = hashTypedData(buildConfirmTypedData({ domain, ...proposal }));
    expect(hashTypedData(buildConfirmTypedData({ domain, ...proposal, ...change }))).not.toBe(base);
  });

  it.each([
    ["chainId", { chainId: 31338 }],
    ["verifyingContract", { verifyingContract: ATTACKER }],
    ["version", { version: "1" }],
  ] as const)("security: a different domain %s gives a different digest", (_name, change) => {
    const base = hashTypedData(buildConfirmTypedData({ domain, ...proposal }));
    expect(hashTypedData(buildConfirmTypedData({ domain: { ...domain, ...change }, ...proposal }))).not.toBe(base);
  });
});

describe("assertConfirmSignature", () => {
  it.each([
    ["empty", "0x"],
    ["64 bytes (EIP-2098 compact)", `0x${"11".repeat(64)}`],
    ["66 bytes", `0x${"11".repeat(66)}`],
    ["not hex", `0x${"zz".repeat(65)}`],
    ["v = 29", `0x${"11".repeat(64)}1d`],
  ] as const)("rejects %s with InvalidSignatureError", (_name, signature) => {
    expect(() => assertConfirmSignature(signature as Hex)).toThrow(InvalidSignatureError);
  });

  // The MultiSig receives the raw bytes and OpenZeppelin ECDSA.recover returns address(0) for v = 0/1:
  // the assertion checks the bytes as they are; normalizeConfirmSignature is the one that rewrites v.
  it.each([
    ["v = 0", "00"],
    ["v = 1", "01"],
  ])("rejects %s, which ECDSA.recover does not accept", async (_name, vByte) => {
    const signature = await owner.signTypedData(buildConfirmTypedData({ domain, ...proposal }));
    expect(() => assertConfirmSignature(concat([slice(signature, 0, 64), `0x${vByte}`]))).toThrow(InvalidSignatureError);
  });

  // OpenZeppelin ECDSA.recover rejects s > n/2 with ECDSAInvalidSignatureS (EIP-2 malleability).
  it("security: rejects a high-s signature (s > n/2), which ECDSA.recover rejects", async () => {
    const signature = await owner.signTypedData(buildConfirmTypedData({ domain, ...proposal }));
    expect(() => assertConfirmSignature(malleate(signature))).toThrow(InvalidSignatureError);
  });

  it("the malleated signature used above is high-s and still recovers the signer with plain ecrecover", async () => {
    const typed = buildConfirmTypedData({ domain, ...proposal });
    const signature = await owner.signTypedData(typed);
    const high = malleate(signature);
    expect(hexToBigInt(slice(high, 32, 64)) > SECP256K1_N / 2n).toBe(true);
    expect(await recoverTypedDataAddress({ ...typed, signature: high })).toBe(owner.address);
  });
});

/** The other valid (r, n - s, v ^ 1) signature of the same message. */
function malleate(signature: Hex): Hex {
  const r = slice(signature, 0, 32);
  const s = hexToBigInt(slice(signature, 32, 64));
  const v = Number(hexToBigInt(slice(signature, 64, 65)));
  return concat([r, numberToHex(SECP256K1_N - s, { size: 32 }), numberToHex(v === 27 ? 28 : 27, { size: 1 })]);
}

describe("normalizeConfirmSignature", () => {
  const word = fc.uint8Array({ minLength: 32, maxLength: 32 }).map((value) => bytesToHex(value));
  // Low-s only: assertConfirmSignature rejects the upper half, so a property over 27/28 must stay below n/2.
  const lowS = fc.bigInt({ min: 1n, max: SECP256K1_N / 2n }).map((value) => numberToHex(value, { size: 32 }));

  it.each([
    ["v = 0", "00"],
    ["v = 1", "01"],
  ])("rewrites %s as 27/28 with the same r and s, and the signer still recovers", async (_name, vByte) => {
    const typed = buildConfirmTypedData({ domain, ...proposal });
    const signed = await owner.signTypedData(typed);
    const raw = concat([slice(signed, 0, 64), `0x${vByte}` as Hex]);
    const normalized = normalizeConfirmSignature(raw);
    expect(slice(normalized, 0, 64)).toBe(slice(raw, 0, 64));
    expect(hexToNumber(slice(normalized, 64, 65))).toBe(Number(vByte) + 27);
    expect(() => assertConfirmSignature(normalized)).not.toThrow();
    // Only the v byte matching the real yParity recovers the signer; the other one is a different, valid-looking key.
    const yParityByte = hexToNumber(slice(signed, 64, 65)) - 27;
    if (Number(vByte) === yParityByte) expect(await recoverTypedDataAddress({ ...typed, signature: normalized })).toBe(owner.address);
  });

  it("a real signature re-encoded with v = yParity recovers the same signer after normalisation", async () => {
    const typed = buildConfirmTypedData({ domain, ...proposal });
    const signed = await owner.signTypedData(typed);
    const yParity = hexToNumber(slice(signed, 64, 65)) - 27;
    const normalized = normalizeConfirmSignature(concat([slice(signed, 0, 64), numberToHex(yParity, { size: 1 })]));
    expect(normalized.toLowerCase()).toBe(signed.toLowerCase());
    expect(await recoverTypedDataAddress({ ...typed, signature: normalized })).toBe(owner.address);
  });

  test.prop([word, lowS, fc.constantFrom(27, 28)], { numRuns: 200 })("leaves a low-s signature with v 27/28 unchanged", (r, s, v) => {
    const signature = concat([r, s, numberToHex(v, { size: 1 })]);
    expect(normalizeConfirmSignature(signature).toLowerCase()).toBe(signature.toLowerCase());
  });

  it("security: rejects a high-s signature instead of flipping it", async () => {
    const signed = await owner.signTypedData(buildConfirmTypedData({ domain, ...proposal }));
    expect(() => normalizeConfirmSignature(malleate(signed))).toThrow(InvalidSignatureError);
    // With v = 0/1 too: normalising v does not launder a malleated s.
    const high = malleate(signed);
    const v = hexToNumber(slice(high, 64, 65)) - 27;
    expect(() => normalizeConfirmSignature(concat([slice(high, 0, 64), numberToHex(v, { size: 1 })]))).toThrow(InvalidSignatureError);
  });

  it.each([
    ["empty", "0x"],
    ["64 bytes", `0x${"11".repeat(64)}`],
    ["v = 2", `0x${"11".repeat(64)}02`],
    ["v = 29", `0x${"11".repeat(64)}1d`],
  ] as const)("rejects %s with InvalidSignatureError", (_name, signature) => {
    expect(() => normalizeConfirmSignature(signature as Hex)).toThrow(InvalidSignatureError);
  });
});

describe("MultiSig events", () => {
  const submitted = fc.record({ txId: uint256, proposer: address, target: address, value: uint256, data: bytes });
  const ownerEvent = fc.record({ txId: uint256, owner: address });
  const executed = fc.record({ txId: uint256, executor: address });

  test.prop([address, submitted], { numRuns: 200 })("parseTransactionSubmitted(encode(x)) equals x", (multiSig, event) => {
    expect(parseTransactionSubmitted([encodeTransactionSubmittedLog(multiSig, event)], multiSig)).toEqual(event);
  });

  test.prop([address, ownerEvent], { numRuns: 200 })("parseTransactionConfirmed(encode(x)) equals x", (multiSig, event) => {
    expect(parseTransactionConfirmed([encodeTransactionConfirmedLog(multiSig, event)], multiSig)).toEqual(event);
  });

  test.prop([address, ownerEvent], { numRuns: 200 })("parseConfirmationRevoked(encode(x)) equals x", (multiSig, event) => {
    expect(parseConfirmationRevoked([encodeConfirmationRevokedLog(multiSig, event)], multiSig)).toEqual(event);
  });

  test.prop([address, executed], { numRuns: 200 })("parseTransactionExecuted(encode(x)) equals x", (multiSig, event) => {
    expect(parseTransactionExecuted([encodeTransactionExecutedLog(multiSig, event)], multiSig)).toEqual(event);
  });

  const sample = {
    submitted: { txId: 1n, proposer: owner.address, target: INDEX_MANAGER, value: 0n, data: "0x1234" as Hex },
    confirmed: { txId: 1n, owner: owner.address },
    executed: { txId: 1n, executor: owner.address },
  };
  const cases = [
    ["TransactionSubmitted", (e: Address) => encodeTransactionSubmittedLog(e, sample.submitted), parseTransactionSubmitted, sample.submitted],
    ["TransactionConfirmed", (e: Address) => encodeTransactionConfirmedLog(e, sample.confirmed), parseTransactionConfirmed, sample.confirmed],
    ["ConfirmationRevoked", (e: Address) => encodeConfirmationRevokedLog(e, sample.confirmed), parseConfirmationRevoked, sample.confirmed],
    ["TransactionExecuted", (e: Address) => encodeTransactionExecutedLog(e, sample.executed), parseTransactionExecuted, sample.executed],
  ] as const;

  it.each(cases)("security: %s from another emitter is ignored", (_name, encode, parse) => {
    expect(() => parse([encode(ATTACKER)], MULTISIG)).toThrow(EventNotFoundError);
  });

  it.each(cases)("security: %s picks the MultiSig log after a spoofed one", (_name, encode, parse, expected) => {
    const spoofed = { ...encode(ATTACKER) };
    expect(parse([spoofed, encode(MULTISIG)], MULTISIG)).toEqual(expected);
  });

  it.each(cases)("%s: no logs -> EventNotFoundError", (_name, _encode, parse) => {
    expect(() => parse([], MULTISIG)).toThrow(EventNotFoundError);
  });

  it("emitter comparison is case-insensitive", () => {
    const log = encodeTransactionExecutedLog(MULTISIG, sample.executed);
    expect(parseTransactionExecuted([log], MULTISIG.toLowerCase() as Address)).toEqual(sample.executed);
  });

  it("encoded topics and data match the MultiSigWallet ABI event", () => {
    const log = encodeTransactionSubmittedLog(MULTISIG, sample.submitted);
    const item = multiSigWalletAbi.find((entry) => entry.type === "event" && entry.name === "TransactionSubmitted");
    expect(item?.type === "event" ? item.inputs.filter((i) => i.indexed).map((i) => i.name) : []).toEqual(["txId", "proposer", "target"]);
    expect(log.topics).toHaveLength(4);
    expect(log.data).toBe(encodeAbiParameters([{ type: "uint256" }, { type: "bytes" }], [0n, "0x1234"]));
  });
});

describe("decodeProposal", () => {
  const routes = {
    asset0Usdc: v3Route([WBTC, addresses.usdc], [3000]),
    asset1Usdc: v3Route([WETH, addresses.usdc], [3000]),
    asset0Asset1: v3Route([WBTC, WETH], [3000]),
  };
  const calls = [
    [
      "PriceFeedManager",
      "registerPriceFeed",
      PriceFeedManagerCalls.registerPriceFeedCallParameters({ priceFeedManager: addresses.priceFeedManager, asset: WBTC, feed: FEED, maxDelay: 3600 }),
      [WBTC, FEED, 3600],
    ],
    [
      "PriceFeedManager",
      "proposePriceFeedUpdate",
      PriceFeedManagerCalls.proposePriceFeedUpdateCallParameters({ priceFeedManager: addresses.priceFeedManager, asset: WBTC, feed: FEED, maxDelay: 60 }),
      [WBTC, FEED, 60],
    ],
    [
      "PriceFeedManager",
      "executePriceFeedUpdate",
      PriceFeedManagerCalls.executePriceFeedUpdateCallParameters({ priceFeedManager: addresses.priceFeedManager, asset: WBTC }),
      [WBTC],
    ],
    [
      "PriceFeedManager",
      "cancelPriceFeedUpdate",
      PriceFeedManagerCalls.cancelPriceFeedUpdateCallParameters({ priceFeedManager: addresses.priceFeedManager, asset: WBTC }),
      [WBTC],
    ],
    [
      "IndexManager",
      "createIndex",
      IndexManagerCalls.createIndexCallParameters({
        indexManager: INDEX_MANAGER,
        feePercentage: 10_000n,
        assetA: { asset: WETH, weight: 400_000n },
        assetB: { asset: WBTC, weight: 600_000n },
      }),
      [10_000, { asset: WETH, weightPercentage: 400_000n }, { asset: WBTC, weightPercentage: 600_000n }],
    ],
    [
      "IndexManager",
      "initializeIndex",
      IndexManagerCalls.initializeIndexCallParameters({ indexManager: INDEX_MANAGER, depositor: MULTISIG, index: INDEX, amount0: 10n ** 8n, routes }),
      [MULTISIG, INDEX, 10n ** 8n, routes.asset0Usdc, routes.asset1Usdc, routes.asset0Asset1],
    ],
    [
      "IndexManager",
      "grantRole",
      IndexManagerCalls.grantRoleCallParameters({ indexManager: INDEX_MANAGER, role: "REBALANCER", account: owner.address }),
      [IndexManagerCalls.roleHash("REBALANCER"), owner.address],
    ],
    [
      "IndexManager",
      "revokeRole",
      IndexManagerCalls.revokeRoleCallParameters({ indexManager: INDEX_MANAGER, role: "ASSET_MANAGER", account: owner.address }),
      [IndexManagerCalls.roleHash("ASSET_MANAGER"), owner.address],
    ],
    [
      "MultiSigWallet",
      "confirmTransaction",
      MultiSigCalls.confirmCallParameters({ multiSig: MULTISIG, txId: 7n }),
      [7n],
    ],
  ] as const;

  it.each(calls)("decodes %s.%s built by the SDK", (contract, functionName, call, args) => {
    const decoded = decodeProposal({ target: call.to, value: call.value, data: call.calldata }, addresses);
    expect(decoded.contract).toBe(contract);
    expect(decoded.functionName).toBe(functionName);
    expect(decoded.target).toBe(call.to);
    expect(decoded.value).toBe(0n);
    // viem decodes tuples with field names; compare through a canonical form that ignores the key order of the poolKey.
    expect(JSON.parse(JSON.stringify(decoded.args, bigintReplacer))).toEqual(JSON.parse(JSON.stringify(args, bigintReplacer)));
  });

  it("an ERC20 approve to a non-protocol target is reported as contract ERC20 with its spender", () => {
    const data = encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [INDEX, maxUint256] });
    expect(decodeProposal({ target: WBTC, value: 0n, data }, addresses)).toEqual({
      contract: "ERC20",
      target: WBTC,
      functionName: "approve",
      args: [INDEX, maxUint256],
      value: 0n,
    });
  });

  it("keeps the proposal value", () => {
    const data = encodeFunctionData({ abi: erc20Abi, functionName: "transfer", args: [ATTACKER, 1n] });
    expect(decodeProposal({ target: WBTC, value: 5n, data }, addresses).value).toBe(5n);
  });

  it("matches the target case-insensitively", () => {
    const call = MultiSigCalls.confirmCallParameters({ multiSig: MULTISIG, txId: 1n });
    const decoded = decodeProposal({ target: MULTISIG.toLowerCase() as Address, value: 0n, data: call.calldata }, addresses);
    expect(decoded.contract).toBe("MultiSigWallet");
  });

  it("security: unknown target with non-ERC20 calldata -> UnknownProposalError", () => {
    const call = IndexManagerCalls.rebalanceCallParameters({ indexManager: INDEX_MANAGER, index: INDEX });
    expect(() => decodeProposal({ target: ATTACKER, value: 0n, data: call.calldata }, addresses)).toThrow(UnknownProposalError);
  });

  it("security: calldata of another contract sent to a protocol target -> UnknownProposalError", () => {
    // createIndex calldata sent to the PriceFeedManager: decoding it with the IndexManager ABI would mislead the owner.
    const call = IndexManagerCalls.grantRoleCallParameters({ indexManager: INDEX_MANAGER, role: "REBALANCER", account: ATTACKER });
    expect(() => decodeProposal({ target: addresses.priceFeedManager, value: 0n, data: call.calldata }, addresses)).toThrow(
      UnknownProposalError,
    );
  });

  it.each([
    ["empty calldata (plain ETH transfer)", "0x"],
    ["a bare unknown selector", "0x12345678"],
  ] as const)("%s to an unknown target -> UnknownProposalError with the cause", (_name, data) => {
    let thrown: unknown;
    try {
      decodeProposal({ target: ATTACKER, value: 1n, data }, addresses);
    } catch (err) {
      thrown = err;
    }
    expect(thrown).toBeInstanceOf(UnknownProposalError);
    expect((thrown as UnknownProposalError).cause).toBeDefined();
  });

  test.prop([address, uint256, bytes], { numRuns: 200 })(
    "a wrapped MultiSig submit decodes back to its inner call",
    (target, value, data) => {
      const inner = { to: target, value, calldata: data };
      const submit = MultiSigCalls.submitCallParameters({ multiSig: MULTISIG, call: inner });
      const decoded = decodeProposal({ target: submit.to, value: submit.value, data: submit.calldata }, addresses);
      expect(decoded).toEqual({ contract: "MultiSigWallet", target: MULTISIG, functionName: "submitTransaction", args: [target, value, data], value: 0n });
    },
  );
});

function bigintReplacer(_key: string, value: unknown): unknown {
  if (typeof value === "bigint") return `${value}n`;
  if (typeof value === "string" && value.startsWith("0x")) return value.toLowerCase();
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)));
  }
  return value;
}
