// RouterManager calldata executed on chain: buy, buy with permit, sell, and the Router reverts
// decoded through toSdkError. State is asserted from the chain, not from the calldata bytes.
import { decodeFunctionData, encodeFunctionData, isAddressEqual, verifyTypedData } from "viem";
import { describe, expect, it } from "vitest";
import {
  ContractRevertError,
  Erc20Manager,
  EventNotFoundError,
  IndexManager,
  IndexNotInitializedError,
  InsufficientAllowanceError,
  InsufficientBalanceError,
  InvalidDeadlineError,
  InvalidToleranceError,
  MAX_TOLERANCE,
  PERCENTAGE_SCALE,
  RequestFailedError,
  RouterManager,
  ZeroAmountError,
  buildPermitTypedData,
  joinPermitSignature,
  parseSharesBurned,
  parseSharesMinted,
  parseUsdc,
  permitDomainFromEip712Domain,
  splitPermitSignature,
  toSdkError,
  type PermitDomain,
} from "../../src/index.js";
import {
  balanceOf,
  buyShares,
  chainNow,
  configureMockUniversalRouter,
  dealErc20,
  loadIndex,
  mockUniversalRouterAbi,
  readError,
  routerAbiOf,
  send,
  simulateError,
  type ForkContext,
  type Wallet,
} from "../helpers/chain.js";

/** 3%: on the fork the swaps go through real Uniswap pools, within ~1% of Chainlink at the pinned block. */
export const TOLERANCE = 30_000n;

async function usdcPermitDomain(ctx: ForkContext): Promise<PermitDomain> {
  const usdc = ctx.addresses.usdc;
  if (ctx.isMock) {
    return permitDomainFromEip712Domain(await ctx.publicClient.readContract(Erc20Manager.eip712DomainRead(usdc)));
  }
  // Mainnet USDC has no eip712Domain(): the SDK documents name() + version() instead.
  const [name, version] = await Promise.all([
    ctx.publicClient.readContract(Erc20Manager.nameRead(usdc)),
    ctx.publicClient.readContract(Erc20Manager.versionRead(usdc)),
  ]);
  return { name, version, chainId: ctx.chainId, verifyingContract: usdc };
}

async function signUsdcPermit(
  ctx: ForkContext,
  wallet: Wallet,
  params: { spender: `0x${string}`; value: bigint; deadline: bigint },
) {
  const owner = wallet.account.address;
  const nonce = await ctx.publicClient.readContract(Erc20Manager.noncesRead({ token: ctx.addresses.usdc, owner }));
  const typedData = buildPermitTypedData({ domain: await usdcPermitDomain(ctx), owner, nonce, ...params });
  const signature = await wallet.signTypedData({ account: wallet.account, ...typedData });
  return { typedData, signature, nonce };
}

export function routerSuite(ctx: ForkContext): void {
  const router = () => ctx.addresses.router;
  const usdc = () => ctx.addresses.usdc;
  const userAddress = () => ctx.user.account.address;

  describe("RouterManager.buyCallParameters", () => {
    it("decodes to buyExactUsdcAmountOfShares(index, amount, tolerance) sent to the Router with no value", () => {
      const usdcAmount = parseUsdc("100");
      const call = RouterManager.buyCallParameters({ router: router(), index: ctx.index, usdcAmount, tolerance: TOLERANCE });
      const decoded = decodeFunctionData({ abi: routerAbiOf(ctx), data: call.calldata });
      expect(decoded.functionName).toBe("buyExactUsdcAmountOfShares");
      expect(decoded.args).toEqual([ctx.index, usdcAmount, TOLERANCE]);
      expect(call.to).toBe(router());
      expect(call.value).toBe(0n);
    });

    it("approve to the Index then buy: USDC leaves, shares, reserves and fees match SharesMinted", async () => {
      const usdcAmount = parseUsdc("10000");
      const user = userAddress();
      await dealErc20(ctx, usdc(), user, usdcAmount);

      // Security: the spender of a Router buy is the Index (it pulls the USDC), never the Router.
      await send(ctx, ctx.user, Erc20Manager.approveCallParameters({ token: usdc(), spender: ctx.index, amount: usdcAmount }));
      expect(
        await ctx.publicClient.readContract(Erc20Manager.allowanceRead({ token: usdc(), owner: user, spender: ctx.index })),
      ).toBe(usdcAmount);

      const before = await loadIndex(ctx);
      const minShares = before.minMintPreview(usdcAmount, TOLERANCE);
      const sharesBefore = await balanceOf(ctx, ctx.index, user);

      const receipt = await send(
        ctx,
        ctx.user,
        RouterManager.buyCallParameters({ router: router(), index: ctx.index, usdcAmount, tolerance: TOLERANCE }),
      );
      const event = parseSharesMinted(receipt.logs, ctx.index);
      const after = await loadIndex(ctx);

      expect(isAddressEqual(event.user, user)).toBe(true);
      expect(event.usdcAmountIn).toBe(usdcAmount);
      // Rounding direction: the offline minimum never promises more than the contract delivers.
      expect(event.sharesMinted).toBeGreaterThanOrEqual(minShares);
      expect(event.feeAmount).toBe((usdcAmount * before.snapshot.feePercentage) / PERCENTAGE_SCALE);
      expect(await balanceOf(ctx, ctx.index, user)).toBe(sharesBefore + event.sharesMinted);
      expect(await balanceOf(ctx, usdc(), user)).toBe(0n);
      expect(after.snapshot.totalSupply).toBe(before.snapshot.totalSupply + event.sharesMinted);
      expect(after.snapshot.reserve0).toBe(before.snapshot.reserve0 + event.asset0Amount);
      expect(after.snapshot.reserve1).toBe(before.snapshot.reserve1 + event.asset1Amount);
      expect(after.snapshot.totalFees).toBe(before.snapshot.totalFees + event.feeAmount);
      expect(
        await ctx.publicClient.readContract(Erc20Manager.allowanceRead({ token: usdc(), owner: user, spender: ctx.index })),
      ).toBe(0n);
    });

    it("wrong emitter ignored: SharesMinted is read only from the Index address", async () => {
      const receipt = await buyShares(ctx, ctx.user, parseUsdc("100"), TOLERANCE);
      expect(() => parseSharesMinted(receipt.logs, ctx.addresses.router)).toThrow(EventNotFoundError);
      // The same log re-attributed to another contract (a spoof in the same tx) must not be accepted.
      const spoofed = receipt.logs.map((log) => ({ ...log, address: ctx.addresses.router }));
      expect(() => parseSharesMinted(spoofed, ctx.index)).toThrow(EventNotFoundError);
      expect(() => parseSharesBurned(receipt.logs, ctx.index)).toThrow(EventNotFoundError);
    });

    it("approve to the Router instead of the Index: the buy reverts and checkBuy flags the missing allowance", async () => {
      const usdcAmount = parseUsdc("100");
      const user = userAddress();
      await dealErc20(ctx, usdc(), user, usdcAmount);
      await send(ctx, ctx.user, Erc20Manager.approveCallParameters({ token: usdc(), spender: router(), amount: usdcAmount }));

      const allowance = await ctx.publicClient.readContract(
        Erc20Manager.allowanceRead({ token: usdc(), owner: user, spender: ctx.index }),
      );
      expect(() =>
        RouterManager.checkBuy({
          usdc: usdc(),
          index: ctx.index,
          usdcAmount,
          isInitialized: true,
          usdcBalance: usdcAmount,
          usdcAllowance: allowance,
        }),
      ).toThrow(InsufficientAllowanceError);

      const call = RouterManager.buyCallParameters({ router: router(), index: ctx.index, usdcAmount, tolerance: TOLERANCE });
      const error = await simulateError(ctx, user, call, routerAbiOf(ctx), "buy");
      expect(error).toBeInstanceOf(ContractRevertError);
      if (ctx.isMock) expect((error as ContractRevertError).errorName).toBe("ERC20InsufficientAllowance");
    });

    it("insufficient USDC balance: Router__InsufficientUsdcBalance decoded with its arguments, checkBuy agrees", async () => {
      const user = userAddress();
      const balance = parseUsdc("50");
      await dealErc20(ctx, usdc(), user, balance);
      const usdcAmount = balance + 1n;

      expect(() =>
        RouterManager.checkBuy({
          usdc: usdc(),
          index: ctx.index,
          usdcAmount,
          isInitialized: true,
          usdcBalance: balance,
          usdcAllowance: usdcAmount,
        }),
      ).toThrow(InsufficientBalanceError);

      const call = RouterManager.buyCallParameters({ router: router(), index: ctx.index, usdcAmount, tolerance: TOLERANCE });
      const error = await simulateError(ctx, user, call, routerAbiOf(ctx), "buy");
      expect(error).toBeInstanceOf(ContractRevertError);
      expect((error as ContractRevertError).errorName).toBe("Router__InsufficientUsdcBalance");
      expect((error as ContractRevertError).args).toEqual([balance, usdcAmount]);
    });

    // The send path of sdk.md §6: no ABI on the client, the revert data only sits in the RPC error.
    it("toSdkError decodes a revert raised by sendTransaction with the manager calldata (the path sdk.md §6 shows)", async () => {
      const user = userAddress();
      await dealErc20(ctx, usdc(), user, parseUsdc("1"));
      const call = RouterManager.buyCallParameters({
        router: router(),
        index: ctx.index,
        usdcAmount: parseUsdc("2"),
        tolerance: TOLERANCE,
      });
      let thrown: unknown;
      try {
        await ctx.user.sendTransaction({ to: call.to, data: call.calldata, value: call.value, chain: ctx.chain, account: ctx.user.account });
      } catch (err) {
        thrown = err;
      }
      expect(thrown).toBeDefined();
      const error = toSdkError(thrown, "buy");
      expect(error).not.toBeInstanceOf(RequestFailedError);
      expect(error).toBeInstanceOf(ContractRevertError);
      expect((error as ContractRevertError).errorName).toBe("Router__InsufficientUsdcBalance");
      expect((error as ContractRevertError).args).toEqual([parseUsdc("1"), parseUsdc("2")]);
      expect(error.cause).toBe(thrown);
    });

    it("zero and negative amounts: the SDK refuses them, the Router reverts Router__InvalidAmounts on zero", async () => {
      for (const usdcAmount of [0n, -1n]) {
        expect(() =>
          RouterManager.buyCallParameters({ router: router(), index: ctx.index, usdcAmount, tolerance: TOLERANCE }),
        ).toThrow(ZeroAmountError);
      }
      // Bypass the SDK guard to prove the contract agrees on the zero case.
      const raw = {
        to: router(),
        calldata: encodeFunctionData({
          abi: routerAbiOf(ctx),
          functionName: "buyExactUsdcAmountOfShares",
          args: [ctx.index, 0n, TOLERANCE],
        }),
        value: 0n,
      };
      const error = await simulateError(ctx, userAddress(), raw, routerAbiOf(ctx), "buy");
      expect((error as ContractRevertError).errorName).toBe("Router__InvalidAmounts");
    });

    it("tolerance bounds: SDK and Router agree on 0 and MAX_TOLERANCE (rejected) and MAX_TOLERANCE - 1 (accepted)", async () => {
      for (const tolerance of [0n, MAX_TOLERANCE, MAX_TOLERANCE + 1n]) {
        expect(() =>
          RouterManager.buyCallParameters({ router: router(), index: ctx.index, usdcAmount: 1n, tolerance }),
        ).toThrow(InvalidToleranceError);
        // The read descriptor does not validate: the Router decides, and its revert is decoded.
        const error = await readError(
          ctx,
          RouterManager.minMintPreviewRead({ router: router(), index: ctx.index, usdcAmount: parseUsdc("1"), tolerance }),
          "minMintPreview",
        );
        expect(error).toBeInstanceOf(ContractRevertError);
        expect((error as ContractRevertError).errorName).toBe("Router__InvalidTolerance");
      }
      const edge = await ctx.publicClient.readContract(
        RouterManager.minMintPreviewRead({
          router: router(),
          index: ctx.index,
          usdcAmount: parseUsdc("1"),
          tolerance: MAX_TOLERANCE - 1n,
        }),
      );
      expect(edge).toBeGreaterThan(0n);
    });

    it("an address that is not an initialized Index: Router__InvalidIndexAddress, checkBuy throws IndexNotInitializedError", async () => {
      const error = await readError(
        ctx,
        RouterManager.minMintPreviewRead({ router: router(), index: usdc(), usdcAmount: 1n, tolerance: TOLERANCE }),
        "minMintPreview",
      );
      expect((error as ContractRevertError).errorName).toBe("Router__InvalidIndexAddress");
      expect(() =>
        RouterManager.checkBuy({
          usdc: usdc(),
          index: usdc(),
          usdcAmount: 1n,
          isInitialized: false,
          usdcBalance: 1n,
          usdcAllowance: 1n,
        }),
      ).toThrow(IndexNotInitializedError);
    });

    it.runIf(ctx.isMock)("swap output below tolerance: Index__ToleranceExceeded is decoded (anvil mocks)", async () => {
      const usdcAmount = parseUsdc("1000");
      const user = userAddress();
      await dealErc20(ctx, usdc(), user, usdcAmount);
      await send(ctx, ctx.user, Erc20Manager.approveCallParameters({ token: usdc(), spender: ctx.index, amount: usdcAmount }));
      // Half the fair rate and no router-side minimum: only the Index check is left to protect the user.
      await configureMockUniversalRouter(ctx, { num: 1n, den: 2n });
      await send(ctx, ctx.deployer, {
        to: ctx.universalRouter,
        calldata: encodeFunctionData({ abi: mockUniversalRouterAbi, functionName: "setEnforceMinAmountOut", args: [false] }),
        value: 0n,
      });
      const call = RouterManager.buyCallParameters({ router: router(), index: ctx.index, usdcAmount, tolerance: TOLERANCE });
      const error = await simulateError(ctx, user, call, routerAbiOf(ctx), "buy");
      expect((error as ContractRevertError).errorName).toBe("Index__ToleranceExceeded");
    });
  });

  describe("RouterManager.buyWithPermitCallParameters", () => {
    it("permit spender is the Index: SDK typed data signed by an anvil account buys in one tx and consumes the nonce", async () => {
      const usdcAmount = parseUsdc("2500");
      const user = userAddress();
      await dealErc20(ctx, usdc(), user, usdcAmount);
      const nowSeconds = await chainNow(ctx);
      const deadline = nowSeconds + 3_600n;
      const { typedData, signature, nonce } = await signUsdcPermit(ctx, ctx.user, {
        spender: ctx.index,
        value: usdcAmount,
        deadline,
      });
      expect(typedData.message.spender).toBe(ctx.index);
      expect(typedData.domain.chainId).toBe(ctx.chainId);
      const split = splitPermitSignature(signature);
      expect(await verifyTypedData({ address: user, ...typedData, signature: joinPermitSignature(split) })).toBe(true);

      const before = await loadIndex(ctx);
      const minShares = before.minMintPreview(usdcAmount, TOLERANCE);
      const call = RouterManager.buyWithPermitCallParameters({
        router: router(),
        index: ctx.index,
        usdcAmount,
        tolerance: TOLERANCE,
        deadline,
        nowSeconds,
        signature: split,
      });
      const decoded = decodeFunctionData({ abi: routerAbiOf(ctx), data: call.calldata });
      expect(decoded.functionName).toBe("buyExactUsdcAmountOfSharesWithPermit");
      expect(decoded.args).toEqual([ctx.index, usdcAmount, TOLERANCE, deadline, split.v, split.r, split.s]);

      const receipt = await send(ctx, ctx.user, call);
      const event = parseSharesMinted(receipt.logs, ctx.index);
      expect(event.sharesMinted).toBeGreaterThanOrEqual(minShares);
      expect(event.usdcAmountIn).toBe(usdcAmount);
      expect(await balanceOf(ctx, ctx.index, user)).toBe(event.sharesMinted);
      expect(await balanceOf(ctx, usdc(), user)).toBe(0n);
      expect(await ctx.publicClient.readContract(Erc20Manager.noncesRead({ token: usdc(), owner: user }))).toBe(nonce + 1n);
      expect(
        await ctx.publicClient.readContract(Erc20Manager.allowanceRead({ token: usdc(), owner: user, spender: ctx.index })),
      ).toBe(0n);
    });

    it("permit spender: a permit signed for the Router is rejected on chain", async () => {
      const usdcAmount = parseUsdc("100");
      const user = userAddress();
      await dealErc20(ctx, usdc(), user, usdcAmount);
      const nowSeconds = await chainNow(ctx);
      const deadline = nowSeconds + 3_600n;
      const { signature } = await signUsdcPermit(ctx, ctx.user, { spender: router(), value: usdcAmount, deadline });
      const call = RouterManager.buyWithPermitCallParameters({
        router: router(),
        index: ctx.index,
        usdcAmount,
        tolerance: TOLERANCE,
        deadline,
        nowSeconds,
        signature: splitPermitSignature(signature),
      });
      const error = await simulateError(ctx, user, call, routerAbiOf(ctx), "buyWithPermit");
      expect(error).toBeInstanceOf(ContractRevertError);
      if (ctx.isMock) expect((error as ContractRevertError).errorName).toBe("ERC2612InvalidSigner");
      expect(await balanceOf(ctx, usdc(), user)).toBe(usdcAmount);
    });

    it("deadline: the SDK rejects a deadline not after the latest block time", async () => {
      const nowSeconds = await chainNow(ctx);
      const signature = { v: 27, r: `0x${"11".repeat(32)}`, s: `0x${"22".repeat(32)}` } as const;
      for (const deadline of [nowSeconds, nowSeconds - 1n]) {
        expect(() =>
          RouterManager.buyWithPermitCallParameters({
            router: router(),
            index: ctx.index,
            usdcAmount: 1n,
            tolerance: TOLERANCE,
            deadline,
            nowSeconds,
            signature,
          }),
        ).toThrow(InvalidDeadlineError);
      }
    });

    it("deadline: a permit that expires before the tx is mined reverts and the revert is decoded", async () => {
      const usdcAmount = parseUsdc("100");
      const user = userAddress();
      await dealErc20(ctx, usdc(), user, usdcAmount);
      const nowSeconds = await chainNow(ctx);
      const deadline = nowSeconds + 5n;
      const { signature } = await signUsdcPermit(ctx, ctx.user, { spender: ctx.index, value: usdcAmount, deadline });
      // Valid when built; the chain moves on before inclusion.
      const call = RouterManager.buyWithPermitCallParameters({
        router: router(),
        index: ctx.index,
        usdcAmount,
        tolerance: TOLERANCE,
        deadline,
        nowSeconds,
        signature: splitPermitSignature(signature),
      });
      await ctx.testClient.increaseTime({ seconds: 60 });
      await ctx.testClient.mine({ blocks: 1 });
      const error = await simulateError(ctx, user, call, routerAbiOf(ctx), "buyWithPermit");
      expect(error).toBeInstanceOf(ContractRevertError);
      if (ctx.isMock) {
        expect((error as ContractRevertError).errorName).toBe("ERC2612ExpiredSignature");
        expect((error as ContractRevertError).args).toEqual([deadline]);
      }
    });
  });

  describe("RouterManager.sellCallParameters", () => {
    it("sells without any share approval: shares burn, USDC arrives, SharesBurned matches the state", async () => {
      const user = userAddress();
      await buyShares(ctx, ctx.user, parseUsdc("5000"), TOLERANCE);
      const shares = await balanceOf(ctx, ctx.index, user);
      const sharesAmount = shares / 2n;
      // Security: the Index burns the shares directly, no allowance to anyone is needed.
      for (const spender of [router(), ctx.index]) {
        expect(
          await ctx.publicClient.readContract(Erc20Manager.allowanceRead({ token: ctx.index, owner: user, spender })),
        ).toBe(0n);
      }

      const before = await loadIndex(ctx);
      const minUsdc = before.minRedeemPreview(sharesAmount, TOLERANCE);
      const usdcBefore = await balanceOf(ctx, usdc(), user);
      const call = RouterManager.sellCallParameters({ router: router(), index: ctx.index, sharesAmount, tolerance: TOLERANCE });
      const decoded = decodeFunctionData({ abi: routerAbiOf(ctx), data: call.calldata });
      expect(decoded.functionName).toBe("sellExactAmountOfSharesForUsdc");
      expect(decoded.args).toEqual([ctx.index, sharesAmount, TOLERANCE]);
      expect(call.to).toBe(router());

      const receipt = await send(ctx, ctx.user, call);
      const event = parseSharesBurned(receipt.logs, ctx.index);
      const after = await loadIndex(ctx);

      expect(isAddressEqual(event.user, user)).toBe(true);
      expect(event.sharesBurned).toBe(sharesAmount);
      expect(event.usdcAmountOut).toBeGreaterThanOrEqual(minUsdc);
      expect(await balanceOf(ctx, usdc(), user)).toBe(usdcBefore + event.usdcAmountOut);
      expect(await balanceOf(ctx, ctx.index, user)).toBe(shares - sharesAmount);
      expect(after.snapshot.totalSupply).toBe(before.snapshot.totalSupply - sharesAmount);
      expect(after.snapshot.reserve0).toBe(before.snapshot.reserve0 - event.asset0Amount);
      expect(after.snapshot.reserve1).toBe(before.snapshot.reserve1 - event.asset1Amount);
      expect(after.snapshot.totalFees).toBe(before.snapshot.totalFees + event.feeAmount);
      expect(() => parseSharesBurned(receipt.logs, router())).toThrow(EventNotFoundError);
    });

    it("selling more shares than held: Router__InsufficientSharesBalance, checkSell agrees", async () => {
      const user = userAddress();
      await buyShares(ctx, ctx.user, parseUsdc("100"), TOLERANCE);
      const shares = await balanceOf(ctx, ctx.index, user);
      expect(() =>
        RouterManager.checkSell({ index: ctx.index, sharesAmount: shares + 1n, isInitialized: true, sharesBalance: shares }),
      ).toThrow(InsufficientBalanceError);
      const call = RouterManager.sellCallParameters({
        router: router(),
        index: ctx.index,
        sharesAmount: shares + 1n,
        tolerance: TOLERANCE,
      });
      const error = await simulateError(ctx, user, call, routerAbiOf(ctx), "sell");
      expect((error as ContractRevertError).errorName).toBe("Router__InsufficientSharesBalance");
      expect((error as ContractRevertError).args).toEqual([shares, shares + 1n]);
    });

    it("zero shares: the SDK refuses, checkSell refuses", () => {
      expect(() =>
        RouterManager.sellCallParameters({ router: router(), index: ctx.index, sharesAmount: 0n, tolerance: TOLERANCE }),
      ).toThrow(ZeroAmountError);
      expect(() =>
        RouterManager.checkSell({ index: ctx.index, sharesAmount: 0n, isInitialized: true, sharesBalance: 1n }),
      ).toThrow(ZeroAmountError);
    });
  });

  describe("Router reads", () => {
    it("constants equal the on-chain values: MAX_TOLERANCE, USDC and IndexManager of the Router", async () => {
      expect(await ctx.publicClient.readContract(RouterManager.maxToleranceRead(router()))).toBe(MAX_TOLERANCE);
      expect(await ctx.publicClient.readContract(RouterManager.usdcRead(router()))).toBe(usdc());
      expect(await ctx.publicClient.readContract(RouterManager.indexManagerRead(router()))).toBe(ctx.addresses.indexManager);
    });

    it("isInitialized for checkBuy comes from the Index snapshot read", async () => {
      const reads = IndexManager.snapshotReads(ctx.index);
      expect(await ctx.publicClient.readContract(reads[7])).toBe(true);
    });
  });
}
