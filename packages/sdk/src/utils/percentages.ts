import { MAX_TOLERANCE, MAX_WEIGHT, MIN_WEIGHT } from "../constants/public.js";

/** 50 bps → 5_000 (0.5% on the 1e6 scale). */
export function toleranceFromBasisPoints(basisPoints: bigint): bigint {
  return basisPoints * 100n;
}

/** Same rule as `Router._validTolerance`. */
export function isValidTolerance(tolerance: bigint): boolean {
  return tolerance > 0n && tolerance < MAX_TOLERANCE;
}

/** Bounds of `Index.proposeUpdateWeights`; the contract also rejects the current weight. */
export function isValidWeight(weight: bigint): boolean {
  return weight > MIN_WEIGHT && weight < MAX_WEIGHT;
}
