import { isHex, parseSignature, serializeSignature, size, type Address, type Hex } from "viem";
import { InvalidSignatureError } from "../errors.js";

export const PERMIT_TYPES = {
  Permit: [
    { name: "owner", type: "address" },
    { name: "spender", type: "address" },
    { name: "value", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

export type PermitDomain = {
  name: string;
  version: string;
  chainId: number;
  verifyingContract: Address;
};

/** Signature split as `buyExactUsdcAmountOfSharesWithPermit` expects it. */
export type PermitSignature = {
  v: number;
  r: Hex;
  s: Hex;
};

/**
 * Domain from the result of `eip712Domain()` (ERC-5267, e.g. OpenZeppelin `ERC20Permit` and the
 * anvil USDC mock). Mainnet USDC lacks it: build the domain from `name()` and `version()` instead.
 */
export function permitDomainFromEip712Domain(
  result: readonly [Hex, string, string, bigint, Address, Hex, readonly bigint[]],
): PermitDomain {
  const [, name, version, chainId, verifyingContract] = result;
  return { name, version, chainId: Number(chainId), verifyingContract };
}

/**
 * EIP-2612 typed data, ready for `signTypedData` (viem) or `useSignTypedData` (wagmi). For a buy
 * through the Router the spender is the Index: the Router calls `permit(user, index, …)`.
 */
export function buildPermitTypedData(params: {
  domain: PermitDomain;
  owner: Address;
  spender: Address;
  /** Token decimals. */
  value: bigint;
  /** From `nonces(owner)`. */
  nonce: bigint;
  /** Unix timestamp in seconds. */
  deadline: bigint;
}) {
  return {
    domain: params.domain,
    types: PERMIT_TYPES,
    primaryType: "Permit" as const,
    message: {
      owner: params.owner,
      spender: params.spender,
      value: params.value,
      nonce: params.nonce,
      deadline: params.deadline,
    },
  };
}

/**
 * Splits a 65-byte signature into `v, r, s`. Compact EIP-2098 signatures (64 bytes) are rejected:
 * the Router takes `v` explicitly.
 * @throws {InvalidSignatureError}
 */
export function splitPermitSignature(signature: Hex): PermitSignature {
  if (!isHex(signature, { strict: true }) || size(signature) !== 65) {
    throw new InvalidSignatureError(signature, "expected 65 bytes of hex");
  }
  let parsed: ReturnType<typeof parseSignature>;
  try {
    parsed = parseSignature(signature);
  } catch (err) {
    throw new InvalidSignatureError(signature, "viem could not parse it", { cause: err });
  }
  const { r, s, v, yParity } = parsed;
  const vNumber = v === undefined ? yParity + 27 : Number(v);
  if (vNumber !== 27 && vNumber !== 28) throw new InvalidSignatureError(signature, `v is ${vNumber}, expected 27 or 28`);
  return { v: vNumber, r, s };
}

/** Inverse of `splitPermitSignature`. */
export function joinPermitSignature(signature: PermitSignature): Hex {
  return serializeSignature({ r: signature.r, s: signature.s, v: BigInt(signature.v) });
}
