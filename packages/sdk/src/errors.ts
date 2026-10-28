import type { Address } from "viem";

/** Base class of every error thrown by the SDK. Callers branch with `instanceof`, never on the message. */
export class SdkError extends Error {
  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = new.target.name;
  }
}

export class ZeroAmountError extends SdkError {
  constructor(
    readonly operation: string,
    readonly amount: bigint,
  ) {
    super(`${operation}: amount must be greater than 0, received ${amount}. Pass a positive bigint in token decimals.`);
  }
}

export class InvalidToleranceError extends SdkError {
  constructor(
    readonly tolerance: bigint,
    readonly maxTolerance: bigint,
  ) {
    super(
      `Tolerance ${tolerance} is out of range. Pass a value greater than 0 and lower than ${maxTolerance} (1e6 scale, 10_000 = 1%).`,
    );
  }
}

export class InvalidDeadlineError extends SdkError {
  constructor(
    readonly deadline: bigint,
    readonly nowSeconds: bigint,
  ) {
    super(`Deadline ${deadline} is not after the current time ${nowSeconds}. Pass a future unix timestamp in seconds.`);
  }
}

export class InvalidWeightError extends SdkError {
  constructor(
    readonly weight: bigint,
    readonly minWeight: bigint,
    readonly maxWeight: bigint,
  ) {
    super(`Weight ${weight} is out of range. Pass a value strictly between ${minWeight} and ${maxWeight} (1e6 scale).`);
  }
}

export class EmptyIndexListError extends SdkError {
  constructor(readonly operation: string) {
    super(`${operation}: the list of Index addresses is empty. Pass at least one address.`);
  }
}

export class InsufficientBalanceError extends SdkError {
  constructor(
    readonly token: Address,
    readonly balance: bigint,
    readonly required: bigint,
  ) {
    super(`Balance of ${token} is ${balance}, ${required} needed. Lower the amount or top up the account.`);
  }
}

export class InsufficientAllowanceError extends SdkError {
  constructor(
    readonly token: Address,
    readonly spender: Address,
    readonly allowance: bigint,
    readonly required: bigint,
  ) {
    super(
      `Allowance of ${token} to ${spender} is ${allowance}, ${required} needed. Send an approve to the spender first, or buy with a permit.`,
    );
  }
}

export class IndexNotInitializedError extends SdkError {
  constructor(readonly index: Address) {
    super(`Index ${index} is not initialized. Pick an initialized Index (IndexManager.getInitializedIndexes).`);
  }
}

export class InvalidPriceError extends SdkError {
  constructor(
    readonly asset: string,
    readonly price: bigint,
  ) {
    super(`Price of ${asset} is ${price}. Pass the positive 18-decimal price from PriceFeedManager.getPrice.`);
  }
}

export class InvalidDecimalsError extends SdkError {
  constructor(
    readonly token: string,
    readonly decimals: number,
  ) {
    super(`Token ${token} has ${decimals} decimals. The protocol supports at most 18.`);
  }
}

/** A value does not fit the Solidity type of the argument it is encoded into (e.g. above uint256). */
export class ValueOutOfRangeError extends SdkError {
  constructor(
    readonly operation: string,
    readonly field: string,
    readonly value: bigint,
    readonly max: bigint,
  ) {
    super(`${operation}: ${field} ${value} is out of range. Pass a value between 0 and ${max}.`);
  }
}

/** A permit or MultiSig confirmation signature that is not a 65-byte ECDSA signature with v = 27 or 28. */
export class InvalidSignatureError extends SdkError {
  constructor(
    readonly signature: string,
    readonly reason: string,
    options?: ErrorOptions,
  ) {
    super(`Invalid signature ${signature}: ${reason}. Pass the 65-byte signature returned by signTypedData.`, options);
  }
}

export class ZeroAddressError extends SdkError {
  constructor(
    readonly operation: string,
    readonly field: string,
  ) {
    super(`${operation}: ${field} is the zero address. Pass a deployed contract or account address.`);
  }
}

/** The two assets of a new Index break a rule of `IndexManager.createIndex`. */
export class InvalidIndexAssetsError extends SdkError {
  constructor(
    readonly assetA: Address,
    readonly assetB: Address,
    readonly reason: string,
  ) {
    super(`Invalid Index assets ${assetA} and ${assetB}: ${reason}. Pass two different non-zero ERC20 addresses other than USDC.`);
  }
}

export class InvalidFeePercentageError extends SdkError {
  constructor(
    readonly feePercentage: bigint,
    readonly minFee: bigint,
    readonly maxFee: bigint,
  ) {
    super(`Fee ${feePercentage} is out of range. Pass a value between ${minFee} and ${maxFee}, both included (1e6 scale, 10_000 = 1%).`);
  }
}

/** A swap route that the SwapManager cannot use (wrong V3 path shape, V4 pool key with unsorted currencies, ...). */
export class InvalidSwapRouteError extends SdkError {
  constructor(readonly reason: string) {
    super(`Invalid swap route: ${reason}. Build it with v3Route or v4Route.`);
  }
}

export class InvalidMaxDelayError extends SdkError {
  constructor(
    readonly maxDelay: number,
    readonly maxAllowed: number,
  ) {
    super(`Feed maxDelay ${maxDelay} is out of range. Pass a whole number of seconds greater than 0 and at most ${maxAllowed}.`);
  }
}

/** A MultiSig transaction that `executeTransaction` would reject. */
export class MultiSigNotExecutableError extends SdkError {
  constructor(
    readonly txId: bigint,
    readonly reason: string,
  ) {
    super(`MultiSig transaction ${txId} cannot be executed: ${reason}.`);
  }
}

/** A MultiSig proposal whose call the SDK cannot decode. Do not confirm it before checking target and calldata by hand. */
export class UnknownProposalError extends SdkError {
  constructor(
    readonly target: Address,
    readonly reason: string,
    options?: ErrorOptions,
  ) {
    super(`Cannot decode the proposal to ${target}: ${reason}. Check target and calldata by hand before confirming.`, options);
  }
}

export class EstimateNotFoundError extends SdkError {
  constructor(
    readonly operation: string,
    readonly target: bigint,
  ) {
    super(`${operation}: no input reaches ${target} within the step limit. Retry with a smaller target or refresh the snapshot.`);
  }
}

export class UnsupportedChainError extends SdkError {
  constructor(readonly chainId: number) {
    super(`Chain ${chainId} has no deployment file. Use 31337 (anvil) or 31338 (mainnet fork), or pass the addresses explicitly.`);
  }
}

export class UnknownIndexActionError extends SdkError {
  constructor(readonly action: number) {
    super(`IndexAction ${action} is not in INDEX_ACTIONS. Regenerate the ABIs and update constants/public.ts.`);
  }
}

export class EventNotFoundError extends SdkError {
  constructor(
    readonly eventName: string,
    readonly emitter: Address,
  ) {
    super(`No ${eventName} event from ${emitter} in these logs. Pass the logs of the receipt of the right transaction.`);
  }
}

/** A contract reverted. `errorName` is the Solidity custom error (e.g. `Router__InvalidTolerance`), when decodable. */
export class ContractRevertError extends SdkError {
  constructor(
    readonly context: string,
    readonly errorName: string | undefined,
    readonly args: readonly unknown[],
    options?: ErrorOptions,
  ) {
    super(`${context}: reverted with ${errorName ?? "an unknown error"}.`, options);
  }
}

/** Anything that is not a revert (network, RPC, wallet rejection), wrapped with its context. */
export class RequestFailedError extends SdkError {
  constructor(
    readonly context: string,
    options?: ErrorOptions,
  ) {
    super(`${context}: request failed. See \`cause\` for the original error.`, options);
  }
}
