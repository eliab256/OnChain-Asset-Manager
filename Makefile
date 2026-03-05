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

# ─── Targets ───────────────────────────────────────────────────────────────────
.PHONY: create-index build test

build:
	forge build

test:
	forge test

create-index:
	forge create src/Index.sol:Index \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--constructor-args \
			"$(INDEX_NAME)" \
			"$(INDEX_SYMBOL)" \
			$(ROUTER_ADDRESS) \
			$(USDC_ADDRESS) \
			"($(ASSET0_ADDRESS),$(WEIGHT0),$(ASSET0_PRICEFEED))" \
			"($(ASSET1_ADDRESS),$(WEIGHT1),$(ASSET1_PRICEFEED))" \
			$(FEE_PERCENTAGE)
