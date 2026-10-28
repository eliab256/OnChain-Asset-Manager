// Values mirrored from src/ContractCodeConstants.sol. Percentages (fees, tolerances, weights)
// use the contracts' 1e6 scale: 10_000 = 1%.

export const USDC_DECIMALS = 6;
export const SHARES_DECIMALS = 18;
/** Decimals of prices, USD values and normalised amounts (`DECIMALS_STANDARD`). */
export const STANDARD_DECIMALS = 18;

/** `MAX_PERCENTAGE`: 100%. */
export const PERCENTAGE_SCALE = 1_000_000n;

/** `MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION` (10%). Valid tolerances are strictly between 0 and this value. */
export const MAX_TOLERANCE = 100_000n;

/** `REBALANCE_THRESHOLD` (3%): above this distance from the target weight the Index needs a rebalance. */
export const REBALANCE_THRESHOLD = 30_000n;

/** `MIN_WEIGHT` (1%) and `MAX_WEIGHT` (100%): a proposed weight for asset0 must be strictly between them. */
export const MIN_WEIGHT = 10_000n;
export const MAX_WEIGHT = 1_000_000n;

/** `MIN_FEES_PERCENTAGE` (0.1%) and `MAX_FEES_PERCENTAGE` (10%) of the IndexManager: an Index fee must be between them, both included. */
export const MIN_FEE_PERCENTAGE = 1_000n;
export const MAX_FEE_PERCENTAGE = 100_000n;

/** `MAX_FEED_DELAY_LIMIT` (2 days), in seconds: a feed `maxDelay` must be greater than 0 and at most this value. */
export const MAX_FEED_DELAY = 172_800;

/** `IndexAction` in src/types.sol: the enum value is the position in this array. */
export const INDEX_ACTIONS = [
  "INITIALIZE",
  "REBALANCE",
  "PROPOSE_WEIGHTS",
  "EXECUTE_WEIGHTS",
  "CANCEL_WEIGHTS",
  "COLLECT_FEES",
] as const;

export type IndexAction = (typeof INDEX_ACTIONS)[number];
