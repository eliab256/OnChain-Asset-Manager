-include .env

# ─── Network ───────────────────────────────────────────────────────────────────
RPC_URL 			?= http://localhost:8545
PRIVATE_KEY 		?= 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# ─── Index params ──────────────────────────────────────────────────────────────
INDEX_NAME 			?= BTC-ETH Index
INDEX_SYMBOL 		?= BTCETH

# Weights: 4 decimals precision (e.g. 500000 = 50%)
WEIGHT0 			?= 500000
WEIGHT1 			?= 500000

# Fee: 4 decimals precision (e.g. 1000 = 0.1%, 10000 = 1%)
FEE_PERCENTAGE 		?= 1000

# ─── Addresses (default: Sepolia) ──────────────────────────────────────────────
ROUTER_ADDRESS 		?= 0x0000000000000000000000000000000000000001
USDC_ADDRESS 		?= 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
ASSET0_ADDRESS 		?= 0xDfBBF048075D9db3c34aB34a0843bC16De8c3B3D  # WBTC Sepolia
ASSET0_PRICEFEED 	?= 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43  # WBTC/USD Sepolia
ASSET1_ADDRESS 		?= 0xf531B8F309Be94191af87605CfBf600D71C2cFe0  # WETH Sepolia
ASSET1_PRICEFEED 	?= 0x694AA1769357215DE4FAC081bf1f309aDC325306  # ETH/USD Sepolia

# ─── Test paths ───────────────────────────────────────────────────────────────
UNIT_TEST_PATH 				?= test/unit/**/*.sol
INDEX_UNIT_TEST_PATH 		?= test/unit/IndexUnitTest/*.sol
INDEX_MANAGER_UNIT_TEST_PATH ?= test/unit/IndexmanagerUnitTest/*.sol
INTEGRATION_TEST_PATH 		?= test/integration/**/*.sol
FUZZ_TEST_PATH 			?= test/fuzz/**/*.sol

# ─── Targets ───────────────────────────────────────────────────────────────────
.PHONY: build test unittest indextest indexmanagertest integrationtest fuzztest \
        test-index test-indexmanager test-router test-swap-manager test-single \
        test-manager coverage coverage-report create-index

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



# ─── Coverage ────────────────────────────────────────────────────────────────

# Usage: make coverage  (shows coverage only for src/ and script/ files)
coverage:
	@forge coverage --report summary 2>&1 | grep -E '(File|^\| src/|^\| script/|^Total)'

# note: need Makefile extension and lcov installed to run this target
coverage-report:
	forge coverage --report lcov --no-match-coverage "test"
	genhtml lcov.info --output-dir coverage && xdg-open coverage/index.html