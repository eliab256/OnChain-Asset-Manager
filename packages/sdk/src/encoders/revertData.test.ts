import { fc, test } from "@fast-check/vitest";
import {
  BaseError,
  bytesToHex,
  ContractFunctionExecutionError,
  ContractFunctionRevertedError,
  encodeErrorResult,
  erc20Abi,
  getAddress,
  HttpRequestError,
  RpcRequestError,
  TransactionExecutionError,
  UnknownRpcError,
  type AbiParameter,
} from "viem";
import { describe, expect, it } from "vitest";
import { protocolErrorsAbi, routerWithErrorsAbi } from "../abis/fragments.js";
import { ContractRevertError, InvalidToleranceError, RequestFailedError, SdkError } from "../errors.js";
import { decodeProtocolError, encodeProtocolError, toSdkError } from "./revertData.js";

const ROUTER = getAddress("0x53839913417ebc7171723489F29B9B54F49b4EEA");

// The protocol errors only use these parameter types (checked by the throw below).
function argArbitrary(parameter: AbiParameter): fc.Arbitrary<unknown> {
  switch (parameter.type) {
    case "uint256":
      return fc.bigInt({ min: 0n, max: 2n ** 256n - 1n });
    case "uint8":
      return fc.integer({ min: 0, max: 255 });
    case "address":
      return fc.uint8Array({ minLength: 20, maxLength: 20 }).map((bytes) => getAddress(bytesToHex(bytes)));
    case "bytes32":
      return fc.uint8Array({ minLength: 32, maxLength: 32 }).map((bytes) => bytesToHex(bytes));
    case "string":
      return fc.string();
    default:
      throw new TypeError(`no arbitrary for ABI type ${parameter.type}: extend argArbitrary`);
  }
}

const protocolErrorArb = fc
  .constantFrom(...protocolErrorsAbi)
  .chain((item) => fc.tuple(fc.constant(item.name), fc.tuple(...item.inputs.map(argArbitrary))));

type EncodeParams = Parameters<typeof encodeProtocolError>[0];

/** What viem's readContract / simulateContract throws when the call reverts. */
function revertedCall(abi: readonly unknown[], data: `0x${string}` | undefined) {
  const reverted = new ContractFunctionRevertedError({ abi: abi as never, data, functionName: "buyExactUsdcAmountOfShares" });
  return new ContractFunctionExecutionError(reverted, {
    abi: abi as never,
    functionName: "buyExactUsdcAmountOfShares",
    args: [ROUTER, 100_000_000n, 10_000n],
    contractAddress: ROUTER,
  });
}

/** What anvil answers to eth_sendTransaction / eth_estimateGas when the call reverts (code 3). */
function rpcRevert(data: unknown) {
  return new RpcRequestError({
    body: { method: "eth_sendTransaction" },
    error: { code: 3, message: "execution reverted", data },
    url: "http://127.0.0.1:8545",
  });
}

/** What viem sendTransaction throws: the RPC error wrapped by the transport and the action. */
function sendTransactionRevert(data: unknown) {
  return new TransactionExecutionError(new UnknownRpcError(rpcRevert(data)), {
    account: null,
    to: ROUTER,
    data: "0x12345678",
  });
}

describe("decodeProtocolError / encodeProtocolError", () => {
  test.prop([protocolErrorArb], { numRuns: 200 })("decode(encode(x)) equals x for every protocol error", ([errorName, args]) => {
    const data = encodeProtocolError({ errorName, args: args.length === 0 ? undefined : args } as unknown as EncodeParams);
    expect(decodeProtocolError(data)).toEqual({ errorName, args });
  });

  it("encodes the same bytes as viem with the contract ABI alone", () => {
    expect(encodeProtocolError({ errorName: "Router__InsufficientUsdcBalance", args: [1n, 2n] })).toBe(
      encodeErrorResult({ abi: routerWithErrorsAbi, errorName: "Router__InsufficientUsdcBalance", args: [1n, 2n] }),
    );
  });

  it("empty revert data -> undefined", () => {
    expect(decodeProtocolError("0x")).toBeUndefined();
  });

  it.each(["0xdeadbeef", "0x12", "0x1234567800"] as const)("unknown or truncated data %s -> undefined, no throw", (data) => {
    expect(decodeProtocolError(data)).toBeUndefined();
  });

  // viem always appends Error(string) and Panic(uint256) to the ABI, so string reverts (mainnet
  // USDC, OpenZeppelin v4 tokens) come back decoded even though they are not protocol errors.
  it("decodes the built-in Error(string) and Panic(uint256)", () => {
    const stringRevert = encodeErrorResult({
      abi: [{ type: "error", name: "Error", inputs: [{ type: "string", name: "message" }] }],
      errorName: "Error",
      args: ["ERC20: transfer amount exceeds balance"],
    });
    expect(decodeProtocolError(stringRevert)).toEqual({ errorName: "Error", args: ["ERC20: transfer amount exceeds balance"] });
    const panic = encodeErrorResult({
      abi: [{ type: "error", name: "Panic", inputs: [{ type: "uint256", name: "code" }] }],
      errorName: "Panic",
      args: [0x11n],
    });
    expect(decodeProtocolError(panic)).toEqual({ errorName: "Panic", args: [0x11n] });
  });
});

describe("toSdkError", () => {
  it("returns an SdkError unchanged", () => {
    const original = new InvalidToleranceError(0n, 100_000n);
    expect(toSdkError(original, "buy")).toBe(original);
  });

  it("a revert decoded by the client -> ContractRevertError with name, args and cause", () => {
    const data = encodeProtocolError({ errorName: "Router__InsufficientUsdcBalance", args: [5n, 10n] });
    const thrown = revertedCall(routerWithErrorsAbi, data);
    const error = toSdkError(thrown, "buy");
    expect(error).toBeInstanceOf(ContractRevertError);
    expect(error).toBeInstanceOf(SdkError);
    expect(error).toMatchObject({ context: "buy", errorName: "Router__InsufficientUsdcBalance", args: [5n, 10n] });
    expect(error.cause).toBe(thrown);
  });

  // A front-end that calls the Router with the bare routerAbi cannot decode Index__ToleranceExceeded
  // raised inside the Index; the SDK still names it from the raw bytes.
  it("a revert the client could not decode is decoded from the raw data with the protocol ABIs", () => {
    const data = encodeProtocolError({ errorName: "Index__ToleranceExceeded" });
    const thrown = revertedCall(erc20Abi, data);
    const error = toSdkError(thrown, "buy");
    expect(error).toBeInstanceOf(ContractRevertError);
    expect(error).toMatchObject({ errorName: "Index__ToleranceExceeded", args: [] });
  });

  it("a revert without data -> ContractRevertError with no error name", () => {
    const error = toSdkError(revertedCall(routerWithErrorsAbi, undefined), "sell");
    expect(error).toBeInstanceOf(ContractRevertError);
    expect(error).toMatchObject({ errorName: undefined, args: [] });
  });

  it("a revert with foreign data -> ContractRevertError with no error name", () => {
    const error = toSdkError(revertedCall(erc20Abi, "0xdeadbeef"), "sell");
    expect(error).toBeInstanceOf(ContractRevertError);
    expect(error).toMatchObject({ errorName: undefined, args: [] });
  });

  // The send path of sdk.md §6: sendTransaction with raw calldata has no ABI, so the revert data
  // only sits in the RPC error. The SDK must still name the protocol error.
  it.each([
    ["a bare RpcRequestError", rpcRevert],
    ["the sendTransaction chain (TransactionExecutionError > UnknownRpcError > RpcRequestError)", sendTransactionRevert],
  ] as const)("%s carrying protocol revert data -> ContractRevertError with name, args and cause", (_label, make) => {
    const data = encodeProtocolError({ errorName: "Router__InsufficientUsdcBalance", args: [1_000_000n, 2_000_000n] });
    const thrown = make(data);
    const error = toSdkError(thrown, "buy");
    expect(error).toBeInstanceOf(ContractRevertError);
    expect(error).toMatchObject({ context: "buy", errorName: "Router__InsufficientUsdcBalance", args: [1_000_000n, 2_000_000n] });
    expect(error.cause).toBe(thrown);
  });

  it("an error raised inside the Index, sent through the Router, is decoded too", () => {
    const error = toSdkError(sendTransactionRevert(encodeProtocolError({ errorName: "Index__ToleranceExceeded" })), "buy");
    expect(error).toBeInstanceOf(ContractRevertError);
    expect(error).toMatchObject({ errorName: "Index__ToleranceExceeded", args: [] });
  });

  // Data that is not a protocol error must not be dressed up as a revert with a made-up name.
  it.each([
    ["unknown selector", "0xdeadbeef"],
    ["truncated protocol error", "0x1234567800"],
    ["empty data", "0x"],
    ["no data", undefined],
    ["non-hex data", "execution reverted"],
    ["a non-string data field", { message: "nested" }],
  ] as const)("RPC revert with %s -> RequestFailedError with cause", (_label, data) => {
    for (const thrown of [rpcRevert(data), sendTransactionRevert(data)]) {
      const error = toSdkError(thrown, "buy");
      expect(error).toBeInstanceOf(RequestFailedError);
      expect(error).toMatchObject({ context: "buy" });
      expect(error.cause).toBe(thrown);
    }
  });

  it("a network error -> RequestFailedError with cause", () => {
    const thrown = new HttpRequestError({ url: "http://127.0.0.1:8545", status: 503 });
    const error = toSdkError(thrown, "snapshot");
    expect(error).toBeInstanceOf(RequestFailedError);
    expect(error).toMatchObject({ context: "snapshot" });
    expect(error.cause).toBe(thrown);
  });

  it.each([
    ["a viem BaseError without a revert", new BaseError("User rejected the request.")],
    ["a plain Error", new Error("boom")],
    ["a string", "boom"],
    ["undefined", undefined],
  ])("%s -> RequestFailedError with cause", (_label, thrown) => {
    const error = toSdkError(thrown, "ctx");
    expect(error).toBeInstanceOf(RequestFailedError);
    expect(error.cause).toBe(thrown);
  });
});
