import { describe, expect, it } from "vitest";
import {
  ContractRevertError,
  EmptyIndexListError,
  EstimateNotFoundError,
  EventNotFoundError,
  IndexNotInitializedError,
  InsufficientAllowanceError,
  InsufficientBalanceError,
  InvalidDeadlineError,
  InvalidDecimalsError,
  InvalidFeePercentageError,
  InvalidIndexAssetsError,
  InvalidMaxDelayError,
  InvalidPriceError,
  InvalidSignatureError,
  InvalidSwapRouteError,
  InvalidToleranceError,
  InvalidWeightError,
  MultiSigNotExecutableError,
  RequestFailedError,
  SdkError,
  UnknownIndexActionError,
  UnknownProposalError,
  UnsupportedChainError,
  ValueOutOfRangeError,
  ZeroAddressError,
  ZeroAmountError,
} from "./errors.js";

const TOKEN = "0x00000000000000000000000000000000000000C0";
const SPENDER = "0x00000000000000000000000000000000000000C1";

// One instance per class, built with distinctive values so the field checks below are meaningful.
const cases = [
  [ZeroAmountError, () => new ZeroAmountError("buy", 0n)],
  [InvalidToleranceError, () => new InvalidToleranceError(100_000n, 100_000n)],
  [InvalidDeadlineError, () => new InvalidDeadlineError(10n, 20n)],
  [InvalidWeightError, () => new InvalidWeightError(10_000n, 10_000n, 1_000_000n)],
  [EmptyIndexListError, () => new EmptyIndexListError("rebalanceMany")],
  [InsufficientBalanceError, () => new InsufficientBalanceError(TOKEN, 1n, 2n)],
  [InsufficientAllowanceError, () => new InsufficientAllowanceError(TOKEN, SPENDER, 1n, 2n)],
  [IndexNotInitializedError, () => new IndexNotInitializedError(TOKEN)],
  [InvalidPriceError, () => new InvalidPriceError("asset0", 0n)],
  [InvalidDecimalsError, () => new InvalidDecimalsError("asset0", 19)],
  [ValueOutOfRangeError, () => new ValueOutOfRangeError("approve", "amount", -1n, 2n ** 256n - 1n)],
  [InvalidSignatureError, () => new InvalidSignatureError("0x1234", "expected 65 bytes of hex")],
  [EstimateNotFoundError, () => new EstimateNotFoundError("estimate", 5n)],
  [UnsupportedChainError, () => new UnsupportedChainError(1)],
  [UnknownIndexActionError, () => new UnknownIndexActionError(9)],
  [EventNotFoundError, () => new EventNotFoundError("SharesMinted", TOKEN)],
  [ContractRevertError, () => new ContractRevertError("buy", "Router__InvalidTolerance", [])],
  [RequestFailedError, () => new RequestFailedError("buy")],
  [ZeroAddressError, () => new ZeroAddressError("createIndex", "assetA")],
  [InvalidIndexAssetsError, () => new InvalidIndexAssetsError(TOKEN, TOKEN, "the two assets are the same")],
  [InvalidFeePercentageError, () => new InvalidFeePercentageError(0n, 1_000n, 100_000n)],
  [InvalidSwapRouteError, () => new InvalidSwapRouteError("bad path")],
  [InvalidMaxDelayError, () => new InvalidMaxDelayError(0, 172_800)],
  [MultiSigNotExecutableError, () => new MultiSigNotExecutableError(3n, "it was already executed")],
  [UnknownProposalError, () => new UnknownProposalError(TOKEN, "unknown selector")],
] as const;

describe("error classes", () => {
  it.each(cases)("%o extends SdkError and Error, and is named after its class", (Class, make) => {
    const error = make();
    expect(error).toBeInstanceOf(Class);
    expect(error).toBeInstanceOf(SdkError);
    expect(error).toBeInstanceOf(Error);
    expect(error.name).toBe(Class.name);
    expect(error.message.length).toBeGreaterThan(0);
  });

  it("the classes are distinct: no error is an instance of another error class", () => {
    for (const [, make] of cases) {
      const error = make();
      const matching = cases.filter(([Class]) => error instanceof Class);
      expect(matching).toHaveLength(1);
    }
  });

  it("SdkError keeps the cause and its own name", () => {
    const cause = new Error("root");
    const error = new SdkError("wrapped", { cause });
    expect(error.cause).toBe(cause);
    expect(error.name).toBe("SdkError");
  });

  it("ContractRevertError, RequestFailedError and InvalidSignatureError keep the cause", () => {
    const cause = new Error("rpc");
    expect(new InvalidSignatureError("0x", "bad", { cause }).cause).toBe(cause);
    expect(new ContractRevertError("ctx", undefined, [], { cause }).cause).toBe(cause);
    expect(new RequestFailedError("ctx", { cause }).cause).toBe(cause);
    expect(new UnknownProposalError(TOKEN, "bad", { cause }).cause).toBe(cause);
  });

  it("the new errors keep the values they were built with", () => {
    expect(new ZeroAddressError("op", "feed")).toMatchObject({ operation: "op", field: "feed" });
    expect(new InvalidIndexAssetsError(TOKEN, SPENDER, "r")).toMatchObject({ assetA: TOKEN, assetB: SPENDER, reason: "r" });
    expect(new InvalidFeePercentageError(5n, 1n, 9n)).toMatchObject({ feePercentage: 5n, minFee: 1n, maxFee: 9n });
    expect(new InvalidSwapRouteError("r")).toMatchObject({ reason: "r" });
    expect(new InvalidMaxDelayError(7, 8)).toMatchObject({ maxDelay: 7, maxAllowed: 8 });
    expect(new MultiSigNotExecutableError(3n, "r")).toMatchObject({ txId: 3n, reason: "r" });
    expect(new UnknownProposalError(TOKEN, "r")).toMatchObject({ target: TOKEN, reason: "r" });
  });
});

describe("error fields", () => {
  // Callers read these fields to build their own UI messages, so they are part of the API.
  it("expose the values they were built with", () => {
    expect(new ZeroAmountError("buy", -3n)).toMatchObject({ operation: "buy", amount: -3n });
    expect(new InvalidToleranceError(7n, 100_000n)).toMatchObject({ tolerance: 7n, maxTolerance: 100_000n });
    expect(new InvalidDeadlineError(10n, 20n)).toMatchObject({ deadline: 10n, nowSeconds: 20n });
    expect(new InvalidWeightError(5n, 10_000n, 1_000_000n)).toMatchObject({
      weight: 5n,
      minWeight: 10_000n,
      maxWeight: 1_000_000n,
    });
    expect(new EmptyIndexListError("collectFeesMany")).toMatchObject({ operation: "collectFeesMany" });
    expect(new InsufficientBalanceError(TOKEN, 1n, 2n)).toMatchObject({ token: TOKEN, balance: 1n, required: 2n });
    expect(new InsufficientAllowanceError(TOKEN, SPENDER, 1n, 2n)).toMatchObject({
      token: TOKEN,
      spender: SPENDER,
      allowance: 1n,
      required: 2n,
    });
    expect(new IndexNotInitializedError(TOKEN)).toMatchObject({ index: TOKEN });
    expect(new InvalidPriceError("USDC", -1n)).toMatchObject({ asset: "USDC", price: -1n });
    expect(new InvalidDecimalsError("asset1", 24)).toMatchObject({ token: "asset1", decimals: 24 });
    expect(new ValueOutOfRangeError("buyWithPermit", "deadline", 2n ** 256n, 2n ** 256n - 1n)).toMatchObject({
      operation: "buyWithPermit",
      field: "deadline",
      value: 2n ** 256n,
      max: 2n ** 256n - 1n,
    });
    expect(new InvalidSignatureError("0xabcd", "v is 29")).toMatchObject({ signature: "0xabcd", reason: "v is 29" });
    expect(new EstimateNotFoundError("estimate", 5n)).toMatchObject({ operation: "estimate", target: 5n });
    expect(new UnsupportedChainError(1)).toMatchObject({ chainId: 1 });
    expect(new UnknownIndexActionError(9)).toMatchObject({ action: 9 });
    expect(new EventNotFoundError("SharesBurned", TOKEN)).toMatchObject({ eventName: "SharesBurned", emitter: TOKEN });
    expect(new ContractRevertError("buy", "Router__InsufficientUsdcBalance", [1n, 2n])).toMatchObject({
      context: "buy",
      errorName: "Router__InsufficientUsdcBalance",
      args: [1n, 2n],
    });
    expect(new RequestFailedError("sell")).toMatchObject({ context: "sell" });
  });
});
