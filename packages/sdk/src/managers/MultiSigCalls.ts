import { encodeFunctionData, maxUint256, type Address, type Hex } from "viem";
import { multiSigWalletWithErrorsAbi } from "../abis/fragments.js";
import { MultiSigNotExecutableError, ValueOutOfRangeError } from "../errors.js";
import { normalizeConfirmSignature } from "../encoders/multiSig.js";
import type { MethodParameters } from "./types.js";

type TxParams = { multiSig: Address; txId: bigint };

function call(multiSig: Address, calldata: Hex): MethodParameters {
  return { to: multiSig, calldata, value: 0n };
}

function assertTxId(operation: string, txId: bigint): void {
  if (txId < 0n || txId > maxUint256) throw new ValueOutOfRangeError(operation, "txId", txId, maxUint256);
}

/**
 * Calls to the MultiSigWallet (2 of 3), which holds `DEFAULT_ADMIN_ROLE` and `ASSET_MANAGER_ROLE` on the IndexManager.
 * Flow: an owner submits a proposal wrapping any `MethodParameters` of the SDK (`submitCallParameters`), the owners
 * confirm it on-chain (`confirmCallParameters`) or off-chain with an EIP-712 signature (`buildConfirmTypedData`,
 * then anyone sends `confirmWithSigCallParameters`), and an owner executes it once the confirmations are enough.
 * Only owners can submit, confirm, revoke and execute; `confirmTransactionWithSig` can be sent by anyone.
 */
export abstract class MultiSigCalls {
  /**
   * Proposes `call` (any write of the SDK, e.g. `IndexManagerCalls.createIndexCallParameters`). The proposer's
   * confirmation is not implicit. The `txId` is in the receipt: `parseTransactionSubmitted`.
   * @throws {ValueOutOfRangeError} `call.value` outside uint256
   */
  static submitCallParameters(params: { multiSig: Address; call: MethodParameters }): MethodParameters {
    if (params.call.value < 0n || params.call.value > maxUint256) {
      throw new ValueOutOfRangeError("submit", "value", params.call.value, maxUint256);
    }
    return call(
      params.multiSig,
      encodeFunctionData({
        abi: multiSigWalletWithErrorsAbi,
        functionName: "submitTransaction",
        args: [params.call.to, params.call.value, params.call.calldata],
      }),
    );
  }

  /** @throws {ValueOutOfRangeError} */
  static confirmCallParameters(params: TxParams): MethodParameters {
    assertTxId("confirm", params.txId);
    return call(
      params.multiSig,
      encodeFunctionData({ abi: multiSigWalletWithErrorsAbi, functionName: "confirmTransaction", args: [params.txId] }),
    );
  }

  /**
   * Records the confirmation of `signer` from a signature of `buildConfirmTypedData`. Any account can send it.
   * A v of 0 / 1 is rewritten as 27 / 28; a high-s signature is rejected (`ECDSA.recover` would revert).
   * @throws {ValueOutOfRangeError} @throws {InvalidSignatureError}
   */
  static confirmWithSigCallParameters(params: TxParams & { signer: Address; signature: Hex }): MethodParameters {
    assertTxId("confirmWithSig", params.txId);
    const signature = normalizeConfirmSignature(params.signature);
    return call(
      params.multiSig,
      encodeFunctionData({
        abi: multiSigWalletWithErrorsAbi,
        functionName: "confirmTransactionWithSig",
        args: [params.txId, params.signer, signature],
      }),
    );
  }

  /**
   * Executes the call. It reverts with `MultiSig__TxFailed` when the call itself reverts, and the transaction stays
   * pending: check it first with `checkExecutable` and a simulation.
   * @throws {ValueOutOfRangeError}
   */
  static executeCallParameters(params: TxParams): MethodParameters {
    assertTxId("execute", params.txId);
    return call(
      params.multiSig,
      encodeFunctionData({ abi: multiSigWalletWithErrorsAbi, functionName: "executeTransaction", args: [params.txId] }),
    );
  }

  /** Also invalidates any confirmation signature of the caller collected before. @throws {ValueOutOfRangeError} */
  static revokeCallParameters(params: TxParams): MethodParameters {
    assertTxId("revoke", params.txId);
    return call(
      params.multiSig,
      encodeFunctionData({ abi: multiSigWalletWithErrorsAbi, functionName: "revokeConfirmation", args: [params.txId] }),
    );
  }

  /**
   * Same checks as `executeTransaction` on state already read (`transactionRead`, `requiredConfirmationsRead`).
   * @throws {MultiSigNotExecutableError}
   */
  static checkExecutable(params: {
    txId: bigint;
    executed: boolean;
    confirmations: bigint;
    requiredConfirmations: bigint;
  }): void {
    if (params.executed) throw new MultiSigNotExecutableError(params.txId, "it was already executed");
    if (params.confirmations < params.requiredConfirmations) {
      throw new MultiSigNotExecutableError(
        params.txId,
        `${params.confirmations} confirmations of ${params.requiredConfirmations} required`,
      );
    }
  }

  /** `[target, value, data, executed, confirmations]`. Reverts if `txId` does not exist. */
  static transactionRead(params: TxParams) {
    return {
      address: params.multiSig,
      abi: multiSigWalletWithErrorsAbi,
      functionName: "getTransaction",
      args: [params.txId],
    } as const;
  }

  /** The next `txId`: ids go from 0 to count - 1. */
  static transactionCountRead(multiSig: Address) {
    return { address: multiSig, abi: multiSigWalletWithErrorsAbi, functionName: "getTransactionCount" } as const;
  }

  static ownersRead(multiSig: Address) {
    return { address: multiSig, abi: multiSigWalletWithErrorsAbi, functionName: "getOwners" } as const;
  }

  static isOwnerRead(params: { multiSig: Address; account: Address }) {
    return {
      address: params.multiSig,
      abi: multiSigWalletWithErrorsAbi,
      functionName: "isOwner",
      args: [params.account],
    } as const;
  }

  static requiredConfirmationsRead(multiSig: Address) {
    return { address: multiSig, abi: multiSigWalletWithErrorsAbi, functionName: "getRequiredConfirmations" } as const;
  }

  static isConfirmedRead(params: TxParams & { owner: Address }) {
    return {
      address: params.multiSig,
      abi: multiSigWalletWithErrorsAbi,
      functionName: "isTransactionConfirmed",
      args: [params.txId, params.owner],
    } as const;
  }

  /** Nonce for `buildConfirmTypedData`. */
  static confirmNonceRead(params: TxParams & { owner: Address }) {
    return {
      address: params.multiSig,
      abi: multiSigWalletWithErrorsAbi,
      functionName: "getConfirmNonce",
      args: [params.txId, params.owner],
    } as const;
  }

  /** Digest the contract will check, to compare with `hashTypedData(buildConfirmTypedData(...))` before signing. */
  static confirmDigestRead(params: TxParams & { signer: Address }) {
    return {
      address: params.multiSig,
      abi: multiSigWalletWithErrorsAbi,
      functionName: "getConfirmDigest",
      args: [params.txId, params.signer],
    } as const;
  }

  /** ERC-5267 domain, for `permitDomainFromEip712Domain`. */
  static eip712DomainRead(multiSig: Address) {
    return { address: multiSig, abi: multiSigWalletWithErrorsAbi, functionName: "eip712Domain" } as const;
  }
}
