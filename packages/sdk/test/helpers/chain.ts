// Fork-test helpers: viem clients against a running anvil (31337 with mocks, 31338 mainnet fork),
// chain detection, state isolation, funding and the reads the tests repeat. No wagmi.
import { indexManagerAbi, multiSigWalletAbi } from "@oam/abi";
import {
  createPublicClient,
  createTestClient,
  createWalletClient,
  decodeFunctionData,
  encodeAbiParameters,
  encodeFunctionData,
  erc20Abi,
  http,
  isAddressEqual,
  keccak256,
  numberToHex,
  pad,
  parseAbi,
  parseEventLogs,
  stringToHex,
  type Abi,
  type Address,
  type Chain,
  type Hex,
  type Log,
  type TransactionReceipt,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { expect } from "vitest";
import {
  ANVIL_CHAIN_ID,
  Erc20Manager,
  INDEX_ACTIONS,
  Index,
  IndexManager,
  IndexManagerCalls,
  MAINNET_FORK_CHAIN_ID,
  PriceFeedReads,
  RouterManager,
  anvil,
  getProtocolAddresses,
  mainnetFork,
  toSdkError,
  type IndexPrices,
  type IndexSnapshotResults,
  type MethodParameters,
  type ProtocolAddresses,
  type SdkError,
  type SupportedChainId,
} from "../../src/index.js";

export const RPC_URL = process.env.SDK_FORK_RPC_URL ?? "http://127.0.0.1:8545";

/** Block pinned by `make anvil-fork` (FORK_BLOCK in the Makefile, MAINNET_FORK_BLOCK in ForkConstants.sol). */
export const MAINNET_FORK_BLOCK = 26_178_000n;

/** Mainnet Multicall3: present on the fork only, plain anvil has no Multicall3. */
export const MULTICALL3 = "0xcA11bde05977b3631167028862bE2a173976CA11" as const;

// Well-known anvil dev keys (public test values, not secrets): 0 = deployer (FEE_COLLECTOR and
// REBALANCER after DeployPeriphery), 1 and 2 = MultiSig owners. The buyers use keys derived from a
// label instead: on mainnet every anvil dev account carries an EIP-7702 delegation (0xef0100…) at
// the pinned block, so USDC verifies their permits through ERC-1271 and rejects ECDSA signatures.
const KEYS = {
  deployer: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  owner1: "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  owner2: "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  user: keccak256(stringToHex("oam-sdk-fork-test:user")),
  other: keccak256(stringToHex("oam-sdk-fork-test:other")),
} as const satisfies Record<string, Hex>;

// Test mocks deployed by HelperConfig on 31337; not part of @oam/abi because they are not protocol contracts.
const mintableAbi = parseAbi(["function mint(address to, uint256 amount)"]);
export const mockFeedAbi = parseAbi([
  "function latestAnswer() view returns (int256)",
  "function decimals() view returns (uint8)",
  "function updateAnswer(int256 answer)",
  "function updateRoundData(uint80 roundId, int256 answer, uint256 timestamp, uint256 startedAt)",
]);
export const mockUniversalRouterAbi = parseAbi([
  "function setExchangeRate(address tokenIn, address tokenOut, uint256 rate)",
  "function setEnforceMinAmountOut(bool enforce)",
  "function exchangeRates(address tokenIn, address tokenOut) view returns (uint256)",
]);

const RATE_PRECISION = 10n ** 18n;

function makeClients(chain: Chain) {
  const transport = http(RPC_URL, { retryCount: 0 });
  // cacheTime 0: evm_revert rewinds the chain, a cached block number would point past the head.
  const publicClient = createPublicClient({ chain, transport, cacheTime: 0 });
  const testClient = createTestClient({ chain, mode: "anvil", transport });
  const wallet = (key: Hex) => createWalletClient({ chain, transport, account: privateKeyToAccount(key) });
  return {
    publicClient,
    testClient,
    deployer: wallet(KEYS.deployer),
    owner1: wallet(KEYS.owner1),
    owner2: wallet(KEYS.owner2),
    user: wallet(KEYS.user),
    other: wallet(KEYS.other),
    /** For addresses unlocked with `anvil_impersonateAccount` (the MultiSig, a contract). */
    impersonated: (address: Address) => createWalletClient({ chain, transport, account: address }),
  };
}

export type Clients = ReturnType<typeof makeClients>;
export type Wallet = Clients["user"];

export type ForkContext = Clients & {
  chainId: SupportedChainId;
  chain: Chain;
  /** True on plain anvil (31337): tokens, feeds and the Universal Router are mocks. */
  isMock: boolean;
  addresses: ProtocolAddresses;
  index: Address;
  asset0: Address;
  asset1: Address;
  universalRouter: Address;
};

/** The chain id of the node at RPC_URL, or undefined when no node answers. */
export async function detectChainId(): Promise<number | undefined> {
  try {
    const probe = createPublicClient({ transport: http(RPC_URL, { retryCount: 0, timeout: 2_000 }) });
    return await probe.getChainId();
  } catch {
    return undefined;
  }
}

/**
 * Builds the context, or returns undefined so the suite can `describe.skipIf` cleanly: no node,
 * an unsupported chain id, or no deployed Index.
 */
export async function setupContext(): Promise<ForkContext | undefined> {
  const chainId = await detectChainId();
  if (chainId !== ANVIL_CHAIN_ID && chainId !== MAINNET_FORK_CHAIN_ID) return undefined;
  const chain = chainId === ANVIL_CHAIN_ID ? anvil : mainnetFork;
  const clients = makeClients(chain);
  const addresses = getProtocolAddresses(chainId);
  const code = await clients.publicClient.getCode({ address: addresses.indexManager });
  if (code === undefined || code === "0x") return undefined;

  // The Index address is not in ProtocolAddresses: the IndexManager registry is the source.
  const initialized = await clients.publicClient.readContract(
    IndexManagerCalls.initializedIndexesRead(addresses.indexManager),
  );
  const index = initialized[0];
  if (index === undefined) return undefined;
  const reads = IndexManager.snapshotReads(index);
  const [asset0, asset1, universalRouter] = await Promise.all([
    clients.publicClient.readContract(reads[0]),
    clients.publicClient.readContract(reads[1]),
    clients.publicClient.readContract({
      address: addresses.indexManager,
      abi: indexManagerAbi,
      functionName: "getUniswapUniversalRouter",
    }),
  ]);

  const ctx: ForkContext = {
    ...clients,
    chainId,
    chain,
    isMock: chainId === ANVIL_CHAIN_ID,
    addresses,
    index,
    asset0,
    asset1,
    universalRouter,
  };
  for (const wallet of [ctx.user, ctx.other]) {
    await ctx.testClient.setBalance({ address: wallet.account.address, value: 10n ** 20n });
  }
  if (ctx.isMock) {
    await refreshMockFeeds(ctx);
    await configureMockUniversalRouter(ctx);
  }
  return ctx;
}

export async function snapshot(ctx: ForkContext): Promise<Hex> {
  return ctx.testClient.snapshot();
}

export async function revert(ctx: ForkContext, id: Hex): Promise<void> {
  await ctx.testClient.revert({ id });
}

/** Chain time of the latest block, the `nowSeconds` the SDK expects (never the local clock). */
export async function chainNow(ctx: ForkContext): Promise<bigint> {
  return (await ctx.publicClient.getBlock({ blockTag: "latest" })).timestamp;
}

type AnyWallet = Wallet | ReturnType<Clients["impersonated"]>;

/**
 * Sends a manager's MethodParameters and returns the receipt whatever its status, for the tests
 * that expect a mined revert. With an explicit `gas` viem skips eth_estimateGas, so a limit below
 * the estimate reaches the chain instead of failing at estimation.
 */
export async function sendUnchecked(ctx: ForkContext, wallet: AnyWallet, call: MethodParameters, options: { gas?: bigint } = {}) {
  const hash = await wallet.sendTransaction({
    to: call.to,
    data: call.calldata,
    value: call.value,
    chain: ctx.chain,
    account: wallet.account,
    ...options,
  });
  return ctx.publicClient.waitForTransactionReceipt({ hash });
}

/**
 * Sends a manager's MethodParameters and asserts the tx succeeded. Without `gas` the limit comes
 * from eth_estimateGas, as in the keeper flow of sdk.md §6. Where the estimate is not guaranteed
 * to be enough, see KEEPER_GAS_LIMIT in suites/indexManager.ts.
 */
export async function send(ctx: ForkContext, wallet: AnyWallet, call: MethodParameters, options: { gas?: bigint } = {}) {
  const receipt = await sendUnchecked(ctx, wallet, call, options);
  expect(receipt.status).toBe("success");
  return receipt;
}

/** eth_estimateGas for a manager's MethodParameters, the limit a keeper gets when it passes none. */
export async function estimateGas(ctx: ForkContext, from: Address, call: MethodParameters): Promise<bigint> {
  return ctx.publicClient.estimateGas({ account: from, to: call.to, data: call.calldata, value: call.value });
}

/**
 * The IndexActionTriggered logs emitted by `indexManager` itself, with the action as its SDK name.
 * The SDK has no parser for the success event, so the filter on the emitter is done here.
 */
export function indexActionsTriggered(logs: readonly Log[], indexManager: Address) {
  return parseEventLogs({ abi: indexManagerAbi, eventName: "IndexActionTriggered", logs: [...logs] })
    .filter((log) => isAddressEqual(log.address, indexManager))
    .map((log) => ({
      index: log.args.indexAddress,
      caller: log.args.caller,
      action: INDEX_ACTIONS[log.args.action],
    }));
}

/**
 * Simulates a call built by a manager, decoding the calldata back with the manager's ABI, and
 * returns what the client threw passed through `toSdkError`. Fails the test if the call succeeds.
 */
export async function simulateError(
  ctx: ForkContext,
  account: Address,
  call: MethodParameters,
  abi: Abi,
  context: string,
): Promise<SdkError> {
  const { functionName, args } = decodeFunctionData({ abi, data: call.calldata });
  try {
    await ctx.publicClient.simulateContract({
      address: call.to,
      abi,
      functionName,
      args: args ?? [],
      account,
      value: call.value,
    });
  } catch (err) {
    return toSdkError(err, context);
  }
  return expect.fail(`${context}: expected a revert, the simulation succeeded`);
}

/** Same as simulateError for a read descriptor. */
export async function readError(
  ctx: ForkContext,
  read: { address: Address; abi: Abi; functionName: string; args?: readonly unknown[] },
  context: string,
): Promise<SdkError> {
  try {
    await ctx.publicClient.readContract(read);
  } catch (err) {
    return toSdkError(err, context);
  }
  return expect.fail(`${context}: expected a revert, the read succeeded`);
}

/** The Router ABI with every protocol error, taken from a descriptor because the fragment is internal. */
export function routerAbiOf(ctx: ForkContext): Abi {
  return RouterManager.maxToleranceRead(ctx.addresses.router).abi;
}

export function indexManagerAbiOf(ctx: ForkContext): Abi {
  return IndexManagerCalls.deployedIndexesRead(ctx.addresses.indexManager).abi;
}

// ─── Funding ──────────────────────────────────────────────────────────────────

const balanceSlots = new Map<Address, bigint>();

/**
 * Gives `account` exactly `amount` of `token`. Mocks have a public mint; on the fork the balance
 * slot is found by probing (like forge-std stdStorage) and written with anvil_setStorageAt, so no
 * swap moves the pools away from Chainlink.
 */
export async function dealErc20(ctx: ForkContext, token: Address, account: Address, amount: bigint): Promise<void> {
  const balance = await ctx.publicClient.readContract(Erc20Manager.balanceOfRead({ token, owner: account }));
  if (ctx.isMock) {
    if (amount < balance) return expect.fail("dealErc20 on mocks can only increase a balance");
    if (amount > balance) {
      await send(ctx, ctx.deployer, {
        to: token,
        calldata: encodeFunctionData({ abi: mintableAbi, functionName: "mint", args: [account, amount - balance] }),
        value: 0n,
      });
    }
    return;
  }
  const known = balanceSlots.get(token);
  const candidates = known === undefined ? [...Array(30).keys()].map(BigInt) : [known];
  for (const slot of candidates) {
    const key = keccak256(encodeAbiParameters([{ type: "address" }, { type: "uint256" }], [account, slot]));
    const previous = await ctx.publicClient.getStorageAt({ address: token, slot: key });
    await ctx.testClient.setStorageAt({ address: token, index: key, value: pad(numberToHex(amount)) });
    const after = await ctx.publicClient.readContract(Erc20Manager.balanceOfRead({ token, owner: account }));
    if (after === amount) {
      balanceSlots.set(token, slot);
      return;
    }
    await ctx.testClient.setStorageAt({ address: token, index: key, value: previous ?? pad("0x0") });
  }
  return expect.fail(`dealErc20: balance slot of ${token} not found`);
}

// ─── Mocks (31337 only) ───────────────────────────────────────────────────────

export async function feedOf(ctx: ForkContext, asset: Address): Promise<Address> {
  const config = await ctx.publicClient.readContract(
    PriceFeedReads.feedConfigRead({ priceFeedManager: ctx.addresses.priceFeedManager, asset }),
  );
  return config.feed;
}

/** The mock feeds are timestamped at deploy; the asset feeds go stale after 1h15m of chain time. */
export async function refreshMockFeeds(ctx: ForkContext, extraAssets: readonly Address[] = []): Promise<void> {
  for (const asset of [ctx.asset0, ctx.asset1, ctx.addresses.usdc, ...extraAssets]) {
    const feed = await feedOf(ctx, asset);
    const answer = await ctx.publicClient.readContract({ address: feed, abi: mockFeedAbi, functionName: "latestAnswer" });
    await send(ctx, ctx.deployer, {
      to: feed,
      calldata: encodeFunctionData({ abi: mockFeedAbi, functionName: "updateAnswer", args: [answer] }),
      value: 0n,
    });
  }
}

/** Multiplies the mock price of `asset` by num/den and re-aligns the mock router rates. */
export async function moveMockPrice(ctx: ForkContext, asset: Address, num: bigint, den: bigint): Promise<void> {
  const feed = await feedOf(ctx, asset);
  const answer = await ctx.publicClient.readContract({ address: feed, abi: mockFeedAbi, functionName: "latestAnswer" });
  await send(ctx, ctx.deployer, {
    to: feed,
    calldata: encodeFunctionData({ abi: mockFeedAbi, functionName: "updateAnswer", args: [(answer * num) / den] }),
    value: 0n,
  });
  await configureMockUniversalRouter(ctx);
}

/** Sets an old `updatedAt` on the mock feed of `asset`, so the PriceFeedManager rejects it. */
export async function makeMockFeedStale(ctx: ForkContext, asset: Address, updatedAt: bigint): Promise<Address> {
  const feed = await feedOf(ctx, asset);
  const answer = await ctx.publicClient.readContract({ address: feed, abi: mockFeedAbi, functionName: "latestAnswer" });
  await send(ctx, ctx.deployer, {
    to: feed,
    calldata: encodeFunctionData({
      abi: mockFeedAbi,
      functionName: "updateRoundData",
      args: [1_000n, answer, updatedAt, updatedAt],
    }),
    value: 0n,
  });
  return feed;
}

/**
 * The deploy leaves the mock Universal Router without rates or liquidity, so every swap would
 * revert. Rates follow the PriceFeedManager prices (same decimals handling as the Index), rounded
 * down like a real pool fee would; liquidity is minted straight to the router.
 */
export async function configureMockUniversalRouter(
  ctx: ForkContext,
  haircut = { num: 1n, den: 1n },
  extraTokens: readonly Address[] = [],
): Promise<void> {
  const tokens = [ctx.addresses.usdc, ctx.asset0, ctx.asset1, ...extraTokens];
  const info = await Promise.all(
    tokens.map(async (token) => ({
      token,
      decimals: await ctx.publicClient.readContract({ address: token, abi: erc20Abi, functionName: "decimals" }),
      price: await ctx.publicClient.readContract(
        PriceFeedReads.priceRead({ priceFeedManager: ctx.addresses.priceFeedManager, asset: token }),
      ),
    })),
  );
  for (const tokenIn of info) {
    for (const tokenOut of info) {
      if (tokenIn.token === tokenOut.token) continue;
      const rate =
        (tokenIn.price * 10n ** BigInt(tokenOut.decimals) * RATE_PRECISION * haircut.num) /
        (tokenOut.price * 10n ** BigInt(tokenIn.decimals) * haircut.den);
      await send(ctx, ctx.deployer, {
        to: ctx.universalRouter,
        calldata: encodeFunctionData({
          abi: mockUniversalRouterAbi,
          functionName: "setExchangeRate",
          args: [tokenIn.token, tokenOut.token, rate],
        }),
        value: 0n,
      });
    }
    const liquidity = 10n ** BigInt(tokenIn.decimals + 12);
    const balance = await ctx.publicClient.readContract(
      Erc20Manager.balanceOfRead({ token: tokenIn.token, owner: ctx.universalRouter }),
    );
    if (balance < liquidity) await dealErc20(ctx, tokenIn.token, ctx.universalRouter, liquidity);
  }
}

// ─── Reads ────────────────────────────────────────────────────────────────────

type At = { blockNumber?: bigint };

/** `snapshotReads` through Promise.all of readContract: plain anvil has no Multicall3. */
export async function readSnapshotResults(ctx: ForkContext, at: At = {}): Promise<IndexSnapshotResults> {
  const r = IndexManager.snapshotReads(ctx.index);
  const pc = ctx.publicClient;
  return Promise.all([
    pc.readContract({ ...r[0], ...at }),
    pc.readContract({ ...r[1], ...at }),
    pc.readContract({ ...r[2], ...at }),
    pc.readContract({ ...r[3], ...at }),
    pc.readContract({ ...r[4], ...at }),
    pc.readContract({ ...r[5], ...at }),
    pc.readContract({ ...r[6], ...at }),
    pc.readContract({ ...r[7], ...at }),
  ]);
}

export async function readPrices(ctx: ForkContext, at: At = {}): Promise<IndexPrices> {
  const priceFeedManager = ctx.addresses.priceFeedManager;
  const [priceAsset0, priceAsset1, priceUsdc] = await Promise.all([
    ctx.publicClient.readContract({ ...PriceFeedReads.priceRead({ priceFeedManager, asset: ctx.asset0 }), ...at }),
    ctx.publicClient.readContract({ ...PriceFeedReads.priceRead({ priceFeedManager, asset: ctx.asset1 }), ...at }),
    ctx.publicClient.readContract({
      ...PriceFeedReads.priceRead({ priceFeedManager, asset: ctx.addresses.usdc }),
      ...at,
    }),
  ]);
  return { priceAsset0, priceAsset1, priceUsdc };
}

/** The SDK entity at one block, built exactly as sdk.md §6 describes. */
export async function loadIndex(ctx: ForkContext, at: At = {}): Promise<Index> {
  const [results, prices] = await Promise.all([readSnapshotResults(ctx, at), readPrices(ctx, at)]);
  return Index.fromSnapshot(IndexManager.toSnapshot(ctx.index, results, prices));
}

export async function balanceOf(ctx: ForkContext, token: Address, owner: Address, at: At = {}): Promise<bigint> {
  return ctx.publicClient.readContract({ ...Erc20Manager.balanceOfRead({ token, owner }), ...at });
}

/** Funds `wallet`, approves the Index and buys: the common setup of the sell and fee tests. */
export async function buyShares(
  ctx: ForkContext,
  wallet: Wallet,
  usdcAmount: bigint,
  tolerance: bigint,
  index: Address = ctx.index,
): Promise<TransactionReceipt> {
  const owner = wallet.account.address;
  const current = await balanceOf(ctx, ctx.addresses.usdc, owner);
  await dealErc20(ctx, ctx.addresses.usdc, owner, current + usdcAmount);
  await send(ctx, wallet, Erc20Manager.approveCallParameters({ token: ctx.addresses.usdc, spender: index, amount: usdcAmount }));
  return send(ctx, wallet, RouterManager.buyCallParameters({ router: ctx.addresses.router, index, usdcAmount, tolerance }));
}

// ─── Governance ───────────────────────────────────────────────────────────────

/** Runs a call through the 2-of-3 MultiSig, as the real ASSET_MANAGER does: submit, two confirmations, execute. */
export async function sendThroughMultiSig(ctx: ForkContext, call: MethodParameters): Promise<TransactionReceipt> {
  const multiSig = ctx.addresses.multiSigWallet;
  const txId = await ctx.publicClient.readContract({
    address: multiSig,
    abi: multiSigWalletAbi,
    functionName: "getTransactionCount",
  });
  const step = (wallet: Wallet, data: Hex) => send(ctx, wallet, { to: multiSig, calldata: data, value: 0n });
  await step(
    ctx.owner1,
    encodeFunctionData({ abi: multiSigWalletAbi, functionName: "submitTransaction", args: [call.to, call.value, call.calldata] }),
  );
  await step(ctx.owner1, encodeFunctionData({ abi: multiSigWalletAbi, functionName: "confirmTransaction", args: [txId] }));
  await step(ctx.owner2, encodeFunctionData({ abi: multiSigWalletAbi, functionName: "confirmTransaction", args: [txId] }));
  return step(ctx.owner1, encodeFunctionData({ abi: multiSigWalletAbi, functionName: "executeTransaction", args: [txId] }));
}

/** Unlocks the MultiSig (a contract) for direct calls; the caller reverts the snapshot afterwards. */
export async function impersonateMultiSig(ctx: ForkContext) {
  const multiSig = ctx.addresses.multiSigWallet;
  await ctx.testClient.impersonateAccount({ address: multiSig });
  await ctx.testClient.setBalance({ address: multiSig, value: 10n ** 20n });
  return ctx.impersonated(multiSig);
}

export function describeTitle(ctx: ForkContext | undefined): string {
  if (ctx === undefined) return "no anvil node with a deployment at " + RPC_URL;
  return ctx.isMock ? `anvil ${ctx.chainId} (mocks)` : `mainnet fork ${ctx.chainId} @ ${MAINNET_FORK_BLOCK}`;
}
