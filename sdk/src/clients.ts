import {
  createPublicClient,
  createWalletClient,
  http,
  type Chain,
  type PublicClient,
  type WalletClient,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

export function createNewPublicClient(
  chain: Chain,
  rpcUrl?: string,
): PublicClient {
  return createPublicClient({
    chain: chain,
    transport: http(rpcUrl),
  });
}

export function createNewWalletClient(
  chain: Chain,
  rpcUrl: string,
  privateKey: `0x${string}`,
): WalletClient {
  const account = privateKeyToAccount(privateKey);
  return createWalletClient({
    chain: chain,
    transport: http(rpcUrl),
    account: account,
  });
}
