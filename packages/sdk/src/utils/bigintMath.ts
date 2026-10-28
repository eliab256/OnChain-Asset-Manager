/** Division rounded up, for non-negative operands. Plain `/` on bigint rounds down like Solidity. */
export function ceilDiv(numerator: bigint, denominator: bigint): bigint {
  return (numerator + denominator - 1n) / denominator;
}

export function absDiff(a: bigint, b: bigint): bigint {
  return a > b ? a - b : b - a;
}
