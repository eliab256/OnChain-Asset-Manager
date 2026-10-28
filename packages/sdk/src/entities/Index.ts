import { maxUint256, type Address } from "viem";
import { MAX_ESTIMATE_DOUBLINGS, STANDARD_UNIT } from "../constants/internal.js";
import { MAX_TOLERANCE, STANDARD_DECIMALS } from "../constants/public.js";
import {
  EstimateNotFoundError,
  IndexNotInitializedError,
  InvalidDecimalsError,
  InvalidPriceError,
  InvalidToleranceError,
  ZeroAmountError,
} from "../errors.js";
import { ceilDiv } from "../utils/bigintMath.js";
import { convertDecimals } from "../utils/decimals.js";
import { isValidTolerance } from "../utils/percentages.js";
import {
  applyFee,
  applyTolerance,
  effectiveWeights,
  isRebalanceNeeded,
  shareValueInUsd,
  sharesToMintFromUsd,
  usdToUsdc,
  usdValueOfAmount,
  usdcToUsd,
} from "../utils/underlyingMath.js";

/**
 * State of an Index at one block. Build it from `IndexManager.snapshotReads` and
 * `PriceFeedReads.price` results with `IndexManager.toSnapshot`.
 */
export type IndexSnapshot = {
  address: Address;
  asset0: Address;
  asset1: Address;
  decimals0: number;
  decimals1: number;
  usdcDecimals: number;
  /** Reserves in token decimals. */
  reserve0: bigint;
  reserve1: bigint;
  /** Target weights, 1e6 scale. */
  weight0: bigint;
  weight1: bigint;
  /** 1e6 scale: 10_000 = 1%. */
  feePercentage: bigint;
  /** Accrued fees not yet collected, as returned by `getFeesInfo`. */
  totalFees: bigint;
  /** Shares, 18 decimals. */
  totalSupply: bigint;
  isInitialized: boolean;
  /** Chainlink prices normalised to 18 decimals by the PriceFeedManager. */
  priceAsset0: bigint;
  priceAsset1: bigint;
  priceUsdc: bigint;
};

export type IndexPrices = Pick<IndexSnapshot, "priceAsset0" | "priceAsset1" | "priceUsdc">;

export type IndexValuation = {
  /** USD values, 18 decimals. */
  usdValue0: bigint;
  usdValue1: bigint;
  totalUsdValue: bigint;
  /** 1e6 scale; both 0 when the Index holds nothing. */
  effectiveWeight0: bigint;
  effectiveWeight1: bigint;
  /** USD value of one share, 18 decimals; 0 when there are no shares. */
  sharePrice: bigint;
};

/**
 * Immutable model of an Index. The previews replicate `Index.minMintPreview` and
 * `Index.minRedeemPreview` with the same rounding, so they equal the on-chain values for the same
 * snapshot. They ignore swap price impact, exactly like the contract previews: the actual mint or
 * redeem is checked on-chain against these minimums.
 */
export class Index {
  readonly snapshot: Readonly<IndexSnapshot>;

  private constructor(snapshot: IndexSnapshot) {
    this.snapshot = Object.freeze({ ...snapshot });
  }

  /**
   * @throws {InvalidDecimalsError} a token has more than 18 decimals
   * @throws {InvalidPriceError} a price is not positive
   */
  static fromSnapshot(snapshot: IndexSnapshot): Index {
    const decimals = [
      ["asset0", snapshot.decimals0],
      ["asset1", snapshot.decimals1],
      ["USDC", snapshot.usdcDecimals],
    ] as const;
    for (const [token, value] of decimals) {
      if (value > STANDARD_DECIMALS) throw new InvalidDecimalsError(token, value);
    }
    const prices = [
      ["asset0", snapshot.priceAsset0],
      ["asset1", snapshot.priceAsset1],
      ["USDC", snapshot.priceUsdc],
    ] as const;
    for (const [asset, price] of prices) {
      if (price <= 0n) throw new InvalidPriceError(asset, price);
    }
    return new Index(snapshot);
  }

  get address(): Address {
    return this.snapshot.address;
  }

  /** Same state with fresh prices, e.g. after a new Chainlink round. */
  withPrices(prices: IndexPrices): Index {
    return Index.fromSnapshot({ ...this.snapshot, ...prices });
  }

  getValuation(): IndexValuation {
    const s = this.snapshot;
    const usdValue0 = usdValueOfAmount(convertDecimals(s.reserve0, s.decimals0, STANDARD_DECIMALS), s.priceAsset0);
    const usdValue1 = usdValueOfAmount(convertDecimals(s.reserve1, s.decimals1, STANDARD_DECIMALS), s.priceAsset1);
    const totalUsdValue = usdValue0 + usdValue1;
    const weights = totalUsdValue === 0n ? { weight0: 0n, weight1: 0n } : effectiveWeights(usdValue0, totalUsdValue);
    return {
      usdValue0,
      usdValue1,
      totalUsdValue,
      effectiveWeight0: weights.weight0,
      effectiveWeight1: weights.weight1,
      sharePrice: s.totalSupply === 0n ? 0n : shareValueInUsd(STANDARD_UNIT, totalUsdValue, s.totalSupply),
    };
  }

  /** @throws {IndexNotInitializedError} */
  needsRebalance(): boolean {
    this.requireInitialized();
    return isRebalanceNeeded(this.getValuation().effectiveWeight0, this.snapshot.weight0);
  }

  /**
   * Minimum shares (18 decimals) for `usdcAmount` (USDC decimals), after fees and tolerance.
   * @throws {IndexNotInitializedError}
   * @throws {InvalidToleranceError}
   */
  minMintPreview(usdcAmount: bigint, tolerance: bigint): bigint {
    this.requireInitialized();
    assertTolerance(tolerance);
    const s = this.snapshot;
    const usdcStd = convertDecimals(usdcAmount, s.usdcDecimals, STANDARD_DECIMALS);
    const netUsd = usdcToUsd(applyFee(usdcStd, s.feePercentage).net, s.priceUsdc);
    const minUsd = applyTolerance(netUsd, tolerance);
    return sharesToMintFromUsd(minUsd, this.getValuation().totalUsdValue, s.totalSupply);
  }

  /**
   * Minimum USDC (USDC decimals) for `sharesAmount` (18 decimals), after fees and tolerance.
   * @throws {IndexNotInitializedError}
   * @throws {InvalidToleranceError}
   */
  minRedeemPreview(sharesAmount: bigint, tolerance: bigint): bigint {
    this.requireInitialized();
    assertTolerance(tolerance);
    const s = this.snapshot;
    const sharesUsd = shareValueInUsd(sharesAmount, this.getValuation().totalUsdValue, s.totalSupply);
    const netUsdcStd = applyFee(usdToUsdc(sharesUsd, s.priceUsdc), s.feePercentage).net;
    return convertDecimals(applyTolerance(netUsdcStd, tolerance), STANDARD_DECIMALS, s.usdcDecimals);
  }

  /**
   * Smallest USDC input whose `minMintPreview` reaches `sharesWanted`. The Router only has
   * exact-input functions: buy with this amount to receive at least `sharesWanted`.
   * @throws {ZeroAmountError} @throws {EstimateNotFoundError}
   */
  estimateUsdcForShares(sharesWanted: bigint, tolerance: bigint): bigint {
    if (sharesWanted <= 0n) throw new ZeroAmountError("estimateUsdcForShares", sharesWanted);
    const probe = 10n ** BigInt(this.snapshot.usdcDecimals);
    const probeShares = this.minMintPreview(probe, tolerance);
    if (probeShares === 0n) throw new EstimateNotFoundError("estimateUsdcForShares", sharesWanted);
    return searchMinimum(
      ceilDiv(sharesWanted * probe, probeShares),
      (usdc) => this.minMintPreview(usdc, tolerance) >= sharesWanted,
      () => new EstimateNotFoundError("estimateUsdcForShares", sharesWanted),
    );
  }

  /**
   * Smallest shares input whose `minRedeemPreview` reaches `usdcWanted`.
   * @throws {ZeroAmountError} @throws {EstimateNotFoundError}
   */
  estimateSharesForUsdc(usdcWanted: bigint, tolerance: bigint): bigint {
    if (usdcWanted <= 0n) throw new ZeroAmountError("estimateSharesForUsdc", usdcWanted);
    const probe = STANDARD_UNIT;
    const probeUsdc = this.minRedeemPreview(probe, tolerance);
    if (probeUsdc === 0n) throw new EstimateNotFoundError("estimateSharesForUsdc", usdcWanted);
    return searchMinimum(
      ceilDiv(usdcWanted * probe, probeUsdc),
      (shares) => this.minRedeemPreview(shares, tolerance) >= usdcWanted,
      () => new EstimateNotFoundError("estimateSharesForUsdc", usdcWanted),
    );
  }

  private requireInitialized(): void {
    if (!this.snapshot.isInitialized) throw new IndexNotInitializedError(this.snapshot.address);
  }
}

function assertTolerance(tolerance: bigint): void {
  if (!isValidTolerance(tolerance)) throw new InvalidToleranceError(tolerance, MAX_TOLERANCE);
}

/**
 * Smallest input for which `isEnough` holds, with `isEnough` monotone (the previews are) and false at 0.
 * Doubles from the linear `guess` until it is enough, then bisects: the guess is only a starting point,
 * because the truncations in the previews can put it on either side of the minimum.
 */
function searchMinimum(guess: bigint, isEnough: (value: bigint) => boolean, onGiveUp: () => Error): bigint {
  let lo = 0n;
  let hi = guess < 1n ? 1n : guess;
  for (let i = 0; !isEnough(hi); i++) {
    if (i >= MAX_ESTIMATE_DOUBLINGS) throw onGiveUp();
    lo = hi;
    hi *= 2n;
  }
  while (hi - lo > 1n) {
    const mid = (lo + hi) / 2n;
    if (isEnough(mid)) hi = mid;
    else lo = mid;
  }
  // The input is encoded as a uint256 argument: a minimum above it is no answer.
  if (hi > maxUint256) throw onGiveUp();
  return hi;
}
