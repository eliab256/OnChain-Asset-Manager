// Governance through the 2-of-3 MultiSigWallet, every step built by the SDK and executed on chain:
// submit (MultiSigCalls.submitCallParameters wrapping PriceFeedManagerCalls / IndexManagerCalls /
// Erc20Manager), one on-chain confirmation, one EIP-712 confirmation (buildConfirmTypedData, sent by
// a non-owner with confirmWithSigCallParameters), execute, then the receipts parsed with
// parseTransactionExecuted / parseIndexCreated. The owners are the anvil accounts 1 and 2 on both
// chains (deployments/<chainId>.json multiSigWallet.owners; account 0 is the deployer, not an owner).
// The new Index is LINK/COMP: mocks on 31337, mainnet tokens and Chainlink feeds on the fork.
import { multiSigWalletAbi, priceFeedManagerAbi } from "@oam/abi";
import {
  concat,
  encodeFunctionData,
  hashTypedData,
  hexToBigInt,
  isAddressEqual,
  maxUint256,
  numberToHex,
  slice,
  type Address,
  type Hex,
  type TransactionReceipt,
} from "viem";
import { describe, expect, it } from "vitest";
import {
  ContractRevertError,
  Erc20Manager,
  InvalidSignatureError,
  IndexManager,
  IndexManagerCalls,
  MAX_FEE_PERCENTAGE,
  MAX_FEED_DELAY,
  MultiSigCalls,
  MultiSigNotExecutableError,
  PriceFeedManagerCalls,
  PriceFeedReads,
  buildConfirmTypedData,
  decodeProposal,
  parseConfirmationRevoked,
  parseIndexCreated,
  parseTransactionConfirmed,
  parseTransactionExecuted,
  parseTransactionSubmitted,
  permitDomainFromEip712Domain,
  v3Route,
  type MethodParameters,
} from "../../src/index.js";
import {
  balanceOf,
  dealErc20,
  impersonateMultiSig,
  indexActionsTriggered,
  mockFeedAbi,
  refreshMockFeeds,
  send,
  simulateError,
  type ForkContext,
  type Wallet,
} from "../helpers/chain.js";
import { extraAssets, testFeedMaxDelay } from "../helpers/indexes.js";

const FEE_PERCENTAGE = 10_000n;
const WEIGHT_LINK = 400_000n;
const WEIGHT_COMP = 600_000n;
const V3_FEE = 3000;
const PRICE_FEED_UPDATE_DELAY = 2n * 24n * 3600n;
const SECP256K1_N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

export function multiSigSuite(ctx: ForkContext): void {
  const multiSig = () => ctx.addresses.multiSigWallet;
  const msAbi = () => MultiSigCalls.ownersRead(multiSig()).abi;
  const maxDelay = () => testFeedMaxDelay(ctx);
  const assets = () => extraAssets(ctx);

  async function readTransaction(txId: bigint) {
    const [target, value, data, executed, confirmations] = await ctx.publicClient.readContract(
      MultiSigCalls.transactionRead({ multiSig: multiSig(), txId }),
    );
    return { target, value, data, executed, confirmations };
  }

  async function submit(proposer: Wallet, call: MethodParameters): Promise<bigint> {
    const receipt = await send(ctx, proposer, MultiSigCalls.submitCallParameters({ multiSig: multiSig(), call }));
    const event = parseTransactionSubmitted(receipt.logs, multiSig());
    expect(event).toMatchObject({ proposer: proposer.account.address, target: call.to, value: call.value });
    expect(event.data.toLowerCase()).toBe(call.calldata.toLowerCase());
    const stored = await readTransaction(event.txId);
    expect(stored).toMatchObject({ target: call.to, value: call.value, executed: false, confirmations: 0n });
    return event.txId;
  }

  async function confirm(owner: Wallet, txId: bigint): Promise<void> {
    const receipt = await send(ctx, owner, MultiSigCalls.confirmCallParameters({ multiSig: multiSig(), txId }));
    expect(parseTransactionConfirmed(receipt.logs, multiSig())).toEqual({ txId, owner: owner.account.address });
  }

  /** Signs the stored transaction with the domain and nonce read from the chain; checks the digest first. */
  async function signConfirmation(signer: Wallet, txId: bigint): Promise<Hex> {
    const stored = await readTransaction(txId);
    const domain = permitDomainFromEip712Domain(await ctx.publicClient.readContract(MultiSigCalls.eip712DomainRead(multiSig())));
    expect(domain).toMatchObject({ name: "MultiSigWallet", version: "2", chainId: ctx.chainId });
    expect(isAddressEqual(domain.verifyingContract, multiSig())).toBe(true);
    const nonce = await ctx.publicClient.readContract(
      MultiSigCalls.confirmNonceRead({ multiSig: multiSig(), txId, owner: signer.account.address }),
    );
    const typed = buildConfirmTypedData({ domain, txId, target: stored.target, value: stored.value, data: stored.data, nonce });
    const onChainDigest = await ctx.publicClient.readContract(
      MultiSigCalls.confirmDigestRead({ multiSig: multiSig(), txId, signer: signer.account.address }),
    );
    expect(hashTypedData(typed)).toBe(onChainDigest);
    return signer.signTypedData({ ...typed, account: signer.account });
  }

  /** Any account can relay the signature: the relayer here is not an owner. */
  async function confirmWithSig(txId: bigint, signer: Wallet, signature: Hex): Promise<void> {
    const call = MultiSigCalls.confirmWithSigCallParameters({ multiSig: multiSig(), txId, signer: signer.account.address, signature });
    const receipt = await send(ctx, ctx.user, call);
    expect(parseTransactionConfirmed(receipt.logs, multiSig())).toEqual({ txId, owner: signer.account.address });
  }

  async function checkExecutable(txId: bigint): Promise<void> {
    const stored = await readTransaction(txId);
    const requiredConfirmations = await ctx.publicClient.readContract(MultiSigCalls.requiredConfirmationsRead(multiSig()));
    MultiSigCalls.checkExecutable({ txId, executed: stored.executed, confirmations: stored.confirmations, requiredConfirmations });
  }

  async function execute(executor: Wallet, txId: bigint): Promise<TransactionReceipt> {
    await checkExecutable(txId);
    const receipt = await send(ctx, executor, MultiSigCalls.executeCallParameters({ multiSig: multiSig(), txId }));
    expect(parseTransactionExecuted(receipt.logs, multiSig())).toEqual({ txId, executor: executor.account.address });
    expect((await readTransaction(txId)).executed).toBe(true);
    return receipt;
  }

  /** submit by owner1, owner1 confirms on chain, owner2 confirms by signature, owner1 executes. */
  async function runProposal(call: MethodParameters): Promise<TransactionReceipt> {
    const txId = await submit(ctx.owner1, call);
    const stored = await readTransaction(txId);
    const decoded = decodeProposal({ target: stored.target, value: stored.value, data: stored.data }, ctx.addresses);
    expect(isAddressEqual(decoded.target, call.to)).toBe(true);
    await confirm(ctx.owner1, txId);
    await confirmWithSig(txId, ctx.owner2, await signConfirmation(ctx.owner2, txId));
    return execute(ctx.owner1, txId);
  }

  async function refreshMockFeed(feed: Address): Promise<void> {
    const answer = await ctx.publicClient.readContract({ address: feed, abi: mockFeedAbi, functionName: "latestAnswer" });
    await send(ctx, ctx.deployer, {
      to: feed,
      calldata: encodeFunctionData({ abi: mockFeedAbi, functionName: "updateAnswer", args: [answer] }),
      value: 0n,
    });
  }

  async function registerFeeds(): Promise<void> {
    const { priceFeedManager } = ctx.addresses;
    for (const { token, feed } of Object.values(assets())) {
      if (ctx.isMock) await refreshMockFeed(feed);
      if (await ctx.publicClient.readContract(PriceFeedReads.hasPriceFeedRead({ priceFeedManager, asset: token }))) continue;
      const call = PriceFeedManagerCalls.registerPriceFeedCallParameters({ priceFeedManager, asset: token, feed, maxDelay: maxDelay() });
      await runProposal(call);
      const config = await ctx.publicClient.readContract(PriceFeedReads.feedConfigRead({ priceFeedManager, asset: token }));
      expect(isAddressEqual(config.feed, feed)).toBe(true);
      expect(config.maxDelay).toBe(maxDelay());
    }
  }

  function createIndexCall(): MethodParameters {
    const { link, comp } = assets();
    return IndexManagerCalls.createIndexCallParameters({
      indexManager: ctx.addresses.indexManager,
      feePercentage: FEE_PERCENTAGE,
      assetA: { asset: comp.token, weight: WEIGHT_COMP },
      assetB: { asset: link.token, weight: WEIGHT_LINK },
      usdc: ctx.addresses.usdc,
    });
  }

  async function createIndex(): Promise<Address> {
    await registerFeeds();
    const receipt = await runProposal(createIndexCall());
    const created = parseIndexCreated(receipt.logs, ctx.addresses.indexManager);
    const { link, comp } = assets();
    const index = await ctx.publicClient.readContract(
      IndexManagerCalls.indexByAssetsRead({ indexManager: ctx.addresses.indexManager, assetA: link.token, assetB: comp.token }),
    );
    // The contract sorts the assets: asset0 is the lower address and keeps its own weight.
    const linkFirst = BigInt(link.token) < BigInt(comp.token);
    expect(created).toEqual({
      index,
      asset0: linkFirst ? link.token : comp.token,
      asset1: linkFirst ? comp.token : link.token,
      asset0Weight: linkFirst ? WEIGHT_LINK : WEIGHT_COMP,
      asset1Weight: linkFirst ? WEIGHT_COMP : WEIGHT_LINK,
      feePercentage: Number(FEE_PERCENTAGE),
      assetManager: multiSig(),
    });
    return index;
  }

  describe("MultiSig governance flow", () => {
    it("the deployment's owners and threshold are those the flow relies on", async () => {
      const owners = await ctx.publicClient.readContract(MultiSigCalls.ownersRead(multiSig()));
      expect(owners).toContain(ctx.owner1.account.address);
      expect(owners).toContain(ctx.owner2.account.address);
      expect(owners).not.toContain(ctx.user.account.address);
      expect(await ctx.publicClient.readContract(MultiSigCalls.requiredConfirmationsRead(multiSig()))).toBe(2n);
      expect(await ctx.publicClient.readContract(MultiSigCalls.isOwnerRead({ multiSig: multiSig(), account: ctx.owner1.account.address }))).toBe(true);
      expect(await ctx.publicClient.readContract(MultiSigCalls.isOwnerRead({ multiSig: multiSig(), account: ctx.user.account.address }))).toBe(false);
    });

    it("registerPriceFeed and createIndex: submit, confirm, confirmWithSig, execute; IndexCreated parsed from the execute receipt", async () => {
      const index = await createIndex();
      expect(await ctx.publicClient.readContract(IndexManagerCalls.deployedIndexesRead(ctx.addresses.indexManager))).toContain(index);
      expect(await ctx.publicClient.readContract(IndexManagerCalls.isIndexInitializedRead({ indexManager: ctx.addresses.indexManager, index }))).toBe(false);
    });

    it("approve via MultiSig, then initializeIndex with v3Route: reserves equal the deposit pulled from the MultiSig", async () => {
      const index = await createIndex();
      const { indexManager, usdc } = ctx.addresses;
      const [asset0Read, asset1Read, decimalsRead, reservesRead] = IndexManager.snapshotReads(index);
      const asset0 = await ctx.publicClient.readContract(asset0Read);
      const asset1 = await ctx.publicClient.readContract(asset1Read);
      const [decimals0, decimals1] = await ctx.publicClient.readContract(decimalsRead);
      // Mock feeds are stamped at deploy; initializeIndex prices both assets and USDC.
      if (ctx.isMock) await refreshMockFeeds(ctx, [asset0, asset1]);

      const amount0 = 100n * 10n ** BigInt(decimals0);
      // COMP keeps balances in uint96: stay well below 2^96 so the storage write reads back intact.
      const funds1 = 10n ** BigInt(decimals1 + 9);
      await dealErc20(ctx, asset0, multiSig(), (await balanceOf(ctx, asset0, multiSig())) + amount0);
      await dealErc20(ctx, asset1, multiSig(), (await balanceOf(ctx, asset1, multiSig())) + funds1);

      for (const token of [asset0, asset1]) {
        const approve = Erc20Manager.approveCallParameters({ token, spender: index, amount: maxUint256 });
        const decoded = decodeProposal({ target: approve.to, value: approve.value, data: approve.calldata }, ctx.addresses);
        expect(decoded).toMatchObject({ contract: "ERC20", functionName: "approve", args: [index, maxUint256] });
        await runProposal(approve);
        // Mainnet COMP keeps allowances in uint96 and stores approve(maxUint256) as 2^96 - 1, so the stored value
        // is token-specific: what initializeIndex needs is an allowance covering everything the MultiSig holds.
        const allowance = await ctx.publicClient.readContract(Erc20Manager.allowanceRead({ token, owner: multiSig(), spender: index }));
        expect(allowance >= (await balanceOf(ctx, token, multiSig()))).toBe(true);
      }

      const before0 = await balanceOf(ctx, asset0, multiSig());
      const before1 = await balanceOf(ctx, asset1, multiSig());
      const call = IndexManagerCalls.initializeIndexCallParameters({
        indexManager,
        depositor: multiSig(),
        index,
        amount0,
        routes: {
          asset0Usdc: v3Route([asset0, usdc], [V3_FEE]),
          asset1Usdc: v3Route([usdc, asset1], [V3_FEE]),
          asset0Asset1: v3Route([asset0, asset1], [V3_FEE]),
        },
        tokens: { asset0, asset1, usdc },
      });
      const receipt = await runProposal(call);

      expect(indexActionsTriggered(receipt.logs, indexManager)).toContainEqual({ index, caller: multiSig(), action: "INITIALIZE" });
      expect(await ctx.publicClient.readContract(IndexManagerCalls.isIndexInitializedRead({ indexManager, index }))).toBe(true);
      const [reserve0, reserve1] = await ctx.publicClient.readContract(reservesRead);
      expect(reserve0).toBe(amount0);
      expect(reserve1).toBeGreaterThan(0n);
      expect(await balanceOf(ctx, asset0, multiSig())).toBe(before0 - amount0);
      expect(await balanceOf(ctx, asset1, multiSig())).toBe(before1 - reserve1);
    });

    it("security: a revoke invalidates a confirmation signature collected before it", async () => {
      const call = createIndexCall();
      const txId = await submit(ctx.owner1, call);
      const stale = await signConfirmation(ctx.owner2, txId);
      await confirm(ctx.owner2, txId);

      const revoked = await send(ctx, ctx.owner2, MultiSigCalls.revokeCallParameters({ multiSig: multiSig(), txId }));
      expect(parseConfirmationRevoked(revoked.logs, multiSig())).toEqual({ txId, owner: ctx.owner2.account.address });
      const owner2 = ctx.owner2.account.address;
      expect(await ctx.publicClient.readContract(MultiSigCalls.isConfirmedRead({ multiSig: multiSig(), txId, owner: owner2 }))).toBe(false);
      expect(await ctx.publicClient.readContract(MultiSigCalls.confirmNonceRead({ multiSig: multiSig(), txId, owner: owner2 }))).toBe(1n);

      const replay = MultiSigCalls.confirmWithSigCallParameters({ multiSig: multiSig(), txId, signer: owner2, signature: stale });
      const error = await simulateError(ctx, ctx.user.account.address, replay, msAbi(), "confirmWithSig");
      expect(error).toBeInstanceOf(ContractRevertError);
      expect((error as ContractRevertError).errorName).toBe("MultiSig__InvalidSignature");

      // A fresh signature at the new nonce is accepted.
      await confirmWithSig(txId, ctx.owner2, await signConfirmation(ctx.owner2, txId));
      expect((await readTransaction(txId)).confirmations).toBe(1n);
    });

    it("security: a signature is bound to its signer and replays are rejected", async () => {
      const txId = await submit(ctx.owner1, createIndexCall());
      const byOwner1 = await signConfirmation(ctx.owner1, txId);
      const asOwner2 = MultiSigCalls.confirmWithSigCallParameters({
        multiSig: multiSig(),
        txId,
        signer: ctx.owner2.account.address,
        signature: byOwner1,
      });
      const wrongSigner = await simulateError(ctx, ctx.user.account.address, asOwner2, msAbi(), "confirmWithSig");
      expect((wrongSigner as ContractRevertError).errorName).toBe("MultiSig__InvalidSignature");

      await confirmWithSig(txId, ctx.owner1, byOwner1);
      const replay = MultiSigCalls.confirmWithSigCallParameters({ multiSig: multiSig(), txId, signer: ctx.owner1.account.address, signature: byOwner1 });
      const replayed = await simulateError(ctx, ctx.user.account.address, replay, msAbi(), "confirmWithSig");
      expect((replayed as ContractRevertError).errorName).toBe("MultiSig__TxAlreadyConfirmed");
    });

    it("security: a signature by a non-owner is rejected with MultiSig__NotOwner", async () => {
      const txId = await submit(ctx.owner1, createIndexCall());
      const stored = await readTransaction(txId);
      const domain = permitDomainFromEip712Domain(await ctx.publicClient.readContract(MultiSigCalls.eip712DomainRead(multiSig())));
      const typed = buildConfirmTypedData({ domain, txId, target: stored.target, value: stored.value, data: stored.data, nonce: 0n });
      const signature = await ctx.user.signTypedData({ ...typed, account: ctx.user.account });
      const call = MultiSigCalls.confirmWithSigCallParameters({ multiSig: multiSig(), txId, signer: ctx.user.account.address, signature });
      const error = await simulateError(ctx, ctx.user.account.address, call, msAbi(), "confirmWithSig");
      expect((error as ContractRevertError).errorName).toBe("MultiSig__NotOwner");
    });

    // Why assertConfirmSignature rejects high-s: the chain does too. The calldata is encoded by hand
    // because the SDK builder now refuses this signature.
    it("security: OpenZeppelin ECDSA in the MultiSig rejects a high-s signature with ECDSAInvalidSignatureS", async () => {
      const txId = await submit(ctx.owner1, createIndexCall());
      const signature = await signConfirmation(ctx.owner2, txId);
      const s = hexToBigInt(slice(signature, 32, 64));
      const v = Number(hexToBigInt(slice(signature, 64, 65)));
      const high = concat([slice(signature, 0, 32), numberToHex(SECP256K1_N - s, { size: 32 }), numberToHex(v === 27 ? 28 : 27, { size: 1 })]);
      const call = {
        to: multiSig(),
        value: 0n,
        calldata: encodeFunctionData({
          abi: multiSigWalletAbi,
          functionName: "confirmTransactionWithSig",
          args: [txId, ctx.owner2.account.address, high],
        }),
      };
      const error = await simulateError(ctx, ctx.user.account.address, call, msAbi(), "confirmWithSig");
      expect((error as ContractRevertError).errorName).toBe("ECDSAInvalidSignatureS");
    });

    // Why the SDK normalises v: the raw v = 0/1 bytes, encoded by hand, are rejected by the contract.
    it("security: the MultiSig rejects raw v = 0/1 bytes with ECDSAInvalidSignature", async () => {
      const txId = await submit(ctx.owner1, createIndexCall());
      const signature = await signConfirmation(ctx.owner2, txId);
      const v = Number(hexToBigInt(slice(signature, 64, 65)));
      const vZero = concat([slice(signature, 0, 64), numberToHex(v - 27, { size: 1 })]);
      const call = {
        to: multiSig(),
        value: 0n,
        calldata: encodeFunctionData({
          abi: multiSigWalletAbi,
          functionName: "confirmTransactionWithSig",
          args: [txId, ctx.owner2.account.address, vZero],
        }),
      };
      const error = await simulateError(ctx, ctx.user.account.address, call, msAbi(), "confirmWithSig");
      expect((error as ContractRevertError).errorName).toBe("ECDSAInvalidSignature");
    });

    it("a v = 0/1 signature passed through confirmWithSigCallParameters is accepted on chain", async () => {
      const txId = await submit(ctx.owner1, createIndexCall());
      const signature = await signConfirmation(ctx.owner2, txId);
      const v = Number(hexToBigInt(slice(signature, 64, 65)));
      const yParityByte = concat([slice(signature, 0, 64), numberToHex(v - 27, { size: 1 })]);
      await confirmWithSig(txId, ctx.owner2, yParityByte);
      expect(
        await ctx.publicClient.readContract(MultiSigCalls.isConfirmedRead({ multiSig: multiSig(), txId, owner: ctx.owner2.account.address })),
      ).toBe(true);
      expect((await readTransaction(txId)).confirmations).toBe(1n);
    });

    it("security: confirmWithSigCallParameters refuses a high-s signature before it reaches the chain", async () => {
      const txId = await submit(ctx.owner1, createIndexCall());
      const signature = await signConfirmation(ctx.owner2, txId);
      const s = hexToBigInt(slice(signature, 32, 64));
      const v = Number(hexToBigInt(slice(signature, 64, 65)));
      const high = concat([slice(signature, 0, 32), numberToHex(SECP256K1_N - s, { size: 32 }), numberToHex(v === 27 ? 28 : 27, { size: 1 })]);
      expect(() =>
        MultiSigCalls.confirmWithSigCallParameters({ multiSig: multiSig(), txId, signer: ctx.owner2.account.address, signature: high }),
      ).toThrow(InvalidSignatureError);
    });

    it("checkExecutable agrees with executeTransaction: short of confirmations, then already executed", async () => {
      const { asset0 } = ctx;
      const { priceFeedManager } = ctx.addresses;
      const config = await ctx.publicClient.readContract(PriceFeedReads.feedConfigRead({ priceFeedManager, asset: asset0 }));
      // A harmless proposal: an update of the asset0 feed to a different maxDelay, to be cancelled later.
      const call = PriceFeedManagerCalls.proposePriceFeedUpdateCallParameters({
        priceFeedManager,
        asset: asset0,
        feed: config.feed,
        maxDelay: config.maxDelay === MAX_FEED_DELAY ? MAX_FEED_DELAY - 1 : MAX_FEED_DELAY,
      });
      const txId = await submit(ctx.owner1, call);
      await confirm(ctx.owner1, txId);

      await expect(checkExecutable(txId)).rejects.toBeInstanceOf(MultiSigNotExecutableError);
      const executeCall = MultiSigCalls.executeCallParameters({ multiSig: multiSig(), txId });
      const short = await simulateError(ctx, ctx.owner1.account.address, executeCall, msAbi(), "execute");
      expect((short as ContractRevertError).errorName).toBe("MultiSig__ConfirmationsNotMet");

      await confirm(ctx.owner2, txId);
      await execute(ctx.owner2, txId);
      await expect(checkExecutable(txId)).rejects.toBeInstanceOf(MultiSigNotExecutableError);
      const again = await simulateError(ctx, ctx.owner1.account.address, executeCall, msAbi(), "execute");
      expect((again as ContractRevertError).errorName).toBe("MultiSig__TxAlreadyExecuted");
    });

    it("a proposal whose call reverts makes execute revert with MultiSig__TxFailed and stays pending", async () => {
      // createIndex of LINK/COMP before their feeds are registered: the IndexManager reverts.
      const { priceFeedManager } = ctx.addresses;
      const anyRegistered = await Promise.all(
        Object.values(assets()).map(({ token }) => ctx.publicClient.readContract(PriceFeedReads.hasPriceFeedRead({ priceFeedManager, asset: token }))),
      );
      expect(anyRegistered).toEqual([false, false]);
      const txId = await submit(ctx.owner1, createIndexCall());
      await confirm(ctx.owner1, txId);
      await confirm(ctx.owner2, txId);
      await checkExecutable(txId);
      const error = await simulateError(ctx, ctx.owner1.account.address, MultiSigCalls.executeCallParameters({ multiSig: multiSig(), txId }), msAbi(), "execute");
      expect((error as ContractRevertError).errorName).toBe("MultiSig__TxFailed");
      expect((await readTransaction(txId)).executed).toBe(false);
    });
  });

  describe("PriceFeedManagerCalls on chain (as the MultiSig)", () => {
    it("propose, then execute after the 2-day delay, updates maxDelay; MAX_FEED_DELAY is accepted", async () => {
      const ms = await impersonateMultiSig(ctx);
      const { priceFeedManager } = ctx.addresses;
      const asset = ctx.addresses.usdc;
      const before = await ctx.publicClient.readContract(PriceFeedReads.feedConfigRead({ priceFeedManager, asset }));
      const newDelay = before.maxDelay === MAX_FEED_DELAY ? MAX_FEED_DELAY - 1 : MAX_FEED_DELAY;
      await send(ctx, ms, PriceFeedManagerCalls.proposePriceFeedUpdateCallParameters({ priceFeedManager, asset, feed: before.feed, maxDelay: newDelay }));
      const pending = PriceFeedReads.toPendingFeedUpdate(
        await ctx.publicClient.readContract(PriceFeedReads.pendingFeedUpdateRead({ priceFeedManager, asset })),
      );
      expect(pending).toMatchObject({ feed: before.feed, maxDelay: newDelay });

      await ctx.testClient.increaseTime({ seconds: Number(PRICE_FEED_UPDATE_DELAY + 1n) });
      await ctx.testClient.mine({ blocks: 1 });
      await send(ctx, ms, PriceFeedManagerCalls.executePriceFeedUpdateCallParameters({ priceFeedManager, asset }));
      const after = await ctx.publicClient.readContract(PriceFeedReads.feedConfigRead({ priceFeedManager, asset }));
      expect(after).toMatchObject({ feed: before.feed, maxDelay: newDelay });
      expect(
        PriceFeedReads.toPendingFeedUpdate(await ctx.publicClient.readContract(PriceFeedReads.pendingFeedUpdateRead({ priceFeedManager, asset }))),
      ).toBeUndefined();
    });

    it("propose then cancel leaves no pending update", async () => {
      const ms = await impersonateMultiSig(ctx);
      const { priceFeedManager } = ctx.addresses;
      const asset = ctx.asset0;
      const before = await ctx.publicClient.readContract(PriceFeedReads.feedConfigRead({ priceFeedManager, asset }));
      const newDelay = before.maxDelay === 1 ? 2 : 1;
      await send(ctx, ms, PriceFeedManagerCalls.proposePriceFeedUpdateCallParameters({ priceFeedManager, asset, feed: before.feed, maxDelay: newDelay }));
      await send(ctx, ms, PriceFeedManagerCalls.cancelPriceFeedUpdateCallParameters({ priceFeedManager, asset }));
      expect(
        PriceFeedReads.toPendingFeedUpdate(await ctx.publicClient.readContract(PriceFeedReads.pendingFeedUpdateRead({ priceFeedManager, asset }))),
      ).toBeUndefined();
      expect(await ctx.publicClient.readContract(PriceFeedReads.feedConfigRead({ priceFeedManager, asset }))).toEqual(before);
    });

    it("constants: MAX_FEED_DELAY + 1 is rejected on chain with PriceFeedManager__InvalidMaxDelay", async () => {
      const { priceFeedManager } = ctx.addresses;
      const config = await ctx.publicClient.readContract(PriceFeedReads.feedConfigRead({ priceFeedManager, asset: ctx.asset0 }));
      // Encoded by hand: the SDK builder refuses this value before it reaches the chain.
      const call = {
        to: priceFeedManager,
        value: 0n,
        calldata: encodeFunctionData({
          abi: priceFeedManagerAbi,
          functionName: "proposePriceFeedUpdate",
          args: [ctx.asset0, config.feed, MAX_FEED_DELAY + 1],
        }),
      };
      const error = await simulateError(ctx, multiSig(), call, priceFeedManagerAbiOf(ctx), "proposePriceFeedUpdate");
      expect((error as ContractRevertError).errorName).toBe("PriceFeedManager__InvalidMaxDelay");
    });
  });

  describe("createIndex fee bounds on chain", () => {
    // The fee is checked before the duplicate check: with the existing pair, a fee inside the bounds
    // gets to IndexManager__IndexAlreadyExists, a fee outside stops at IndexManager__InvalidFeePercentage.
    it("constants: MAX_FEE_PERCENTAGE passes the fee check, MAX_FEE_PERCENTAGE + 1 does not", async () => {
      const abi = IndexManagerCalls.deployedIndexesRead(ctx.addresses.indexManager).abi;
      const atMax = IndexManagerCalls.createIndexCallParameters({
        indexManager: ctx.addresses.indexManager,
        feePercentage: MAX_FEE_PERCENTAGE,
        assetA: { asset: ctx.asset0, weight: 500_000n },
        assetB: { asset: ctx.asset1, weight: 500_000n },
      });
      const passed = await simulateError(ctx, multiSig(), atMax, abi, "createIndex");
      expect((passed as ContractRevertError).errorName).toBe("IndexManager__IndexAlreadyExists");

      const overMax = {
        ...atMax,
        calldata: encodeFunctionData({
          abi,
          functionName: "createIndex",
          args: [Number(MAX_FEE_PERCENTAGE) + 1, { asset: ctx.asset0, weightPercentage: 500_000n }, { asset: ctx.asset1, weightPercentage: 500_000n }],
        }),
      };
      const rejected = await simulateError(ctx, multiSig(), overMax, abi, "createIndex");
      expect((rejected as ContractRevertError).errorName).toBe("IndexManager__InvalidFeePercentage");
    });
  });
}

/** The PriceFeedManager ABI with every protocol error, taken from a read descriptor of the SDK. */
function priceFeedManagerAbiOf(ctx: ForkContext) {
  return PriceFeedReads.priceRead({ priceFeedManager: ctx.addresses.priceFeedManager, asset: ctx.asset0 }).abi;
}
