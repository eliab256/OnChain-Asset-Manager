import type { Address, Hex } from "viem";

/**
 * A ready-to-send contract call. Send it with any client:
 * viem `walletClient.sendTransaction({ to, data: calldata, value })` or wagmi `useSendTransaction`.
 */
export type MethodParameters = {
  to: Address;
  calldata: Hex;
  value: bigint;
};
