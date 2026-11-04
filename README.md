# On-Chain Asset Manager

A non-custodial index fund protocol on Ethereum. You deposit USDC and get ERC20 shares of a two-asset basket (for example WETH/WBTC at 60/40). The protocol prices everything with Chainlink, buys and sells the underlying assets on Uniswap V3 or V4 through the Universal Router, and handles rebalancing, fees and weight changes on-chain.

> ⚠️ **Disclaimer.** I built this project to learn. It has not been audited and is not meant for mainnet. The open findings of the internal security review are listed in [Known limitations](#6-known-limitations).

---

## Table of contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Smart contracts](#3-smart-contracts)
4. [Actors and roles](#4-actors-and-roles)
5. [Cross-cutting design decisions](#5-cross-cutting-design-decisions)
6. [Known limitations](#6-known-limitations)
7. [Mainnet fork environment](#7-mainnet-fork-environment)
8. [Project structure](#8-project-structure)
9. [Clone and configuration](#9-clone-and-configuration)
10. [Testing](#10-testing)
11. [Contributing](#11-contributing)
12. [License](#12-license)
13. [Contacts](#13-contacts)

---

## 1. Overview

Each index holds exactly two ERC20 tokens with target weights. Users only ever touch USDC and the index shares:

- **Buy.** USDC goes in, the protocol fee is taken, the rest is swapped into the two assets and shares are minted at the oracle NAV.
- **Sell.** Shares are burned, the matching value of the assets is swapped back to USDC, the fee is taken and the rest goes to the user.
- **Rebalance.** When the real weight of asset0 drifts more than 3 percentage points from its target, a rebalancer swaps one asset for the other to get back on target.
- **Weight changes.** New target weights wait 2 days before they can be executed, so holders who disagree can leave first.

### Numbers that define the protocol

All of these are constants in `src/ContractCodeConstants.sol` or `src/IndexManager.sol`. Percentages use 4 decimals: `1_000_000` is 100%, `10_000` is 1%.

| Parameter | Value | Where it applies |
|---|---|---|
| Protocol fee | 0.1% to 10%, fixed per index at creation | Taken on the USDC of every mint and every redeem |
| User tolerance | above 0 and below 10% (`100_000`) | Minimum shares on mint, minimum USDC on redeem |
| Target weights | each strictly between 1% and 100%, sum 100% | Creation and weight proposals |
| Rebalance threshold | 3 percentage points on asset0 | `rebalanceIndex` reverts below it |
| Rebalance slippage | 1% of the swapped notional | Router `amountOutMinimum` and post-swap value check |
| Weight update | 2-day delay, then a 3-day execution window | `proposeNewWeights` / `executeSingleWeightUpdate` |
| Price feed replacement | 2-day delay, then a 3-day execution window | `PriceFeedManager` |
| Feed staleness (`maxDelay`) | per feed, at most 2 days | Every price read |
| Proxy upgrades | at least 2 days through the `TimelockController` | SwapManager, PriceFeedManager, Router |
| Admin MultiSig | 2 of 3 | Every admin action |

---

## 2. Architecture

```
 Owner 1   Owner 2   Owner 3
     \        |        /          2-of-3, EIP-712 confirmations
      MultiSigWallet ─────────────────────────────────┐
         │ DEFAULT_ADMIN_ROLE + ASSET_MANAGER_ROLE     │ proposer / executor / canceller
         ▼                                             ▼
   IndexManager (not upgradeable)            TimelockController (min delay 2 days, no admin)
   │  REBALANCER_ROLE, FEE_COLLECTOR_ROLE              │ the only upgrader of the three proxies
   │                                                   │
   ├─ owner of ──► SwapManager proxy ◄─────────────────┤
   ├─ owner of ──► PriceFeedManager proxy ◄────────────┤
   ├─ creates ───► Router proxy ◄──────────────────────┘
   │
   └─ deployIndex ──► IndexFactory ──CREATE2──► Index (ERC20 shares + permit)
                                                 ▲   │ getPrice ──► PriceFeedManager ──► Chainlink
                       user ──► Router ──────────┘   │ build*SwapParams ──► SwapManager
                                                     └─ transfer + execute ──► Universal Router ──► Uniswap V3/V4
```

There are three kinds of contracts, and the split is deliberate:

- **Fixed contracts** (`Index`, `IndexManager`, `IndexFactory`, `MultiSigWallet`). They hold funds or permissions, so their rules never change after deployment.
- **Shared, upgradeable services** (`Router`, `PriceFeedManager`, `SwapManager`). One proxy each, used by every index. They carry the logic that's most likely to need a fix: user input validation, oracle configuration, swap encoding. An upgrade fixes all indexes at once and always waits 2 days in the timelock.
- **Governance** (`MultiSigWallet`, `TimelockController`). Every admin action needs 2 of 3 owners, and every upgrade also needs 2 days of public notice.

### How a deployment comes together

`script/DeployPeriphery.s.sol` runs these steps in order:

1. Deploy the `MultiSigWallet` (3 owners, threshold 2).
2. Deploy the OpenZeppelin `TimelockController` with the MultiSig as the only proposer and executor and no admin.
3. Deploy the `IndexFactory`, passing it `type(Index).creationCode`.
4. Deploy the `IndexManager`. Its constructor creates the three ERC1967 proxies (SwapManager, PriceFeedManager, Router) from fresh implementations, sets itself as owner and the timelock as upgrader.
5. Register the USDC/USD feed while the deployer still holds `ASSET_MANAGER_ROLE`.
6. Grant `DEFAULT_ADMIN_ROLE` and `ASSET_MANAGER_ROLE` to the MultiSig and revoke both from the deployer. The deployer keeps `REBALANCER_ROLE` and `FEE_COLLECTOR_ROLE`.

`script/DeployAndInitNewIndex.s.sol` then goes through the MultiSig (submit, confirm, execute) to register any missing asset feed, call `createIndex` and call `initializeIndex` with the seed deposit.

---

## 3. Smart contracts

Runtime sizes come from `forge build --sizes` (EIP-170 limit: 24,576 bytes).

### 3.1 `Index.sol`: the vault

**What it does.** One `Index` per asset pair. It's an ERC20 (with ERC-2612 permit) whose shares represent a pro-rata claim on two reserves, `s_asset0Reserve` and `s_asset1Reserve`. It holds the tokens, prices them, runs the swaps for mint, redeem and rebalance, and accrues fees in USDC. Runtime size: 17,735 bytes.

| Function | Caller | Effect |
|---|---|---|
| `initialize(depositor, amount0)` | IndexManager | Pulls `amount0` of asset0 and the matching amount of asset1 (computed from the target weights and Chainlink prices) from the depositor. Mints shares equal to the USD value of the seed, with 18 decimals, so 1 share is worth about $1 at launch |
| `mintShares(to, usdcIn, tolerance)` | Router | Takes the fee, swaps the rest into the assets, mints shares from the oracle value of what was actually received |
| `redeem(from, shares, tolerance)` | Router | Sells assets worth the shares, takes the fee, sends USDC, burns the shares |
| `minMintPreview`, `minRedeemPreview` | anyone | Minimum output for a given tolerance, after fees |
| `proposeUpdateWeights`, `executeWeightUpdate`, `cancelWeightUpdate` | IndexManager | Timelocked weight changes |
| `rebalanceIndex()` | IndexManager or the Index itself | One asset-to-asset swap back to the target weights |
| `collectFees(collector)` | IndexManager | Sends the accrued USDC fees to the collector |

**Mint step by step.**
1. The Index pulls the USDC from the user (the user approves USDC to the Index, not to the Router).
2. It reads the three Chainlink prices once and caches reserves and USD values in a struct.
3. The fee stays in the Index (`s_totalFees`). The net amount is split between the two assets.
4. The split corrects the weights on the way in: if asset0 is overweight, the whole deposit buys asset1; otherwise asset0 gets the gap to its target first and asset1 gets the rest.
5. The Index sends the USDC to the Universal Router and executes the swap. Received amounts are measured as balance deltas.
6. Shares are minted from the oracle USD value of the assets received. If that's below `expected × (1 − tolerance)`, the call reverts with `Index__ToleranceExceeded`.

Redeem mirrors this: it sells the overweight asset first, measures what left the Index, and checks the net USDC against the tolerance.

**Rebalance.** `rebalanceIndex` reverts with `Index__RebalanceNotNeeded` unless the effective weight of asset0 is more than 3 points from its target. It computes the amounts with `UnderlyingMath.calculateRebalanceAmounts`, does a single swap with `amountOutMinimum` set to the oracle-expected amount minus 1%, and then checks that the total USD value lost is at most 1% of the swapped notional.

**Weight updates.** `executeWeightUpdate` applies the new weights and then tries a rebalance through an external self-call (`try this.rebalanceIndex()`), so a failed rebalance rolls back its own state but keeps the new weights. The outcome is one of three events: `WeightsUpdateRebalanceSkipped` (not needed), `WeightsUpdateRebalanceFailed(reason)` (a custom error), or a revert of the whole execution when the rebalance hit a common error (see [section 5](#custom-errors-vs-common-errors)).

**Why it's built this way.**

- **Internal reserves rather than `balanceOf`**, because NAV must not move when someone sends tokens to the contract. Donations and the classic ERC4626 inflation attack have no effect on share price.
- **Reserves stored in each token's native decimals rather than normalized to 18**, because the stored number then matches what the token contract holds. Conversion to 18 decimals happens only inside calculations, so rounding doesn't pile up across operations.
- **Shares priced from the oracle value of what was received rather than from the USDC paid**, because the depositor carries their own swap slippage. If the pool gives a bad price, the depositor gets fewer shares; existing holders aren't diluted.
- **Deposits and withdrawals that lean toward the target weights rather than a fixed pro-rata split**, because each flow then does part of the rebalancing for free and the index needs fewer dedicated rebalance swaps. The cost is a small oracle-lag arbitrage, documented as M-04.
- **No `AccessControl` on the Index, only two immutable addresses (`i_indexManager`, `i_router`)**, because the callers never change. Dropping it removed the role storage, the `RoleGranted` events in the constructor and a few KB of bytecode, which mattered for EIP-170.
- **The Index is not upgradeable**, because it holds the funds. Holders can read the rules once and know they'll stay. The logic around it that might need fixes (Router, feeds, swap encoding) lives in the upgradeable services.
- **Fee fixed at creation, with no setter**, because a fee that can change after you deposit is a trust assumption. `s_feePercentage` is written only in the constructor.
- **A 3-day expiry window after the 2-day delay**, because a proposal nobody executed for weeks shouldn't become executable at a moment when users have stopped watching.

### 3.2 `IndexManager.sol`: the governance executor

**What it does.** The admin entry point. It validates and registers new indexes, forwards governance calls to them, and owns the SwapManager and PriceFeedManager proxies. It uses OpenZeppelin `AccessControl` with four roles (see [section 4](#4-actors-and-roles)). Runtime size: 9,584 bytes.

| Function | Role | Notes |
|---|---|---|
| `createIndex(fee, assetA, assetB)` | `ASSET_MANAGER_ROLE` | Rejects identical assets, USDC as an asset, fees outside 0.1%–10%, weights outside (1%, 100%) or not summing to 100%, and assets (or USDC) without a registered feed. Sorts the assets by address and deploys through the factory. Emits `IndexCreated` |
| `initializeIndex(depositor, index, amount0, route0Usdc, route1Usdc, route01)` | `ASSET_MANAGER_ROLE` | Registers the three swap routes in the SwapManager, then calls `Index.initialize` |
| `rebalanceSingleIndex`, `rebalanceMultipleIndexes` | `REBALANCER_ROLE` | |
| `proposeNewWeights(index, weight0)`, `cancelWeightUpdate` | `ASSET_MANAGER_ROLE` | weight1 is always `100% − weight0` |
| `executeSingleWeightUpdate`, `executeWeightUpdateForMultipleIndexes` | `ASSET_MANAGER_ROLE` | |
| `collectFeesFromSingleIndex`, `collectFeesFromMultipleIndexes` | `FEE_COLLECTOR_ROLE` | Fees go to the caller; `getTotalFeesCollected()` keeps the running total |

Getters: `getDeployedIndexes`, `getInitializedIndexes` (pass it to the batch functions to cover every index), `getIndexByAssetsAddresses` (any order), `getIndexAssets`, `isIndexAddress`, `checkIsIndexInitialized`, and the addresses of the Router, SwapManager, PriceFeedManager, IndexFactory and Universal Router.

**Why it's built this way.**

- **The IndexManager creates the three proxies in its own constructor and stores them as immutables rather than taking addresses through setters**, because a setter for the SwapManager was a finding in the first review (M-01): whoever could call it could redirect every swap. With immutables the wiring can't change; the proxies' logic can, but only through the timelock.
- **Events stay minimal: `IndexCreated`, `IndexActionTriggered(index, caller, action)` and `IndexActionFailed(index, caller, action, reasonData)`**, because the Index already emits every state change. Duplicating them here would give an off-chain indexer two sources of truth to reconcile.
- **Batch functions absorb failures rather than reverting**, because one index with a stale feed shouldn't block the rebalance or fee collection of every other index. Each failure is logged with the original revert data.
- **One index per asset pair**, enforced by the `s_getIndex[asset0][asset1]` mapping and by the CREATE2 salt `keccak256(asset0, asset1)`. Liquidity for a pair isn't split across competing indexes, and the address of an index can be computed before it exists.

### 3.3 `IndexFactory.sol` and `SplitCode.sol`: the deployer

**What it does.** Deploys new indexes with CREATE2. At construction it splits `type(Index).creationCode` in two halves and stores each half as the runtime code of a data contract (`SplitCode.write`, runtime = `0x00` + data, so calling a data contract is a no-op). `deployIndex` copies both halves back into memory with `EXTCODECOPY`, appends the constructor arguments and runs CREATE2. It has no permissions and emits no events, and it always passes `msg.sender` as the new index's IndexManager. Runtime size: 1,737 bytes.

**Why it's built this way.** With the Index creation code embedded, the IndexManager was about 37 KB with the optimizer on, well past the 24,576-byte limit. I compared four options:

| Option | Why I didn't pick it |
|---|---|
| A plain factory holding `type(Index).creationCode` | The factory itself would be about 24.5 KB, right at the limit; any future change to the Index would break it |
| EIP-1167 clones with immutable args | Would have meant rewriting the Index as an initializable contract (upgradeable versions of ERC20Permit/EIP712, immutables moved to clone args or storage) |
| External libraries for the Index logic | Shrinks the Index but leaves its creation code inside the IndexManager |
| Diamond (EIP-2535) | Far more machinery than a two-asset vault needs |

The split-code factory keeps the Index exactly as it was (constructor and immutables included), and it has room to grow: each half can reach 24,575 bytes.

Being permissionless is safe because of the `msg.sender` rule. Anyone can call the factory directly, but they get an Index that they manage themselves and that the IndexManager, the Router (which checks `checkIsIndexInitialized`) and the official indexer never recognize. That's why off-chain code must discover indexes from `IndexCreated` on the IndexManager and never from the factory.

### 3.4 `Router.sol`: the user entry point

**What it does.** The only contract allowed to call `mintShares` and `redeem`. It validates the inputs and forwards the call with `msg.sender` as the user. UUPS proxy, storage in an ERC-7201 namespace, no owner.

| Function | Description |
|---|---|
| `buyExactUsdcAmountOfShares(index, usdc, tolerance)` | Buy shares with an exact USDC amount (USDC approved to the Index) |
| `buyExactUsdcAmountOfSharesWithPermit(index, usdc, tolerance, deadline, v, r, s)` | Same, with a USDC permit signed for the Index, so no separate approve transaction |
| `sellExactAmountOfSharesForUsdc(index, shares, tolerance)` | Sell an exact amount of shares (no share approval needed) |
| `getMinMintPreview(index, usdc, tolerance)` | Minimum shares for that USDC, after fees and tolerance |
| `getMinRedeemPreview(index, shares, tolerance)` | Minimum USDC for those shares, after fees and tolerance |
| `getMaxTolerance()` | `100_000` (10%), exclusive |

Every buy and sell checks that the index is registered and initialized in the IndexManager, that the amount isn't 0, that `0 < tolerance < 100_000`, and that the caller's balance covers the amount. Then the call runs under OpenZeppelin `ReentrancyGuard`.

**Why it's built this way.**

- **Validation lives in the Router rather than in each Index**, because it's the part most likely to grow (new entry points, new checks) and a proxy lets that happen without redeploying any index.
- **Every Index stores the same Router proxy as an immutable**, so one upgrade applies to all indexes and an Index can never be pointed at a different Router.
- **Router upgrades go through the same 2-day timelock as the other proxies**, because the Router is trusted with a lot. Users approve USDC to the Index and `redeem` burns shares without an allowance, so whoever controls the Router logic could mint with any approved USDC or force a redeem. The timelock's `CallScheduled` event carries the full `upgradeToAndCall` calldata, so users get 2 days to revoke approvals or exit.

### 3.5 `PriceFeedManager.sol`: the oracle registry

**What it does.** Maps each asset to one Chainlink feed and its own `maxDelay`. Every index reads prices through it. UUPS proxy, owned by the IndexManager, storage in an ERC-7201 namespace. Feed operations are allowed to anyone holding `ASSET_MANAGER_ROLE` on the IndexManager (the PriceFeedManager asks its owner with `hasRole`), so in practice to the MultiSig, which calls the PriceFeedManager directly.

| Function | Notes |
|---|---|
| `registerPriceFeed(asset, feed, maxDelay)` | Once per asset. Checks that the asset answers `symbol()` and `decimals() <= 18`, that the feed has code, returns a positive answer and `decimals() <= 18`, and that `0 < maxDelay <= 2 days` |
| `proposePriceFeedUpdate` / `executePriceFeedUpdate` / `cancelPriceFeedUpdate` | Replacement with a 2-day delay and a 3-day window. The feed is validated again at execution, in case it was deprecated during the wait |
| `getPrice(asset)` | Price with 18 decimals. Reverts if the feed isn't set, the answer is `<= 0`, `answeredInRound < roundId`, or the answer is older than `maxDelay` |

**Why it's built this way.**

- **One shared registry rather than feed addresses stored in each Index**, because Chainlink does deprecate and migrate feeds. With per-index immutables, a dead feed would freeze every index that uses the asset. Here one replacement fixes them all.
- **A `maxDelay` per feed rather than one global staleness limit**, because heartbeats differ a lot: USDC/USD updates every 24 hours, ETH/USD every hour. A single limit is either too loose for one or too strict for the other. The deploy scripts set `maxDelay` to heartbeat plus a margin.
- **Asset metadata is validated here, at registration, rather than in `createIndex`**, because every index needs a registered feed anyway, and moving the check saved bytecode in the IndexManager.

### 3.6 `SwapManager.sol`: the swap encoder

**What it does.** Stores three routes per index (asset0↔USDC, asset1↔USDC, asset0↔asset1) and builds the Universal Router `commands` and `inputs` for single or double swaps. A route is either a Uniswap V3 path (single or multi-hop) or a Uniswap V4 `PoolKey`. The Index transfers the input tokens to the Universal Router first and the swap runs with `payerIsUser = false`, so no Permit2 approval is needed. It emits no events. UUPS proxy, owned by the IndexManager, storage in an ERC-7201 namespace. Runtime size: 10,012 bytes.

`registerIndex` (called by `initializeIndex`) checks that each route's end tokens match the index's assets and USDC in either direction. V3 paths are reversed automatically depending on the swap direction.

**Why it's built this way.**

- **Swap encoding in a separate upgradeable contract rather than inside the Index**, because Universal Router commands are the part of the protocol most tied to an external system. If Uniswap changes the input format, one upgrade fixes every index. The `lib/v4-periphery` dependency is pinned to the version used by the mainnet Universal Router for the same reason.
- **V3 and V4 side by side, chosen per route**, because liquidity moves between versions at different speeds per pair. The deploy scripts use V3 pools for all three routes today, and a new index can use V4 for a pair where V4 is deeper, with no contract change.
- **No `amountOutMinimum` on the USDC legs of mint and redeem**, because the user's tolerance is checked by the Index on the combined result of both legs, which is the number the user actually cares about.

### 3.7 `UpgraderAuth.sol` and the `TimelockController`

**What it does.** `UpgraderAuth` is the abstract UUPS authorization inherited by the three proxies. It stores a single `upgrader` address in an ERC-7201 slot, set once in `initialize` with no setter, and `_authorizeUpgrade` accepts only that address. The upgrader is an OpenZeppelin `TimelockController` with a 2-day minimum delay, the MultiSig as proposer, executor and canceller, and no admin.

Upgrade flow:

1. The MultiSig calls `timelock.schedule(proxy, 0, abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImpl, data)), predecessor, salt, 2 days)`. The timelock emits `CallScheduled`.
2. After at least 2 days the MultiSig calls `timelock.execute(...)` with the same parameters. `UpgraderAuth` checks `msg.sender == upgrader`, OpenZeppelin checks `proxiableUUID`, the proxy emits `Upgraded(newImpl)` and the timelock emits `CallExecuted`.
3. Until then the MultiSig can call `timelock.cancel(id)`, which emits `Cancelled`.

Several upgrades can be grouped with `scheduleBatch`/`executeBatch`. There's no expiry: a scheduled upgrade stays executable until it's executed or cancelled.

**Why it's built this way.**

- **Upgrade rights separated from ownership**, because the owner of SwapManager and PriceFeedManager is the IndexManager, which calls them on every index creation. If the owner could also upgrade, the IndexManager would need upgrade functions of its own and any bug there would become an upgrade path. Now the IndexManager has no upgrade function at all.
- **OpenZeppelin's `TimelockController` rather than a custom delay**, because it's audited, widely used and its events are understood by existing monitoring tools.
- **No admin on the timelock**, so the 2-day delay itself can only be changed by a timelocked operation.
- **UUPS rather than Transparent proxies**, because there's no `ProxyAdmin` to manage and the upgrade rule is plain code in the implementation.

### 3.8 `MultiSigWallet.sol`: the admin

**What it does.** A minimal 2-of-3 multisig with immutable owners and threshold. Owners `submitTransaction`, `confirmTransaction` and `executeTransaction`, and can `revokeConfirmation` before execution. An owner can also confirm off-chain: they sign EIP-712 typed data `Confirm(txId, target, value, dataHash, nonce)` and anyone can submit it with `confirmTransactionWithSig`. The nonce is per (txId, owner) and goes up on every use and on every revoke, so a signature collected before a revoke stops working.

**Why it's built this way.** A production deployment would use a Safe. This one is written from scratch as an exercise in EIP-712 domain separation and replay protection, and it keeps the whole admin path testable inside Foundry. Off-chain confirmations exist so that owners can approve a proposal from the front-end without paying gas; the SDK builds the typed data and a backend can collect the signatures until the threshold is reached.

### 3.9 Libraries

| Library | Purpose |
|---|---|
| `UnderlyingMath` | USD valuation, effective weights, mint/redeem allocation toward the target weights, rebalance amounts, decimal conversion |
| `SharesMath` | Shares to mint, share value in USD, minimum amount after a tolerance |
| `RevertData` | `isCommonError`: tells a custom error from a common one (see below) |
| `SplitCode` | Stores bytes as contract code and reads them back (used by the IndexFactory) |

---

## 4. Actors and roles

### IndexManager roles (OpenZeppelin `AccessControl`)

The constructor grants all four roles to the deployer. `DeployPeriphery` then moves `DEFAULT_ADMIN_ROLE` and `ASSET_MANAGER_ROLE` to the MultiSig; the deployer keeps `REBALANCER_ROLE` and `FEE_COLLECTOR_ROLE`.

| Role | Holder after deploy | Can | Cannot |
|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` | MultiSig | Grant and revoke any role on the IndexManager | Call operational functions, upgrade the proxies |
| `ASSET_MANAGER_ROLE` | MultiSig | Create and initialize indexes; propose, execute and cancel weight updates; register and replace price feeds on the PriceFeedManager | Rebalance, collect fees, mint or redeem |
| `REBALANCER_ROLE` | Deployer | Rebalance one index or a list (`getInitializedIndexes()` covers all) | Create indexes, change weights, collect fees |
| `FEE_COLLECTOR_ROLE` | Deployer | Withdraw fees from one index or a list; fees go to the caller | Rebalance, create indexes, change weights |

Splitting the roles means the rebalancer can be a keeper bot with a hot key, while index creation and weights stay behind the MultiSig.

### Index access control

The Index has no roles. Its constructor stores two immutable addresses (`getIndexManager()`, `getRouter()`).

| Modifier | Allowed caller | Functions | Error |
|---|---|---|---|
| `onlyIndexManager` | The IndexManager set at construction, and the Index itself (for the rebalance self-call in `executeWeightUpdate`) | `initialize`, `proposeUpdateWeights`, `executeWeightUpdate`, `cancelWeightUpdate`, `collectFees`, `rebalanceIndex` | `Index__CallerNotIndexManager` |
| `onlyRouter` | The Router proxy (same for every index) | `mintShares`, `redeem` | `Index__CallerNotRouter` |

### Users

Anyone can buy and sell through the Router (see [3.4](#34-routersol-the-user-entry-point)). Calling the Index directly reverts with `Index__CallerNotRouter`. Users can't rebalance, collect fees or change weights.

---

## 5. Cross-cutting design decisions

### USDC as the only user currency

Deposits, redemptions, fees and NAV are all in USDC. A position is easy to read in dollars, and fees and slippage are directly comparable. The USDC/USD price still comes from Chainlink: a deposit is valued at the real USD value of the USDC, so a depeg doesn't let anyone mint at $1.

### Two assets per index

Two assets keep the rebalance to a single swap and the math readable: the weight of asset1 is always `100% − weight0`, and "overweight" has one meaning. A third asset is the obvious next step (see [Contributing](#11-contributing)).

### Custom errors vs common errors

Single-index actions (`rebalanceSingleIndex`, `executeSingleWeightUpdate`, `collectFeesFromSingleIndex`) and the rebalance inside `executeWeightUpdate` sort a failed call in two groups with `RevertData.isCommonError`:

- **Custom errors of the Index** (for example `Index__RebalanceSlippageTooHigh`): logged in an event (`IndexActionFailed` or `WeightsUpdateRebalanceFailed`) with the raw revert data, and the transaction succeeds.
- **Common errors** (revert data under 4 bytes, which includes out of gas, plus `Error(string)` and `Panic`): the transaction reverts with the same revert data.

The reason is gas estimation. Because of the 63/64 rule, a call can run out of gas inside the try while the outer transaction still has enough left to finish. If that were caught, `eth_estimateGas` could return a gas limit at which the action always "succeeds" by emitting a failure event, and a keeper would burn gas forever without rebalancing. Reverting on common errors forces the estimate up to a limit where the action really works. Batch functions catch everything, so one broken index doesn't block the others.

### Storage layout of the proxies

All three proxies keep their state in ERC-7201 namespaced structs (`onchainassetmanager.storage.<Contract>`), with nothing in the sequential slots. A new version can add fields or new parents without colliding with existing storage, and `UpgraderAuth` has its own namespace too.

### Frozen ABIs

Since the end of phase 1 (2026-10-24, git tag `abi-v1`) function signatures, events and errors are frozen. `packages/abi` generates typed ABIs from the Foundry artifacts with `@wagmi/cli`, a pre-commit hook fails if `generated.ts` is out of date, and any ABI change needs an explicit decision. The SDK, the indexer and the front-end can be built against a stable target.

### Off-chain stack

The contracts are one part of a monorepo:

- `packages/abi` (`@oam/abi`): generated ABIs and deployed addresses per chain.
- `packages/sdk` (`@oam/sdk`): framework-agnostic TypeScript SDK on viem. It does no I/O: it returns calldata, read descriptors, EIP-712 typed data and event parsers, and the front-end or keeper sends them. Details in `packages/sdk/sdk.md`.
- `packages/db` (`@oam/db`): Prisma schema, migrations and client shared by the indexer, the API and the keeper (see `packages/db/db.md`).
- `apps/indexer` (`@oam/indexer`): off-chain indexer on Postgres, being rewritten with viem.

---

## 6. Known limitations

These come from the internal security review (no Critical or High findings open). They are known trade-offs or work still to do, listed here so nobody has to discover them.

- **No exit without swaps, no pause (M-02).** Mint, redeem and rebalance all need fresh prices from three feeds and a working swap route. If a feed goes stale, redeems revert until it recovers or is replaced (at least 2 days). Routes can only change through a SwapManager upgrade: `updateRoute` exists but the IndexManager doesn't expose it. The planned fix is an in-kind redeem that pays out a share of both reserves with no oracle and no swap.
- **Oracle-lag arbitrage (M-04).** Shares are priced at the Chainlink NAV while deposits and withdrawals lean toward one asset. When the market moves within a feed's deviation threshold, a trader can capture part of that gap at the expense of passive holders, minus the protocol and pool fees. Still to be measured on a fork.
- **The deployer keeps the rebalancer and fee collector roles (L-10).** Fine for local development; a real deployment would hand them to a keeper and the MultiSig.
- **IndexFactory, SplitCode and the custom/common error split** haven't been through the review yet.

---

## 7. Mainnet fork environment

Integration tests run against a mainnet fork pinned to block 26,178,000.

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js and npm (ABIs, SDK, lint)
- Docker (only for the local Postgres)
- An archive RPC for Ethereum mainnet, for example from [Alchemy](https://www.alchemy.com/)

### Environment variables

Copy `.env.example` to `.env` in the project root (never commit `.env`):

```bash
# Archive RPC of Ethereum mainnet: fork tests and make anvil-fork / DEV_PROFILE=fork
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/<YOUR_ALCHEMY_KEY>

# Deployer address, read by HelperConfig only when running on mainnet
MAINNET_DEPLOYER=0xYourDeployerAddressHere

# Host port of the local Postgres (docker-compose.yml); 5432 is often taken by a system Postgres
POSTGRES_PORT=5434
```

The database package reads `packages/db/.env` (copy `packages/db/.env.example`): `DATABASE_URL` points at the Postgres of `docker-compose.yml`. With `make db` running, `npm run migrate --workspace @oam/db` applies the migrations and `npm run generate --workspace @oam/db` regenerates the client (`npm install` also does it).

> **Note:** the `[rpc_endpoints]` section in `foundry.toml` references `${MAINNET_RPC_URL}`. The variable name in `.env` must match exactly.

### Start a local mainnet fork

```bash
make anvil-fork
```

The fork reads state at block 26,178,000 (so the RPC must be an archive node) and runs with chain id 31338, so nothing deployed or signed there can be confused with mainnet. The real Chainlink feeds don't update on the fork: about 1h15m after start the price reads revert and the fork has to be restarted.

### Run tests against the fork

```bash
forge test            # all tests (unit + integration)
make unittest         # unit tests only, no RPC needed
make integrationtest  # integration tests only, fork required
```

---

## 8. Project structure

```
.
├── src/
│   ├── Index.sol                    # Vault: mint, redeem, rebalance, weights, fees
│   ├── IndexManager.sol             # Governance executor, creates the three proxies
│   ├── IndexFactory.sol             # Split-code CREATE2 factory for new indexes
│   ├── Router.sol                   # User entry point (UUPS proxy)
│   ├── PriceFeedManager.sol         # Shared Chainlink feed registry (UUPS proxy)
│   ├── SwapManager.sol              # Uniswap V3/V4 route registry and encoder (UUPS proxy)
│   ├── UpgraderAuth.sol             # UUPS authorization bound to a single upgrader
│   ├── MultiSigWallet.sol           # 2-of-3 multisig with EIP-712 confirmations
│   ├── ContractCodeConstants.sol    # Protocol constants (fees, weights, delays, slippage)
│   ├── types.sol                    # Shared structs and enums
│   ├── Interface/                   # IIndex, IIndexManager, IIndexFactory, IRouter, IPriceFeedManager,
│   │                                # ISwapManager, IMultiSigWallet, IUpgraderAuth
│   ├── errors/                      # Custom errors per contract (Index, IndexManager, IndexFactory, Router,
│   │                                # PriceFeedManager, MultiSigWallet, SplitCode, UpgraderAuth)
│   ├── events/                      # Events of Index, IndexManager, PriceFeedManager, MultiSigWallet
│   └── libraries/
│       ├── UnderlyingMath.sol       # USD valuation, allocation, rebalance amounts, decimals
│       ├── SharesMath.sol           # Share mint/redeem/tolerance arithmetic
│       ├── RevertData.sol           # Custom error vs common error
│       └── SplitCode.sol            # Bytes stored as contract code (STOP-prefixed)
│
├── script/
│   ├── CodeConstants.sol            # Chain ids, mainnet addresses, MultiSig and timelock settings
│   ├── DeployPeriphery.s.sol        # MultiSig, timelock, IndexFactory, IndexManager (+ proxies), USDC feed, roles
│   ├── DeployAndInitNewIndex.s.sol  # Missing feeds, createIndex and initializeIndex through the MultiSig
│   ├── DeploymentFile.sol           # Path of deployments/<chainId>.json and write guard (only under --broadcast)
│   ├── FundAccounts.s.sol           # Tops up WETH/WBTC/USDC of the test accounts
│   ├── HelperConfig.s.sol           # Network config (mainnet, fork 31338) and Anvil mocks
│   ├── HelperConfigFromDeployment.s.sol # Same config, Anvil mocks loaded from deployments/
│   └── RefreshMockFeeds.s.sol       # Anvil only: re-publishes every mock feed answer
│
├── test/
│   ├── mocks/                       # Tokens, USDC, Universal Router, feeds, V2 implementations, malicious indexes
│   ├── unit/                        # Base.t.sol plus one folder or file per contract (see Testing)
│   └── integration/
│       ├── ForkConstants.sol        # MAINNET_FORK_BLOCK
│       ├── Interactions/            # Real tokens, feeds and Universal Router on the fork
│       └── ScriptsTest/             # Deployment scripts on local and forked chains
│
├── packages/abi/                    # @oam/abi: generated ABIs and deployed addresses
├── packages/sdk/                    # @oam/sdk: TypeScript SDK (viem, no I/O)
├── packages/db/                     # @oam/db: Prisma schema, migrations and client
├── apps/indexer/                    # @oam/indexer: off-chain indexer
├── apps/web/                        # @oam/web: front-end dApp (Vite + React + wagmi), skeleton only
├── deployments/                     # <chainId>.json written by the scripts
├── bin/                             # dev.sh (make dev), snapshot.sh (make snapshot), anvil-common.sh
├── .githooks/pre-commit             # Fails the commit if the generated ABIs are stale
├── invariant.md                     # Invariants per contract (Italian)
├── docker-compose.yml               # Local Postgres for the indexer
├── tsconfig.base.json               # Compiler options shared by packages/* and apps/*
└── eslint.config.mjs                # ESLint for every TypeScript workspace
```

### Make targets

```bash
make build                  # forge build
make test                   # all tests (unit + integration)
make unittest               # test/unit/**/*.sol
make integrationtest        # test/integration/**/*.sol (requires the mainnet fork)
make indextest              # IndexUnitTest only
make indexmanagertest       # IndexmanagerUnitTest only
make coverage               # coverage summary for src/ only
make coverage-report        # full lcov HTML report (requires lcov)
make test-single NAME=<fn>  # one test by name with -vvvv
make abi / make check-abi   # regenerate packages/abi / fail if it's stale
make anvil / make anvil-fork   # plain Anvil / the mainnet fork (chain id 31338)
make deploy-anvil           # periphery + WETH/WBTC index on plain Anvil, then fund the test accounts
make deploy-fork            # fund the test accounts, then periphery + WETH/WBTC index on the fork
make deploy-index           # one more index on an existing deployment (INDEX_* env vars)
make fund                   # top up WETH/WBTC/USDC of Anvil accounts 0-9 (Anvil or fork)
make refresh-feeds          # Anvil only: make every mock feed fresh again
make snapshot               # fresh Anvil + deploy + fund, state saved to .anvil/31337.json
make anvil-load             # start Anvil from the snapshot
make dev                    # Postgres + chain + contracts + funded accounts (DEV_PROFILE=fork for the fork)
make db / make db-down      # start / stop the local Postgres
make lint / make typecheck  # ESLint and tsc on every TypeScript workspace
```

---

## 9. Clone and configuration

```bash
# 1. Clone
git clone https://github.com/eliab256/OnChain-Asset-Manager.git
cd OnChain-Asset-Manager

# 2. Install Foundry and Node dependencies
forge install
npm install

# 3. Enable the pre-commit hook (once per clone)
git config core.hooksPath .githooks

# 4. Create the environment file and fill in MAINNET_RPC_URL and MAINNET_DEPLOYER
cp .env.example .env

# 5. Build and run the unit tests (no RPC needed)
make build
make unittest
```

### Run the full deployment locally

Start the node in one terminal and deploy from another. Both targets use the Anvil default accounts: account 0 is the deployer and MultiSig owner 1, accounts 1 and 2 are the other owners.

```bash
# Plain Anvil with mocks
make anvil
make deploy-anvil

# Mainnet fork (MAINNET_RPC_URL in .env, archive node)
make anvil-fork
make deploy-fork
```

`deploy-fork` runs `FundAccounts` (100 WETH, 5 WBTC and 1,000,000 USDC written into the balance slots of Anvil accounts 0-9, with no swaps, so the WBTC/WETH pool stays aligned with Chainlink), then `DeployPeriphery` and `DeployAndInitNewIndex`. `deploy-anvil` runs `DeployPeriphery`, `DeployAndInitNewIndex` and then `FundAccounts`, which mints the same amounts of the mock tokens. `FundAccounts` only tops up, so `make fund` can run again at any time. `FUND_ACCOUNTS` (comma-separated addresses), `FUND_ACCOUNT_COUNT`, `FUND_WETH`, `FUND_WBTC` and `FUND_USDC` change accounts and amounts. The broadcasts use `--legacy` because Anvil forwards `eth_feeHistory` with reward percentiles to the upstream RPC, which may answer 503.

Every run writes `deployments/<chainId>.json`: chain id, `startBlock`, deployer, MultiSig (owners, threshold), timelock, IndexManager, IndexFactory, the three proxies with their implementations, the network config, the Anvil mocks and an `indexes` object keyed by index address. `DeployPeriphery` rewrites the file and `DeployAndInitNewIndex` adds one entry under `indexes`. The file is written only with `--broadcast`, never during `forge test`. Block numbers are the ones the script sees, so treat them as lower bounds when indexing.

### One-command dev environment

```bash
make snapshot               # once: fresh Anvil, deploy, fund, state saved to .anvil/31337.json
make dev                    # Postgres (docker compose) + Anvil from the snapshot + fresh mock feeds
DEV_PROFILE=fork make dev   # Postgres + mainnet fork + deploy + fund (no snapshot)
```

`make dev` needs port 8545 free and Docker running. Without a snapshot it deploys from scratch. After loading a snapshot it runs `make refresh-feeds`, because the chain time jumps to the wall clock and the mock feeds would be stale. If `deployments/31337.json` no longer matches the snapshot (no code at the IndexManager address), it stops and asks for a new `make snapshot`. Anvil logs go to `.anvil/anvil.log`; Ctrl-C stops Anvil and leaves Postgres running (`make db-down`). Snapshots are for plain Anvil only: on the fork the real Chainlink feeds go stale about an hour after the fork starts.

To add another index to an existing deployment:

```bash
make deploy-index INDEX_ASSET_A=LINK INDEX_ASSET_B=COMP INDEX_WEIGHT_A=600000 INDEX_WEIGHT_B=400000
```

| Variable | Default | Meaning |
|---|---|---|
| `INDEX_ASSET_A`, `INDEX_ASSET_B` | `WETH`, `WBTC` | `WETH`, `WBTC`, `LINK` or `COMP` |
| `INDEX_WEIGHT_A`, `INDEX_WEIGHT_B` | `500000` each | target weights, 1,000,000 = 100% |
| `INDEX_FEE` | `10000` | fee, 1,000,000 = 100% (10000 = 1%) |
| `INDEX_DEPOSIT_A`, `INDEX_DEPOSIT_B` | 1 unit of A, B computed | initial deposit in native decimals; 0 = computed from the other at the target weights and Chainlink prices |

From the command line `DeployAndInitNewIndex` needs `--sig "run()"`; the Make target already passes it.

---

## 10. Testing

**1009 tests in 50 suites, all passing**: 926 unit tests and 83 integration tests on the mainnet fork.

### Mocks

Unit tests run in memory with no RPC. The main mocks:

| Mock | Purpose |
|---|---|
| `MockUSDC` (`USDCMock.sol`) | 6-decimal ERC20 with permit, like real USDC |
| `AssetTokenMock`, `DecimalsTokenMocks` | ERC20s with configurable decimals (WETH 18, WBTC 8, LINK 18, COMP 18) and malformed metadata for the validation tests |
| `UniversalRouterMock` | Simulates `execute()` with configurable exchange rates, without pools |
| `AggregatorConfigurableMock` | Chainlink feed whose round data, decimals and failure modes are all settable (Chainlink's `MockV3Aggregator` provides the default prices) |
| `SwapManagerV2Mock`, `PriceFeedManagerV2Mock`, `RouterV2Mock`, `ProxiableWrongUuidMock` | Upgrade targets, valid and invalid |
| `ReentrantIndexMock`, `GasBurningIndexMock`, `MalformedIndexMocks` | Hostile or broken indexes for the Router, SwapManager and error-handling tests |
| `SplitCodeHarness`, `SwapManagerHarness`, `RawCreateDeployerMock` | Expose internal functions or deploy outside the factory |

### Unit tests (`test/unit/`)

Most suites inherit from `Base.t.sol`, which runs the real deployment scripts (`DeployPeriphery`, `DeployAndInitNewIndex`) on the local chain (id 31337), with `HelperConfig` deploying the mocks, then funds the mock router and creates a WBTC/WETH index at 60/40.

| Suite | Scope |
|---|---|
| `IndexUnitTest/` | Deploy and init, mint, redeem, rebalance and weights, fees, events, getters, price feed migration |
| `IndexmanagerUnitTest/` | Index creation and asset validation, init, route validation, rebalance, weights and the inner rebalance, fees, `IndexActionTriggered`/`IndexActionFailed`, common errors |
| `IndexFactoryUnitTest/` | Constructor, code pointers, `deployIndex`, wiring with the IndexManager |
| `RouterUnitTest/` | Input validation, buy (with and without permit), sell, getters, upgrades |
| `PriceFeedManagerUnitTest/` | Initialization, registration, `getPrice` checks, timelocked replacement and its events |
| `SwapManager.t.sol`, `SwapManager.RouteValidation.t.sol` | V3/V4 route registration and validation, directional paths, calldata building |
| `UpgraderAuthUnitTest/` | Upgrader storage and init, direct-upgrade rejection, schedule/execute/cancel/batch upgrades of all three proxies through the timelock, timelock roles and events |
| `MultiSigWallet*.t.sol` | Submit, confirm, execute, revoke, EIP-712 confirmations and replay protection, events |
| `LibrariesUnitTest/` | `SharesMath`, `UnderlyingMath` (with fuzz tests), `SplitCode` |

### Integration tests (`test/integration/`)

The fork is created with `vm.createSelectFork("mainnet", MAINNET_FORK_BLOCK)` and uses the real USDC, WETH, WBTC, LINK and COMP, the real Chainlink feeds and the mainnet Universal Router (`0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af`) against real V3 pools. `IntegrationBase.t.sol` deploys the protocol on top and funds the deployer with `deal()`.

The block is pinned in `test/integration/ForkConstants.sol` so results don't depend on live prices. When bumping it, pick a block where the WBTC/WETH pool is within 1% of Chainlink, otherwise the rebalance tests revert with `V3TooLittleReceived`.

| Suite | Scope |
|---|---|
| `IntegrationPriceFeeds.t.sol` | Real feeds: freshness, decimals, positive answers |
| `IntegrationUniRouter.t.sol` | Mint, redeem and rebalance end to end through the Universal Router |
| `ScriptsTest/` | `DeployPeriphery`, `DeployAndInitNewIndex` and `HelperConfig` on local and forked chains |

### Running tests

```bash
make test                       # all tests
make unittest                   # unit tests only (no RPC)
make integrationtest            # integration tests only (fork)
make test-single NAME=test_mintShares_mintsCorrectShares   # one test with full trace
```

After `forge lint`, run `forge build --force` before testing: lint can leave artifacts without bytecode in `out/` and the next `forge test` silently skips some suites. Always check the suite count.

---

## 11. Contributing

This started as a learning project and there's plenty left to do.

### Ideas

- **In-kind redeem and pause**: the fix for M-02 described in [Known limitations](#6-known-limitations).
- **Three-asset indexes**: extend `Index.sol` and the allocation math beyond two assets.
- **Performance fee**: a high-watermark fee on top of the flat protocol fee.
- **Invariant tests**: turn the properties in `invariant.md` into Foundry invariant suites, and add fuzzing to the rebalance logic.
- **Multi-chain deployment**: `HelperConfig` entries and scripts for L2s such as Arbitrum, Base or Optimism.
- **Gas**: cheaper mint and redeem paths.

### How to contribute

1. Fork the repository.
2. Create a feature branch: `git checkout -b feat/your-feature`.
3. Write tests for any new behaviour.
4. Make sure everything passes: `make test`.
5. Open a pull request with a clear description of the change.

Please follow the existing style: NatSpec with units on every function and event, `i_` and `s_` prefixes for immutables and storage, errors named `Contract__Name`, named constants instead of magic numbers. Any change to a signature, event or error changes the frozen ABI and needs to be discussed first.

---

## 12. License

Released under the [MIT License](LICENSE).

---

## 13. Contacts

| Channel | Link |
|---|---|
| GitHub | [github.com/eliab256](https://github.com/eliab256) |
| LinkedIn | [linkedin.com/in/elia-bordoni](https://www.linkedin.com/in/elia-bordoni/) |
| Email | bordonielia96@gmail.com |

Feel free to open an issue on GitHub for bugs, feature requests or questions.
