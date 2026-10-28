import { fc, test } from "@fast-check/vitest";
import { multiSigWalletAbi } from "@oam/abi";
import { bytesToHex, concat, decodeFunctionData, encodeFunctionData, getAddress, hexToNumber, maxUint256, numberToHex, slice, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { describe, expect, it } from "vitest";
import { InvalidSignatureError, MultiSigNotExecutableError, ValueOutOfRangeError } from "../errors.js";
import { buildConfirmTypedData } from "../encoders/multiSig.js";
import { Erc20Manager } from "./Erc20Manager.js";
import { IndexManagerCalls } from "./IndexManagerCalls.js";
import { MultiSigCalls } from "./MultiSigCalls.js";
import { PriceFeedManagerCalls } from "./PriceFeedManagerCalls.js";

const owner = privateKeyToAccount("0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d");
const MULTISIG = getAddress("0xB7f8BC63BbcaD18155201308C8f3540b07f84F5e");
const INDEX_MANAGER = getAddress("0x68B1D87F95878fE05B998F19b66F4baba5De1aed");
const PRICE_FEED_MANAGER = getAddress("0xa12fFA0B9f159BB4C54bce579611927Addc51610");
const WBTC = getAddress("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599");
const WETH = getAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
const FEED = getAddress("0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6");
const INDEX = getAddress("0x2d2DF19A06b90e886EDcf42f0D9bB0147076084d");

const address = fc.uint8Array({ minLength: 20, maxLength: 20 }).map((bytes) => getAddress(bytesToHex(bytes)));
const uint256 = fc.bigInt({ min: 0n, max: maxUint256 });
const bytes = fc.uint8Array({ maxLength: 300 }).map((value) => bytesToHex(value));

function decode(calldata: Hex) {
  return decodeFunctionData({ abi: multiSigWalletAbi, data: calldata });
}

// Arrows keep the static builders bound to their class (unbound-method).
type TxParams = Parameters<typeof MultiSigCalls.confirmCallParameters>[0];

const txCalls = [
  ["confirmCallParameters", (p: TxParams) => MultiSigCalls.confirmCallParameters(p), "confirmTransaction"],
  ["executeCallParameters", (p: TxParams) => MultiSigCalls.executeCallParameters(p), "executeTransaction"],
  ["revokeCallParameters", (p: TxParams) => MultiSigCalls.revokeCallParameters(p), "revokeConfirmation"],
] as const;

describe("submitCallParameters", () => {
  const inner = [
    ["registerPriceFeed", PriceFeedManagerCalls.registerPriceFeedCallParameters({ priceFeedManager: PRICE_FEED_MANAGER, asset: WBTC, feed: FEED, maxDelay: 3600 })],
    [
      "createIndex",
      IndexManagerCalls.createIndexCallParameters({
        indexManager: INDEX_MANAGER,
        feePercentage: 10_000n,
        assetA: { asset: WBTC, weight: 500_000n },
        assetB: { asset: WETH, weight: 500_000n },
      }),
    ],
    ["approve", Erc20Manager.approveCallParameters({ token: WBTC, spender: INDEX, amount: 10n ** 8n })],
  ] as const;

  it.each(inner)("wraps %s as submitTransaction(to, value, calldata) on the MultiSig", (_name, call) => {
    const submit = MultiSigCalls.submitCallParameters({ multiSig: MULTISIG, call });
    expect(submit.to).toBe(MULTISIG);
    expect(submit.value).toBe(0n);
    expect(decode(submit.calldata)).toEqual({ functionName: "submitTransaction", args: [call.to, call.value, call.calldata] });
  });

  test.prop([address, address, uint256, bytes], { numRuns: 200 })(
    "wraps any MethodParameters: decoded target, value and data equal the inner call",
    (multiSig, to, value, calldata) => {
      const submit = MultiSigCalls.submitCallParameters({ multiSig, call: { to, value, calldata } });
      expect(submit.to).toBe(multiSig);
      expect(submit.value).toBe(0n);
      expect(decode(submit.calldata)).toEqual({ functionName: "submitTransaction", args: [to, value, calldata] });
    },
  );

  // A value outside uint256 must not leak viem's IntegerOutOfRangeError (sdk.md §7).
  it.each([maxUint256 + 1n, -1n])("value %s outside uint256 -> ValueOutOfRangeError", (value) => {
    expect(() =>
      MultiSigCalls.submitCallParameters({ multiSig: MULTISIG, call: { to: INDEX_MANAGER, value, calldata: "0x" } }),
    ).toThrow(ValueOutOfRangeError);
  });

  it.each([0n, maxUint256])("value %s at the uint256 bound is accepted", (value) => {
    const submit = MultiSigCalls.submitCallParameters({ multiSig: MULTISIG, call: { to: INDEX_MANAGER, value, calldata: "0x" } });
    expect(decode(submit.calldata).args?.[1]).toBe(value);
  });
});

describe("confirm / execute / revoke", () => {
  it.each(txCalls)("%s calls %s(txId) on the MultiSig with no value", (_name, build, functionName) => {
    const call = build({ multiSig: MULTISIG, txId: 5n });
    expect(call.to).toBe(MULTISIG);
    expect(call.value).toBe(0n);
    expect(decode(call.calldata)).toEqual({ functionName, args: [5n] });
  });

  test.prop([fc.constantFrom(...txCalls), address, uint256], { numRuns: 200 })(
    "decoded txId equals the input over the whole uint256 range",
    ([, build, functionName], multiSig, txId) => {
      const call = build({ multiSig, txId });
      expect(call.to).toBe(multiSig);
      expect(decode(call.calldata)).toEqual({ functionName, args: [txId] });
    },
  );

  it.each(txCalls.flatMap(([name, build]) => [[name, build, -1n] as const, [name, build, maxUint256 + 1n] as const]))(
    "%s with txId %s -> ValueOutOfRangeError",
    (_name, build, txId) => {
      expect(() => build({ multiSig: MULTISIG, txId })).toThrow(ValueOutOfRangeError);
    },
  );

  it.each(txCalls)("%s accepts the bounds 0 and maxUint256", (_name, build) => {
    expect(() => build({ multiSig: MULTISIG, txId: 0n })).not.toThrow();
    expect(() => build({ multiSig: MULTISIG, txId: maxUint256 })).not.toThrow();
  });
});

describe("confirmWithSigCallParameters", () => {
  const domain = { name: "MultiSigWallet", version: "2", chainId: 31337, verifyingContract: MULTISIG };

  it("calls confirmTransactionWithSig(txId, signer, signature) with a real signature", async () => {
    const signature = await owner.signTypedData(
      buildConfirmTypedData({ domain, txId: 2n, target: INDEX_MANAGER, value: 0n, data: "0x", nonce: 0n }),
    );
    const call = MultiSigCalls.confirmWithSigCallParameters({ multiSig: MULTISIG, txId: 2n, signer: owner.address, signature });
    expect(call.to).toBe(MULTISIG);
    expect(call.value).toBe(0n);
    expect(decode(call.calldata)).toEqual({ functionName: "confirmTransactionWithSig", args: [2n, owner.address, signature] });
  });

  it.each([
    ["empty", "0x"],
    ["64 bytes", `0x${"11".repeat(64)}`],
    ["not hex", `0x${"gg".repeat(65)}`],
  ] as const)("signature %s -> InvalidSignatureError", (_name, signature) => {
    expect(() =>
      MultiSigCalls.confirmWithSigCallParameters({ multiSig: MULTISIG, txId: 0n, signer: owner.address, signature: signature }),
    ).toThrow(InvalidSignatureError);
  });

  // The MultiSig's ECDSA.recover rejects v = 0/1 (ECDSAInvalidSignature): the builder forwards them as 27/28.
  it.each(["00", "01"])("a signature with v byte 0x%s is forwarded with v 27/28 and the same r, s", async (vByte) => {
    const signed = await owner.signTypedData(
      buildConfirmTypedData({ domain, txId: 2n, target: INDEX_MANAGER, value: 0n, data: "0x", nonce: 0n }),
    );
    const signature = concat([slice(signed, 0, 64), `0x${vByte}`]);
    const call = MultiSigCalls.confirmWithSigCallParameters({ multiSig: MULTISIG, txId: 2n, signer: owner.address, signature });
    const forwarded = decode(call.calldata).args?.[2] as Hex;
    expect(slice(forwarded, 0, 64)).toBe(slice(signature, 0, 64));
    expect(hexToNumber(slice(forwarded, 64, 65))).toBe(Number(vByte) + 27);
  });

  it("security: a high-s signature -> InvalidSignatureError (ECDSAInvalidSignatureS on chain)", async () => {
    const signed = await owner.signTypedData(
      buildConfirmTypedData({ domain, txId: 2n, target: INDEX_MANAGER, value: 0n, data: "0x", nonce: 0n }),
    );
    const n = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
    const s = BigInt(slice(signed, 32, 64));
    const v = hexToNumber(slice(signed, 64, 65));
    const high = concat([slice(signed, 0, 32), numberToHex(n - s, { size: 32 }), numberToHex(v === 27 ? 28 : 27, { size: 1 })]);
    expect(() => MultiSigCalls.confirmWithSigCallParameters({ multiSig: MULTISIG, txId: 2n, signer: owner.address, signature: high })).toThrow(
      InvalidSignatureError,
    );
  });

  it.each([-1n, maxUint256 + 1n])("txId %s -> ValueOutOfRangeError", (txId) => {
    const signature = `0x${"11".repeat(64)}1b` as Hex;
    expect(() => MultiSigCalls.confirmWithSigCallParameters({ multiSig: MULTISIG, txId, signer: owner.address, signature })).toThrow(
      ValueOutOfRangeError,
    );
  });
});

describe("checkExecutable", () => {
  // Same order as executeTransaction: notExecuted first, then confirmations >= required.
  it("passes with exactly the required confirmations and with more", () => {
    expect(() => MultiSigCalls.checkExecutable({ txId: 0n, executed: false, confirmations: 2n, requiredConfirmations: 2n })).not.toThrow();
    expect(() => MultiSigCalls.checkExecutable({ txId: 0n, executed: false, confirmations: 3n, requiredConfirmations: 2n })).not.toThrow();
  });

  it.each([
    ["one confirmation short", { executed: false, confirmations: 1n }],
    ["no confirmations", { executed: false, confirmations: 0n }],
    ["already executed", { executed: true, confirmations: 2n }],
    ["already executed and short", { executed: true, confirmations: 0n }],
  ])("%s -> MultiSigNotExecutableError", (_name, state) => {
    expect(() => MultiSigCalls.checkExecutable({ txId: 4n, requiredConfirmations: 2n, ...state })).toThrow(MultiSigNotExecutableError);
  });

  test.prop([fc.boolean(), fc.bigInt({ min: 0n, max: 10n }), fc.bigInt({ min: 1n, max: 10n })], { numRuns: 1000 })(
    "throws exactly when executed or confirmations < required",
    (executed, confirmations, requiredConfirmations) => {
      const run = () => MultiSigCalls.checkExecutable({ txId: 1n, executed, confirmations, requiredConfirmations });
      if (executed || confirmations < requiredConfirmations) expect(run).toThrow(MultiSigNotExecutableError);
      else expect(run).not.toThrow();
    },
  );
});

describe("read descriptors", () => {
  const OWNER = owner.address;
  const reads = [
    ["transactionRead", MultiSigCalls.transactionRead({ multiSig: MULTISIG, txId: 3n }), "getTransaction", [3n]],
    ["transactionCountRead", MultiSigCalls.transactionCountRead(MULTISIG), "getTransactionCount", undefined],
    ["ownersRead", MultiSigCalls.ownersRead(MULTISIG), "getOwners", undefined],
    ["isOwnerRead", MultiSigCalls.isOwnerRead({ multiSig: MULTISIG, account: OWNER }), "isOwner", [OWNER]],
    ["requiredConfirmationsRead", MultiSigCalls.requiredConfirmationsRead(MULTISIG), "getRequiredConfirmations", undefined],
    ["isConfirmedRead", MultiSigCalls.isConfirmedRead({ multiSig: MULTISIG, txId: 3n, owner: OWNER }), "isTransactionConfirmed", [3n, OWNER]],
    ["confirmNonceRead", MultiSigCalls.confirmNonceRead({ multiSig: MULTISIG, txId: 3n, owner: OWNER }), "getConfirmNonce", [3n, OWNER]],
    ["confirmDigestRead", MultiSigCalls.confirmDigestRead({ multiSig: MULTISIG, txId: 3n, signer: OWNER }), "getConfirmDigest", [3n, OWNER]],
    ["eip712DomainRead", MultiSigCalls.eip712DomainRead(MULTISIG), "eip712Domain", undefined],
  ] as const;

  it.each(reads)("%s targets the MultiSig", (_name, read, functionName, args) => {
    expect(read.address).toBe(MULTISIG);
    expect(read.functionName).toBe(functionName);
    expect("args" in read ? read.args : undefined).toEqual(args);
  });

  it.each(reads)("%s encodes as a view function of the generated MultiSigWallet ABI", (_name, read) => {
    const data = encodeFunctionData(read as Parameters<typeof encodeFunctionData>[0]);
    expect(decode(data).functionName).toBe(read.functionName);
    const item = multiSigWalletAbi.find((entry) => entry.type === "function" && entry.name === read.functionName);
    expect(item?.type === "function" ? item.stateMutability : undefined).toMatch(/^(view|pure)$/);
  });

  it("the descriptors carry the MultiSig errors, so a revert decodes", () => {
    const abi = MultiSigCalls.transactionRead({ multiSig: MULTISIG, txId: 0n }).abi;
    expect(abi.some((item) => item.type === "error" && item.name === "MultiSig__InvalidSignature")).toBe(true);
  });
});
