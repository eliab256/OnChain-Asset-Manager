/**
 * Same age check as `PriceFeedManager.getPrice`. `blockTimestamp` must be the chain time (latest
 * block), not the local clock: on the fork the two differ. A stale feed blocks every Index using it.
 */
export function isPriceFeedStale(params: {
  updatedAt: bigint;
  blockTimestamp: bigint;
  maxDelay: number;
}): boolean {
  return params.blockTimestamp - params.updatedAt > BigInt(params.maxDelay);
}
