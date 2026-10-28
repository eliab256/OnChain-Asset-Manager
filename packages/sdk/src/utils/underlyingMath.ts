import { PERCENTAGE_SCALE, REBALANCE_THRESHOLD } from "../constants/public.js";
import { STANDARD_UNIT } from "../constants/internal.js";
import { absDiff } from "./bigintMath.js";

// TypeScript port of the pure math in src/libraries/UnderlyingMath.sol, src/libraries/SharesMath.sol
// and the preview helpers of src/Index.sol. Every division truncates like Solidity, in the same
// order, so the results match the contract to the unit. Amounts are 18-decimal unless noted.

/** `UnderlyingMath.calculateUSDValueOfTokenAmountStdDecimals`. */
export function usdValueOfAmount(amountStd: bigint, price: bigint): bigint {
  return (amountStd * price) / STANDARD_UNIT;
}

/** `Index._usdcToUsd`. */
export function usdcToUsd(usdcAmountStd: bigint, priceUsdc: bigint): bigint {
  return (usdcAmountStd * priceUsdc) / STANDARD_UNIT;
}

/** `Index._usdToUsdc`. */
export function usdToUsdc(usdValue: bigint, priceUsdc: bigint): bigint {
  return (usdValue * STANDARD_UNIT) / priceUsdc;
}

/** `Index._calculateFees`. */
export function applyFee(amount: bigint, feePercentage: bigint): { fee: bigint; net: bigint } {
  const fee = (amount * feePercentage) / PERCENTAGE_SCALE;
  return { fee, net: amount - fee };
}

/** `SharesMath.calculateNetAmountFromTolerance`. */
export function applyTolerance(amount: bigint, tolerance: bigint): bigint {
  return (amount * (PERCENTAGE_SCALE - tolerance)) / PERCENTAGE_SCALE;
}

/** `SharesMath.calculateSharesToMintFromUsdcAmount` (the input is a USD value, despite the name). */
export function sharesToMintFromUsd(usdValue: bigint, totalUsdValue: bigint, totalShares: bigint): bigint {
  return totalShares === 0n ? usdValue : (usdValue * totalShares) / totalUsdValue;
}

/** `SharesMath.calculateShareValueInUsd`. */
export function shareValueInUsd(sharesAmount: bigint, totalUsdValue: bigint, totalShares: bigint): bigint {
  return totalUsdValue === 0n ? 0n : (sharesAmount * totalUsdValue) / totalShares;
}

/** `UnderlyingMath.calculateEffectiveWeights` on the 1e6 scale. */
export function effectiveWeights(usdValue0: bigint, totalUsdValue: bigint): { weight0: bigint; weight1: bigint } {
  const weight0 = (usdValue0 * PERCENTAGE_SCALE) / totalUsdValue;
  return { weight0, weight1: PERCENTAGE_SCALE - weight0 };
}

/** `Index._checkIfRebalanceNeeded`: only asset0 is compared, asset1 is its complement. */
export function isRebalanceNeeded(effectiveWeight0: bigint, targetWeight0: bigint): boolean {
  return absDiff(effectiveWeight0, targetWeight0) > REBALANCE_THRESHOLD;
}
