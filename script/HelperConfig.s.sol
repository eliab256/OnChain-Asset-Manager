//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CodeConstants} from "./CodeConstants.sol";
import {Script} from "forge-std/Script.sol";
import {MockUSDC} from "../test/mocks/USDCMock.sol";
import {UniversalRouterMock} from "../test/mocks/UniversalRouterMock.sol";
import {AssetTokenMock} from "../test/mocks/AssetTokenMock.sol";
import {
    MockV3Aggregator
} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {AssetAvailable, PoolVersion, SwapRoute} from "../src/types.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

struct AssetConfig {
    address token;
    address priceFeed;
}

struct NetworkConfig {
    address usdcAddress;
    address usdcPriceFeedAddress;
    address uniswapUniversalRouter;
    address deployerAccount;
    address feeCollector;
    address rebalancer;
    address[] multiSigOwners;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();
    error HelperConfig__InvalidIndexConfig();
    error HelperConfig__GetRealContractsOnMainnet();

    uint24 public constant DEFAULT_V4_POOL_FEE = 3000;
    int24 public constant DEFAULT_V4_TICK_SPACING = 60;
    uint24 public constant DEFAULT_V3_POOL_FEE = 3000;

    NetworkConfig public activeNetworkConfig;

    mapping(AssetAvailable => mapping(uint256 => AssetConfig))
        public assetConfigByChainId;

    /**
     * @notice Initializes HelperConfig and sets active network configuration based on current chain
     * @dev Automatically detects chain ID and loads appropriate configuration
     * @dev Reverts with HelperConfig__InvalidChainId if chain is not supported
     */
    constructor() {
        if (block.chainid == MAINNET_CHAIN_ID) {
            activeNetworkConfig = getMainnetConfig();
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

    function getActiveAssetConfig(
        AssetAvailable asset
    ) public view returns (AssetConfig memory) {
        return assetConfigByChainId[asset][block.chainid];
    }
    /**
     * @notice Returns network configuration for Ethereum mainnet.
     * @return NetworkConfig Configuration struct with Ethereum mainnet parameters.
     */
    function getMainnetConfig() public returns (NetworkConfig memory) {
        address mainnetDeployer = vm.envAddress("MAINNET_DEPLOYER");

        address[] memory owners = new address[](3);
        owners[0] = vm.envAddress("MULTISIG_OWNER_1");
        owners[1] = vm.envAddress("MULTISIG_OWNER_2");
        owners[2] = vm.envAddress("MULTISIG_OWNER_3");

        assetConfigByChainId[AssetAvailable.WETH][
            MAINNET_CHAIN_ID
        ] = AssetConfig({
            token: WETH_MAINNET,
            priceFeed: WETH_USD_PRICEFEED_MAINNET
        });

        assetConfigByChainId[AssetAvailable.WBTC][
            MAINNET_CHAIN_ID
        ] = AssetConfig({
            token: WBTC_MAINNET,
            priceFeed: WBTC_USD_PRICEFEED_MAINNET
        });

        assetConfigByChainId[AssetAvailable.LINK][
            MAINNET_CHAIN_ID
        ] = AssetConfig({
            token: LINK_MAINNET,
            priceFeed: LINK_USD_PRICEFEED_MAINNET
        });

        assetConfigByChainId[AssetAvailable.COMP][
            MAINNET_CHAIN_ID
        ] = AssetConfig({
            token: COMP_MAINNET,
            priceFeed: COMP_USD_PRICEFEED_MAINNET
        });
        return
            NetworkConfig({
                usdcAddress: USDC_MAINNET,
                usdcPriceFeedAddress: USDC_USD_PRICEFEED_MAINNET,
                uniswapUniversalRouter: UNISWAP_V4_UNIVERSAL_ROUTER_MAINNET,
                deployerAccount: mainnetDeployer,
                feeCollector: mainnetDeployer,
                rebalancer: mainnetDeployer,
                multiSigOwners: owners
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
        AssetTokenMock mockComp = new AssetTokenMock("Compound", "COMP", 18);

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
        MockV3Aggregator mockCompPriceFeed = new MockV3Aggregator(
            PRICE_FEED_DECIMALS,
            int256(50 * 10 ** PRICE_FEED_DECIMALS)
        );

        assetConfigByChainId[AssetAvailable.WETH][
            ANVIL_CHAIN_ID
        ] = AssetConfig({
            token: address(mockWeth),
            priceFeed: address(mockWethPriceFeed)
        });

        assetConfigByChainId[AssetAvailable.WBTC][
            ANVIL_CHAIN_ID
        ] = AssetConfig({
            token: address(mockWbtc),
            priceFeed: address(mockWbtcPriceFeed)
        });

        assetConfigByChainId[AssetAvailable.LINK][
            ANVIL_CHAIN_ID
        ] = AssetConfig({
            token: address(mockLink),
            priceFeed: address(mockLinkPriceFeed)
        });

        assetConfigByChainId[AssetAvailable.COMP][
            ANVIL_CHAIN_ID
        ] = AssetConfig({
            token: address(mockComp),
            priceFeed: address(mockCompPriceFeed)
        });

        UniversalRouterMock mockUniRouter = new UniversalRouterMock();

        address anvilFeeCollector = makeAddr("feeCollector");
        address anvilRebalancer = makeAddr("rebalancer");

        address[] memory owners = new address[](3);
        owners[0] = ANVIL_OWNER_1;
        owners[1] = ANVIL_OWNER_2;
        owners[2] = ANVIL_OWNER_3;

        return
            NetworkConfig({
                usdcAddress: address(mockUsdc),
                usdcPriceFeedAddress: address(mockUsdcPriceFeed),
                uniswapUniversalRouter: address(mockUniRouter),
                deployerAccount: ANVIL_DEPLOYER,
                feeCollector: anvilFeeCollector,
                rebalancer: anvilRebalancer,
                multiSigOwners: owners
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
        if (chainId == MAINNET_CHAIN_ID) {
            return getMainnetConfig();
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

    /**
     * @notice Returns the default swap routes for a pair of sorted index assets.
     * @dev The generated routes assume Uniswap V4 pools with no hooks, fee tier 3000, and tick spacing 60.
     * @param _asset0 The sorted asset0 token address.
     * @param _asset1 The sorted asset1 token address.
     * @return routeAsset0Usdc The default route for Asset0 ↔ USDC swaps.
     * @return routeAsset1Usdc The default route for Asset1 ↔ USDC swaps.
     * @return routeAsset0Asset1 The default route for Asset0 ↔ Asset1 swaps.
     */
    function getDefaultSwapRoutes(
        address _asset0,
        address _asset1
    )
        public
        view
        returns (
            SwapRoute memory routeAsset0Usdc,
            SwapRoute memory routeAsset1Usdc,
            SwapRoute memory routeAsset0Asset1
        )
    {
        // USDC ↔ asset routes use V3 (deep, established liquidity).
        routeAsset0Usdc = _buildDefaultV3Route(
            _asset0,
            activeNetworkConfig.usdcAddress
        );
        routeAsset1Usdc = _buildDefaultV3Route(
            _asset1,
            activeNetworkConfig.usdcAddress
        );
        // Asset ↔ asset route also uses V3 (V4 pools currently lack
        // sufficient liquidity on mainnet).
        routeAsset0Asset1 = _buildDefaultV3Route(_asset0, _asset1);
    }

    /**
     * @notice Builds a default Uniswap V4 route for two tokens.
     * @dev Tokens are sorted to satisfy the `PoolKey` requirement.
     * @param _tokenA The first token address.
     * @param _tokenB The second token address.
     * @return route The generated V4 route.
     */
    function buildDefaultV4Route(
        address _tokenA,
        address _tokenB
    ) public pure returns (SwapRoute memory route) {
        return _buildDefaultV4Route(_tokenA, _tokenB);
    }

    function _buildDefaultV4Route(
        address _tokenA,
        address _tokenB
    ) internal pure returns (SwapRoute memory route) {
        (address currency0, address currency1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);

        route = SwapRoute({
            version: PoolVersion.V4,
            poolKey: PoolKey({
                currency0: Currency.wrap(currency0),
                currency1: Currency.wrap(currency1),
                fee: DEFAULT_V4_POOL_FEE,
                tickSpacing: DEFAULT_V4_TICK_SPACING,
                hooks: IHooks(address(0))
            }),
            v3Path: bytes("")
        });
    }

    /**
     * @notice Builds a default Uniswap V3 route for two tokens.
     * @dev The path is encoded as: tokenA (20 bytes) + fee (3 bytes) + tokenB (20 bytes).
     *      Direction is adjusted at swap time by SwapManager._getDirectionalV3Path.
     * @param _tokenA The first token address.
     * @param _tokenB The second token address.
     * @return route The generated V3 route.
     */
    function _buildDefaultV3Route(
        address _tokenA,
        address _tokenB
    ) internal pure returns (SwapRoute memory route) {
        route = SwapRoute({
            version: PoolVersion.V3,
            poolKey: PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(0)),
                fee: 0,
                tickSpacing: 0,
                hooks: IHooks(address(0))
            }),
            v3Path: abi.encodePacked(_tokenA, DEFAULT_V3_POOL_FEE, _tokenB)
        });
    }

    function getAssetTokenMocks()
        public
        view
        returns (
            AssetTokenMock,
            MockUSDC,
            AssetTokenMock,
            AssetTokenMock,
            AssetTokenMock
        )
    {
        if (block.chainid != ANVIL_CHAIN_ID) {
            revert HelperConfig__GetRealContractsOnMainnet();
        }
        AssetConfig memory wethConfig = getActiveAssetConfig(
            AssetAvailable.WETH
        );
        AssetConfig memory wbtcConfig = getActiveAssetConfig(
            AssetAvailable.WBTC
        );
        AssetConfig memory linkConfig = getActiveAssetConfig(
            AssetAvailable.LINK
        );
        AssetConfig memory compConfig = getActiveAssetConfig(
            AssetAvailable.COMP
        );

        return (
            AssetTokenMock(wethConfig.token),
            MockUSDC(activeNetworkConfig.usdcAddress),
            AssetTokenMock(wbtcConfig.token),
            AssetTokenMock(linkConfig.token),
            AssetTokenMock(compConfig.token)
        );
    }

    function getPriceFeedMocks()
        public
        view
        returns (
            MockV3Aggregator,
            MockV3Aggregator,
            MockV3Aggregator,
            MockV3Aggregator,
            MockV3Aggregator
        )
    {
        if (block.chainid != ANVIL_CHAIN_ID) {
            revert HelperConfig__GetRealContractsOnMainnet();
        }
        AssetConfig memory wethConfig = getActiveAssetConfig(
            AssetAvailable.WETH
        );
        AssetConfig memory wbtcConfig = getActiveAssetConfig(
            AssetAvailable.WBTC
        );
        AssetConfig memory linkConfig = getActiveAssetConfig(
            AssetAvailable.LINK
        );
        AssetConfig memory compConfig = getActiveAssetConfig(
            AssetAvailable.COMP
        );

        return (
            MockV3Aggregator(wethConfig.priceFeed),
            MockV3Aggregator(activeNetworkConfig.usdcPriceFeedAddress),
            MockV3Aggregator(wbtcConfig.priceFeed),
            MockV3Aggregator(linkConfig.priceFeed),
            MockV3Aggregator(compConfig.priceFeed)
        );
    }

    function getUniswapUniversalRouter()
        public
        view
        returns (UniversalRouterMock)
    {
        return UniversalRouterMock(activeNetworkConfig.uniswapUniversalRouter);
    }
}
