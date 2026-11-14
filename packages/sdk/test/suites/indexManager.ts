// IndexManagerCalls executed on chain with the accounts that actually hold the roles after
// DeployPeriphery: the MultiSig is admin and ASSET_MANAGER and holds REBALANCER and FEE_COLLECTOR as
// fallback; the keeper accounts of the deployment config hold REBALANCER (rebalance, executeWeightUpdate)
// and FEE_COLLECTOR (collectFees); the deployer holds no role. The keeper actions are sent by the
// keepers, the MultiSig fallback has its own named test. Index actions failing with a custom error
// do not revert: they are read back with parseIndexActionFailure. Since the single entry points bubble up common errors (out of gas,
// Error(string), Panic), and Index.executeWeightUpdate re-throws them from its inner rebalance,
// eth_estimateGas is enough for every single action; the batch ones still swallow everything.
import { indexAbi, indexManagerAbi } from "@oam/abi";
import {
  decodeFunctionData,
  getAddress,
  isAddressEqual,
  keccak256,
  parseEventLogs,
  stringToHex,
  type Address,
  type Log,
} from "viem";
import { describe, expect, it } from "vitest";
import {
  ContractRevertError,
  EmptyIndexListError,
  IndexManager,
  IndexManagerCalls,
  IndexNotInitializedError,
  InvalidWeightError,
  MAX_WEIGHT,
  MIN_WEIGHT,
  REBALANCE_THRESHOLD,
  decodeProtocolError,
  parseIndexActionFailure,
  parseUsdc,
  type IndexManagerRole,
  type MethodParameters,
} from "../../src/index.js";
import {
  balanceOf,
  buyShares,
  chainNow,
  estimateGas,
  impersonateMultiSig,
  indexActionsTriggered,
  indexManagerAbiOf,
  loadIndex,
  moveMockPrice,
  refreshMockFeeds,
  revert,
  send,
  sendThroughMultiSig,
  sendUnchecked,
  snapshot,
  simulateError,
  type ForkContext,
} from "../helpers/chain.js";
import { createUninitializedIndex } from "../helpers/indexes.js";
import { TOLERANCE } from "./router.js";

const WEIGHT_UPDATE_DELAY = 2n * 24n * 3600n;
const NEW_WEIGHT0 = 600_000n;
/**
 * Explicit limit for the batch actions only: they turn every Index failure, out of gas included,
 * into IndexActionFailed, so the contract gives no guarantee that the least successful gas is a gas
 * at which the Index call runs. For executeWeightUpdateMany an inner out of gas now reverts the whole
 * Index call, which the batch reports as IndexActionFailed with the proposal still pending: the tx
 * succeeds but nothing changes. On this deploy the 1/64 left after an inner out of gas cannot pay
 * for the event, so no such limit was found, but that depends on the gas left after the call.
 * The single actions (rebalance, collectFees, executeWeightUpdate) do not need it.
 */
const KEEPER_GAS_LIMIT = 3_000_000n;
/** Below the estimate but far above what the IndexManager modifiers and the call setup cost. */
const UNDER_ESTIMATE_STEPS = [1_000n, 5_000n, 20_000n, 50_000n] as const;

/**
 * WeightsUpdateRebalanceFailed emitted by the Index itself (its own try/catch around rebalanceIndex),
 * as decoded error names so a failing assertion says why: "0x" stands for empty revert data.
 */
function weightsRebalanceFailures(logs: readonly Log[], index: `0x${string}`): string[] {
  return parseEventLogs({ abi: indexAbi, eventName: "WeightsUpdateRebalanceFailed", logs: [...logs] })
    .filter((log) => isAddressEqual(log.address, index))
    .map((log) => decodeProtocolError(log.args.reasonData)?.errorName ?? log.args.reasonData);
}

export function indexManagerSuite(ctx: ForkContext): void {
  const indexManager = () => ctx.addresses.indexManager;
  const deployer = () => ctx.deployer.account.address;
  const rebalancer = () => ctx.keepers.rebalancer;
  const feeCollector = () => ctx.keepers.feeCollector;
  const single = () => ({ indexManager: indexManager(), index: ctx.index });

  /** The SDK error layer must decode the OpenZeppelin revert with the account and the missing role hash. */
  async function expectUnauthorized(account: Address, call: MethodParameters, role: IndexManagerRole): Promise<void> {
    const { functionName } = decodeFunctionData({ abi: indexManagerAbiOf(ctx), data: call.calldata });
    const error = await simulateError(ctx, account, call, indexManagerAbiOf(ctx), functionName);
    expect(error, `${functionName} from ${account}`).toBeInstanceOf(ContractRevertError);
    expect((error as ContractRevertError).errorName).toBe("AccessControlUnauthorizedAccount");
    expect((error as ContractRevertError).args).toEqual([account, IndexManagerCalls.roleHash(role)]);
  }

  async function pending() {
    return IndexManager.toPendingWeightUpdate(await ctx.publicClient.readContract(IndexManager.pendingWeightsRead(ctx.index)));
  }

  describe("IndexManagerCalls roles and registry reads", () => {
    it("roleHash equals the role constants of the deployed IndexManager", async () => {
      const onChain: Record<IndexManagerRole, `0x${string}`> = {
        DEFAULT_ADMIN: await ctx.publicClient.readContract({ address: indexManager(), abi: indexManagerAbi, functionName: "DEFAULT_ADMIN_ROLE" }),
        ASSET_MANAGER: await ctx.publicClient.readContract({ address: indexManager(), abi: indexManagerAbi, functionName: "ASSET_MANAGER_ROLE" }),
        REBALANCER: await ctx.publicClient.readContract({ address: indexManager(), abi: indexManagerAbi, functionName: "REBALANCER_ROLE" }),
        FEE_COLLECTOR: await ctx.publicClient.readContract({ address: indexManager(), abi: indexManagerAbi, functionName: "FEE_COLLECTOR_ROLE" }),
      };
      for (const role of Object.keys(onChain) as IndexManagerRole[]) {
        expect(IndexManagerCalls.roleHash(role)).toBe(onChain[role]);
      }
    });

    // The keys are derived here, the addresses are read from the deploy: a drift between the two
    // would make every keeper test fail with AccessControlUnauthorizedAccount for the wrong reason.
    it("keeper wallets are the config.rebalancer / config.feeCollector accounts of the deployment file", () => {
      expect(ctx.rebalancer.account.address).toBe(ctx.keepers.rebalancer);
      expect(ctx.feeCollector.account.address).toBe(ctx.keepers.feeCollector);
      expect(isAddressEqual(ctx.keepers.rebalancer, ctx.keepers.feeCollector)).toBe(false);
      expect(isAddressEqual(ctx.keepers.rebalancer, deployer())).toBe(false);
      expect(isAddressEqual(ctx.keepers.feeCollector, deployer())).toBe(false);
    });

    it("hasRoleRead: MultiSig holds all four roles, each keeper only its own, the deployer and a user none", async () => {
      const has = (role: IndexManagerRole, account: Address) =>
        ctx.publicClient.readContract(IndexManagerCalls.hasRoleRead({ indexManager: indexManager(), role, account }));
      const expected: readonly (readonly [string, Address, readonly IndexManagerRole[]])[] = [
        ["MultiSig", ctx.addresses.multiSigWallet, ["DEFAULT_ADMIN", "ASSET_MANAGER", "REBALANCER", "FEE_COLLECTOR"]],
        ["rebalancer", ctx.keepers.rebalancer, ["REBALANCER"]],
        ["fee collector", ctx.keepers.feeCollector, ["FEE_COLLECTOR"]],
        ["deployer", deployer(), []],
        ["user", ctx.user.account.address, []],
      ];
      const roles: readonly IndexManagerRole[] = ["DEFAULT_ADMIN", "ASSET_MANAGER", "REBALANCER", "FEE_COLLECTOR"];
      for (const [name, account, held] of expected) {
        for (const role of roles) {
          expect(await has(role, account), `${name} ${role}`).toBe(held.includes(role));
        }
      }
    });

    it("registry reads find the Index in either asset order and reject non-Index addresses", async () => {
      expect(await ctx.publicClient.readContract(IndexManagerCalls.deployedIndexesRead(indexManager()))).toContain(ctx.index);
      expect(await ctx.publicClient.readContract(IndexManagerCalls.initializedIndexesRead(indexManager()))).toContain(ctx.index);
      expect(await ctx.publicClient.readContract(IndexManagerCalls.isIndexInitializedRead(single()))).toBe(true);
      expect(
        await ctx.publicClient.readContract(
          IndexManagerCalls.isIndexInitializedRead({ indexManager: indexManager(), index: ctx.addresses.usdc }),
        ),
      ).toBe(false);
      for (const [assetA, assetB] of [
        [ctx.asset0, ctx.asset1],
        [ctx.asset1, ctx.asset0],
      ] as const) {
        expect(
          await ctx.publicClient.readContract(IndexManagerCalls.indexByAssetsRead({ indexManager: indexManager(), assetA, assetB })),
        ).toBe(ctx.index);
      }
      expect(
        await ctx.publicClient.readContract(
          IndexManagerCalls.indexByAssetsRead({ indexManager: indexManager(), assetA: ctx.asset0, assetB: ctx.addresses.usdc }),
        ),
      ).toBe("0x0000000000000000000000000000000000000000");
    });

    it("empty Index lists are refused before any call", () => {
      const params = { indexManager: indexManager(), indexes: [] };
      expect(() => IndexManagerCalls.rebalanceManyCallParameters(params)).toThrow(EmptyIndexListError);
      expect(() => IndexManagerCalls.collectFeesManyCallParameters(params)).toThrow(EmptyIndexListError);
      expect(() => IndexManagerCalls.executeWeightUpdateManyCallParameters(params)).toThrow(EmptyIndexListError);
    });
  });

  describe("collectFees", () => {
    it("the fee collector (the caller) receives exactly the accrued fees; Index fees reset; no IndexActionFailed", async () => {
      await buyShares(ctx, ctx.user, parseUsdc("40000"), TOLERANCE);
      const fees = (await loadIndex(ctx)).snapshot.totalFees;
      expect(fees).toBeGreaterThan(0n);
      const usdcBefore = await balanceOf(ctx, ctx.addresses.usdc, feeCollector());
      const multiSigBefore = await balanceOf(ctx, ctx.addresses.usdc, ctx.addresses.multiSigWallet);
      const collectedBefore = await ctx.publicClient.readContract({
        address: indexManager(),
        abi: indexManagerAbi,
        functionName: "getTotalFeesCollected",
      });

      const call = IndexManagerCalls.collectFeesCallParameters(single());
      const decoded = decodeFunctionData({ abi: indexManagerAbiOf(ctx), data: call.calldata });
      expect(decoded.functionName).toBe("collectFeesFromSingleIndex");
      expect(decoded.args).toEqual([ctx.index]);
      expect(call.to).toBe(indexManager());
      expect(call.value).toBe(0n);

      const receipt = await send(ctx, ctx.feeCollector, call);
      expect(parseIndexActionFailure(receipt.logs, single())).toBeUndefined();
      const triggered = indexActionsTriggered(receipt.logs, indexManager());
      expect(triggered.map((log) => log.action)).toEqual(["COLLECT_FEES"]);
      expect(isAddressEqual(triggered[0]?.caller ?? ctx.index, feeCollector())).toBe(true);
      expect(await balanceOf(ctx, ctx.addresses.usdc, feeCollector())).toBe(usdcBefore + fees);
      // The fallback holder of FEE_COLLECTOR_ROLE gets nothing when the keeper collects.
      expect(await balanceOf(ctx, ctx.addresses.usdc, ctx.addresses.multiSigWallet)).toBe(multiSigBefore);
      expect((await loadIndex(ctx)).snapshot.totalFees).toBe(0n);
      expect(
        await ctx.publicClient.readContract({ address: indexManager(), abi: indexManagerAbi, functionName: "getTotalFeesCollected" }),
      ).toBe(collectedBefore + fees);
    });

    it("nothing to collect: the tx succeeds and parseIndexActionFailure reports Index__NoFeesToCollect", async () => {
      await buyShares(ctx, ctx.user, parseUsdc("100"), TOLERANCE);
      await send(ctx, ctx.feeCollector, IndexManagerCalls.collectFeesCallParameters(single()));
      const receipt = await send(
        ctx,
        ctx.feeCollector,
        IndexManagerCalls.collectFeesManyCallParameters({ indexManager: indexManager(), indexes: [ctx.index] }),
      );
      const failure = parseIndexActionFailure(receipt.logs, single());
      expect(failure).toBeDefined();
      expect(failure?.action).toBe("COLLECT_FEES");
      expect(failure?.errorName).toBe("Index__NoFeesToCollect");
      expect(isAddressEqual(failure?.caller ?? ctx.index, feeCollector())).toBe(true);
      expect(isAddressEqual(failure?.index ?? ctx.addresses.usdc, ctx.index)).toBe(true);
    });

    it("wrong emitter ignored: the same IndexActionFailed is not accepted from another address or for another Index", async () => {
      const receipt = await send(ctx, ctx.rebalancer, IndexManagerCalls.rebalanceCallParameters(single()));
      expect(parseIndexActionFailure(receipt.logs, single())).toBeDefined();
      expect(parseIndexActionFailure(receipt.logs, { indexManager: ctx.index, index: ctx.index })).toBeUndefined();
      expect(parseIndexActionFailure(receipt.logs, { indexManager: indexManager(), index: ctx.addresses.usdc })).toBeUndefined();
      const spoofed = receipt.logs.map((log) => ({ ...log, address: ctx.addresses.router }));
      expect(parseIndexActionFailure(spoofed, single())).toBeUndefined();
    });

    // The rebalancer is a keeper too, but fees must only ever reach the FEE_COLLECTOR_ROLE holders.
    it("accounts without FEE_COLLECTOR_ROLE (user, deployer, rebalancer) are rejected with AccessControlUnauthorizedAccount", async () => {
      for (const account of [ctx.user.account.address, deployer(), ctx.keepers.rebalancer]) {
        for (const call of [
          IndexManagerCalls.collectFeesCallParameters(single()),
          IndexManagerCalls.collectFeesManyCallParameters({ indexManager: indexManager(), indexes: [ctx.index] }),
        ]) {
          await expectUnauthorized(account, call, "FEE_COLLECTOR");
        }
      }
    });
  });

  describe("rebalance", () => {
    it("balanced Index: needsRebalance() is false and the IndexManager reports Index__RebalanceNotNeeded", async () => {
      expect((await loadIndex(ctx)).needsRebalance()).toBe(false);
      for (const call of [
        IndexManagerCalls.rebalanceCallParameters(single()),
        IndexManagerCalls.rebalanceManyCallParameters({ indexManager: indexManager(), indexes: [ctx.index] }),
      ]) {
        const receipt = await send(ctx, ctx.rebalancer, call);
        const failure = parseIndexActionFailure(receipt.logs, single());
        expect(failure?.action).toBe("REBALANCE");
        expect(failure?.errorName).toBe("Index__RebalanceNotNeeded");
        expect(isAddressEqual(failure?.caller ?? ctx.index, rebalancer())).toBe(true);
      }
    });

    it.runIf(ctx.isMock)("price moved past the threshold: needsRebalance() agrees with the contract and the rebalance restores the weights", async () => {
      await moveMockPrice(ctx, ctx.asset0, 120n, 100n);
      const before = await loadIndex(ctx);
      expect(before.needsRebalance()).toBe(true);

      const receipt = await send(ctx, ctx.rebalancer, IndexManagerCalls.rebalanceCallParameters(single()));
      expect(parseIndexActionFailure(receipt.logs, single())).toBeUndefined();
      const after = await loadIndex(ctx);
      expect(after.snapshot.reserve0).toBeLessThan(before.snapshot.reserve0);
      expect(after.snapshot.reserve1).toBeGreaterThan(before.snapshot.reserve1);
      expect(after.needsRebalance()).toBe(false);
      const drift = after.getValuation().effectiveWeight0 - after.snapshot.weight0;
      expect(drift < 0n ? -drift : drift).toBeLessThanOrEqual(REBALANCE_THRESHOLD);
      const [effective0] = await ctx.publicClient.readContract(IndexManager.effectiveWeightsRead(ctx.index));
      expect(after.getValuation().effectiveWeight0).toBe(effective0);
    });

    // rebalanceSingleIndex bubbles up an out-of-gas of the Index instead of emitting
    // IndexActionFailed(0x), so the least gas at which the tx succeeds is a gas at which the
    // rebalance runs: the keeper flow of sdk.md §6 (no explicit gas) is safe for single actions.
    it.runIf(ctx.isMock)("gas: with the estimated limit (implicit or explicit) the single rebalance really runs", async () => {
      await moveMockPrice(ctx, ctx.asset0, 120n, 100n);
      const before = await loadIndex(ctx);
      expect(before.needsRebalance()).toBe(true);
      const call = IndexManagerCalls.rebalanceCallParameters(single());
      const estimated = await estimateGas(ctx, rebalancer(), call);

      for (const options of [{}, { gas: estimated }]) {
        const id = await snapshot(ctx);
        const receipt = await send(ctx, ctx.rebalancer, call, options);
        expect(receipt.gasUsed).toBeLessThanOrEqual(estimated);
        expect(parseIndexActionFailure(receipt.logs, single())).toBeUndefined();
        const triggered = indexActionsTriggered(receipt.logs, indexManager());
        expect(triggered).toHaveLength(1);
        expect(triggered[0]?.action).toBe("REBALANCE");
        expect(isAddressEqual(triggered[0]?.index ?? ctx.addresses.usdc, ctx.index)).toBe(true);
        expect(isAddressEqual(triggered[0]?.caller ?? ctx.index, rebalancer())).toBe(true);
        const after = await loadIndex(ctx);
        expect(after.snapshot.reserve0).toBeLessThan(before.snapshot.reserve0);
        expect(after.snapshot.reserve1).toBeGreaterThan(before.snapshot.reserve1);
        expect(after.needsRebalance()).toBe(false);
        await revert(ctx, id);
      }
    });

    // Any limit under the estimate must revert (mined with status reverted, no logs, state
    // untouched), never mine a "successful" tx that only says IndexActionFailed(0x).
    it.runIf(ctx.isMock)("gas: below the estimate the single rebalance reverts instead of succeeding without effect", async () => {
      await moveMockPrice(ctx, ctx.asset0, 120n, 100n);
      const before = await loadIndex(ctx);
      const call = IndexManagerCalls.rebalanceCallParameters(single());
      // The caller must hold REBALANCER_ROLE: without it every limit reverts and the test proves nothing.
      const estimated = await estimateGas(ctx, rebalancer(), call);

      for (const step of UNDER_ESTIMATE_STEPS) {
        const gas = estimated - step;
        await expect(
          ctx.publicClient.call({ account: rebalancer(), to: call.to, data: call.calldata, gas }),
        ).rejects.toThrow();
        const receipt = await sendUnchecked(ctx, ctx.rebalancer, call, { gas });
        expect(receipt.status, `gas ${gas} (estimate - ${step})`).toBe("reverted");
        expect(receipt.logs).toHaveLength(0);
        const after = await loadIndex(ctx);
        expect(after.snapshot.reserve0).toBe(before.snapshot.reserve0);
        expect(after.snapshot.reserve1).toBe(before.snapshot.reserve1);
      }
    });

    it("accounts without REBALANCER_ROLE (user, deployer, fee collector) are rejected with AccessControlUnauthorizedAccount", async () => {
      for (const account of [ctx.user.account.address, deployer(), feeCollector()]) {
        for (const call of [
          IndexManagerCalls.rebalanceCallParameters(single()),
          IndexManagerCalls.rebalanceManyCallParameters({ indexManager: indexManager(), indexes: [ctx.index] }),
        ]) {
          await expectUnauthorized(account, call, "REBALANCER");
        }
      }
    });
  });

  describe("weights (propose/cancel: ASSET_MANAGER = MultiSig; execute: REBALANCER = keeper, MultiSig as fallback)", () => {
    it("proposeNewWeights through the MultiSig: pending weights and timelock read back with toPendingWeightUpdate", async () => {
      expect(await pending()).toBeUndefined();
      const call = IndexManagerCalls.proposeNewWeightsCallParameters({ ...single(), newWeight0: NEW_WEIGHT0 });
      const decoded = decodeFunctionData({ abi: indexManagerAbiOf(ctx), data: call.calldata });
      expect(decoded.functionName).toBe("proposeNewWeights");
      expect(decoded.args).toEqual([ctx.index, NEW_WEIGHT0]);

      const receipt = await sendThroughMultiSig(ctx, call);
      const minedAt = (await ctx.publicClient.getBlock({ blockNumber: receipt.blockNumber })).timestamp;
      expect(await pending()).toEqual({
        weight0: NEW_WEIGHT0,
        weight1: MAX_WEIGHT - NEW_WEIGHT0,
        executableAt: minedAt + WEIGHT_UPDATE_DELAY,
      });
    });

    it("cancelWeightUpdate clears the proposal", async () => {
      const multiSig = await impersonateMultiSig(ctx);
      await send(ctx, multiSig, IndexManagerCalls.proposeNewWeightsCallParameters({ ...single(), newWeight0: NEW_WEIGHT0 }));
      expect(await pending()).toBeDefined();
      await send(ctx, multiSig, IndexManagerCalls.cancelWeightUpdateCallParameters(single()));
      expect(await pending()).toBeUndefined();
    });

    it("executeWeightUpdate before the delay: IndexActionFailed with Index__NotPendingWeightUpdate, weights unchanged", async () => {
      const multiSig = await impersonateMultiSig(ctx);
      await send(ctx, multiSig, IndexManagerCalls.proposeNewWeightsCallParameters({ ...single(), newWeight0: NEW_WEIGHT0 }));
      const receipt = await send(ctx, ctx.rebalancer, IndexManagerCalls.executeWeightUpdateCallParameters(single()));
      const failure = parseIndexActionFailure(receipt.logs, single());
      expect(failure?.action).toBe("EXECUTE_WEIGHTS");
      expect(failure?.errorName).toBe("Index__NotPendingWeightUpdate");
      expect(isAddressEqual(failure?.caller ?? ctx.index, rebalancer())).toBe(true);
      expect((await loadIndex(ctx)).snapshot.weight0).toBe(500_000n);
    });

    /**
     * Proposes NEW_WEIGHT0 as the MultiSig (ASSET_MANAGER) and moves chain time past the delay; the
     * execution is left to the caller (the rebalancer keeper, or the MultiSig fallback). The warp makes every
     * feed stale (maxDelay is far below two days): on mocks they are refreshed so the rebalance inside
     * executeWeightUpdate can price the assets; the mainnet feeds cannot be, see the tests below.
     */
    async function proposeAndWait(): Promise<void> {
      const multiSig = await impersonateMultiSig(ctx);
      await send(ctx, multiSig, IndexManagerCalls.proposeNewWeightsCallParameters({ ...single(), newWeight0: NEW_WEIGHT0 }));
      const proposal = await pending();
      const now = await chainNow(ctx);
      await ctx.testClient.increaseTime({ seconds: Number((proposal?.executableAt ?? now) - now + 1n) });
      await ctx.testClient.mine({ blocks: 1 });
      if (ctx.isMock) await refreshMockFeeds(ctx);
    }

    it("executeWeightUpdate after the delay (chain time, not the local clock) applies the new weights", async () => {
      await proposeAndWait();
      // Batch entry point: KEEPER_GAS_LIMIT is still required, see its comment.
      const receipt = await send(
        ctx,
        ctx.rebalancer,
        IndexManagerCalls.executeWeightUpdateManyCallParameters({ indexManager: indexManager(), indexes: [ctx.index] }),
        { gas: KEEPER_GAS_LIMIT },
      );
      expect(parseIndexActionFailure(receipt.logs, single())).toBeUndefined();
      const [weight0, weight1] = await ctx.publicClient.readContract(IndexManager.snapshotReads(ctx.index)[4]);
      expect([weight0, weight1]).toEqual([NEW_WEIGHT0, MAX_WEIGHT - NEW_WEIGHT0]);
      expect(await pending()).toBeUndefined();
      if (ctx.isMock) {
        expect(weightsRebalanceFailures(receipt.logs, ctx.index)).toEqual([]);
        expect((await loadIndex(ctx)).needsRebalance()).toBe(false);
      }
    });

    it("gas: the single executeWeightUpdate with the estimated limit applies the weights and the IndexManager reports it", async () => {
      await proposeAndWait();
      const receipt = await send(ctx, ctx.rebalancer, IndexManagerCalls.executeWeightUpdateCallParameters(single()));
      expect(parseIndexActionFailure(receipt.logs, single())).toBeUndefined();
      const triggered = indexActionsTriggered(receipt.logs, indexManager());
      expect(triggered.map((log) => log.action)).toEqual(["EXECUTE_WEIGHTS"]);
      expect(isAddressEqual(triggered[0]?.caller ?? ctx.index, rebalancer())).toBe(true);
      const [weight0, weight1] = await ctx.publicClient.readContract(IndexManager.snapshotReads(ctx.index)[4]);
      expect([weight0, weight1]).toEqual([NEW_WEIGHT0, MAX_WEIGHT - NEW_WEIGHT0]);
      expect(await pending()).toBeUndefined();
    });

    // REBALANCER_ROLE is also held by the MultiSig, so the owners can still apply a weight change when
    // the keeper is down. Run through the real 2-of-3 flow: msg.sender at the IndexManager is the MultiSig.
    it("fallback path: the MultiSig (REBALANCER_ROLE fallback holder) executes the weight update through submit/confirm/execute", async () => {
      await proposeAndWait();
      const receipt = await sendThroughMultiSig(ctx, IndexManagerCalls.executeWeightUpdateCallParameters(single()));
      expect(parseIndexActionFailure(receipt.logs, single())).toBeUndefined();
      const triggered = indexActionsTriggered(receipt.logs, indexManager());
      expect(triggered.map((log) => log.action)).toEqual(["EXECUTE_WEIGHTS"]);
      expect(isAddressEqual(triggered[0]?.caller ?? ctx.index, ctx.addresses.multiSigWallet)).toBe(true);
      const [weight0, weight1] = await ctx.publicClient.readContract(IndexManager.snapshotReads(ctx.index)[4]);
      expect([weight0, weight1]).toEqual([NEW_WEIGHT0, MAX_WEIGHT - NEW_WEIGHT0]);
      expect(await pending()).toBeUndefined();
    });

    // After the delay, so the only reason left to refuse the call is the role. Before 2026-11-14 the
    // call required ASSET_MANAGER_ROLE; the fee collector is a keeper too, but not this one. The mined
    // tx proves the refusal is a revert, not an IndexActionFailed that would leave a success receipt.
    it("accounts without REBALANCER_ROLE (user, deployer, fee collector) cannot execute a ready weight update; the proposal stays pending", async () => {
      await proposeAndWait();
      const proposal = await pending();
      expect(proposal).toBeDefined();
      for (const account of [ctx.user.account.address, deployer(), feeCollector()]) {
        for (const call of [
          IndexManagerCalls.executeWeightUpdateCallParameters(single()),
          IndexManagerCalls.executeWeightUpdateManyCallParameters({ indexManager: indexManager(), indexes: [ctx.index] }),
        ]) {
          await expectUnauthorized(account, call, "REBALANCER");
        }
      }
      const receipt = await sendUnchecked(ctx, ctx.user, IndexManagerCalls.executeWeightUpdateCallParameters(single()), {
        gas: KEEPER_GAS_LIMIT,
      });
      expect(receipt.status).toBe("reverted");
      expect(await pending()).toEqual(proposal);
    });

    // The weight change moves the target by 10%, past REBALANCE_THRESHOLD, so the Index rebalances
    // inside executeWeightUpdate. A common error of that inner rebalance (out of gas included) now
    // reverts the whole update, so the least gas at which the tx succeeds is a gas at which the
    // rebalance runs: the keeper flow of sdk.md §6 (no explicit gas) applies weights and rebalance.
    // Both the implicit estimate (no gas) and the same estimate passed explicitly, so a keeper that
    // pins the estimated limit gets the same outcome.
    it.runIf(ctx.isMock)("gas: the rebalance inside an estimated single executeWeightUpdate is not starved of gas", async () => {
      await proposeAndWait();
      const call = IndexManagerCalls.executeWeightUpdateCallParameters(single());
      const estimated = await estimateGas(ctx, rebalancer(), call);

      for (const options of [{}, { gas: estimated }]) {
        const id = await snapshot(ctx);
        const receipt = await send(ctx, ctx.rebalancer, call, options);
        expect(receipt.gasUsed).toBeLessThanOrEqual(estimated);
        expect(parseIndexActionFailure(receipt.logs, single())).toBeUndefined();
        expect(indexActionsTriggered(receipt.logs, indexManager()).map((log) => log.action)).toEqual(["EXECUTE_WEIGHTS"]);
        expect(weightsRebalanceFailures(receipt.logs, ctx.index)).toEqual([]);
        const after = await loadIndex(ctx);
        expect([after.snapshot.weight0, after.snapshot.weight1]).toEqual([NEW_WEIGHT0, MAX_WEIGHT - NEW_WEIGHT0]);
        expect(after.needsRebalance()).toBe(false);
        expect(await pending()).toBeUndefined();
        await revert(ctx, id);
      }
    });

    // Any limit under the estimate must revert as a whole (mined with status reverted, no logs),
    // never apply the weights with a starved rebalance nor consume the proposal.
    it("gas: below the estimate the single executeWeightUpdate reverts and the proposal stays pending", async () => {
      await proposeAndWait();
      const proposal = await pending();
      expect(proposal).toBeDefined();
      // Raw Index reads, no prices: after the warp the mainnet feeds are stale and loadIndex would revert.
      const [, , , reservesRead, weightsRead] = IndexManager.snapshotReads(ctx.index);
      const indexState = async () => ({
        reserves: await ctx.publicClient.readContract(reservesRead),
        weights: await ctx.publicClient.readContract(weightsRead),
      });
      const before = await indexState();
      const call = IndexManagerCalls.executeWeightUpdateCallParameters(single());
      // The caller must hold REBALANCER_ROLE: without it every limit reverts and the test proves nothing.
      const estimated = await estimateGas(ctx, rebalancer(), call);

      for (const step of UNDER_ESTIMATE_STEPS) {
        const gas = estimated - step;
        const receipt = await sendUnchecked(ctx, ctx.rebalancer, call, { gas });
        expect(receipt.status, `gas ${gas} (estimate - ${step})`).toBe("reverted");
        expect(receipt.logs).toHaveLength(0);
        expect(await pending()).toEqual(proposal);
        expect(await indexState()).toEqual(before);
      }
    });

    it("invalid weights: SDK refuses MIN_WEIGHT and MAX_WEIGHT; the current weight passes the SDK and the Index rejects it", async () => {
      for (const newWeight0 of [MIN_WEIGHT, MAX_WEIGHT, 0n]) {
        expect(() => IndexManagerCalls.proposeNewWeightsCallParameters({ ...single(), newWeight0 })).toThrow(InvalidWeightError);
      }
      const current = (await loadIndex(ctx)).snapshot.weight0;
      const error = await simulateError(
        ctx,
        ctx.addresses.multiSigWallet,
        IndexManagerCalls.proposeNewWeightsCallParameters({ ...single(), newWeight0: current }),
        indexManagerAbiOf(ctx),
        "proposeNewWeights",
      );
      expect((error as ContractRevertError).errorName).toBe("Index__InvalidWeight");
    });

    // The keepers hold the roles that execute a weight change, never the one that chooses it.
    it("accounts without ASSET_MANAGER_ROLE (deployer, rebalancer, fee collector) cannot propose or cancel", async () => {
      const multiSig = await impersonateMultiSig(ctx);
      await send(ctx, multiSig, IndexManagerCalls.proposeNewWeightsCallParameters({ ...single(), newWeight0: NEW_WEIGHT0 }));
      for (const account of [deployer(), rebalancer(), feeCollector()]) {
        for (const call of [
          IndexManagerCalls.proposeNewWeightsCallParameters({ ...single(), newWeight0: NEW_WEIGHT0 + 1n }),
          IndexManagerCalls.cancelWeightUpdateCallParameters(single()),
        ]) {
          await expectUnauthorized(account, call, "ASSET_MANAGER");
        }
      }
    });
  });

  // checkInitialized mirrors the areIndexesInitialized modifier on the list read from the chain: the SDK and the
  // contract must reject the same first address. The batch is simulated as the rebalancer keeper, because
  // REBALANCER_ROLE is checked before the list and any other caller would only see AccessControlUnauthorizedAccount.
  describe("checkInitialized agrees with IndexManager__NotIndexInitialized", () => {
    const outsider = getAddress(keccak256(stringToHex("oam-sdk-fork-test:not-an-index")).slice(0, 42));

    async function initializedIndexes() {
      return ctx.publicClient.readContract(IndexManagerCalls.initializedIndexesRead(indexManager()));
    }

    async function batchError(indexes: readonly Address[]) {
      const error = await simulateError(
        ctx,
        rebalancer(),
        IndexManagerCalls.rebalanceManyCallParameters({ indexManager: indexManager(), indexes }),
        indexManagerAbiOf(ctx),
        "rebalanceMany",
      );
      expect(error).toBeInstanceOf(ContractRevertError);
      return error as ContractRevertError;
    }

    function sdkError(indexes: readonly Address[], initialized: readonly Address[]): IndexNotInitializedError {
      try {
        IndexManagerCalls.checkInitialized({ indexes, initializedIndexes: initialized });
      } catch (err) {
        expect(err).toBeInstanceOf(IndexNotInitializedError);
        return err as IndexNotInitializedError;
      }
      return expect.fail("checkInitialized passed, expected IndexNotInitializedError");
    }

    it("the deployed Index passes: it is in initializedIndexesRead", async () => {
      expect(await ctx.publicClient.readContract(IndexManagerCalls.hasRoleRead({ indexManager: indexManager(), role: "REBALANCER", account: rebalancer() }))).toBe(true);
      const initialized = await initializedIndexes();
      expect(() => IndexManagerCalls.checkInitialized({ indexes: [ctx.index], initializedIndexes: initialized })).not.toThrow();
      expect(() =>
        IndexManagerCalls.checkInitialized({ indexes: [ctx.index.toLowerCase() as Address], initializedIndexes: initialized }),
      ).not.toThrow();
    });

    it("an address that is not an Index: SDK and contract both report it", async () => {
      const indexes = [ctx.index, outsider];
      const error = sdkError(indexes, await initializedIndexes());
      expect(error.index).toBe(outsider);
      const revert = await batchError(indexes);
      expect(revert.errorName).toBe("IndexManager__NotIndexInitialized");
      expect(revert.args).toEqual([error.index]);
    });

    it("a deployed but not initialized Index: SDK and contract both report it, first in order", async () => {
      const uninitialized = await createUninitializedIndex(ctx);
      expect(await ctx.publicClient.readContract(IndexManagerCalls.deployedIndexesRead(indexManager()))).toContain(uninitialized);
      const initialized = await initializedIndexes();
      expect(initialized).not.toContain(uninitialized);

      const indexes = [ctx.index, uninitialized, outsider];
      const error = sdkError(indexes, initialized);
      expect(error.index).toBe(uninitialized);
      const revert = await batchError(indexes);
      expect(revert.errorName).toBe("IndexManager__NotIndexInitialized");
      expect(revert.args).toEqual([error.index]);
    });
  });
}
