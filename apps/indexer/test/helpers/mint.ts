// A real mint on plain anvil (31337), built with @oam/sdk: Router.buyExactUsdcAmountOfShares, as a user does it.
// On 31337 tokens, feeds and the Universal Router are mocks, so prepareMint first refreshes the feeds (they go stale
// after 1h15m of chain time, and --load-state moves the clock to now) and gives the mock router rates and liquidity,
// as packages/sdk/test/helpers/chain.ts does. Every transaction mines a block (anvil automine).
import { indexManagerAbi, protocolAddresses } from "@oam/abi";
import { Erc20Manager, IndexManager, IndexManagerCalls, PriceFeedReads, RouterManager, anvil, type MethodParameters } from "@oam/sdk";
import {
  createPublicClient,
  createTestClient,
  createWalletClient,
  encodeFunctionData,
  erc20Abi,
  http,
  keccak256,
  parseAbi,
  stringToHex,
  type Address,
  type TransactionReceipt,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ANVIL_CHAIN_ID } from "./anvil.js";

// Anvil dev key 0, the deployer: owner of nothing in the protocol, it only signs the calls to the mocks.
// Public test value, not a secret.
const DEPLOYER_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
/** The buyer of the tests: a key derived from a label, so it holds nothing from the deploy. */
const BUYER_KEY = keccak256(stringToHex("oam-indexer-live-test:buyer"));
/** Slippage tolerance of the buy, in the Router's scale (the SDK tests use the same value). */
const TOLERANCE = 30_000n;
const RATE_PRECISION = 10n ** 18n;

const mintableAbi = parseAbi(["function mint(address to, uint256 amount)"]);
const mockFeedAbi = parseAbi(["function latestAnswer() view returns (int256)", "function updateAnswer(int256 answer)"]);
const mockUniversalRouterAbi = parseAbi(["function setExchangeRate(address tokenIn, address tokenOut, uint256 rate)"]);

export type Minter = {
  publicClient: ReturnType<typeof createPublicClient>;
  testClient: ReturnType<typeof createTestClient>;
  /** The Index that receives the mints: the first initialized one of the IndexManager. */
  index: Address;
  /** Funds the buyer with `usdcAmount`, approves the Index and buys: 3 transactions, 3 blocks. Returns the buy's receipt. */
  mint: (usdcAmount: bigint) => Promise<TransactionReceipt>;
};

/**
 * Clients, the Index and the mocks set up for a buy. Take the evm_snapshot before calling it: its transactions are test state.
 * @param rpcUrl The anvil of the tests (TEST_RPC_URL).
 */
export async function prepareMint(rpcUrl: string): Promise<Minter> {
  const transport = http(rpcUrl, { retryCount: 0 });
  // cacheTime 0: evm_revert rewinds the chain, a cached block number would point past the head.
  const publicClient = createPublicClient({ chain: anvil, transport, cacheTime: 0 });
  const testClient = createTestClient({ chain: anvil, mode: "anvil", transport });
  const deployer = createWalletClient({ chain: anvil, transport, account: privateKeyToAccount(DEPLOYER_KEY) });
  const buyer = createWalletClient({ chain: anvil, transport, account: privateKeyToAccount(BUYER_KEY) });
  const { indexManager, router, priceFeedManager, usdc } = protocolAddresses[ANVIL_CHAIN_ID];

  async function send(wallet: typeof deployer, call: MethodParameters): Promise<TransactionReceipt> {
    const hash = await wallet.sendTransaction({ to: call.to, data: call.calldata, value: call.value, chain: anvil, account: wallet.account });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== "success") throw new Error(`transaction to ${call.to} reverted (${hash})`);
    return receipt;
  }
  const mintMock = (token: Address, to: Address, amount: bigint) =>
    send(deployer, { to: token, calldata: encodeFunctionData({ abi: mintableAbi, functionName: "mint", args: [to, amount] }), value: 0n });

  const first = (await publicClient.readContract(IndexManagerCalls.initializedIndexesRead(indexManager)))[0];
  if (first === undefined) throw new Error("no initialized Index on anvil: run make snapshot or make dev");
  // A typed const: the narrowing of `first` does not reach the closures below.
  const index: Address = first;
  const reads = IndexManager.snapshotReads(index);
  const [asset0, asset1, universalRouter] = await Promise.all([
    publicClient.readContract(reads[0]),
    publicClient.readContract(reads[1]),
    publicClient.readContract({ address: indexManager, abi: indexManagerAbi, functionName: "getUniswapUniversalRouter" }),
  ]);
  await testClient.setBalance({ address: buyer.account.address, value: 10n ** 20n });

  // Feeds: the same answer with a fresh timestamp.
  const tokens = [usdc, asset0, asset1];
  for (const asset of tokens) {
    const { feed } = await publicClient.readContract(PriceFeedReads.feedConfigRead({ priceFeedManager, asset }));
    const answer = await publicClient.readContract({ address: feed, abi: mockFeedAbi, functionName: "latestAnswer" });
    await send(deployer, { to: feed, calldata: encodeFunctionData({ abi: mockFeedAbi, functionName: "updateAnswer", args: [answer] }), value: 0n });
  }

  // Mock router: rates from the PriceFeedManager prices, and liquidity of every token.
  const info = await Promise.all(
    tokens.map(async (token) => ({
      token,
      decimals: await publicClient.readContract({ address: token, abi: erc20Abi, functionName: "decimals" }),
      price: await publicClient.readContract(PriceFeedReads.priceRead({ priceFeedManager, asset: token })),
    })),
  );
  for (const tokenIn of info) {
    for (const tokenOut of info) {
      if (tokenIn.token === tokenOut.token) continue;
      const rate = (tokenIn.price * 10n ** BigInt(tokenOut.decimals) * RATE_PRECISION) / (tokenOut.price * 10n ** BigInt(tokenIn.decimals));
      await send(deployer, {
        to: universalRouter,
        calldata: encodeFunctionData({ abi: mockUniversalRouterAbi, functionName: "setExchangeRate", args: [tokenIn.token, tokenOut.token, rate] }),
        value: 0n,
      });
    }
    const liquidity = 10n ** BigInt(tokenIn.decimals + 12);
    const balance = await publicClient.readContract(Erc20Manager.balanceOfRead({ token: tokenIn.token, owner: universalRouter }));
    if (balance < liquidity) await mintMock(tokenIn.token, universalRouter, liquidity - balance);
  }

  async function mint(usdcAmount: bigint): Promise<TransactionReceipt> {
    await mintMock(usdc, buyer.account.address, usdcAmount);
    await send(buyer, Erc20Manager.approveCallParameters({ token: usdc, spender: index, amount: usdcAmount }));
    return send(buyer, RouterManager.buyCallParameters({ router, index, usdcAmount, tolerance: TOLERANCE }));
  }

  return { publicClient, testClient, index, mint };
}
