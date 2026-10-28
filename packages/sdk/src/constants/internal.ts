// Not re-exported from src/index.ts.

export const STANDARD_UNIT = 10n ** 18n;

/**
 * The exact-out estimates double their linear guess until the forward preview reaches the target,
 * then bisect. 256 doublings from 1 cover the whole uint256 range.
 */
export const MAX_ESTIMATE_DOUBLINGS = 256;
