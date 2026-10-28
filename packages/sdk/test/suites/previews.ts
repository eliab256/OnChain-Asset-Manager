// Differential tests: the SDK Index entity (snapshotReads + toSnapshot + PriceFeedReads prices)
// against the Router views at the same block, and the estimates checked against the contract.
import { fc, test } from "@fast-check/vitest";
import { describe, expect, it } from "vitest";
import { MAX_TOLERANCE, RouterManager, parseShares, parseUsdc, type Index } from "../../src/index.js";
import {
  balanceOf,
  buyShares,
  loadIndex,
  moveMockPrice,
  readPrices,
  send,
  type ForkContext,
} from "../helpers/chain.js";
import { TOLERANCE } from "./router.js";

// Each run is a handful of RPC reads against the node, so the fork budget stays small.
const FORK_RUNS = { numRuns: 15 };

// Realistic bounds: 1 USDC unit up to 10M USDC; tolerance strictly inside (0, MAX_TOLERANCE) as the
// Router enforces. Values fit uint256 by construction, so TS bigint and Solidity cannot diverge here.
const usdcAmountArb = fc.bigInt({ min: 1n, max: 10_000_000n * 10n ** 6n });
const toleranceArb = fc.bigInt({ min: 1n, max: MAX_TOLERANCE - 1n });

async function atLatest(ctx: ForkContext): Promise<{ blockNumber: bigint; fund: Index }> {
  const blockNumber = await ctx.publicClient.getBlockNumber();
  return { blockNumber, fund: await loadIndex(ctx, { blockNumber }) };
}

async function contractMintPreview(ctx: ForkContext, usdcAmount: bigint, tolerance: bigint, blockNumber?: bigint) {
  return ctx.publicClient.readContract({
    ...RouterManager.minMintPreviewRead({ router: ctx.addresses.router, index: ctx.index, usdcAmount, tolerance }),
    ...(blockNumber === undefined ? {} : { blockNumber }),
  });
}

async function contractRedeemPreview(ctx: ForkContext, sharesAmount: bigint, tolerance: bigint, blockNumber?: bigint) {
  return ctx.publicClient.readContract({
    ...RouterManager.minRedeemPreviewRead({ router: ctx.addresses.router, index: ctx.index, sharesAmount, tolerance }),
    ...(blockNumber === undefined ? {} : { blockNumber }),
  });
}

export function previewsSuite(ctx: ForkContext): void {
  describe("Index.minMintPreview / minRedeemPreview against the Router at the same block", () => {
    test.prop([usdcAmountArb, toleranceArb], FORK_RUNS)("minMintPreview equals Router.getMinMintPreview", async (usdcAmount, tolerance) => {
      const { blockNumber, fund } = await atLatest(ctx);
      expect(fund.minMintPreview(usdcAmount, tolerance)).toBe(
        await contractMintPreview(ctx, usdcAmount, tolerance, blockNumber),
      );
    });

    // Up to the whole supply: redeeming more than exists is not a state the contract can reach.
    test.prop([fc.bigInt({ min: 1n, max: 10n ** 30n }), toleranceArb], FORK_RUNS)(
      "minRedeemPreview equals Router.getMinRedeemPreview",
      async (raw, tolerance) => {
        const { blockNumber, fund } = await atLatest(ctx);
        const sharesAmount = (raw % fund.snapshot.totalSupply) + 1n;
        expect(fund.minRedeemPreview(sharesAmount, tolerance)).toBe(
          await contractRedeemPreview(ctx, sharesAmount, tolerance, blockNumber),
        );
      },
    );

    it("still equal after buys and sells moved supply, reserves and accrued fees", async () => {
      await buyShares(ctx, ctx.user, parseUsdc("12345.678901"), TOLERANCE);
      const shares = await balanceOf(ctx, ctx.index, ctx.user.account.address);
      await send(
        ctx,
        ctx.user,
        RouterManager.sellCallParameters({
          router: ctx.addresses.router,
          index: ctx.index,
          sharesAmount: shares / 3n,
          tolerance: TOLERANCE,
        }),
      );
      const { blockNumber, fund } = await atLatest(ctx);
      expect(fund.snapshot.totalFees).toBeGreaterThan(0n);
      for (const tolerance of [1n, TOLERANCE, MAX_TOLERANCE - 1n]) {
        for (const usdcAmount of [1n, parseUsdc("1"), parseUsdc("999999.999999")]) {
          expect(fund.minMintPreview(usdcAmount, tolerance)).toBe(
            await contractMintPreview(ctx, usdcAmount, tolerance, blockNumber),
          );
        }
        for (const sharesAmount of [1n, parseShares("1"), shares / 7n]) {
          expect(fund.minRedeemPreview(sharesAmount, tolerance)).toBe(
            await contractRedeemPreview(ctx, sharesAmount, tolerance, blockNumber),
          );
        }
      }
    });

    it("previews read at an older block reproduce that block, not the current state", async () => {
      const { blockNumber, fund } = await atLatest(ctx);
      const usdcAmount = parseUsdc("1000");
      await buyShares(ctx, ctx.user, parseUsdc("50000"), TOLERANCE);
      expect(fund.minMintPreview(usdcAmount, TOLERANCE)).toBe(
        await contractMintPreview(ctx, usdcAmount, TOLERANCE, blockNumber),
      );
    });

    it.runIf(ctx.isMock)("stale state: after a price move only withPrices(fresh prices) matches the contract again", async () => {
      const stale = await loadIndex(ctx);
      await moveMockPrice(ctx, ctx.asset0, 110n, 100n);
      const { blockNumber } = await atLatest(ctx);
      const fresh = stale.withPrices(await readPrices(ctx, { blockNumber }));
      const sharesAmount = parseShares("100");
      const onChain = await contractRedeemPreview(ctx, sharesAmount, TOLERANCE, blockNumber);
      expect(stale.minRedeemPreview(sharesAmount, TOLERANCE)).not.toBe(onChain);
      expect(fresh.minRedeemPreview(sharesAmount, TOLERANCE)).toBe(onChain);
      // withPrices is immutable: the old instance keeps the old prices.
      expect(stale.snapshot.priceAsset0).not.toBe(fresh.snapshot.priceAsset0);
    });
  });

  describe("Index.estimateUsdcForShares / estimateSharesForUsdc verified on chain", () => {
    it("estimateUsdcForShares: the contract preview of the estimate reaches the target and the buy delivers it", async () => {
      const fund = await loadIndex(ctx);
      const sharesWanted = parseShares("250");
      const usdcAmount = fund.estimateUsdcForShares(sharesWanted, TOLERANCE);
      expect(await contractMintPreview(ctx, usdcAmount, TOLERANCE)).toBeGreaterThanOrEqual(sharesWanted);

      const receipt = await buyShares(ctx, ctx.user, usdcAmount, TOLERANCE);
      expect(receipt.status).toBe("success");
      // Estimates never under-deliver: the user ends up with at least the shares asked for.
      expect(await balanceOf(ctx, ctx.index, ctx.user.account.address)).toBeGreaterThanOrEqual(sharesWanted);
    });

    it("estimateUsdcForShares is the smallest input: one USDC unit less misses the target on chain", async () => {
      const fund = await loadIndex(ctx);
      for (const sharesWanted of [parseShares("1"), parseShares("250"), parseShares("123456.789")]) {
        const usdcAmount = fund.estimateUsdcForShares(sharesWanted, TOLERANCE);
        expect(await contractMintPreview(ctx, usdcAmount - 1n, TOLERANCE)).toBeLessThan(sharesWanted);
      }
    });

    // The linear guess from a 1-share probe overshoots for large targets: the search must return the exact minimum.
    it("estimateSharesForUsdc is the smallest input: it equals the true minimum, confirmed by the contract", async () => {
      await buyShares(ctx, ctx.user, parseUsdc("200000"), TOLERANCE);
      const fund = await loadIndex(ctx);
      for (const usdcWanted of [parseUsdc("1"), parseUsdc("5000"), parseUsdc("123456.789")]) {
        const estimate = fund.estimateSharesForUsdc(usdcWanted, TOLERANCE);
        // Binary search on the offline preview, which the differential tests above prove equal to the contract.
        let lo = 0n;
        let hi = estimate;
        while (hi - lo > 1n) {
          const mid = (lo + hi) / 2n;
          if (fund.minRedeemPreview(mid, TOLERANCE) >= usdcWanted) hi = mid;
          else lo = mid;
        }
        expect(await contractRedeemPreview(ctx, hi, TOLERANCE)).toBeGreaterThanOrEqual(usdcWanted);
        expect(await contractRedeemPreview(ctx, hi - 1n, TOLERANCE)).toBeLessThan(usdcWanted);
        expect(estimate).toBe(hi);
      }
    });

    it("estimateSharesForUsdc: the contract preview of the estimate reaches the target and the sell delivers it", async () => {
      await buyShares(ctx, ctx.user, parseUsdc("20000"), TOLERANCE);
      const fund = await loadIndex(ctx);
      const usdcWanted = parseUsdc("5000");
      const sharesAmount = fund.estimateSharesForUsdc(usdcWanted, TOLERANCE);
      expect(await contractRedeemPreview(ctx, sharesAmount, TOLERANCE)).toBeGreaterThanOrEqual(usdcWanted);
      expect(sharesAmount).toBeLessThanOrEqual(await balanceOf(ctx, ctx.index, ctx.user.account.address));

      const usdcBefore = await balanceOf(ctx, ctx.addresses.usdc, ctx.user.account.address);
      await send(
        ctx,
        ctx.user,
        RouterManager.sellCallParameters({ router: ctx.addresses.router, index: ctx.index, sharesAmount, tolerance: TOLERANCE }),
      );
      expect((await balanceOf(ctx, ctx.addresses.usdc, ctx.user.account.address)) - usdcBefore).toBeGreaterThanOrEqual(
        usdcWanted,
      );
    });
  });
}
