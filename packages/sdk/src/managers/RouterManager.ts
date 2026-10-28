import { encodeFunctionData, maxUint256, type Address } from "viem";
import { routerWithErrorsAbi } from "../abis/fragments.js";
import { MAX_TOLERANCE } from "../constants/public.js";
import {
  IndexNotInitializedError,
  InsufficientAllowanceError,
  InsufficientBalanceError,
  InvalidDeadlineError,
  InvalidSignatureError,
  InvalidToleranceError,
  ValueOutOfRangeError,
  ZeroAmountError,
} from "../errors.js";
import type { PermitSignature } from "../encoders/permit.js";
import { isValidTolerance } from "../utils/percentages.js";
import type { MethodParameters } from "./types.js";

export type BuyParams = {
  router: Address;
  index: Address;
  /** USDC to spend, USDC decimals. */
  usdcAmount: bigint;
  /** 1e6 scale: 10_000 = 1%. */
  tolerance: bigint;
};

export type BuyWithPermitParams = BuyParams & {
  /** Unix timestamp in seconds, the one signed in the permit. */
  deadline: bigint;
  /** Chain time of the latest block, in seconds: the SDK has no clock. */
  nowSeconds: bigint;
  signature: PermitSignature;
};

export type SellParams = {
  router: Address;
  index: Address;
  /** Shares to sell, 18 decimals. */
  sharesAmount: bigint;
  /** 1e6 scale: 10_000 = 1%. */
  tolerance: bigint;
};

function assertTradeInputs(operation: string, amount: bigint, tolerance: bigint): void {
  if (amount <= 0n) throw new ZeroAmountError(operation, amount);
  if (amount > maxUint256) throw new ValueOutOfRangeError(operation, "amount", amount, maxUint256);
  if (!isValidTolerance(tolerance)) throw new InvalidToleranceError(tolerance, MAX_TOLERANCE);
}

/**
 * Router calls. Write functions return `{ to, calldata, value }`; `*Read` functions return a read
 * descriptor for viem `readContract` or wagmi `useReadContract`. The ABI includes every protocol
 * error, so a revert inside the Index or the PriceFeedManager is decoded too.
 */
export abstract class RouterManager {
  /**
   * Buys shares with an exact USDC amount. Needs a USDC allowance to the Index (not the Router).
   * @throws {ZeroAmountError} @throws {ValueOutOfRangeError} @throws {InvalidToleranceError}
   */
  static buyCallParameters(params: BuyParams): MethodParameters {
    assertTradeInputs("buy", params.usdcAmount, params.tolerance);
    return {
      to: params.router,
      calldata: encodeFunctionData({
        abi: routerWithErrorsAbi,
        functionName: "buyExactUsdcAmountOfShares",
        args: [params.index, params.usdcAmount, params.tolerance],
      }),
      value: 0n,
    };
  }

  /**
   * Buys with a USDC permit signed for spender = Index, in a single transaction.
   * @throws {ZeroAmountError} @throws {ValueOutOfRangeError} @throws {InvalidToleranceError}
   * @throws {InvalidDeadlineError} @throws {InvalidSignatureError}
   */
  static buyWithPermitCallParameters(params: BuyWithPermitParams): MethodParameters {
    assertTradeInputs("buyWithPermit", params.usdcAmount, params.tolerance);
    if (params.deadline <= params.nowSeconds) throw new InvalidDeadlineError(params.deadline, params.nowSeconds);
    if (params.deadline > maxUint256) {
      throw new ValueOutOfRangeError("buyWithPermit", "deadline", params.deadline, maxUint256);
    }
    const { v, r, s } = params.signature;
    if (v !== 27 && v !== 28) throw new InvalidSignatureError(`v=${v}`, "v must be 27 or 28");
    return {
      to: params.router,
      calldata: encodeFunctionData({
        abi: routerWithErrorsAbi,
        functionName: "buyExactUsdcAmountOfSharesWithPermit",
        args: [params.index, params.usdcAmount, params.tolerance, params.deadline, v, r, s],
      }),
      value: 0n,
    };
  }

  /**
   * Sells an exact amount of shares. No approve needed: the Index burns the shares directly.
   * @throws {ZeroAmountError} @throws {ValueOutOfRangeError} @throws {InvalidToleranceError}
   */
  static sellCallParameters(params: SellParams): MethodParameters {
    assertTradeInputs("sell", params.sharesAmount, params.tolerance);
    return {
      to: params.router,
      calldata: encodeFunctionData({
        abi: routerWithErrorsAbi,
        functionName: "sellExactAmountOfSharesForUsdc",
        args: [params.index, params.sharesAmount, params.tolerance],
      }),
      value: 0n,
    };
  }

  /**
   * Same checks the Router runs on-chain, on state the caller has already read, so the user gets a
   * readable error before signing. Pass `allowance` as `undefined` for a buy with permit.
   * @throws {ZeroAmountError} @throws {IndexNotInitializedError}
   * @throws {InsufficientBalanceError} @throws {InsufficientAllowanceError}
   */
  static checkBuy(state: {
    usdc: Address;
    index: Address;
    usdcAmount: bigint;
    isInitialized: boolean;
    usdcBalance: bigint;
    usdcAllowance: bigint | undefined;
  }): void {
    if (state.usdcAmount <= 0n) throw new ZeroAmountError("buy", state.usdcAmount);
    if (!state.isInitialized) throw new IndexNotInitializedError(state.index);
    if (state.usdcBalance < state.usdcAmount) {
      throw new InsufficientBalanceError(state.usdc, state.usdcBalance, state.usdcAmount);
    }
    if (state.usdcAllowance !== undefined && state.usdcAllowance < state.usdcAmount) {
      throw new InsufficientAllowanceError(state.usdc, state.index, state.usdcAllowance, state.usdcAmount);
    }
  }

  /** @throws {ZeroAmountError} @throws {IndexNotInitializedError} @throws {InsufficientBalanceError} */
  static checkSell(state: {
    index: Address;
    sharesAmount: bigint;
    isInitialized: boolean;
    sharesBalance: bigint;
  }): void {
    if (state.sharesAmount <= 0n) throw new ZeroAmountError("sell", state.sharesAmount);
    if (!state.isInitialized) throw new IndexNotInitializedError(state.index);
    if (state.sharesBalance < state.sharesAmount) {
      throw new InsufficientBalanceError(state.index, state.sharesBalance, state.sharesAmount);
    }
  }

  /** Minimum shares (18 decimals) for `usdcAmount`, computed by the contract. `Index.minMintPreview` gives the same offline. */
  static minMintPreviewRead(params: { router: Address; index: Address; usdcAmount: bigint; tolerance: bigint }) {
    return {
      address: params.router,
      abi: routerWithErrorsAbi,
      functionName: "getMinMintPreview",
      args: [params.index, params.usdcAmount, params.tolerance],
    } as const;
  }

  /** Minimum USDC (USDC decimals) for `sharesAmount`, computed by the contract. */
  static minRedeemPreviewRead(params: { router: Address; index: Address; sharesAmount: bigint; tolerance: bigint }) {
    return {
      address: params.router,
      abi: routerWithErrorsAbi,
      functionName: "getMinRedeemPreview",
      args: [params.index, params.sharesAmount, params.tolerance],
    } as const;
  }

  static maxToleranceRead(router: Address) {
    return { address: router, abi: routerWithErrorsAbi, functionName: "getMaxTolerance" } as const;
  }

  static usdcRead(router: Address) {
    return { address: router, abi: routerWithErrorsAbi, functionName: "getUsdc" } as const;
  }

  static indexManagerRead(router: Address) {
    return { address: router, abi: routerWithErrorsAbi, functionName: "getIndexManager" } as const;
  }
}
