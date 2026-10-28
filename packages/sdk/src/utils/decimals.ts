import { formatUnits, parseUnits } from "viem";
import { SHARES_DECIMALS, STANDARD_DECIMALS, USDC_DECIMALS } from "../constants/public.js";

export function parseUsdc(value: string): bigint {
  return parseUnits(value, USDC_DECIMALS);
}

export function formatUsdc(amount: bigint): string {
  return formatUnits(amount, USDC_DECIMALS);
}

export function parseShares(value: string): bigint {
  return parseUnits(value, SHARES_DECIMALS);
}

export function formatShares(amount: bigint): string {
  return formatUnits(amount, SHARES_DECIMALS);
}

/** Prices and USD values returned by the contracts have 18 decimals. */
export function formatUsdValue(value: bigint): string {
  return formatUnits(value, STANDARD_DECIMALS);
}

/** `UnderlyingMath.convertToSpecificDecimal`: scaling down truncates, like the contract. */
export function convertDecimals(amount: bigint, fromDecimals: number, toDecimals: number): bigint {
  if (toDecimals === fromDecimals) return amount;
  if (toDecimals > fromDecimals) return amount * 10n ** BigInt(toDecimals - fromDecimals);
  return amount / 10n ** BigInt(fromDecimals - toDecimals);
}
