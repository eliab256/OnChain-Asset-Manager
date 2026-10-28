import { encodeFunctionData, erc20Abi, maxUint256, type Address } from "viem";
import { permitTokenAbi } from "../abis/fragments.js";
import { ValueOutOfRangeError } from "../errors.js";
import type { MethodParameters } from "./types.js";

/** USDC, the Index assets and the Index shares (the Index is an ERC20 with permit). */
export abstract class Erc20Manager {
  /**
   * For a buy through the Router the spender is the Index, not the Router. An amount of 0 revokes.
   * @throws {ValueOutOfRangeError}
   */
  static approveCallParameters(params: { token: Address; spender: Address; amount: bigint }): MethodParameters {
    if (params.amount < 0n || params.amount > maxUint256) {
      throw new ValueOutOfRangeError("approve", "amount", params.amount, maxUint256);
    }
    return {
      to: params.token,
      calldata: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [params.spender, params.amount] }),
      value: 0n,
    };
  }

  static balanceOfRead(params: { token: Address; owner: Address }) {
    return { address: params.token, abi: erc20Abi, functionName: "balanceOf", args: [params.owner] } as const;
  }

  static allowanceRead(params: { token: Address; owner: Address; spender: Address }) {
    return {
      address: params.token,
      abi: erc20Abi,
      functionName: "allowance",
      args: [params.owner, params.spender],
    } as const;
  }

  /** Permit nonce for `buildPermitTypedData`. */
  static noncesRead(params: { token: Address; owner: Address }) {
    return { address: params.token, abi: permitTokenAbi, functionName: "nonces", args: [params.owner] } as const;
  }

  /** ERC-5267 domain, for `permitDomainFromEip712Domain`. Reverts on mainnet USDC: use `nameRead` + `versionRead`. */
  static eip712DomainRead(token: Address) {
    return { address: token, abi: permitTokenAbi, functionName: "eip712Domain" } as const;
  }

  static nameRead(token: Address) {
    return { address: token, abi: erc20Abi, functionName: "name" } as const;
  }

  static versionRead(token: Address) {
    return { address: token, abi: permitTokenAbi, functionName: "version" } as const;
  }
}
