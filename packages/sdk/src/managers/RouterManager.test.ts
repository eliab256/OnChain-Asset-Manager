import { fc, test } from "@fast-check/vitest";
import { routerAbi } from "@oam/abi";
import { bytesToHex, decodeFunctionData, encodeFunctionData, getAddress, maxUint256, recoverTypedDataAddress, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { describe, expect, it } from "vitest";
import { routerWithErrorsAbi } from "../abis/fragments.js";
import { MAX_TOLERANCE } from "../constants/public.js";
import { buildPermitTypedData, splitPermitSignature } from "../encoders/permit.js";
import {
  IndexNotInitializedError,
  InsufficientAllowanceError,
  InsufficientBalanceError,
  InvalidDeadlineError,
  InvalidSignatureError,
  InvalidToleranceError,
  SdkError,
  ValueOutOfRangeError,
  ZeroAmountError,
} from "../errors.js";
import { RouterManager } from "./RouterManager.js";

const ROUTER = getAddress("0x53839913417ebc7171723489F29B9B54F49b4EEA");
const INDEX = getAddress("0x2d2DF19A06b90e886EDcf42f0D9bB0147076084d");
const USDC = getAddress("0x5FbDB2315678afecb367f032d93F642f64180aa3");
const user = privateKeyToAccount("0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d");

const address = fc.uint8Array({ minLength: 20, maxLength: 20 }).map((bytes) => getAddress(bytesToHex(bytes)));
// Amounts and deadlines are uint256 in the Router; above that the builders throw ValueOutOfRangeError.
const amount = fc.bigInt({ min: 1n, max: 2n ** 256n - 1n });
const tolerance = fc.bigInt({ min: 1n, max: MAX_TOLERANCE - 1n });
const word = fc.uint8Array({ minLength: 32, maxLength: 32 }).map((bytes) => bytesToHex(bytes));

/** Decoded with the generated Router ABI, independently of the merged ABI the SDK encodes with. */
function decode(calldata: Hex) {
  return decodeFunctionData({ abi: routerAbi, data: calldata });
}

const buy = { router: ROUTER, index: INDEX, usdcAmount: 100_000_000n, tolerance: 10_000n };
const sell = { router: ROUTER, index: INDEX, sharesAmount: 65_340_000_000_000_000_000n, tolerance: 10_000n };
const signature = { v: 27, r: `0x${"11".repeat(32)}`, s: `0x${"22".repeat(32)}` } as const;
const permitBuy = { ...buy, deadline: 1_900_000_100n, nowSeconds: 1_900_000_000n, signature };

describe("buyCallParameters", () => {
  it("calls buyExactUsdcAmountOfShares(index, usdcAmount, tolerance) on the Router with no value", () => {
    const call = RouterManager.buyCallParameters(buy);
    expect(call.to).toBe(ROUTER);
    expect(call.value).toBe(0n);
    expect(decode(call.calldata)).toEqual({
      functionName: "buyExactUsdcAmountOfShares",
      args: [INDEX, 100_000_000n, 10_000n],
    });
  });

  test.prop([address, address, amount, tolerance], { numRuns: 200 })("decoded calldata equals the inputs", (router, index, usdcAmount, tol) => {
    const call = RouterManager.buyCallParameters({ router, index, usdcAmount, tolerance: tol });
    expect(call.to).toBe(router);
    expect(decode(call.calldata).args).toEqual([index, usdcAmount, tol]);
  });

  it.each([0n, -1n])("security: zero or negative amount %s -> ZeroAmountError", (usdcAmount) => {
    expect(() => RouterManager.buyCallParameters({ ...buy, usdcAmount })).toThrow(ZeroAmountError);
  });

  // Router._validTolerance: 0 < tolerance < MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION.
  it.each([0n, -1n, MAX_TOLERANCE, MAX_TOLERANCE + 1n, 2n ** 256n])("security: tolerance out of range %s -> InvalidToleranceError", (tol) => {
    expect(() => RouterManager.buyCallParameters({ ...buy, tolerance: tol })).toThrow(InvalidToleranceError);
  });

  it.each([1n, MAX_TOLERANCE - 1n])("tolerance at the bound %s is accepted", (tol) => {
    expect(decode(RouterManager.buyCallParameters({ ...buy, tolerance: tol }).calldata).args[2]).toBe(tol);
  });

  // Without the bound viem throws IntegerOutOfRangeError, which a caller branching on
  // `instanceof SdkError` would miss.
  it.each([maxUint256 + 1n, 2n ** 300n])("security: an amount above uint256 (%s) -> ValueOutOfRangeError", (usdcAmount) => {
    let thrown: unknown;
    try {
      RouterManager.buyCallParameters({ ...buy, usdcAmount });
    } catch (err) {
      thrown = err;
    }
    expect(thrown).toBeInstanceOf(ValueOutOfRangeError);
    expect(thrown).toBeInstanceOf(SdkError);
    expect(thrown).toMatchObject({ operation: "buy", field: "amount", value: usdcAmount, max: maxUint256 });
  });

  it("an amount of exactly maxUint256 is encoded", () => {
    expect(decode(RouterManager.buyCallParameters({ ...buy, usdcAmount: maxUint256 }).calldata).args[1]).toBe(maxUint256);
  });
});

describe("buyWithPermitCallParameters", () => {
  it("calls buyExactUsdcAmountOfSharesWithPermit with deadline, v, r, s in the contract order", () => {
    const call = RouterManager.buyWithPermitCallParameters(permitBuy);
    expect(call.to).toBe(ROUTER);
    expect(call.value).toBe(0n);
    expect(decode(call.calldata)).toEqual({
      functionName: "buyExactUsdcAmountOfSharesWithPermit",
      args: [INDEX, 100_000_000n, 10_000n, 1_900_000_100n, 27, signature.r, signature.s],
    });
  });

  test.prop([address, amount, tolerance, fc.bigInt({ min: 1n, max: 2n ** 255n }), fc.constantFrom(27, 28), word, word], { numRuns: 200 })(
    "decoded calldata equals the inputs",
    (index, usdcAmount, tol, deadline, v, r, s) => {
      const call = RouterManager.buyWithPermitCallParameters({
        router: ROUTER,
        index,
        usdcAmount,
        tolerance: tol,
        deadline,
        nowSeconds: deadline - 1n,
        signature: { v, r, s },
      });
      expect(decode(call.calldata).args).toEqual([index, usdcAmount, tol, deadline, v, r, s]);
    },
  );

  it.each([
    ["equal to now", 1_900_000_000n],
    ["in the past", 1_899_999_999n],
    ["zero", 0n],
  ])("security: deadline %s -> InvalidDeadlineError", (_label, deadline) => {
    expect(() => RouterManager.buyWithPermitCallParameters({ ...permitBuy, deadline })).toThrow(InvalidDeadlineError);
  });

  it("a deadline one second after the latest block is accepted", () => {
    expect(() => RouterManager.buyWithPermitCallParameters({ ...permitBuy, deadline: permitBuy.nowSeconds + 1n })).not.toThrow();
  });

  it("security: zero amount and invalid tolerance are rejected before the deadline", () => {
    expect(() => RouterManager.buyWithPermitCallParameters({ ...permitBuy, usdcAmount: 0n })).toThrow(ZeroAmountError);
    expect(() => RouterManager.buyWithPermitCallParameters({ ...permitBuy, tolerance: MAX_TOLERANCE })).toThrow(InvalidToleranceError);
  });

  it("security: an amount above uint256 -> ValueOutOfRangeError", () => {
    const usdcAmount = maxUint256 + 1n;
    let thrown: unknown;
    try {
      RouterManager.buyWithPermitCallParameters({ ...permitBuy, usdcAmount });
    } catch (err) {
      thrown = err;
    }
    expect(thrown).toBeInstanceOf(ValueOutOfRangeError);
    expect(thrown).toMatchObject({ operation: "buyWithPermit", field: "amount", value: usdcAmount, max: maxUint256 });
  });

  it("security: a deadline above uint256 -> ValueOutOfRangeError", () => {
    const deadline = maxUint256 + 1n;
    let thrown: unknown;
    try {
      RouterManager.buyWithPermitCallParameters({ ...permitBuy, deadline });
    } catch (err) {
      thrown = err;
    }
    expect(thrown).toBeInstanceOf(ValueOutOfRangeError);
    expect(thrown).toMatchObject({ operation: "buyWithPermit", field: "deadline", value: deadline, max: maxUint256 });
  });

  it("a deadline of exactly maxUint256 (permit that never expires) is encoded", () => {
    const call = RouterManager.buyWithPermitCallParameters({ ...permitBuy, deadline: maxUint256 });
    expect(decode(call.calldata).args[3]).toBe(maxUint256);
  });

  // ecrecover in the token only accepts 27/28; v is a uint8, so 256 would also break the encoder.
  it.each([0, 1, 26, 29, 255, 256, -1])("security: signature v = %i -> InvalidSignatureError", (v) => {
    expect(() => RouterManager.buyWithPermitCallParameters({ ...permitBuy, signature: { ...signature, v } })).toThrow(
      InvalidSignatureError,
    );
  });

  it.each([27, 28])("signature v = %i is accepted", (v) => {
    const call = RouterManager.buyWithPermitCallParameters({ ...permitBuy, signature: { ...signature, v } });
    expect(decode(call.calldata).args[4]).toBe(v);
  });

  // The Router calls usdc.permit(msg.sender, _indexAddress, _usdcAmount, _deadline, v, r, s). Rebuild
  // that permit from the decoded calldata alone: it must recover to the user who signed.
  it("security: the permit the Router verifies (spender = Index from the calldata) recovers to the signer", async () => {
    const domain = { name: "USD Coin", version: "1", chainId: 31337, verifyingContract: USDC };
    const typedData = buildPermitTypedData({
      domain,
      owner: user.address,
      spender: INDEX,
      value: buy.usdcAmount,
      nonce: 0n,
      deadline: permitBuy.deadline,
    });
    const split = splitPermitSignature(await user.signTypedData(typedData));
    const call = RouterManager.buyWithPermitCallParameters({ ...permitBuy, signature: split });
    const decoded = decodeFunctionData({ abi: routerAbi, data: call.calldata });
    if (decoded.functionName !== "buyExactUsdcAmountOfSharesWithPermit") expect.unreachable();
    const [index, value, , deadline, v, r, s] = decoded.args;
    const asVerified = buildPermitTypedData({ domain, owner: user.address, spender: index, value, nonce: 0n, deadline });
    const recovered = await recoverTypedDataAddress({ ...asVerified, signature: { v: BigInt(v), r, s } });
    expect(recovered).toBe(user.address);
  });
});

describe("sellCallParameters", () => {
  it("calls sellExactAmountOfSharesForUsdc(index, sharesAmount, tolerance) on the Router", () => {
    const call = RouterManager.sellCallParameters(sell);
    expect(call.to).toBe(ROUTER);
    expect(call.value).toBe(0n);
    expect(decode(call.calldata)).toEqual({
      functionName: "sellExactAmountOfSharesForUsdc",
      args: [INDEX, sell.sharesAmount, 10_000n],
    });
  });

  test.prop([address, amount, tolerance], { numRuns: 200 })("decoded calldata equals the inputs", (index, sharesAmount, tol) => {
    expect(decode(RouterManager.sellCallParameters({ router: ROUTER, index, sharesAmount, tolerance: tol }).calldata).args).toEqual([
      index,
      sharesAmount,
      tol,
    ]);
  });

  it.each([0n, -1n])("security: zero or negative amount %s -> ZeroAmountError", (sharesAmount) => {
    expect(() => RouterManager.sellCallParameters({ ...sell, sharesAmount })).toThrow(ZeroAmountError);
  });

  it.each([0n, MAX_TOLERANCE, MAX_TOLERANCE + 1n])("security: tolerance out of range %s -> InvalidToleranceError", (tol) => {
    expect(() => RouterManager.sellCallParameters({ ...sell, tolerance: tol })).toThrow(InvalidToleranceError);
  });

  it.each([maxUint256 + 1n, 2n ** 300n])("security: an amount above uint256 (%s) -> ValueOutOfRangeError", (sharesAmount) => {
    let thrown: unknown;
    try {
      RouterManager.sellCallParameters({ ...sell, sharesAmount });
    } catch (err) {
      thrown = err;
    }
    expect(thrown).toBeInstanceOf(ValueOutOfRangeError);
    expect(thrown).toMatchObject({ operation: "sell", field: "amount", value: sharesAmount, max: maxUint256 });
  });

  it("an amount of exactly maxUint256 is encoded", () => {
    expect(decode(RouterManager.sellCallParameters({ ...sell, sharesAmount: maxUint256 }).calldata).args[1]).toBe(maxUint256);
  });
});

describe("checkBuy", () => {
  const state = {
    usdc: USDC,
    index: INDEX,
    usdcAmount: 100n,
    isInitialized: true,
    usdcBalance: 100n,
    usdcAllowance: 100n as bigint | undefined,
  };

  it("passes with balance and allowance exactly equal to the amount", () => {
    expect(() => RouterManager.checkBuy(state)).not.toThrow();
  });

  it("passes without an allowance for a buy with permit", () => {
    expect(() => RouterManager.checkBuy({ ...state, usdcAllowance: undefined })).not.toThrow();
  });

  it.each([0n, -1n])("security: amount %s -> ZeroAmountError", (usdcAmount) => {
    expect(() => RouterManager.checkBuy({ ...state, usdcAmount })).toThrow(ZeroAmountError);
  });

  it("an Index not initialized -> IndexNotInitializedError", () => {
    expect(() => RouterManager.checkBuy({ ...state, isInitialized: false })).toThrow(IndexNotInitializedError);
  });

  it("balance one unit short -> InsufficientBalanceError on USDC", () => {
    expect(() => RouterManager.checkBuy({ ...state, usdcBalance: 99n })).toThrow(InsufficientBalanceError);
    try {
      RouterManager.checkBuy({ ...state, usdcBalance: 99n });
    } catch (error) {
      expect(error).toMatchObject({ token: USDC, balance: 99n, required: 100n });
    }
  });

  // The Index pulls the USDC (transferFrom in mintShares), so the allowance that matters is to the Index.
  it("security: allowance one unit short -> InsufficientAllowanceError naming the Index as spender", () => {
    expect(() => RouterManager.checkBuy({ ...state, usdcAllowance: 99n })).toThrow(InsufficientAllowanceError);
    try {
      RouterManager.checkBuy({ ...state, usdcAllowance: 99n });
    } catch (error) {
      expect(error).toMatchObject({ token: USDC, spender: INDEX, allowance: 99n, required: 100n });
    }
  });

  it("an allowance of 0 is not mistaken for a permit buy", () => {
    expect(() => RouterManager.checkBuy({ ...state, usdcAllowance: 0n })).toThrow(InsufficientAllowanceError);
  });
});

describe("checkSell", () => {
  const state = { index: INDEX, sharesAmount: 10n, isInitialized: true, sharesBalance: 10n };

  it("passes with a balance exactly equal to the amount", () => {
    expect(() => RouterManager.checkSell(state)).not.toThrow();
  });

  it.each([0n, -1n])("security: amount %s -> ZeroAmountError", (sharesAmount) => {
    expect(() => RouterManager.checkSell({ ...state, sharesAmount })).toThrow(ZeroAmountError);
  });

  it("an Index not initialized -> IndexNotInitializedError", () => {
    expect(() => RouterManager.checkSell({ ...state, isInitialized: false })).toThrow(IndexNotInitializedError);
  });

  it("balance one unit short -> InsufficientBalanceError on the Index shares", () => {
    try {
      RouterManager.checkSell({ ...state, sharesBalance: 9n });
      expect.unreachable();
    } catch (error) {
      expect(error).toBeInstanceOf(InsufficientBalanceError);
      expect(error).toMatchObject({ token: INDEX, balance: 9n, required: 10n });
    }
  });
});

describe("read descriptors", () => {
  const reads = [
    [
      "minMintPreviewRead",
      RouterManager.minMintPreviewRead({ router: ROUTER, index: INDEX, usdcAmount: 5n, tolerance: 7n }),
      "getMinMintPreview",
      [INDEX, 5n, 7n],
    ],
    [
      "minRedeemPreviewRead",
      RouterManager.minRedeemPreviewRead({ router: ROUTER, index: INDEX, sharesAmount: 5n, tolerance: 7n }),
      "getMinRedeemPreview",
      [INDEX, 5n, 7n],
    ],
    ["maxToleranceRead", RouterManager.maxToleranceRead(ROUTER), "getMaxTolerance", undefined],
    ["usdcRead", RouterManager.usdcRead(ROUTER), "getUsdc", undefined],
    ["indexManagerRead", RouterManager.indexManagerRead(ROUTER), "getIndexManager", undefined],
  ] as const;

  it.each(reads)("%s targets the Router with the merged ABI and the right function", (_name, read, functionName, args) => {
    expect(read.address).toBe(ROUTER);
    expect(read.abi).toBe(routerWithErrorsAbi);
    expect(read.functionName).toBe(functionName);
    expect("args" in read ? read.args : undefined).toEqual(args);
  });

  it.each(reads)("%s encodes as a view function of the generated Router ABI", (_name, read) => {
    const data = encodeFunctionData(read as Parameters<typeof encodeFunctionData>[0]);
    const decoded = decodeFunctionData({ abi: routerAbi, data });
    expect(decoded.functionName).toBe(read.functionName);
    const item = routerAbi.find((entry) => entry.type === "function" && entry.name === read.functionName);
    expect(item?.type === "function" ? item.stateMutability : undefined).toMatch(/^(view|pure)$/);
  });
});
