// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {
    HelperConfig,
    AssetConfig,
    NetworkConfig
} from "../../../script/HelperConfig.s.sol";
import {CodeConstants} from "../../../script/CodeConstants.sol";
import {AssetAvailable, SwapRoute, PoolVersion} from "../../../src/types.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract HelperConfigTest is Test, CodeConstants {
    HelperConfig public anvilHelperConfig;
    HelperConfig public mainnetHelperConfig;

    uint256 mainnetForkId;

    modifier onAnvilFork() {
        anvilHelperConfig = new HelperConfig();
        _;
    }

    modifier onMainnetFork() {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        mainnetHelperConfig = new HelperConfig();
        _;
    }

    function setUp() public {}

    function testGetActiveNetworkConfigOnAnvil() public onAnvilFork {
        // On Anvil: verify all fields are populated with non-zero mock addresses
        assertEq(block.chainid, 31337, "Should be on Anvil fork");
        NetworkConfig memory config = anvilHelperConfig
            .getActiveNetworkConfig();

        assertNotEq(
            config.usdcAddress,
            address(0),
            "USDC address must not be zero"
        );
        assertNotEq(
            config.usdcPriceFeedAddress,
            address(0),
            "USDC price feed must not be zero"
        );
        assertNotEq(
            config.uniswapUniversalRouter,
            address(0),
            "Router must not be zero"
        );
        assertEq(
            config.deployerAccount,
            ANVIL_DEPLOYER,
            "Deployer must be Anvil default"
        );
        assertNotEq(
            config.feeCollector,
            address(0),
            "Fee collector must not be zero"
        );
        assertNotEq(
            config.rebalancer,
            address(0),
            "Rebalancer must not be zero"
        );

        // Verify asset configs are populated for all supported assets
        AssetConfig memory weth = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.WETH
        );
        AssetConfig memory wbtc = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.WBTC
        );
        AssetConfig memory link = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.LINK
        );
        AssetConfig memory usdc = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.USDC
        );

        assertNotEq(
            weth.token,
            WETH_MAINNET,
            "WETH token must not be mainnet address"
        );
        assertNotEq(
            weth.priceFeed,
            WETH_USD_PRICEFEED_MAINNET,
            "WETH feed must not be mainnet address"
        );
        assertNotEq(
            wbtc.token,
            WBTC_MAINNET,
            "WBTC token must not be mainnet address"
        );
        assertNotEq(
            wbtc.priceFeed,
            WBTC_USD_PRICEFEED_MAINNET,
            "WBTC feed must not be mainnet address"
        );
        assertNotEq(
            link.token,
            LINK_MAINNET,
            "LINK token must not be mainnet address"
        );
        assertNotEq(
            link.priceFeed,
            LINK_USD_PRICEFEED_MAINNET,
            "LINK feed must not be mainnet address"
        );
        assertNotEq(
            usdc.token,
            USDC_MAINNET,
            "USDC token must not be mainnet address"
        );
        assertNotEq(
            usdc.priceFeed,
            USDC_USD_PRICEFEED_MAINNET,
            "USDC feed must not be mainnet address"
        );
    }

    function testGetActiveNetworkConfigOnMainnet() public onMainnetFork {
        // Verify network config points to real mainnet contracts
        NetworkConfig memory config = mainnetHelperConfig
            .getActiveNetworkConfig();

        assertEq(
            config.usdcAddress,
            USDC_MAINNET,
            "USDC must be mainnet address"
        );
        assertEq(
            config.usdcPriceFeedAddress,
            USDC_USD_PRICEFEED_MAINNET,
            "USDC feed must be mainnet"
        );
        assertEq(
            config.uniswapUniversalRouter,
            UNISWAP_V4_UNIVERSAL_ROUTER_MAINNET,
            "Router must be mainnet"
        );

        // Verify asset configs point to real mainnet contracts
        AssetConfig memory weth = mainnetHelperConfig.getActiveAssetConfig(
            AssetAvailable.WETH
        );
        AssetConfig memory wbtc = mainnetHelperConfig.getActiveAssetConfig(
            AssetAvailable.WBTC
        );
        AssetConfig memory link = mainnetHelperConfig.getActiveAssetConfig(
            AssetAvailable.LINK
        );
        AssetConfig memory usdc = mainnetHelperConfig.getActiveAssetConfig(
            AssetAvailable.USDC
        );

        assertEq(weth.token, WETH_MAINNET, "WETH token must be mainnet");
        assertEq(
            weth.priceFeed,
            WETH_USD_PRICEFEED_MAINNET,
            "WETH feed must be mainnet"
        );
        assertEq(wbtc.token, WBTC_MAINNET, "WBTC token must be mainnet");
        assertEq(
            wbtc.priceFeed,
            WBTC_USD_PRICEFEED_MAINNET,
            "WBTC feed must be mainnet"
        );
        assertEq(link.token, LINK_MAINNET, "LINK token must be mainnet");
        assertEq(
            link.priceFeed,
            LINK_USD_PRICEFEED_MAINNET,
            "LINK feed must be mainnet"
        );
        assertEq(usdc.token, USDC_MAINNET, "USDC token must be mainnet");
        assertEq(
            usdc.priceFeed,
            USDC_USD_PRICEFEED_MAINNET,
            "USDC feed must be mainnet"
        );
    }

    function testHelperConfigRevertIfUnsupportedChain() public {
        // Create and select a fork of an unsupported chain (e.g., Polygon)
        vm.createSelectFork(vm.rpcUrl("polygon"));

        // Expect the constructor to revert with the correct error message
        vm.expectRevert(HelperConfig.HelperConfig__InvalidChainId.selector);
        HelperConfig unsupportedHelperConfig = new HelperConfig();
    }

    function testGetActiveAssetConfigWorksOnAnvil() public onAnvilFork {
        AssetConfig memory wethConfig = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.WETH
        );
        assertNotEq(
            wethConfig.token,
            address(0),
            "WETH token must not be zero"
        );
        assertNotEq(
            wethConfig.priceFeed,
            address(0),
            "WETH price feed must not be zero"
        );
    }

    function testGetActiveAssetConfigWorksOnMainnet() public onMainnetFork {
        AssetConfig memory wethConfig = mainnetHelperConfig
            .getActiveAssetConfig(AssetAvailable.WETH);
        assertEq(
            wethConfig.token,
            WETH_MAINNET,
            "WETH token must be mainnet address"
        );
        assertEq(
            wethConfig.priceFeed,
            WETH_USD_PRICEFEED_MAINNET,
            "WETH price feed must be mainnet address"
        );
    }

    function testGetFeeCollectorOnAnvil() public onAnvilFork {
        address feeCollector = anvilHelperConfig.getFeeCollector();
        assertEq(
            feeCollector,
            anvilHelperConfig.getActiveNetworkConfig().feeCollector,
            "Fee collector must match active network config"
        );
        assertEq(
            feeCollector,
            makeAddr("feeCollector"),
            "Fee collector must match makeAddr('feeCollector')"
        );
    }

    function testGetRebalancerOnAnvil() public onAnvilFork {
        address rebalancer = anvilHelperConfig.getRebalancer();
        assertEq(
            rebalancer,
            anvilHelperConfig.getActiveNetworkConfig().rebalancer,
            "Rebalancer must match active network config"
        );
        assertEq(
            rebalancer,
            makeAddr("rebalancer"),
            "Rebalancer must match makeAddr('rebalancer')"
        );
    }

    function testGetFeeCollectorOnMainnet() public onMainnetFork {
        address feeCollector = mainnetHelperConfig.getFeeCollector();
        assertEq(
            feeCollector,
            mainnetHelperConfig.getActiveNetworkConfig().feeCollector,
            "Fee collector must match active network config"
        );
        address expectedDeployer = vm.envAddress("MAINNET_DEPLOYER");
        assertEq(
            feeCollector,
            expectedDeployer,
            "Fee collector must match MAINNET_DEPLOYER from .env"
        );
    }

    function testGetRebalancerOnMainnet() public onMainnetFork {
        address rebalancer = mainnetHelperConfig.getRebalancer();
        assertEq(
            rebalancer,
            mainnetHelperConfig.getActiveNetworkConfig().rebalancer,
            "Rebalancer must match active network config"
        );
        address expectedDeployer = vm.envAddress("MAINNET_DEPLOYER");
        assertEq(
            rebalancer,
            expectedDeployer,
            "Rebalancer must match MAINNET_DEPLOYER from .env"
        );
    }

    // ──────────────────────────────────────────────
    //  buildDefaultV4Route
    // ──────────────────────────────────────────────

    function testBuildDefaultV4RouteSortsCurrencies() public onAnvilFork {
        address tokenA = makeAddr("tokenA"); // higher address
        address tokenB = address(1); // lower address

        SwapRoute memory route = anvilHelperConfig.buildDefaultV4Route(
            tokenA,
            tokenB
        );

        // currency0 must be the lower address
        assertEq(
            Currency.unwrap(route.poolKey.currency0),
            tokenB,
            "currency0 must be lower address"
        );
        assertEq(
            Currency.unwrap(route.poolKey.currency1),
            tokenA,
            "currency1 must be higher address"
        );
    }

    function testBuildDefaultV4RouteSetsCorrectPoolParams() public onAnvilFork {
        address tokenA = makeAddr("tokenA");
        address tokenB = makeAddr("tokenB");

        SwapRoute memory route = anvilHelperConfig.buildDefaultV4Route(
            tokenA,
            tokenB
        );

        assertEq(
            uint8(route.version),
            uint8(PoolVersion.V4),
            "Version must be V4"
        );
        assertEq(route.poolKey.fee, 3000, "Fee must be 3000");
        assertEq(route.poolKey.tickSpacing, 60, "Tick spacing must be 60");
        assertEq(
            address(route.poolKey.hooks),
            address(0),
            "Hooks must be zero address"
        );
        assertEq(route.v3Path.length, 0, "v3Path must be empty for V4 route");
    }

    function testBuildDefaultV4RouteIsSymmetric() public onAnvilFork {
        address tokenA = makeAddr("tokenA");
        address tokenB = makeAddr("tokenB");

        SwapRoute memory routeAB = anvilHelperConfig.buildDefaultV4Route(
            tokenA,
            tokenB
        );
        SwapRoute memory routeBA = anvilHelperConfig.buildDefaultV4Route(
            tokenB,
            tokenA
        );

        assertEq(
            Currency.unwrap(routeAB.poolKey.currency0),
            Currency.unwrap(routeBA.poolKey.currency0),
            "currency0 must be equal regardless of argument order"
        );
        assertEq(
            Currency.unwrap(routeAB.poolKey.currency1),
            Currency.unwrap(routeBA.poolKey.currency1),
            "currency1 must be equal regardless of argument order"
        );
    }

    // ──────────────────────────────────────────────
    //  getDefaultSwapRoutes
    // ──────────────────────────────────────────────

    function testGetDefaultSwapRoutesReturnsThreeRoutes() public onAnvilFork {
        AssetConfig memory wethCfg = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.WETH
        );
        AssetConfig memory linkCfg = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.LINK
        );

        // Sort assets like the production code expects
        (address asset0, address asset1) = wethCfg.token < linkCfg.token
            ? (wethCfg.token, linkCfg.token)
            : (linkCfg.token, wethCfg.token);

        (
            SwapRoute memory routeAsset0Usdc,
            SwapRoute memory routeAsset1Usdc,
            SwapRoute memory routeAsset0Asset1
        ) = anvilHelperConfig.getDefaultSwapRoutes(asset0, asset1);

        // All three must be V4
        assertEq(
            uint8(routeAsset0Usdc.version),
            uint8(PoolVersion.V4),
            "Route0-USDC must be V4"
        );
        assertEq(
            uint8(routeAsset1Usdc.version),
            uint8(PoolVersion.V4),
            "Route1-USDC must be V4"
        );
        assertEq(
            uint8(routeAsset0Asset1.version),
            uint8(PoolVersion.V4),
            "Route0-1 must be V4"
        );
    }

    function testGetDefaultSwapRoutesAsset0UsdcContainsCorrectPair()
        public
        onAnvilFork
    {
        AssetConfig memory wethCfg = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.WETH
        );
        AssetConfig memory linkCfg = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.LINK
        );
        NetworkConfig memory config = anvilHelperConfig
            .getActiveNetworkConfig();

        (address asset0, address asset1) = wethCfg.token < linkCfg.token
            ? (wethCfg.token, linkCfg.token)
            : (linkCfg.token, wethCfg.token);

        (SwapRoute memory routeAsset0Usdc, , ) = anvilHelperConfig
            .getDefaultSwapRoutes(asset0, asset1);

        // The pool key must contain asset0 and usdc (sorted)
        address c0 = Currency.unwrap(routeAsset0Usdc.poolKey.currency0);
        address c1 = Currency.unwrap(routeAsset0Usdc.poolKey.currency1);

        assertTrue(
            (c0 == asset0 && c1 == config.usdcAddress) ||
                (c0 == config.usdcAddress && c1 == asset0),
            "Route asset0-USDC must contain asset0 and USDC"
        );
        // Sorted invariant
        assertTrue(c0 < c1, "currency0 must be less than currency1");
    }

    function testGetDefaultSwapRoutesAsset1UsdcContainsCorrectPair()
        public
        onAnvilFork
    {
        AssetConfig memory wethCfg = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.WETH
        );
        AssetConfig memory linkCfg = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.LINK
        );
        NetworkConfig memory config = anvilHelperConfig
            .getActiveNetworkConfig();

        (address asset0, address asset1) = wethCfg.token < linkCfg.token
            ? (wethCfg.token, linkCfg.token)
            : (linkCfg.token, wethCfg.token);

        (, SwapRoute memory routeAsset1Usdc, ) = anvilHelperConfig
            .getDefaultSwapRoutes(asset0, asset1);

        address c0 = Currency.unwrap(routeAsset1Usdc.poolKey.currency0);
        address c1 = Currency.unwrap(routeAsset1Usdc.poolKey.currency1);

        assertTrue(
            (c0 == asset1 && c1 == config.usdcAddress) ||
                (c0 == config.usdcAddress && c1 == asset1),
            "Route asset1-USDC must contain asset1 and USDC"
        );
        assertTrue(c0 < c1, "currency0 must be less than currency1");
    }

    function testGetDefaultSwapRoutesAsset0Asset1ContainsCorrectPair()
        public
        onAnvilFork
    {
        AssetConfig memory wethCfg = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.WETH
        );
        AssetConfig memory linkCfg = anvilHelperConfig.getActiveAssetConfig(
            AssetAvailable.LINK
        );

        (address asset0, address asset1) = wethCfg.token < linkCfg.token
            ? (wethCfg.token, linkCfg.token)
            : (linkCfg.token, wethCfg.token);

        (, , SwapRoute memory routeAsset0Asset1) = anvilHelperConfig
            .getDefaultSwapRoutes(asset0, asset1);

        address c0 = Currency.unwrap(routeAsset0Asset1.poolKey.currency0);
        address c1 = Currency.unwrap(routeAsset0Asset1.poolKey.currency1);

        assertEq(c0, asset0, "currency0 must be asset0 (already sorted)");
        assertEq(c1, asset1, "currency1 must be asset1 (already sorted)");
    }

    function testGetAssetTokenMocksRevertIfNotAnvil() public onMainnetFork {
        vm.expectRevert(HelperConfig.HelperConfig__GetRealContractsOnMainnet.selector);
        mainnetHelperConfig.getAssetTokenMocks();
    }


    function testGetPriceFeedMocksRevertIfNotAnvil() public onMainnetFork {
        vm.expectRevert(HelperConfig.HelperConfig__GetRealContractsOnMainnet.selector);
        mainnetHelperConfig.getPriceFeedMocks();
    }
}
