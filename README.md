# On-Chain Asset Manager

A decentralized, non-custodial index fund protocol built on Ethereum. Users deposit USDC and receive ERC20 shares representing a proportional stake in a basket of on-chain assets. The protocol handles rebalancing, fee collection and weight governance entirely on-chain via Uniswap V3 swaps routed through the Universal Router.

> ⚠️ **Disclaimer** — This project was built for educational purposes only. It has not been audited and is not intended for production use or mainnet deployment.

---

## Table of Contents

1. [Description](#1-description)
2. [Actors and Roles](#2-actors-and-roles)
3. [Init Mainnet Fork Environment](#3-init-mainnet-fork-environment)
4. [Project Structure](#4-project-structure)
5. [Clone and Configuration](#5-clone-and-configuration)
6. [Technical Choices](#6-technical-choices)
7. [Testing](#7-testing)
8. [Contributing](#8-contributing)
9. [License](#9-license)
10. [Contacts](#10-contacts)

---

## 1. Description

**On-Chain Asset Manager** is a smart-contract system that lets users invest in a curated basket of ERC20 tokens through a single USDC deposit. The protocol autonomously:

- **Mints** index shares proportional to the USDC deposited, net of protocol fees.
- **Redeems** shares back to USDC by selling the underlying assets.
- **Rebalances** the portfolio when an asset's effective weight drifts beyond a configurable threshold.
- **Governs** weight changes through a time-locked proposal mechanism, giving users time to react before new weights take effect.

### Core contracts

| Contract           | Responsibility                                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `IndexManager.sol` | Governance executor — creates and initialises indexes, orchestrates rebalancing, fee collection and weight updates |
| `Index.sol`        | The vault — holds assets, mints/burns shares, calculates NAV, enforces slippage tolerance                          |
| `Router.sol`       | UX entry point — validates user inputs, routes buy/sell calls to the correct index                                 |
| `SwapManager.sol`  | Swap abstraction — builds Uniswap V3/V4 swap parameters for the Universal Router                                   |

### Key design properties

- **USDC-denominated** — all shares are priced in USDC, providing a stable USD reference for users.
- **Two-asset indexes** — each index holds exactly two ERC20 tokens with configurable target weights (4-decimal precision, e.g. `600000` = 60 %).
- **Chainlink price feeds** — all USD valuations use Chainlink aggregators; stale-price protection is enforced on every read.
- **Slippage protection** — mint tolerance and rebalance max-slippage are enforced on-chain, not just off-chain.
- **Role-based access control** — `ASSET_MANAGER_ROLE`, `FEE_COLLECTOR_ROLE` and `REBALANCER_ROLE` are separated so governance can be distributed across multiple addresses.

---

## 2. Actors and Roles

The protocol uses **OpenZeppelin `AccessControl`** to enforce role-based permissions across two contract layers.

### IndexManager roles

These roles are defined in `IndexManager.sol`. The deployer receives all three roles at construction time but can grant or revoke them to separate addresses.

| Role                 | What it **can** do                                                                                                                  | What it **cannot** do                                                             |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `DEFAULT_ADMIN_ROLE` | Grant and revoke any role on IndexManager                                                                                           | Cannot call any operational function directly                                     |
| `ASSET_MANAGER_ROLE` | Create and initialise indexes, set the Router and SwapManager addresses, propose and execute weight updates (single, multiple, all) | Cannot rebalance indexes, cannot collect fees, cannot mint or redeem shares       |
| `REBALANCER_ROLE`    | Trigger rebalancing on a single index, on a list of indexes, or on all indexes at once                                              | Cannot create indexes, change weights, collect fees, or modify contract addresses |
| `FEE_COLLECTOR_ROLE` | Withdraw accrued protocol fees from a single index, from a list of indexes, or from all indexes                                     | Cannot rebalance, create indexes, change weights, or modify contract addresses    |

### Index roles

These roles are defined in `Index.sol` and are assigned automatically during deployment and initialisation.

| Role                 | Holder                                       | What it does                                                                        |
| -------------------- | -------------------------------------------- | ----------------------------------------------------------------------------------- |
| `INDEX_MANAGER_ROLE` | IndexManager contract (and the Index itself) | Initialise the index, execute rebalancing, execute weight updates, collect fees     |
| `ROUTER_ROLE`        | Router contract                              | Call `mintShares` and `redeem` — the only entry points for user buy/sell operations |

### User (no role required)

Any externally-owned account can interact with the protocol through the **Router** contract:

| Action       | Function                         | Description                                                              |
| ------------ | -------------------------------- | ------------------------------------------------------------------------ |
| Buy shares   | `buyExactUsdcAmountOfShares`     | Deposit USDC and receive proportional index shares, net of protocol fees |
| Sell shares  | `sellExactAmountOfSharesForUsdc` | Burn index shares and receive USDC                                       |
| Preview buy  | `getMinMintPreview`              | Estimate the minimum shares received for a given USDC amount             |
| Preview sell | `getMinRedeemPreview`            | Estimate the minimum USDC received for a given shares amount             |

Users **cannot** bypass the Router to call Index directly (the `ROUTER_ROLE` check will revert), and they **cannot** rebalance, collect fees, or change weights.

---

## 3. Init Mainnet Fork Environment

Integration and rebalance tests run against a mainnet fork using Alchemy. The fork is configured automatically by Foundry when the environment variables below are present.

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) `>= 0.2`
- An [Alchemy](https://www.alchemy.com/) account with an Ethereum mainnet app

### Environment variables

Create a `.env` file in the project root (never commit this file):

```bash
# Ethereum mainnet — used by foundry.toml [rpc_endpoints] and fork tests
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/<YOUR_ALCHEMY_KEY>

# Deployer address — read by HelperConfig when running on mainnet
MAINNET_DEPLOYER=0xYourDeployerAddressHere
```

> **Note:** the `[rpc_endpoints]` section in `foundry.toml` references `${MAINNET_RPC_URL}`. Make sure the variable name in your `.env` matches exactly.

### Start a local mainnet fork

```bash
# Load environment variables
source .env

# Start Anvil with a mainnet fork
anvil --fork-url $MAINNET_RPC_URL
```

### Run tests against the fork

```bash
# All tests (unit + integration)
forge test

# Only unit tests (no fork needed)
make unittest

# Only integration tests (fork required)
make integrationtest
```

---

## 4. Project Structure

```
.
├── script/
│   ├── CodeConstants.sol            # Chain IDs, mainnet addresses, deployer constants
│   ├── DeployPeriphery.s.sol        # Deploys IndexManager, Router, SwapManager
│   ├── DeployAndInitNewIndex.s.sol  # Deploys and seeds a new Index
│   └── HelperConfig.s.sol           # Network config and mock setup for Anvil
│
├── src/
│   ├── ContractCodeConstants.sol    # Protocol-wide constants (fees, weights, thresholds)
│   ├── Index.sol                    # Core vault: mint, redeem, rebalance, fees
│   ├── IndexManager.sol             # Governance: create, init, rebalance, collect fees
│   ├── Router.sol                   # User entry point: input validation, buy/sell routing
│   ├── SwapManager.sol              # Uniswap V3/V4 swap parameter builder
│   ├── types.sol                    # Shared structs and enums
│   ├── Interface/
│   │   ├── IIndex.sol
│   │   ├── IIndexManager.sol
│   │   ├── IRouter.sol
│   │   └── ISwapManager.sol
│   ├── errors/
│   │   ├── IndexErrors.sol
│   │   ├── IndexManagerErrors.sol
│   │   └── RouterErrors.sol
│   ├── events/
│   │   ├── IndexEvents.sol
│   │   └── IndexManagerEvents.sol
│   └── libraries/
│       ├── SharesMath.sol           # Share mint/redeem/tolerance arithmetic
│       └── UnderlyingMath.sol       # USD valuation, rebalance amounts, decimal conversion
│
└── test/
    ├── mocks/
    │   ├── AssetTokenMock.sol       # Configurable-decimal ERC20 mock
    │   ├── USDCMock.sol             # 6-decimal USDC mock
    │   └── UniversalRouterMock.sol  # Swap simulator with configurable exchange rates
    ├── unit/
    │   ├── Base.t.sol               # Shared setup: deploy, seed index, fund mock router
    │   ├── SwapManager.t.sol
    │   ├── IndexUnitTest/
    │   │   ├── Index.DeployInitAndCollectFees.t.sol
    │   │   ├── Index.Getters.t.sol
    │   │   ├── Index.Mint.t.sol
    │   │   ├── Index.Redeem.t.sol
    │   │   └── Index.RebalanceAndWeights.t.sol
    │   ├── IndexmanagerUnitTest/
    │   │   ├── IndexManager.deployAndInitIndex.t.sol
    │   │   ├── IndexManager.Getters.t.sol
    │   │   ├── IndexManager.initialSettings.t.sol
    │   │   ├── IndexManager.Rebalance.t.sol
    │   │   ├── IndexManager.Weights.t.sol
    │   │   └── Indexmanager.CollectFees.t.sol
    │   ├── RouterUnitTest/
    │   │   ├── Router.BuyShares.t.sol
    │   │   ├── Router.Getters.t.sol
    │   │   └── Router.SellShares.t.sol
    │   └── LibrariesUnitTest/
    │       ├── SharesMath.t.sol
    │       └── UnderlyingMath.t.sol
    └── integration/
        ├── Interactions/
        │   ├── IntegrationBase.t.sol      # Mainnet fork setup: real tokens, real price feeds
        │   ├── IntegrationPriceFeeds.t.sol # Chainlink feed staleness and price validation
        │   └── IntegrationUniRouter.t.sol  # End-to-end mint, redeem, rebalance via Universal Router
        └── ScriptsTest/
            ├── DeployAndInitIndex.t.sol
            ├── DeployPeriphery.t.sol
            └── HelperConfig.t.sol
```

### Make targets

```bash
make build                  # forge build
make test                   # all tests (unit + integration)
make unittest               # test/unit/**/*.sol
make integrationtest        # test/integration/**/*.sol (requires mainnet fork)
make indextest              # IndexUnitTest only
make indexmanagertest       # IndexmanagerUnitTest only
make coverage               # coverage summary for src/ only
make coverage-report        # full lcov HTML report (requires lcov installed)
make test-single NAME=<fn>  # run a single test by name with -vvvv
```

---

## 5. Clone and Configuration

```bash
# 1. Clone
git clone https://github.com/<your-username>/on-chain-asset-manager.git
cd on-chain-asset-manager

# 2. Install Foundry dependencies
forge install

# 3. Create the environment file
cp .env.example .env
# Fill in MAINNET_RPC_URL and MAINNET_DEPLOYER

# 4. Build
make build

# 5. Run unit tests (no RPC needed)
make unittest
```

### Run the full deployment on a local fork

```bash
source .env
anvil --fork-url $MAINNET_RPC_URL &

# Deploy IndexManager, Router, SwapManager
forge script script/DeployPeriphery.s.sol --broadcast --rpc-url http://localhost:8545

# Deploy and initialise a WETH/WBTC 60/40 index
forge script script/DeployAndInitNewIndex.s.sol --broadcast --rpc-url http://localhost:8545
```

---

## 6. Technical Choices

### USDC as the deposit and redemption currency

All user interactions — deposits, withdrawals and internal accounting — are denominated in USDC rather than ETH. This was a deliberate choice for two reasons:

- **Stable reference value** — ETH price volatility makes it difficult for users to reason about the value of their position. USDC provides a stable $1 baseline that makes NAV, fees and slippage immediately intuitive.
- **Simplified arithmetic** — holding a constant-value unit of account avoids the need to track an additional price feed for the deposit currency itself and reduces the risk of compounding rounding errors across conversions.

### Reserves stored in token decimals

`s_asset0Reserve` and `s_asset1Reserve` are stored in the native decimals of each underlying token (e.g. 8 for WBTC, 18 for WETH). Conversion to the 18-decimal standard happens only at computation time. This avoids cumulative precision loss that would occur from repeatedly converting between decimal representations.

### Uniswap V3 and V4 coexistence

`SwapManager` supports both V3 (path-encoded) and V4 (PoolKey-based) routes independently per swap type. This allows a new index to use V4 pools for the most liquid pairs while falling back to V3 for pairs that have not yet migrated, without changing any contract logic.

### Time-locked weight updates

Weight proposals are subject to `WEIGHT_UPDATE_DELAY` (2 days) before execution. This gives users a window to exit before a composition change takes effect, a pattern commonly used in DeFi governance to prevent rug-pull-style reconfigurations.

### Role separation

Three distinct roles are enforced via OpenZeppelin `AccessControl`:

| Role                 | Allowed operations                                                                               |
| -------------------- | ------------------------------------------------------------------------------------------------ |
| `ASSET_MANAGER_ROLE` | Create/initialise indexes, propose/execute weight updates, set router and swap manager addresses |
| `REBALANCER_ROLE`    | Trigger rebalancing on one or multiple indexes                                                   |
| `FEE_COLLECTOR_ROLE` | Withdraw accrued protocol fees                                                                   |

Separating these roles means that in a real deployment the rebalancer could be a keeper bot while fee collection remains in the hands of a multisig.

---

## 7. Testing

The project has **446 tests** (378 unit + 68 integration), all passing. Tests are organised into two distinct layers, each with a different isolation strategy.

### Mocks

Unit tests run entirely in-memory with no external dependencies. Three custom mocks replace the real on-chain infrastructure:

| Mock                  | Purpose                                                                                                                                                                           |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MockUSDC`            | Minimal ERC20 with 6 decimals, matching real USDC behaviour                                                                                                                       |
| `AssetTokenMock`      | ERC20 with **configurable decimals** (set at construction or changed at runtime via `setDecimals`). Used to simulate WETH (18 dec), WBTC (8 dec), LINK (18 dec) and COMP (18 dec) |
| `UniversalRouterMock` | Simulates the Uniswap Universal Router `execute()` function. Uses a configurable `exchangeRates` mapping to compute swap outputs deterministically, without touching any pool     |

Additionally, Chainlink's own `MockV3Aggregator` is used to provide deterministic USD prices for each asset and USDC.

### Unit tests (`test/unit/`)

All unit tests inherit from `Base.t.sol`, which:

1. Runs the deployment scripts (`DeployPeriphery`, `DeployAndInitNewIndex`) against the Anvil local chain (chain ID 31337).
2. `HelperConfig` detects the local chain and deploys all mocks: token mocks, price feed mocks, and the `UniversalRouterMock`.
3. Seeds the mock router with token balances so it can simulate swap outputs.
4. Creates and initialises a WBTC/WETH index with a 60/40 weight split.

Because every external dependency is mocked, unit tests are **fast**, **deterministic** and require **no RPC connection**.

Test suites cover:

| Suite                   | Scope                                                                                                                               |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `IndexUnitTest/`        | Deployment, initialisation, minting, redeeming, rebalancing, weight proposals, fee collection, getter functions                     |
| `IndexmanagerUnitTest/` | Index creation, initialisation, role-gated functions, rebalance orchestration, weight update orchestration, fee collection, getters |
| `RouterUnitTest/`       | Input validation (amount, balance, tolerance, index address), buy/sell share routing, getter functions                              |
| `LibrariesUnitTest/`    | `SharesMath` (mint/redeem/tolerance arithmetic) and `UnderlyingMath` (USD valuation, decimal conversion, rebalance math)            |
| `SwapManager.t.sol`     | V3/V4 route registration, directional path building, route update logic                                                             |

### Integration tests (`test/integration/`)

Integration tests run against an **Ethereum mainnet fork** created via `vm.createSelectFork("mainnet")`. They use real on-chain contracts:

- **Real ERC20 tokens** — USDC, WETH, WBTC, LINK, COMP at their mainnet addresses.
- **Real Chainlink price feeds** — live aggregator contracts for each asset/USD pair and USDC/USD.
- **Real Uniswap Universal Router** — the mainnet Universal Router V2 (`0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af`) executes actual V3 pool swaps.

`IntegrationBase.t.sol` sets up the fork, deploys the protocol contracts on top of it, and funds the deployer with tokens via `deal()`.

| Suite                         | Scope                                                                                                                                              |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `IntegrationPriceFeeds.t.sol` | Validates that real Chainlink feeds return non-stale prices, correct decimals and positive answers                                                 |
| `IntegrationUniRouter.t.sol`  | End-to-end flows: mint shares with real swaps, redeem shares, rebalance after price drift — all through the Universal Router against real V3 pools |
| `ScriptsTest/`                | Verifies that deployment scripts (`DeployPeriphery`, `DeployAndInitNewIndex`, `HelperConfig`) execute correctly on both local and forked chains    |

### Running tests

```bash
# All tests
make test

# Unit tests only (no RPC needed)
make unittest

# Integration tests only (mainnet fork)
make integrationtest

# Single test by name with full trace
make test-single NAME=test_mintShares_mintsCorrectShares
```

---

## 8. Contributing

Contributions are welcome and encouraged. This project was built as a learning exercise and there is plenty of room for improvement.

### Ideas for contributions

- **Multi-chain deployment** — add `HelperConfig` entries and deployment scripts for L2s such as Arbitrum, Base or Optimism.
- **Three-asset indexes** — the current architecture supports exactly two assets. Extending `Index.sol` to support a third asset is a natural next step noted in the roadmap.
- **Performance fee** — implement a high-watermark performance fee on top of the existing protocol fee.
- **Timelock governance** — replace the manual `WEIGHT_UPDATE_DELAY` with a proper on-chain Timelock or Governor contract.
- **Additional test coverage** — fuzz tests and invariant tests for the math libraries and the rebalance logic.
- **Gas optimization**: Further reduce transaction costs
- **Access control refinement**: Role-based granular permissions
- **Emergency pause mechanisms**: Circuit breakers for extreme market conditions

### How to contribute

1. Fork the repository.
2. Create a feature branch: `git checkout -b feat/your-feature`.
3. Write tests for any new behaviour.
4. Ensure all existing tests pass: `make test`.
5. Open a pull request with a clear description of the change.

Please follow the existing code style (NatSpec on all public functions, no magic numbers, named constants for all thresholds).

---

## 9. License

This project is released under the [MIT License](LICENSE).

---

## 10. Contacts

| Channel  | Link                                                                      |
| -------- | ------------------------------------------------------------------------- |
| GitHub   | [github.com/eliab256](https://github.com/eliab256)                        |
| LinkedIn | [linkedin.com/in/elia-bordoni](https://www.linkedin.com/in/elia-bordoni/) |
| Email    | bordonielia96@gmail.com                                                   |

Feel free to open an issue on GitHub for bug reports, feature requests or questions.
