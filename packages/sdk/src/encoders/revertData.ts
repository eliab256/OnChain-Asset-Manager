import {
  BaseError,
  ContractFunctionRevertedError,
  decodeErrorResult,
  encodeErrorResult,
  isHex,
  type EncodeErrorResultParameters,
  type Hex,
} from "viem";
import { protocolErrorsAbi } from "../abis/fragments.js";
import { ContractRevertError, RequestFailedError, SdkError } from "../errors.js";

export type DecodedProtocolError = {
  errorName: string;
  args: readonly unknown[];
};

/**
 * Decodes raw revert data, e.g. `reasonData` of `IndexActionFailed`. Returns `undefined` when the
 * data is empty or the error is not part of the protocol ABIs.
 */
export function decodeProtocolError(data: Hex): DecodedProtocolError | undefined {
  if (data === "0x") return undefined;
  try {
    const decoded = decodeErrorResult({ abi: protocolErrorsAbi, data });
    return { errorName: decoded.errorName, args: decoded.args ?? [] };
  } catch {
    return undefined;
  }
}

/** Inverse of `decodeProtocolError`. */
export function encodeProtocolError(
  params: Omit<EncodeErrorResultParameters<typeof protocolErrorsAbi>, "abi">,
): Hex {
  return encodeErrorResult({ abi: protocolErrorsAbi, ...params } as EncodeErrorResultParameters<
    typeof protocolErrorsAbi
  >);
}

/**
 * Turns what a client threw (viem `readContract`, `simulateContract`, `writeContract`, `sendTransaction`
 * with the SDK calldata, or wagmi) into a
 * typed SDK error, keeping the original as `cause`. The SDK never calls the network: this only
 * interprets errors raised by the caller's client.
 */
export function toSdkError(err: unknown, context: string): SdkError {
  if (err instanceof SdkError) return err;

  if (err instanceof BaseError) {
    const revert = err.walk((inner) => inner instanceof ContractFunctionRevertedError);
    if (revert instanceof ContractFunctionRevertedError) {
      const decoded = revert.data
        ? { errorName: revert.data.errorName, args: revert.data.args ?? [] }
        : revert.raw
          ? decodeProtocolError(revert.raw)
          : undefined;
      return new ContractRevertError(context, decoded?.errorName, decoded?.args ?? [], { cause: err });
    }

    // `sendTransaction` with raw calldata has no ABI to decode with: the revert data only sits in
    // the `data` field of the RPC error (e.g. `RpcRequestError`).
    // Stop at the first `data` that decodes, not the first hex one: an outer error could carry other bytes.
    const withData = err.walk((inner) => decodedRevertOf(inner) !== undefined);
    const decoded = withData ? decodedRevertOf(withData) : undefined;
    if (decoded) return new ContractRevertError(context, decoded.errorName, decoded.args, { cause: err });
  }

  return new RequestFailedError(context, { cause: err });
}

/** Protocol error decoded from an error's `data` field, if it holds revert data of the protocol. */
function decodedRevertOf(inner: unknown): DecodedProtocolError | undefined {
  if (typeof inner !== "object" || inner === null || !("data" in inner)) return undefined;
  const { data } = inner;
  return typeof data === "string" && isHex(data, { strict: true }) ? decodeProtocolError(data) : undefined;
}
