-include .env

# ─── Local networks ────────────────────────────────────────────────────────────
RPC_URL 			?= http://127.0.0.1:8545
# Fork of mainnet at the same block as the fork tests (test/integration/ForkConstants.sol),
# with its own chain id so nothing can be confused with or replayed on mainnet.
FORK_BLOCK 			?= 26178000
FORK_CHAIN_ID 		?= 31338

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
        abi check-abi anvil anvil-fork deploy-periphery deploy-index fund-fork \
        deploy-anvil deploy-fork

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

# Writes WETH, WBTC and USDC balances of the deployer straight into storage (no swaps,
# so the WBTC/WETH pool stays aligned with Chainlink). Runs only on the fork chain id.
fund-fork:
	forge script script/FundForkAccount.s.sol:FundForkAccount --rpc-url $(RPC_URL)

deploy-anvil: deploy-periphery deploy-index

deploy-fork: fund-fork deploy-periphery deploy-index

# ─── ABI ─────────────────────────────────────────────────────────────────────

# Regenerate packages/abi/src/generated.ts from the Foundry artifacts
abi:
	npm run abi

# Fail if the generated ABIs differ from the ones staged/committed
check-abi:
	npm run check-abi

# ─── Coverage ────────────────────────────────────────────────────────────────

# Usage: make coverage  (shows coverage only for src/ and script/ files)
coverage:
	@forge coverage --report summary 2>&1 | grep -E '(File|^\| src/|^\| script/|^Total)'

# note: need Makefile extension and lcov installed to run this target
coverage-report:
	forge coverage --report lcov --no-match-coverage "test"
	genhtml lcov.info --output-dir coverage && xdg-open coverage/index.html