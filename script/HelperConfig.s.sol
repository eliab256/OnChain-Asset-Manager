//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CodeConstants} from "./CodeConstants.sol";
import {Script} from "forge-std/Script.sol";
import {IndexAsset} from "../src/types.sol";
import {MockUSDC} from "../test/mocks/USDCMock.sol";
import {AssetTokenMock} from "../test/mocks/AssetTokenMock.sol";
import {
    MockV3Aggregator
} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {IndexAsset, TokenAvailable} from "../src/types.sol";

struct TokenConfig {
    address token;
    address priceFeed;
}

struct NetworkConfig {
    address usdcAddress;
    address deployerAccount;
    address feeCollector;
    address rebalancer;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();
    error HelperConfig__InvalidIndexConfig();

    NetworkConfig public activeNetworkConfig;

    mapping(TokenAvailable => mapping(uint256 => TokenConfig))
        public tokenConfigByChainId;

    /**
     * @notice Initializes HelperConfig and sets active network configuration based on current chain
     * @dev Automatically detects chain ID and loads appropriate configuration
     * @dev Reverts with HelperConfig__InvalidChainId if chain is not supported
     */
    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaConfig();
        } else if (block.chainid == ANVIL_CHAIN_ID) {
            activeNetworkConfig = getAnvilConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }
    function getActiveNetworkConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        return activeNetworkConfig;
    }

    function getActiveTokenConfig(
        TokenAvailable token
    ) public view returns (TokenConfig memory) {
        return tokenConfigByChainId[token][block.chainid];
    }
    /**
     * @notice Returns network configuration for Sepolia testnet
     * @return NetworkConfig Configuration struct with Sepolia testnet parameters
     */
    function getSepoliaConfig() public returns (NetworkConfig memory) {
        tokenConfigByChainId[TokenAvailable.USDC][
            SEPOLIA_CHAIN_ID
        ] = TokenConfig({
            token: USDC_SEPOLIA,
            priceFeed: USDC_USD_PRICEFEED_SEPOLIA
        });

        tokenConfigByChainId[TokenAvailable.WETH][
            SEPOLIA_CHAIN_ID
        ] = TokenConfig({
            token: WETH_SEPOLIA,
            priceFeed: WETH_USD_PRICEFEED_SEPOLIA
        });

        tokenConfigByChainId[TokenAvailable.WBTC][
            SEPOLIA_CHAIN_ID
        ] = TokenConfig({
            token: WBTC_SEPOLIA,
            priceFeed: WBTC_USD_PRICEFEED_SEPOLIA
        });

        tokenConfigByChainId[TokenAvailable.LINK][
            SEPOLIA_CHAIN_ID
        ] = TokenConfig({
            token: LINK_SEPOLIA,
            priceFeed: LINK_USD_PRICEFEED_SEPOLIA
        });
        return
            NetworkConfig({
                usdcAddress: USDC_SEPOLIA,
                deployerAccount: SEPOLIA_DEPLOYER,
                feeCollector: SEPOLIA_DEPLOYER,
                rebalancer: SEPOLIA_DEPLOYER
            });
    }

    /**
     * @notice Returns network configuration for Anvil local development network
     * @return NetworkConfig Configuration struct with Anvil local development network parameters
     */
    function getAnvilConfig() public returns (NetworkConfig memory) {
        MockUSDC mockUsdc = new MockUSDC();
        AssetTokenMock mockWeth = new AssetTokenMock(
            "Wrapped Ether",
            "WETH",
            18
        );
        AssetTokenMock mockWbtc = new AssetTokenMock(
            "Wrapped Bitcoin",
            "WBTC",
            8
        );
        AssetTokenMock mockLink = new AssetTokenMock(
            "Chainlink Token",
            "LINK",
            18
        );

        MockV3Aggregator mockWethPriceFeed = new MockV3Aggregator(
            PRICE_FEED_DECIMALS,
            int256(2000 * 10 ** PRICE_FEED_DECIMALS)
        );
        MockV3Aggregator mockUsdcPriceFeed = new MockV3Aggregator(
            PRICE_FEED_DECIMALS,
            int256(1 * 10 ** PRICE_FEED_DECIMALS)
        );
        MockV3Aggregator mockWbtcPriceFeed = new MockV3Aggregator(
            PRICE_FEED_DECIMALS,
            int256(30000 * 10 ** PRICE_FEED_DECIMALS)
        );
        MockV3Aggregator mockLinkPriceFeed = new MockV3Aggregator(
            PRICE_FEED_DECIMALS,
            int256(7 * 10 ** PRICE_FEED_DECIMALS)
        );

        tokenConfigByChainId[TokenAvailable.USDC][
            ANVIL_CHAIN_ID
        ] = TokenConfig({
            token: address(mockUsdc),
            priceFeed: address(mockUsdcPriceFeed)
        });

        tokenConfigByChainId[TokenAvailable.WETH][
            ANVIL_CHAIN_ID
        ] = TokenConfig({
            token: address(mockWeth),
            priceFeed: address(mockWethPriceFeed)
        });

        tokenConfigByChainId[TokenAvailable.WBTC][
            ANVIL_CHAIN_ID
        ] = TokenConfig({
            token: address(mockWbtc),
            priceFeed: address(mockWbtcPriceFeed)
        });

        tokenConfigByChainId[TokenAvailable.LINK][
            ANVIL_CHAIN_ID
        ] = TokenConfig({
            token: address(mockLink),
            priceFeed: address(mockLinkPriceFeed)
        });

        address anvilFeeCollector = makeAddr("feeCollector");
        address anvilRebalancer = makeAddr("rebalancer");

        return
            NetworkConfig({
                usdcAddress: address(mockUsdc),
                deployerAccount: ANVIL_DEPLOYER,
                feeCollector: anvilFeeCollector,
                rebalancer: anvilRebalancer
            });
    }
    /**
     * @notice Returns network configuration for a specific chain ID
     * @dev Allows retrieving configuration for chains other than the current one
     * @dev Useful for testing deployment on multiple chains
     * @param chainId The chain ID to get configuration for
     * @return NetworkConfig Configuration struct for the specified chain
     * @custom:throws HelperConfig__InvalidChainId if chainId is not supported
     */
    function getConfigByChainId(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        if (chainId == SEPOLIA_CHAIN_ID) {
            return getSepoliaConfig();
        } else if (chainId == ANVIL_CHAIN_ID) {
            return getAnvilConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    //Helpers
    function getFeeCollector() public view returns (address) {
        return activeNetworkConfig.feeCollector;
    }

    function getRebalancer() public view returns (address) {
        return activeNetworkConfig.rebalancer;
    }

    function getAssetTokenMocks()
        public
        view
        returns (AssetTokenMock, MockUSDC, AssetTokenMock, AssetTokenMock)
    {
        TokenConfig memory usdcConfig = getActiveTokenConfig(
            TokenAvailable.USDC
        );
        TokenConfig memory wethConfig = getActiveTokenConfig(
            TokenAvailable.WETH
        );
        TokenConfig memory wbtcConfig = getActiveTokenConfig(
            TokenAvailable.WBTC
        );
        TokenConfig memory linkConfig = getActiveTokenConfig(
            TokenAvailable.LINK
        );

        return (
            AssetTokenMock(wethConfig.token),
            MockUSDC(usdcConfig.token),
            AssetTokenMock(wbtcConfig.token),
            AssetTokenMock(linkConfig.token)
        );
    }

    function getPriceFeedMocks()
        public
        view
        returns (
            MockV3Aggregator,
            MockV3Aggregator,
            MockV3Aggregator,
            MockV3Aggregator
        )
    {
        TokenConfig memory usdcConfig = getActiveTokenConfig(
            TokenAvailable.USDC
        );
        TokenConfig memory wethConfig = getActiveTokenConfig(
            TokenAvailable.WETH
        );
        TokenConfig memory wbtcConfig = getActiveTokenConfig(
            TokenAvailable.WBTC
        );
        TokenConfig memory linkConfig = getActiveTokenConfig(
            TokenAvailable.LINK
        );

        return (
            MockV3Aggregator(wethConfig.priceFeed),
            MockV3Aggregator(usdcConfig.priceFeed),
            MockV3Aggregator(wbtcConfig.priceFeed),
            MockV3Aggregator(linkConfig.priceFeed)
        );
    }
}
