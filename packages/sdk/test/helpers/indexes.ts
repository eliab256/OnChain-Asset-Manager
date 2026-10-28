// Extra Indexes for the batch tests on anvil 31337. The deploy creates one Index only; a batch
// needs several, each in a different state. They are created here exactly as
// script/DeployAndInitNewIndex.s.sol does (MultiSig = ASSET_MANAGER: feed registration,
// createIndex, approve, initializeIndex with the default V3 routes of HelperConfig), from the mock
// tokens and feeds the deploy left in deployments/31337.json. The caller reverts the snapshot.
// Every call is built by the SDK (PriceFeedManagerCalls, IndexManagerCalls, v3Route), so this
// helper also exercises those builders against the contracts.
import { encodeFunctionData, getAddress, maxUint256, type Address } from "viem";
import anvilDeployment from "../../../../deployments/31337.json" with { type: "json" };
import {
  Erc20Manager,
  IndexManager,
  IndexManagerCalls,
  MAX_FEED_DELAY,
  PriceFeedManagerCalls,
  PriceFeedReads,
  v3Route,
} from "../../src/index.js";
import { balanceOf, dealErc20, impersonateMultiSig, mockFeedAbi, send, type ForkContext } from "./chain.js";

/** `DEFAULT_V3_POOL_FEE` of script/HelperConfig.s.sol; the mock router ignores it but SwapManager stores the path. */
const DEFAULT_V3_POOL_FEE = 3000;
/** Fee and weights of the default deploy-index run: 1% fee, 50/50. */
const FEE_PERCENTAGE = 10_000n;
const HALF_WEIGHT = 500_000n;

export type MockAsset = { token: Address; feed: Address };

/** The mock tokens deployed by HelperConfig on 31337 that the default Index does not use. */
export function extraMockAssets(): { link: MockAsset; comp: MockAsset } {
  const { LINK, COMP } = anvilDeployment.mocks;
  return {
    link: { token: getAddress(LINK.token), feed: getAddress(LINK.priceFeed) },
    comp: { token: getAddress(COMP.token), feed: getAddress(COMP.priceFeed) },
  };
}

const route = (tokenA: Address, tokenB: Address) => v3Route([tokenA, tokenB], [DEFAULT_V3_POOL_FEE]);

/**
 * Registers the feeds that are missing (with the maxDelay of the default Index's asset0 feed),
 * then creates and initializes a 50/50 Index of `assetA` and `assetB`. Refreshes both mock feeds first.
 */
export async function createMockIndex(ctx: ForkContext, assetA: MockAsset, assetB: MockAsset): Promise<Address> {
  const multiSig = await impersonateMultiSig(ctx);
  const { indexManager, priceFeedManager, usdc } = ctx.addresses;
  const { maxDelay } = await ctx.publicClient.readContract(PriceFeedReads.feedConfigRead({ priceFeedManager, asset: ctx.asset0 }));

  for (const { token, feed } of [assetA, assetB]) {
    // Timestamped at deploy like every mock feed: initializeIndex prices both assets.
    const answer = await ctx.publicClient.readContract({ address: feed, abi: mockFeedAbi, functionName: "latestAnswer" });
    await send(ctx, ctx.deployer, {
      to: feed,
      calldata: encodeFunctionData({ abi: mockFeedAbi, functionName: "updateAnswer", args: [answer] }),
      value: 0n,
    });
    if (await ctx.publicClient.readContract(PriceFeedReads.hasPriceFeedRead({ priceFeedManager, asset: token }))) continue;
    await send(ctx, multiSig, PriceFeedManagerCalls.registerPriceFeedCallParameters({ priceFeedManager, asset: token, feed, maxDelay }));
  }

  await send(
    ctx,
    multiSig,
    IndexManagerCalls.createIndexCallParameters({
      indexManager,
      feePercentage: FEE_PERCENTAGE,
      assetA: { asset: assetA.token, weight: HALF_WEIGHT },
      assetB: { asset: assetB.token, weight: HALF_WEIGHT },
      usdc,
    }),
  );
  const index = await ctx.publicClient.readContract(
    IndexManagerCalls.indexByAssetsRead({ indexManager, assetA: assetA.token, assetB: assetB.token }),
  );

  const [asset0Read, asset1Read, decimalsRead] = IndexManager.snapshotReads(index);
  const asset0 = await ctx.publicClient.readContract(asset0Read);
  const asset1 = await ctx.publicClient.readContract(asset1Read);
  const [decimals0, decimals1] = await ctx.publicClient.readContract(decimalsRead);
  // The Index computes the asset1 deposit from the asset0 one at the feed prices: approve a surplus.
  const amount0 = 100n * 10n ** BigInt(decimals0);
  for (const [token, amount] of [
    [asset0, amount0],
    [asset1, 10n ** BigInt(decimals1 + 12)],
  ] as const) {
    const current = await balanceOf(ctx, token, multiSig.account.address);
    await dealErc20(ctx, token, multiSig.account.address, current + amount);
    await send(ctx, multiSig, Erc20Manager.approveCallParameters({ token, spender: index, amount: maxUint256 }));
  }

  await send(
    ctx,
    multiSig,
    IndexManagerCalls.initializeIndexCallParameters({
      indexManager,
      depositor: multiSig.account.address,
      index,
      amount0,
      routes: { asset0Usdc: route(asset0, usdc), asset1Usdc: route(asset1, usdc), asset0Asset1: route(asset0, asset1) },
      tokens: { asset0, asset1, usdc },
    }),
  );
  return index;
}

/** Mainnet LINK and COMP with their Chainlink USD feeds (script/CodeConstants.sol), for the fork 31338. */
export const MAINNET_EXTRA_ASSETS: { link: MockAsset; comp: MockAsset } = {
  link: { token: getAddress("0x514910771AF9Ca656af840dff83E8264EcF986CA"), feed: getAddress("0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c") },
  comp: { token: getAddress("0xc00e94Cb662C3520282E6f5717214004A7f26888"), feed: getAddress("0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5") },
};

/** LINK and COMP of the running chain: mocks on 31337, mainnet tokens on the fork. Neither is in the deployed Index. */
export function extraAssets(ctx: ForkContext): { link: MockAsset; comp: MockAsset } {
  return ctx.isMock ? extraMockAssets() : MAINNET_EXTRA_ASSETS;
}

/**
 * maxDelay for the feeds registered by the tests: the deploy value (1h15m) on 31337, where the mocks are refreshed;
 * on the fork the node time drifts from the pinned block, so the widest allowed value keeps the feeds fresh.
 */
export function testFeedMaxDelay(ctx: ForkContext): number {
  return ctx.isMock ? 4500 : MAX_FEED_DELAY;
}

/**
 * A LINK/COMP Index registered by the IndexManager (`createIndex` through the impersonated MultiSig) but never
 * initialized. Registers the missing feeds first; registration validates the answer, not its age.
 */
export async function createUninitializedIndex(ctx: ForkContext): Promise<Address> {
  const multiSig = await impersonateMultiSig(ctx);
  const { indexManager, priceFeedManager, usdc } = ctx.addresses;
  const { link, comp } = extraAssets(ctx);
  for (const { token, feed } of [link, comp]) {
    if (await ctx.publicClient.readContract(PriceFeedReads.hasPriceFeedRead({ priceFeedManager, asset: token }))) continue;
    await send(
      ctx,
      multiSig,
      PriceFeedManagerCalls.registerPriceFeedCallParameters({ priceFeedManager, asset: token, feed, maxDelay: testFeedMaxDelay(ctx) }),
    );
  }
  await send(
    ctx,
    multiSig,
    IndexManagerCalls.createIndexCallParameters({
      indexManager,
      feePercentage: FEE_PERCENTAGE,
      assetA: { asset: link.token, weight: HALF_WEIGHT },
      assetB: { asset: comp.token, weight: HALF_WEIGHT },
      usdc,
    }),
  );
  return ctx.publicClient.readContract(IndexManagerCalls.indexByAssetsRead({ indexManager, assetA: link.token, assetB: comp.token }));
}
