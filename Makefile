-include .env

# ─── Local networks ────────────────────────────────────────────────────────────
RPC_URL 			?= http://127.0.0.1:8545
# Fork of mainnet at the same block as the fork tests (test/integration/ForkConstants.sol),
# with its own chain id so nothing can be confused with or replayed on mainnet.
FORK_BLOCK 			?= 26178000
FORK_CHAIN_ID 		?= 31338
# State saved by make snapshot (anvil only) and loaded by make anvil-load / make dev
STATE_DIR 			?= .anvil

# Anvil default accounts 0..2: deployer (and multisig owner 1), owners 2 and 3
ANVIL_KEY_0 		?= 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ANVIL_KEY_1 		?= 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
ANVIL_KEY_2 		?= 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a

# Index created by deploy-index (read by DeployAndInitNewIndex.run() with these defaults):
# INDEX_ASSET_A=WETH INDEX_ASSET_B=WBTC INDEX_WEIGHT_A=500000 INDEX_WEIGHT_B=500000
# INDEX_FEE=10000 INDEX_DEPOSIT_A / INDEX_DEPOSIT_B (native decimals, 0 = computed)

# ─── Test paths ───────────────────────────────────────────────────────────────
UNIT_TEST_PATH 				?= test/unit/**/*.sol
INDEX_UNIT_TEST_PATH 		?= test/unit/IndexUnitTest/*.sol
INDEX_MANAGER_UNIT_TEST_PATH ?= test/unit/IndexmanagerUnitTest/*.sol
INTEGRATION_TEST_PATH 		?= test/integration/**/*.sol
FUZZ_TEST_PATH 			?= test/fuzz/**/*.sol

# ─── Targets ───────────────────────────────────────────────────────────────────
.PHONY: build test unittest indextest indexmanagertest integrationtest fuzztest \
        test-index test-indexmanager test-router test-swap-manager test-single \
        test-manager coverage coverage-report \
        abi check-abi anvil anvil-fork anvil-load deploy-periphery deploy-index fund \
        refresh-feeds deploy-anvil deploy-fork snapshot db db-down dev lint typecheck

build:
	forge build

test:
	forge test

unittest:
	forge test --match-path '$(UNIT_TEST_PATH)'

indextest:
	forge test --match-path '$(INDEX_UNIT_TEST_PATH)'

indexmanagertest:
	forge test --match-path '$(INDEX_MANAGER_UNIT_TEST_PATH)'

integrationtest:
	forge test --match-path '$(INTEGRATION_TEST_PATH)'

test-index:
	forge test --match-path test/unit/Index.t.sol

test-indexmanager:
	forge test --match-path '$(INDEX_MANAGER_UNIT_TEST_PATH)'

test-router:
	forge test --match-path test/unit/Router.t.sol

test-swap-manager:
	forge test --match-path test/unit/SwapManager.t.sol

test-single:
	forge test --match-test $(NAME) -vvvv

# Test only IndexManager.t.sol
test-manager:
	@forge test --match-contract IndexManagerTest



# ─── Deploy ──────────────────────────────────────────────────────────────────
# Start the node in another terminal (make anvil / make anvil-fork), then run
# make deploy-anvil / make deploy-fork. Addresses land in deployments/<chainId>.json.

anvil:
	anvil

# Needs an archive RPC: the fork reads state at a past block
anvil-fork:
	@test -n "$(MAINNET_RPC_URL)" || (echo "MAINNET_RPC_URL is not set in .env" && exit 1)
	anvil --fork-url $(MAINNET_RPC_URL) --fork-block-number $(FORK_BLOCK) --chain-id $(FORK_CHAIN_ID)

# --legacy: on the fork anvil forwards eth_feeHistory with reward percentiles to the
# upstream RPC, which may not serve it (503). Legacy gas pricing uses eth_gasPrice instead.
deploy-periphery:
	forge script script/DeployPeriphery.s.sol:DeployPeriphery --rpc-url $(RPC_URL) \
		--broadcast --legacy --private-key $(ANVIL_KEY_0)

deploy-index:
	forge script script/DeployAndInitNewIndex.s.sol:DeployAndInitNewIndex --sig "run()" \
		--rpc-url $(RPC_URL) --broadcast --slow --legacy \
		--private-keys $(ANVIL_KEY_0) --private-keys $(ANVIL_KEY_1) --private-keys $(ANVIL_KEY_2)

# Tops up WETH, WBTC and USDC of the first 10 anvil accounts (FUND_ACCOUNTS / FUND_ACCOUNT_COUNT
# to change them). Fork: balances written straight into storage, no swaps, so the WBTC/WETH pool
# stays aligned with Chainlink. Anvil: mints the mocks listed in deployments/31337.json.
fund:
	forge script script/FundAccounts.s.sol:FundAccounts --rpc-url $(RPC_URL) \
		--broadcast --legacy --private-key $(ANVIL_KEY_0)

# Anvil only: re-publishes the current answer of every mock feed, so it is fresh again
# (needed after anvil-load, when the chain time jumps to the wall clock)
refresh-feeds:
	forge script script/RefreshMockFeeds.s.sol:RefreshMockFeeds --rpc-url $(RPC_URL) \
		--broadcast --legacy --private-key $(ANVIL_KEY_0)

# Fund after the deploy: the mock tokens exist only from then
deploy-anvil: deploy-periphery deploy-index fund

# Fund before the deploy: the deployer needs the assets of the initial deposit
deploy-fork: fund deploy-periphery deploy-index

# ─── Snapshot and dev environment ────────────────────────────────────────────
# Anvil only: on the fork the Chainlink feeds go stale anyway (localHelpers/roadmap.md §6).

# Fresh anvil + deploy + fund, state saved to $(STATE_DIR)/31337.json. Port 8545 must be free.
snapshot:
	STATE_DIR=$(STATE_DIR) bin/snapshot.sh

# Restart from the snapshot, then run make refresh-feeds in another terminal
anvil-load:
	anvil --load-state $(STATE_DIR)/31337.json

# Postgres + chain + contracts + funded accounts. DEV_PROFILE=fork for the mainnet fork.
dev:
	STATE_DIR=$(STATE_DIR) bin/dev.sh

# Local Postgres (docker-compose.yml); data survives db-down
db:
	docker compose up -d --wait

db-down:
	docker compose down

# ─── ABI ─────────────────────────────────────────────────────────────────────

# Regenerate packages/abi/src/generated.ts from the Foundry artifacts
abi:
	npm run abi

# Fail if the generated ABIs differ from the ones staged/committed
check-abi:
	npm run check-abi

# ─── TypeScript ──────────────────────────────────────────────────────────────

lint:
	npm run lint

typecheck:
	npm run typecheck

# ─── Coverage ────────────────────────────────────────────────────────────────

# Usage: make coverage  (shows coverage only for src/ and script/ files)
coverage:
	@forge coverage --report summary 2>&1 | grep -E '(File|^\| src/|^\| script/|^Total)'

# note: need Makefile extension and lcov installed to run this target
coverage-report:
	forge coverage --report lcov --no-match-coverage "test"
	genhtml lcov.info --output-dir coverage && xdg-open coverage/index.html