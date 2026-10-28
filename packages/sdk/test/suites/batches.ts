// The IndexManager batch calls executed on chain, their receipts classified with
// parseRebalanceBatch / parseWeightUpdateBatch / parseCollectFeesBatch, and every list checked
// against the state the chain reports afterwards (reserves, weights, pending proposals, balances).
//
// On anvil 31337 two more Indexes are created from the mock LINK and COMP, so one batch holds an
// Index in each state:
//   A = the deployed WBTC/WETH Index: its WBTC price is moved, so it needs a rebalance;
//   B = LINK/COMP: the COMP feed is made stale, so every action that prices it fails;
//   C = WETH/LINK: untouched, within the threshold.
// A is listed twice: the second call finds the work already done.
// On the mainnet fork the feeds cannot be moved and a warp makes them all stale, so only the
// outcomes reachable with the deployed Index (listed twice) run there.
import { indexManagerAbi } from "@oam/abi";
import { encodeFunctionData, parseAbi, type Address, type Hex } from "viem";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  IndexManager,
  IndexManagerCalls,
  MAX_WEIGHT,
  encodeProtocolError,
  parseCollectFeesBatch,
  parseRebalanceBatch,
  parseUsdc,
  parseWeightUpdateBatch,
  type FailureReason,
} from "../../src/index.js";
import {
  balanceOf,
  buyShares,
  chainNow,
  configureMockUniversalRouter,
  dealErc20,
  feedOf,
  impersonateMultiSig,
  makeMockFeedStale,
  moveMockPrice,
  refreshMockFeeds,
  revert,
  send,
  snapshot,
  type ForkContext,
} from "../helpers/chain.js";
import { createMockIndex, extraMockAssets } from "../helpers/indexes.js";
import { TOLERANCE } from "./router.js";

/**
 * Explicit limit, as for every batch (see KEEPER_GAS_LIMIT in suites/indexManager.ts): a batch turns
 * an out of gas of one Index into IndexActionFailed(0x) and goes on. Four actions, two of them with swaps.
 */
const BATCH_GAS_LIMIT = 10_000_000n;
const WEIGHT_UPDATE_DELAY = 2n * 24n * 3600n;
const STALE_FOR = 2n * 24n * 3600n;

const PRICE_IS_STALE = encodeProtocolError({ errorName: "PriceFeedManager__PriceIsStale" });
const NOT_PENDING = encodeProtocolError({ errorName: "Index__NotPendingWeightUpdate" });
const protocolReason = (errorName: string, args: readonly unknown[] = []): FailureReason => ({ kind: "protocol", errorName, args });

// MockUSDC (test/mocks/USDCMock.sol) has a public burn: the way to leave an Index short of its fees on 31337.
const mockUsdcAbi = parseAbi(["function burn(address from, uint256 amount)"]);

export function batchesSuite(ctx: ForkContext): void {
  const indexManager = () => ctx.addresses.indexManager;
  const deployer = () => ctx.deployer.account.address;

  const reserves = async (index: Address) => ctx.publicClient.readContract(IndexManager.snapshotReads(index)[3]);
  const weights = async (index: Address) => ctx.publicClient.readContract(IndexManager.snapshotReads(index)[4]);
  const accruedFees = async (index: Address) => (await ctx.publicClient.readContract(IndexManager.snapshotReads(index)[5]))[1];
  const pendingOf = async (index: Address) =>
    IndexManager.toPendingWeightUpdate(await ctx.publicClient.readContract(IndexManager.pendingWeightsRead(index)));
  const totalFeesCollected = async () =>
    ctx.publicClient.readContract({ address: indexManager(), abi: indexManagerAbi, functionName: "getTotalFeesCollected" });

  async function proposeAndWait(proposals: readonly (readonly [Address, bigint])[]) {
    const multiSig = await impersonateMultiSig(ctx);
    for (const [index, newWeight0] of proposals) {
      await send(ctx, multiSig, IndexManagerCalls.proposeNewWeightsCallParameters({ indexManager: indexManager(), index, newWeight0 }));
    }
    await ctx.testClient.increaseTime({ seconds: Number(WEIGHT_UPDATE_DELAY + 1n) });
    await ctx.testClient.mine({ blocks: 1 });
    return multiSig;
  }

  describe.runIf(ctx.isMock)("batches over three Indexes (anvil mocks)", () => {
    const { link, comp } = extraMockAssets();
    const A = () => ctx.index;
    let B: Address;
    let C: Address;
    let base: Hex;

    // Created once for the three tests: each test runs inside the snapshot of the entry file, which
    // brings the chain back here; afterAll removes the Indexes so the suites after this one see the deploy.
    beforeAll(async () => {
      base = await snapshot(ctx);
      B = await createMockIndex(ctx, link, comp);
      // WETH already has its feed registered by the deploy: createMockIndex skips it.
      C = await createMockIndex(ctx, { token: ctx.asset1, feed: await feedOf(ctx, ctx.asset1) }, link);
      await configureMockUniversalRouter(ctx, undefined, [link.token, comp.token]);
    });
    afterAll(async () => {
      await revert(ctx, base);
    });

    it("setup: B holds LINK/COMP, C holds WETH and LINK, none holds WBTC except A", async () => {
      const assetsOf = async (index: Address) => {
        const [asset0, asset1] = IndexManager.snapshotReads(index);
        return [await ctx.publicClient.readContract(asset0), await ctx.publicClient.readContract(asset1)];
      };
      expect((await assetsOf(B)).sort()).toEqual([link.token, comp.token].sort());
      expect((await assetsOf(C)).sort()).toEqual([ctx.asset1, link.token].sort());
      expect(await assetsOf(A())).toContain(ctx.asset0);
    });

    it("rebalanceMultipleIndexes: rebalanced, not needed and failed (stale price), each list in the order of `indexes`", async () => {
      await moveMockPrice(ctx, ctx.asset0, 120n, 100n);
      await makeMockFeedStale(ctx, comp.token, (await chainNow(ctx)) - STALE_FOR);
      const indexes = [A(), C, B, A()];
      const beforeA = await reserves(A());
      const beforeB = await reserves(B);
      const beforeC = await reserves(C);

      const receipt = await send(
        ctx,
        ctx.deployer,
        IndexManagerCalls.rebalanceManyCallParameters({ indexManager: indexManager(), indexes }),
        { gas: BATCH_GAS_LIMIT },
      );
      const afterA = await reserves(A());

      expect(parseRebalanceBatch(receipt.logs, { indexManager: indexManager(), indexes })).toEqual({
        rebalanced: [
          {
            index: A(),
            asset0ReserveBefore: beforeA[0],
            asset1ReserveBefore: beforeA[1],
            asset0ReserveAfter: afterA[0],
            asset1ReserveAfter: afterA[1],
          },
        ],
        notNeeded: [{ index: C }, { index: A() }],
        failed: [{ index: B, reasonData: PRICE_IS_STALE, reason: protocolReason("PriceFeedManager__PriceIsStale") }],
      });
      // WBTC went up 20%: the rebalance sold WBTC (asset0 of A) for WETH.
      expect(afterA[0]).toBeLessThan(beforeA[0]);
      expect(afterA[1]).toBeGreaterThan(beforeA[1]);
      expect(await reserves(B)).toEqual(beforeB);
      expect(await reserves(C)).toEqual(beforeC);
    });

    it("executeWeightUpdateForMultipleIndexes: rebalanced, skipped, rebalance failed, and not pending", async () => {
      // A moves 10% (past the 3% threshold), C 1% (within it), B prices a stale COMP in its rebalance.
      const multiSig = await proposeAndWait([
        [A(), 600_000n],
        [C, 510_000n],
        [B, 400_000n],
      ]);
      await refreshMockFeeds(ctx, [link.token, comp.token]);
      await makeMockFeedStale(ctx, comp.token, (await chainNow(ctx)) - STALE_FOR);
      const indexes = [A(), C, B, A()];
      const beforeA = await reserves(A());
      const beforeB = await reserves(B);
      const beforeC = await reserves(C);

      const receipt = await send(
        ctx,
        multiSig,
        IndexManagerCalls.executeWeightUpdateManyCallParameters({ indexManager: indexManager(), indexes }),
        { gas: BATCH_GAS_LIMIT },
      );
      const afterA = await reserves(A());

      expect(parseWeightUpdateBatch(receipt.logs, { indexManager: indexManager(), indexes })).toEqual({
        updated: [
          {
            index: A(),
            asset0Weight: 600_000n,
            asset1Weight: MAX_WEIGHT - 600_000n,
            rebalance: {
              status: "rebalanced",
              asset0ReserveBefore: beforeA[0],
              asset1ReserveBefore: beforeA[1],
              asset0ReserveAfter: afterA[0],
              asset1ReserveAfter: afterA[1],
            },
          },
          { index: C, asset0Weight: 510_000n, asset1Weight: MAX_WEIGHT - 510_000n, rebalance: { status: "skipped" } },
          {
            index: B,
            asset0Weight: 400_000n,
            asset1Weight: MAX_WEIGHT - 400_000n,
            rebalance: { status: "failed", reasonData: PRICE_IS_STALE, reason: protocolReason("PriceFeedManager__PriceIsStale") },
          },
        ],
        failed: [{ index: A(), reasonData: NOT_PENDING, reason: protocolReason("Index__NotPendingWeightUpdate") }],
      });
      // The parsed lists agree with the chain: weights applied everywhere, proposals consumed,
      // reserves moved only where the rebalance ran.
      expect(await weights(A())).toEqual([600_000n, MAX_WEIGHT - 600_000n]);
      expect(await weights(C)).toEqual([510_000n, MAX_WEIGHT - 510_000n]);
      expect(await weights(B)).toEqual([400_000n, MAX_WEIGHT - 400_000n]);
      for (const index of [A(), B, C]) expect(await pendingOf(index), index).toBeUndefined();
      expect(afterA).not.toEqual(beforeA);
      expect(await reserves(B)).toEqual(beforeB);
      expect(await reserves(C)).toEqual(beforeC);
    });

    it("collectFeesFromMultipleIndexes: collected, no fees and failed (Index short of USDC)", async () => {
      await buyShares(ctx, ctx.user, parseUsdc("1000"), TOLERANCE, A());
      await buyShares(ctx, ctx.user, parseUsdc("1000"), TOLERANCE, C);
      const feesA = await accruedFees(A());
      const feesC = await accruedFees(C);
      expect(feesA).toBeGreaterThan(0n);
      expect(feesC).toBeGreaterThan(0n);
      const usdcOfC = await balanceOf(ctx, ctx.addresses.usdc, C);
      await send(ctx, ctx.deployer, {
        to: ctx.addresses.usdc,
        calldata: encodeFunctionData({ abi: mockUsdcAbi, functionName: "burn", args: [C, usdcOfC] }),
        value: 0n,
      });
      const indexes = [A(), B, C, A()];
      const collectorBefore = await balanceOf(ctx, ctx.addresses.usdc, deployer());
      const totalBefore = await totalFeesCollected();

      const receipt = await send(
        ctx,
        ctx.deployer,
        IndexManagerCalls.collectFeesManyCallParameters({ indexManager: indexManager(), indexes }),
        { gas: BATCH_GAS_LIMIT },
      );

      // OpenZeppelin ERC20InsufficientBalance(sender, balance, needed) from MockUSDC.transfer.
      const insufficient = encodeProtocolError({ errorName: "ERC20InsufficientBalance", args: [C, 0n, feesC] });
      expect(parseCollectFeesBatch(receipt.logs, { indexManager: indexManager(), indexes })).toEqual({
        collected: [{ index: A(), feeAmount: feesA }],
        noFees: [{ index: B }, { index: A() }],
        failed: [{ index: C, reasonData: insufficient, reason: protocolReason("ERC20InsufficientBalance", [C, 0n, feesC]) }],
      });
      expect(await balanceOf(ctx, ctx.addresses.usdc, deployer())).toBe(collectorBefore + feesA);
      expect(await totalFeesCollected()).toBe(totalBefore + feesA);
      expect(await accruedFees(A())).toBe(0n);
      expect(await accruedFees(C)).toBe(feesC);
    });
  });

  describe.runIf(!ctx.isMock)("batches with the deployed Index listed twice (mainnet fork)", () => {
    const X = () => ctx.index;

    it("rebalanceMultipleIndexes: not needed twice at the pinned prices, failed with a stale price after a warp", async () => {
      const indexes = [X(), X()];
      const call = IndexManagerCalls.rebalanceManyCallParameters({ indexManager: indexManager(), indexes });
      const balanced = await send(ctx, ctx.deployer, call, { gas: BATCH_GAS_LIMIT });
      expect(parseRebalanceBatch(balanced.logs, { indexManager: indexManager(), indexes })).toEqual({
        rebalanced: [],
        notNeeded: [{ index: X() }, { index: X() }],
        failed: [],
      });

      await ctx.testClient.increaseTime({ seconds: Number(STALE_FOR) });
      await ctx.testClient.mine({ blocks: 1 });
      const stale = await send(ctx, ctx.deployer, call, { gas: BATCH_GAS_LIMIT });
      const failure = { index: X(), reasonData: PRICE_IS_STALE, reason: protocolReason("PriceFeedManager__PriceIsStale") };
      expect(parseRebalanceBatch(stale.logs, { indexManager: indexManager(), indexes })).toEqual({
        rebalanced: [],
        notNeeded: [],
        failed: [failure, failure],
      });
    });

    it("executeWeightUpdateForMultipleIndexes: weights applied with the inner rebalance failed (stale after the delay), then not pending", async () => {
      const multiSig = await proposeAndWait([[X(), 600_000n]]);
      const before = await reserves(X());
      const indexes = [X(), X()];
      const receipt = await send(
        ctx,
        multiSig,
        IndexManagerCalls.executeWeightUpdateManyCallParameters({ indexManager: indexManager(), indexes }),
        { gas: BATCH_GAS_LIMIT },
      );
      expect(parseWeightUpdateBatch(receipt.logs, { indexManager: indexManager(), indexes })).toEqual({
        updated: [
          {
            index: X(),
            asset0Weight: 600_000n,
            asset1Weight: MAX_WEIGHT - 600_000n,
            rebalance: { status: "failed", reasonData: PRICE_IS_STALE, reason: protocolReason("PriceFeedManager__PriceIsStale") },
          },
        ],
        failed: [{ index: X(), reasonData: NOT_PENDING, reason: protocolReason("Index__NotPendingWeightUpdate") }],
      });
      expect(await weights(X())).toEqual([600_000n, MAX_WEIGHT - 600_000n]);
      expect(await pendingOf(X())).toBeUndefined();
      expect(await reserves(X())).toEqual(before);
    });

    it("collectFeesFromMultipleIndexes: collected, then no fees for the same Index", async () => {
      await buyShares(ctx, ctx.user, parseUsdc("1000"), TOLERANCE);
      const fees = await accruedFees(X());
      expect(fees).toBeGreaterThan(0n);
      const collectorBefore = await balanceOf(ctx, ctx.addresses.usdc, deployer());
      const indexes = [X(), X()];
      const receipt = await send(
        ctx,
        ctx.deployer,
        IndexManagerCalls.collectFeesManyCallParameters({ indexManager: indexManager(), indexes }),
        { gas: BATCH_GAS_LIMIT },
      );
      expect(parseCollectFeesBatch(receipt.logs, { indexManager: indexManager(), indexes })).toEqual({
        collected: [{ index: X(), feeAmount: fees }],
        noFees: [{ index: X() }],
        failed: [],
      });
      expect(await balanceOf(ctx, ctx.addresses.usdc, deployer())).toBe(collectorBefore + fees);
    });

    // Mainnet USDC (FiatTokenV2_2) reverts with require(..., "ERC20: transfer amount exceeds balance"):
    // a batch reports it as Error(string), the kind single actions never emit.
    it("collectFeesFromMultipleIndexes: an Index short of USDC fails with the Error(string) of mainnet USDC", async () => {
      await buyShares(ctx, ctx.user, parseUsdc("1000"), TOLERANCE);
      const fees = await accruedFees(X());
      await dealErc20(ctx, ctx.addresses.usdc, X(), 0n);
      const indexes = [X()];
      const receipt = await send(
        ctx,
        ctx.deployer,
        IndexManagerCalls.collectFeesManyCallParameters({ indexManager: indexManager(), indexes }),
        { gas: BATCH_GAS_LIMIT },
      );
      const result = parseCollectFeesBatch(receipt.logs, { indexManager: indexManager(), indexes });
      expect(result.collected).toEqual([]);
      expect(result.noFees).toEqual([]);
      expect(result.failed).toHaveLength(1);
      expect(result.failed[0]?.index).toBe(X());
      expect(result.failed[0]?.reason).toEqual({ kind: "errorString", message: "ERC20: transfer amount exceeds balance" });
      expect(await accruedFees(X())).toBe(fees);
    });
  });
}
