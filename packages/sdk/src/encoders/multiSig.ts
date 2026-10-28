import {
  indexManagerAbi,
  multiSigWalletAbi,
  priceFeedManagerAbi,
  routerAbi,
  swapManagerAbi,
  timelockControllerAbi,
} from "@oam/abi";
import {
  decodeFunctionData,
  encodeAbiParameters,
  encodeEventTopics,
  erc20Abi,
  hexToBigInt,
  hexToNumber,
  isAddressEqual,
  keccak256,
  parseEventLogs,
  slice,
  type Abi,
  type Address,
  type Hex,
  type Log,
} from "viem";
import type { ProtocolAddresses } from "../constants/addresses.js";
import { EventNotFoundError, InvalidSignatureError, UnknownProposalError } from "../errors.js";
import { joinPermitSignature, splitPermitSignature, type PermitDomain } from "./permit.js";

/** Half the secp256k1 order: OpenZeppelin `ECDSA.recover` rejects a larger `s` (malleable signature). */
const SECP256K1_HALF_N = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0n;

/** `CONFIRM_TYPEHASH` of src/MultiSigWallet.sol. */
export const CONFIRM_TYPES = {
  Confirm: [
    { name: "txId", type: "uint256" },
    { name: "target", type: "address" },
    { name: "value", type: "uint256" },
    { name: "dataHash", type: "bytes32" },
    { name: "nonce", type: "uint256" },
  ],
} as const;

/**
 * EIP-712 typed data of a MultiSig confirmation, ready for `signTypedData` (viem) or `useSignTypedData` (wagmi).
 * Anyone can then submit the signature with `MultiSigCalls.confirmWithSigCallParameters`.
 * `target`, `value` and `data` are those stored in the MultiSig (`MultiSigCalls.transactionRead`), not those of the
 * proposal you meant to make: decode them with `decodeProposal` before signing.
 */
export function buildConfirmTypedData(params: {
  /** From `MultiSigCalls.eip712DomainRead` through `permitDomainFromEip712Domain`. */
  domain: PermitDomain;
  txId: bigint;
  target: Address;
  /** Wei. */
  value: bigint;
  data: Hex;
  /** From `MultiSigCalls.confirmNonceRead` for this txId and signer; it grows at every revoke. */
  nonce: bigint;
}) {
  return {
    domain: params.domain,
    types: CONFIRM_TYPES,
    primaryType: "Confirm" as const,
    message: {
      txId: params.txId,
      target: params.target,
      value: params.value,
      dataHash: keccak256(params.data),
      nonce: params.nonce,
    },
  };
}

/**
 * Checks that a confirmation signature is one `ECDSA.recover` accepts as is: 65 bytes `r, s, v` with v = 27 or 28 and
 * low `s`. Wallets that return v = 0 / 1 are handled by `normalizeConfirmSignature`.
 * @throws {InvalidSignatureError}
 */
export function assertConfirmSignature(signature: Hex): void {
  splitPermitSignature(signature);
  const v = hexToNumber(slice(signature, 64, 65));
  if (v !== 27 && v !== 28) throw new InvalidSignatureError(signature, `v byte is ${v}, expected 27 or 28`);
  if (hexToBigInt(slice(signature, 32, 64)) > SECP256K1_HALF_N) {
    throw new InvalidSignatureError(signature, "s is in the upper half of the curve order (malleable signature)");
  }
}

/**
 * The signature with v rewritten as 27 / 28, checked with `assertConfirmSignature`. A high-s signature is rejected,
 * not flipped: sign again with a standard wallet.
 * @throws {InvalidSignatureError}
 */
export function normalizeConfirmSignature(signature: Hex): Hex {
  const normalized = joinPermitSignature(splitPermitSignature(signature));
  assertConfirmSignature(normalized);
  return normalized;
}

export type TransactionSubmittedEvent = {
  txId: bigint;
  proposer: Address;
  target: Address;
  /** Wei. */
  value: bigint;
  data: Hex;
};

export type TransactionConfirmedEvent = { txId: bigint; owner: Address };
export type ConfirmationRevokedEvent = { txId: bigint; owner: Address };
export type TransactionExecutedEvent = { txId: bigint; executor: Address };

/** A log as found in `receipt.logs`; only address, topics and data are read. */
type ReceiptLog = Log<bigint, number, boolean>;

function toLog(address: Address, topics: readonly (Hex | Hex[] | null)[], data: Hex): ReceiptLog {
  const [signature, ...indexed] = topics.filter((topic): topic is Hex => typeof topic === "string");
  return {
    address,
    topics: signature ? [signature, ...indexed] : [],
    data,
    blockHash: null,
    blockNumber: null,
    logIndex: null,
    transactionHash: null,
    transactionIndex: null,
    removed: false,
  };
}

/**
 * The proposal of a `submitTransaction` receipt; `txId` is what the owners confirm and execute.
 * Only logs emitted by `multiSig` count.
 * @throws {EventNotFoundError}
 */
export function parseTransactionSubmitted(logs: readonly ReceiptLog[], multiSig: Address): TransactionSubmittedEvent {
  const event = parseEventLogs({ abi: multiSigWalletAbi, eventName: "TransactionSubmitted", logs: [...logs] }).find(
    (log) => isAddressEqual(log.address, multiSig),
  );
  if (!event) throw new EventNotFoundError("TransactionSubmitted", multiSig);
  return { ...event.args };
}

/** @throws {EventNotFoundError} */
export function parseTransactionConfirmed(logs: readonly ReceiptLog[], multiSig: Address): TransactionConfirmedEvent {
  const event = parseEventLogs({ abi: multiSigWalletAbi, eventName: "TransactionConfirmed", logs: [...logs] }).find(
    (log) => isAddressEqual(log.address, multiSig),
  );
  if (!event) throw new EventNotFoundError("TransactionConfirmed", multiSig);
  return { ...event.args };
}

/** @throws {EventNotFoundError} */
export function parseConfirmationRevoked(logs: readonly ReceiptLog[], multiSig: Address): ConfirmationRevokedEvent {
  const event = parseEventLogs({ abi: multiSigWalletAbi, eventName: "ConfirmationRevoked", logs: [...logs] }).find(
    (log) => isAddressEqual(log.address, multiSig),
  );
  if (!event) throw new EventNotFoundError("ConfirmationRevoked", multiSig);
  return { ...event.args };
}

/**
 * The events of the executed call (e.g. `IndexCreated`) are in the same receipt.
 * @throws {EventNotFoundError}
 */
export function parseTransactionExecuted(logs: readonly ReceiptLog[], multiSig: Address): TransactionExecutedEvent {
  const event = parseEventLogs({ abi: multiSigWalletAbi, eventName: "TransactionExecuted", logs: [...logs] }).find(
    (log) => isAddressEqual(log.address, multiSig),
  );
  if (!event) throw new EventNotFoundError("TransactionExecuted", multiSig);
  return { ...event.args };
}

/** Inverse of `parseTransactionSubmitted`. */
export function encodeTransactionSubmittedLog(multiSig: Address, event: TransactionSubmittedEvent): ReceiptLog {
  const topics = encodeEventTopics({
    abi: multiSigWalletAbi,
    eventName: "TransactionSubmitted",
    args: { txId: event.txId, proposer: event.proposer, target: event.target },
  });
  const data = encodeAbiParameters([{ type: "uint256" }, { type: "bytes" }], [event.value, event.data]);
  return toLog(multiSig, topics, data);
}

/** Inverse of `parseTransactionConfirmed`. */
export function encodeTransactionConfirmedLog(multiSig: Address, event: TransactionConfirmedEvent): ReceiptLog {
  const topics = encodeEventTopics({ abi: multiSigWalletAbi, eventName: "TransactionConfirmed", args: { ...event } });
  return toLog(multiSig, topics, "0x");
}

/** Inverse of `parseConfirmationRevoked`. */
export function encodeConfirmationRevokedLog(multiSig: Address, event: ConfirmationRevokedEvent): ReceiptLog {
  const topics = encodeEventTopics({ abi: multiSigWalletAbi, eventName: "ConfirmationRevoked", args: { ...event } });
  return toLog(multiSig, topics, "0x");
}

/** Inverse of `parseTransactionExecuted`. */
export function encodeTransactionExecutedLog(multiSig: Address, event: TransactionExecutedEvent): ReceiptLog {
  const topics = encodeEventTopics({ abi: multiSigWalletAbi, eventName: "TransactionExecuted", args: { ...event } });
  return toLog(multiSig, topics, "0x");
}

export type ProposalContract =
  | "IndexManager"
  | "PriceFeedManager"
  | "SwapManager"
  | "Router"
  | "MultiSigWallet"
  | "TimelockController"
  | "ERC20";

/** What a MultiSig proposal calls, to show to an owner before they confirm it. */
export type DecodedProposal = {
  contract: ProposalContract;
  target: Address;
  functionName: string;
  args: readonly unknown[];
  /** Wei. */
  value: bigint;
};

/**
 * Decodes the call a MultiSig transaction makes. The ABI is chosen by `target` among the protocol contracts in
 * `addresses`; any other target is decoded as an ERC20 (e.g. an `approve` before `initializeIndex`).
 * @throws {UnknownProposalError} the target is not a protocol contract and the calldata is not an ERC20 call
 */
export function decodeProposal(
  proposal: { target: Address; value: bigint; data: Hex },
  addresses: ProtocolAddresses,
): DecodedProposal {
  const known: readonly [Address, ProposalContract, Abi][] = [
    [addresses.indexManager, "IndexManager", indexManagerAbi],
    [addresses.priceFeedManager, "PriceFeedManager", priceFeedManagerAbi],
    [addresses.swapManager, "SwapManager", swapManagerAbi],
    [addresses.router, "Router", routerAbi],
    [addresses.multiSigWallet, "MultiSigWallet", multiSigWalletAbi],
    [addresses.timelock, "TimelockController", timelockControllerAbi],
  ];
  const match = known.find(([address]) => isAddressEqual(address, proposal.target));
  const [contract, abi]: [ProposalContract, Abi] = match ? [match[1], match[2]] : ["ERC20", erc20Abi];
  let decoded: { functionName: string; args?: readonly unknown[] | undefined };
  try {
    decoded = decodeFunctionData({ abi, data: proposal.data });
  } catch (err) {
    throw new UnknownProposalError(proposal.target, `the calldata is not a ${contract} function`, { cause: err });
  }
  return {
    contract,
    target: proposal.target,
    functionName: decoded.functionName,
    args: decoded.args ?? [],
    value: proposal.value,
  };
}
