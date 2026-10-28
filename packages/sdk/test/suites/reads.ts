// Read descriptors of PriceFeedReads, IndexManager (the Index contract) and Erc20Manager, the
// approve calldata, and the deployment addresses, all checked against the live contracts.
import { indexManagerAbi } from "@oam/abi";
import { decodeFunctionData, erc20Abi } from "viem";
import { describe, expect, it } from "vitest";
import {
  ANVIL_CHAIN_ID,
  ContractRevertError,
  Erc20Manager,
  IndexManager,
  MAINNET_FORK_CHAIN_ID,
  PriceFeedReads,
  SHARES_DECIMALS,
  STANDARD_DECIMALS,
  USDC_DECIMALS,
  UnsupportedChainError,
  getProtocolAddresses,
  isPriceFeedStale,
  parseUsdc,
  permitDomainFromEip712Domain,
  toSdkError,
} from "../../src/index.js";
import {
  MAINNET_FORK_BLOCK,
  MULTICALL3,
  chainNow,
  loadIndex,
  makeMockFeedStale,
  mockFeedAbi,
  readError,
  readSnapshotResults,
  send,
  type ForkContext,
} from "../helpers/chain.js";

export function readsSuite(ctx: ForkContext): void {
  const priceFeedManager = () => ctx.addresses.priceFeedManager;

  describe("getProtocolAddresses and chain id", () => {
    it("the chain id comes from the node and selects the matching deployment file", async () => {
      const chainId = await ctx.publicClient.getChainId();
      expect([ANVIL_CHAIN_ID, MAINNET_FORK_CHAIN_ID]).toContain(chainId);
      expect(getProtocolAddresses(chainId)).toEqual(ctx.addresses);
      expect(() => getProtocolAddresses(1)).toThrow(UnsupportedChainError);
    });

    it("every address of the deployment file matches what the IndexManager reports and has code", async () => {
      const im = ctx.addresses.indexManager;
      const read = (functionName: "getRouterAddress" | "getPriceFeedManagerAddress" | "getSwapManagerAddress" | "getIndexFactory") =>
        ctx.publicClient.readContract({ address: im, abi: indexManagerAbi, functionName });
      expect(await read("getRouterAddress")).toBe(ctx.addresses.router);
      expect(await read("getPriceFeedManagerAddress")).toBe(ctx.addresses.priceFeedManager);
      expect(await read("getSwapManagerAddress")).toBe(ctx.addresses.swapManager);
      expect(await read("getIndexFactory")).toBe(ctx.addresses.indexFactory);
      for (const address of Object.values(ctx.addresses).filter((value) => typeof value === "string")) {
        const code = await ctx.publicClient.getCode({ address });
        expect(code?.length ?? 0).toBeGreaterThan(2);
      }
    });

    it.runIf(!ctx.isMock)("mainnet fork: pinned at the project block, never latest", async () => {
      expect(ctx.addresses.startBlock).toBe(MAINNET_FORK_BLOCK);
      expect(await ctx.publicClient.getBlockNumber()).toBeGreaterThanOrEqual(MAINNET_FORK_BLOCK);
      const forkBlock = await ctx.publicClient.getBlock({ blockNumber: MAINNET_FORK_BLOCK });
      expect(forkBlock.number).toBe(MAINNET_FORK_BLOCK);
    });
  });

  describe("PriceFeedReads", () => {
    it("priceRead equals the Chainlink answer scaled to 18 decimals; feeds are configured and fresh at chain time", async () => {
      const now = await chainNow(ctx);
      for (const asset of [ctx.asset0, ctx.asset1, ctx.addresses.usdc]) {
        expect(await ctx.publicClient.readContract(PriceFeedReads.hasPriceFeedRead({ priceFeedManager: priceFeedManager(), asset }))).toBe(true);
        const { feed, maxDelay } = await ctx.publicClient.readContract(
          PriceFeedReads.feedConfigRead({ priceFeedManager: priceFeedManager(), asset }),
        );
        const [, answer, , updatedAt] = await ctx.publicClient.readContract(PriceFeedReads.latestRoundDataRead(feed));
        const feedDecimals = await ctx.publicClient.readContract({ address: feed, abi: mockFeedAbi, functionName: "decimals" });
        const price = await ctx.publicClient.readContract(PriceFeedReads.priceRead({ priceFeedManager: priceFeedManager(), asset }));
        expect(price).toBe(answer * 10n ** BigInt(STANDARD_DECIMALS - feedDecimals));
        expect(isPriceFeedStale({ updatedAt, blockTimestamp: now, maxDelay })).toBe(false);
        const pendingUpdate = await ctx.publicClient.readContract(
          PriceFeedReads.pendingFeedUpdateRead({ priceFeedManager: priceFeedManager(), asset }),
        );
        expect(PriceFeedReads.toPendingFeedUpdate(pendingUpdate)).toBeUndefined();
      }
    });

    it("an asset without a feed: hasPriceFeedRead is false and priceRead reverts with a decoded protocol error", async () => {
      const notAnAsset = ctx.index;
      expect(
        await ctx.publicClient.readContract(PriceFeedReads.hasPriceFeedRead({ priceFeedManager: priceFeedManager(), asset: notAnAsset })),
      ).toBe(false);
      const error = await readError(ctx, PriceFeedReads.priceRead({ priceFeedManager: priceFeedManager(), asset: notAnAsset }), "price");
      expect(error).toBeInstanceOf(ContractRevertError);
      expect((error as ContractRevertError).errorName).toMatch(/^PriceFeedManager__/);
    });

    it.runIf(ctx.isMock)("stale feed: isPriceFeedStale agrees with the PriceFeedManager, which refuses the price", async () => {
      const now = await chainNow(ctx);
      const { maxDelay } = await ctx.publicClient.readContract(
        PriceFeedReads.feedConfigRead({ priceFeedManager: priceFeedManager(), asset: ctx.asset0 }),
      );
      const feed = await makeMockFeedStale(ctx, ctx.asset0, now - BigInt(maxDelay) - 10n);
      const [, , , updatedAt] = await ctx.publicClient.readContract(PriceFeedReads.latestRoundDataRead(feed));
      expect(isPriceFeedStale({ updatedAt, blockTimestamp: await chainNow(ctx), maxDelay })).toBe(true);
      const error = await readError(ctx, PriceFeedReads.priceRead({ priceFeedManager: priceFeedManager(), asset: ctx.asset0 }), "price");
      expect(error).toBeInstanceOf(ContractRevertError);
      expect((error as ContractRevertError).errorName).toMatch(/^PriceFeedManager__/);
    });
  });

  describe("IndexManager (Index contract reads)", () => {
    it("toSnapshot maps the reads to the right fields: decimals, weights, fees, supply", async () => {
      const fund = await loadIndex(ctx);
      const s = fund.snapshot;
      const decimalsOf = (token: `0x${string}`) => ctx.publicClient.readContract({ address: token, abi: erc20Abi, functionName: "decimals" });
      expect(s.decimals0).toBe(await decimalsOf(ctx.asset0));
      expect(s.decimals1).toBe(await decimalsOf(ctx.asset1));
      expect(s.usdcDecimals).toBe(USDC_DECIMALS);
      expect(await decimalsOf(ctx.index)).toBe(SHARES_DECIMALS);
      expect(s.weight0 + s.weight1).toBe(1_000_000n);
      expect(s.isInitialized).toBe(true);
      expect(s.totalSupply).toBe(await ctx.publicClient.readContract({ address: ctx.index, abi: erc20Abi, functionName: "totalSupply" }));
      // Reserves are internal accounting, not balanceOf, yet they must be covered by real balances.
      expect(await ctx.publicClient.readContract(Erc20Manager.balanceOfRead({ token: ctx.asset0, owner: ctx.index }))).toBeGreaterThanOrEqual(s.reserve0);
    });

    it("getValuation equals the contract's own usdValue and effective weights at the same block", async () => {
      const blockNumber = await ctx.publicClient.getBlockNumber();
      const valuation = (await loadIndex(ctx, { blockNumber })).getValuation();
      const [usd0, usd1, total] = await ctx.publicClient.readContract({ ...IndexManager.usdValueRead(ctx.index), blockNumber });
      const [w0, w1] = await ctx.publicClient.readContract({ ...IndexManager.effectiveWeightsRead(ctx.index), blockNumber });
      expect([valuation.usdValue0, valuation.usdValue1, valuation.totalUsdValue]).toEqual([usd0, usd1, total]);
      expect([valuation.effectiveWeight0, valuation.effectiveWeight1]).toEqual([w0, w1]);
    });

    it("pendingWeightsRead with no proposal maps to undefined", async () => {
      const result = await ctx.publicClient.readContract(IndexManager.pendingWeightsRead(ctx.index));
      expect(IndexManager.toPendingWeightUpdate(result)).toBeUndefined();
    });

    it.runIf(!ctx.isMock)("snapshotReads works unchanged through Multicall3 on the fork and equals the Promise.all path", async () => {
      const blockNumber = await ctx.publicClient.getBlockNumber();
      const viaMulticall = await ctx.publicClient.multicall({
        contracts: IndexManager.snapshotReads(ctx.index),
        allowFailure: false,
        multicallAddress: MULTICALL3,
        blockNumber,
      });
      expect(viaMulticall).toEqual(await readSnapshotResults(ctx, { blockNumber }));
    });
  });

  describe("Erc20Manager", () => {
    it("approve: decoded calldata, allowance set on chain, then revoked with 0", async () => {
      const token = ctx.addresses.usdc;
      const owner = ctx.user.account.address;
      const amount = parseUsdc("123.45");
      const call = Erc20Manager.approveCallParameters({ token, spender: ctx.index, amount });
      const decoded = decodeFunctionData({ abi: erc20Abi, data: call.calldata });
      expect(decoded.functionName).toBe("approve");
      expect(decoded.args).toEqual([ctx.index, amount]);
      expect(call.to).toBe(token);
      expect(call.value).toBe(0n);

      await send(ctx, ctx.user, call);
      expect(await ctx.publicClient.readContract(Erc20Manager.allowanceRead({ token, owner, spender: ctx.index }))).toBe(amount);
      // Security: the approval reaches the intended spender only.
      expect(await ctx.publicClient.readContract(Erc20Manager.allowanceRead({ token, owner, spender: ctx.addresses.router }))).toBe(0n);
      await send(ctx, ctx.user, Erc20Manager.approveCallParameters({ token, spender: ctx.index, amount: 0n }));
      expect(await ctx.publicClient.readContract(Erc20Manager.allowanceRead({ token, owner, spender: ctx.index }))).toBe(0n);
    });

    it("Index shares permit domain: eip712Domain maps to the Index as verifying contract on this chain", async () => {
      const domain = permitDomainFromEip712Domain(await ctx.publicClient.readContract(Erc20Manager.eip712DomainRead(ctx.index)));
      expect(domain.verifyingContract).toBe(ctx.index);
      expect(domain.chainId).toBe(ctx.chainId);
      expect(domain.name).toBe(await ctx.publicClient.readContract(Erc20Manager.nameRead(ctx.index)));
      expect(await ctx.publicClient.readContract(Erc20Manager.noncesRead({ token: ctx.index, owner: ctx.user.account.address }))).toBe(0n);
    });

    it.runIf(!ctx.isMock)("mainnet USDC has no eip712Domain(), as the SDK documents; name and version are readable", async () => {
      let thrown: unknown;
      try {
        await ctx.publicClient.readContract(Erc20Manager.eip712DomainRead(ctx.addresses.usdc));
      } catch (err) {
        thrown = err;
      }
      expect(thrown).toBeDefined();
      expect(toSdkError(thrown, "eip712Domain")).toBeInstanceOf(ContractRevertError);
      expect(await ctx.publicClient.readContract(Erc20Manager.nameRead(ctx.addresses.usdc))).toBe("USD Coin");
      expect(await ctx.publicClient.readContract(Erc20Manager.versionRead(ctx.addresses.usdc))).toBe("2");
    });
  });
}
