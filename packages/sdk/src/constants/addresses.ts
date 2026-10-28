import { isSupportedChainId, protocolAddresses, type ProtocolAddresses } from "@oam/abi";
import { UnsupportedChainError } from "../errors.js";

export type { ProtocolAddresses, SupportedChainId } from "@oam/abi";

/**
 * Proxy addresses of the protocol from deployments/<chainId>.json.
 * @throws {UnsupportedChainError} no deployment file for `chainId`
 */
export function getProtocolAddresses(chainId: number): ProtocolAddresses {
  if (!isSupportedChainId(chainId)) throw new UnsupportedChainError(chainId);
  return protocolAddresses[chainId];
}
