// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {SwapManager} from "../../src/SwapManager.sol";
import {SwapType, SwapRoute, PoolVersion} from "../../src/types.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract SwapManagerTest is BaseTest {
    // =========================================================================
    //  Constants
    // =========================================================================

    /// Uniswap V4 swap command byte (Commands.V4_SWAP)
    uint8 constant V4_SWAP_COMMAND = 0x10;

    /// Uniswap V3 exact-in swap command byte (Commands.V3_SWAP_EXACT_IN)
    uint8 constant V3_SWAP_EXACT_IN_COMMAND = 0x00;

    /// Default V4 pool fee tier matching HelperConfig.DEFAULT_V4_POOL_FEE
    uint24 constant DEFAULT_V4_POOL_FEE = 3000;

    /// Default V4 tick spacing matching HelperConfig.DEFAULT_V4_TICK_SPACING
    int24 constant DEFAULT_V4_TICK_SPACING = 60;

    /// Fee tier used in V3 path encoding for tests
    uint24 constant V3_POOL_FEE = 3000;

    /// Minimum valid V3 path length: 20 (tokenIn) + 3 (fee) + 20 (tokenOut)
    uint256 constant MIN_V3_PATH_LENGTH = 43;

    /// Expected commands array length for a single swap
    uint256 constant SINGLE_SWAP_COMMANDS_LENGTH = 1;

    /// Expected commands array length for a double swap
    uint256 constant DOUBLE_SWAP_COMMANDS_LENGTH = 2;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();
        // initializedIndex already has V4 routes registered via Base.setUp().
        // nonInitializedIndex has NO routes in SwapManager.
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev Builds a valid V4 SwapRoute for two tokens (sorted internally).
    function _buildV4Route(
        address _tokenA,
        address _tokenB
    ) internal pure returns (SwapRoute memory) {
        (address c0, address c1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);

        return
            SwapRoute({
                version: PoolVersion.V4,
                poolKey: PoolKey({
                    currency0: Currency.wrap(c0),
                    currency1: Currency.wrap(c1),
                    fee: DEFAULT_V4_POOL_FEE,
                    tickSpacing: DEFAULT_V4_TICK_SPACING,
                    hooks: IHooks(address(0))
                }),
                v3Path: bytes("")
            });
    }

    /// @dev Builds a valid V3 SwapRoute: tokenA → fee → tokenB.
    function _buildV3Route(
        address _tokenA,
        address _tokenB
    ) internal pure returns (SwapRoute memory) {
        bytes memory path = abi.encodePacked(_tokenA, V3_POOL_FEE, _tokenB);
        return
            SwapRoute({
                version: PoolVersion.V3,
                poolKey: PoolKey({
                    currency0: Currency.wrap(address(0)),
                    currency1: Currency.wrap(address(0)),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                v3Path: path
            });
    }

    /// @dev Registers `nonInitializedIndex` in SwapManager with V3 routes.
    ///      Uses WBTC(asset0) / LINK(asset1) / USDC path encoding.
    function _registerNonInitializedIndexWithV3Routes() internal {
        SwapRoute memory routeAsset0Usdc = _buildV3Route(
            address(mockWbtc),
            address(mockUsdc)
        );
        SwapRoute memory routeAsset1Usdc = _buildV3Route(
            address(mockLink),
            address(mockUsdc)
        );
        SwapRoute memory routeAsset0Asset1 = _buildV3Route(
            address(mockWbtc),
            address(mockLink)
        );

        vm.prank(address(indexManager));
        swapManager.registerIndex(
            address(nonInitializedIndex),
            routeAsset0Usdc,
            routeAsset1Usdc,
            routeAsset0Asset1
        );
    }

    /// @dev Registers `nonInitializedIndex` in SwapManager with V4 routes.
    function _registerNonInitializedIndexWithV4Routes() internal {
        SwapRoute memory r0 = _buildV4Route(
            address(mockWbtc),
            address(mockUsdc)
        );
        SwapRoute memory r1 = _buildV4Route(
            address(mockLink),
            address(mockUsdc)
        );
        SwapRoute memory r01 = _buildV4Route(
            address(mockWbtc),
            address(mockLink)
        );

        vm.prank(address(indexManager));
        swapManager.registerIndex(address(nonInitializedIndex), r0, r1, r01);
    }

    // =========================================================================
    //  registerIndex
    // =========================================================================

    function testRegisterIndexStoresAllThreeV4RoutesCorrectly() public {
        _registerNonInitializedIndexWithV4Routes();

        SwapRoute memory storedR0 = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC
        );
        SwapRoute memory storedR1 = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET1_USDC
        );
        SwapRoute memory storedR01 = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_ASSET1
        );

        assertEq(uint8(storedR0.version), uint8(PoolVersion.V4));
        assertEq(uint8(storedR1.version), uint8(PoolVersion.V4));
        assertEq(uint8(storedR01.version), uint8(PoolVersion.V4));
    }

    function testRegisterIndexStoresAllThreeV3RoutesCorrectly() public {
        _registerNonInitializedIndexWithV3Routes();

        SwapRoute memory storedR0 = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC
        );
        SwapRoute memory storedR1 = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET1_USDC
        );
        SwapRoute memory storedR01 = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_ASSET1
        );

        assertEq(uint8(storedR0.version), uint8(PoolVersion.V3));
        assertEq(uint8(storedR1.version), uint8(PoolVersion.V3));
        assertEq(uint8(storedR01.version), uint8(PoolVersion.V3));

        assertEq(storedR0.v3Path.length, MIN_V3_PATH_LENGTH);
        assertEq(storedR1.v3Path.length, MIN_V3_PATH_LENGTH);
        assertEq(storedR01.v3Path.length, MIN_V3_PATH_LENGTH);
    }

    function testRegisterIndexV3RoutePreservesPathEncoding() public {
        bytes memory expectedPath = abi.encodePacked(
            address(mockWbtc),
            V3_POOL_FEE,
            address(mockUsdc)
        );

        SwapRoute memory v3Route = SwapRoute({
            version: PoolVersion.V3,
            poolKey: PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(0)),
                fee: 0,
                tickSpacing: 0,
                hooks: IHooks(address(0))
            }),
            v3Path: expectedPath
        });

        vm.prank(address(indexManager));
        swapManager.registerIndex(
            address(nonInitializedIndex),
            v3Route,
            _buildV3Route(address(mockLink), address(mockUsdc)),
            _buildV3Route(address(mockWbtc), address(mockLink))
        );

        SwapRoute memory stored = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC
        );
        assertEq(keccak256(stored.v3Path), keccak256(expectedPath));
    }

    function testRegisterIndexV4RoutePreservesPoolKeyFields() public {
        _registerNonInitializedIndexWithV4Routes();

        SwapRoute memory stored = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC
        );

        assertEq(stored.poolKey.fee, DEFAULT_V4_POOL_FEE);
        assertEq(stored.poolKey.tickSpacing, DEFAULT_V4_TICK_SPACING);
        assertEq(address(stored.poolKey.hooks), address(0));

        // Currencies must be sorted (currency0 < currency1)
        address c0 = Currency.unwrap(stored.poolKey.currency0);
        address c1 = Currency.unwrap(stored.poolKey.currency1);
        assertTrue(c0 < c1, "currency0 must be < currency1");
    }

    function testRegisterIndexRevertsIfCallerNotOwner() public {
        SwapRoute memory route = _buildV4Route(
            address(mockWbtc),
            address(mockUsdc)
        );

        vm.prank(user1);
        vm.expectRevert();
        swapManager.registerIndex(
            address(nonInitializedIndex),
            route,
            route,
            route
        );
    }

    function testRegisterIndexRevertsIfV4RouteHasBothCurrenciesZero() public {
        SwapRoute memory invalidV4Route = SwapRoute({
            version: PoolVersion.V4,
            poolKey: PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(0)),
                fee: DEFAULT_V4_POOL_FEE,
                tickSpacing: DEFAULT_V4_TICK_SPACING,
                hooks: IHooks(address(0))
            }),
            v3Path: bytes("")
        });

        vm.prank(address(indexManager));
        vm.expectRevert(SwapManager.SwapManager__InvalidV4PoolKey.selector);
        swapManager.registerIndex(
            address(nonInitializedIndex),
            invalidV4Route,
            _buildV4Route(address(mockLink), address(mockUsdc)),
            _buildV4Route(address(mockWbtc), address(mockLink))
        );
    }

    function testRegisterIndexRevertsIfV3RoutePathTooShort() public {
        // 42 bytes = one byte under the minimum (43)
        bytes memory shortPath = new bytes(MIN_V3_PATH_LENGTH - 1);

        SwapRoute memory invalidV3Route = SwapRoute({
            version: PoolVersion.V3,
            poolKey: PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(0)),
                fee: 0,
                tickSpacing: 0,
                hooks: IHooks(address(0))
            }),
            v3Path: shortPath
        });

        vm.prank(address(indexManager));
        vm.expectRevert(SwapManager.SwapManager__InvalidV3Path.selector);
        swapManager.registerIndex(
            address(nonInitializedIndex),
            invalidV3Route,
            _buildV3Route(address(mockLink), address(mockUsdc)),
            _buildV3Route(address(mockWbtc), address(mockLink))
        );
    }

    function testRegisterIndexRevertsIfSecondRouteIsInvalid() public {
        // First route valid (V4), second route invalid (V3 path too short)
        bytes memory shortPath = new bytes(MIN_V3_PATH_LENGTH - 1);
        SwapRoute memory invalidV3Route = SwapRoute({
            version: PoolVersion.V3,
            poolKey: PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(0)),
                fee: 0,
                tickSpacing: 0,
                hooks: IHooks(address(0))
            }),
            v3Path: shortPath
        });

        vm.prank(address(indexManager));
        vm.expectRevert(SwapManager.SwapManager__InvalidV3Path.selector);
        swapManager.registerIndex(
            address(nonInitializedIndex),
            _buildV4Route(address(mockWbtc), address(mockUsdc)),
            invalidV3Route,
            _buildV4Route(address(mockWbtc), address(mockLink))
        );
    }

    function testRegisterIndexRevertsIfThirdRouteIsInvalid() public {
        SwapRoute memory invalidV4Route = SwapRoute({
            version: PoolVersion.V4,
            poolKey: PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(0)),
                fee: DEFAULT_V4_POOL_FEE,
                tickSpacing: DEFAULT_V4_TICK_SPACING,
                hooks: IHooks(address(0))
            }),
            v3Path: bytes("")
        });

        vm.prank(address(indexManager));
        vm.expectRevert(SwapManager.SwapManager__InvalidV4PoolKey.selector);
        swapManager.registerIndex(
            address(nonInitializedIndex),
            _buildV4Route(address(mockWbtc), address(mockUsdc)),
            _buildV4Route(address(mockLink), address(mockUsdc)),
            invalidV4Route
        );
    }

    function testRegisterIndexAllowsMixedV4AndV3Routes() public {
        // Route0 = V4, Route1 = V4, Route01 = V3 — allowed by design
        SwapRoute memory v3Route01 = _buildV3Route(
            address(mockWbtc),
            address(mockLink)
        );

        vm.prank(address(indexManager));
        swapManager.registerIndex(
            address(nonInitializedIndex),
            _buildV4Route(address(mockWbtc), address(mockUsdc)),
            _buildV4Route(address(mockLink), address(mockUsdc)),
            v3Route01
        );

        SwapRoute memory stored01 = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_ASSET1
        );
        assertEq(uint8(stored01.version), uint8(PoolVersion.V3));
    }

    // =========================================================================
    //  updateRoute
    // =========================================================================

    function testUpdateRouteUpdatesStoredRouteForRegisteredIndex() public {
        // initializedIndex has V4 routes; update ASSET0_USDC to V3
        SwapRoute memory newRoute = _buildV3Route(
            address(mockWeth),
            address(mockUsdc)
        );

        vm.prank(address(indexManager));
        swapManager.updateRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            newRoute
        );

        SwapRoute memory stored = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC
        );
        assertEq(uint8(stored.version), uint8(PoolVersion.V3));
        assertEq(stored.v3Path.length, MIN_V3_PATH_LENGTH);
    }

    function testUpdateRouteSwitchesFromV3ToV4() public {
        _registerNonInitializedIndexWithV3Routes();

        SwapRoute memory newV4Route = _buildV4Route(
            address(mockWbtc),
            address(mockUsdc)
        );

        vm.prank(address(indexManager));
        swapManager.updateRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            newV4Route
        );

        SwapRoute memory stored = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC
        );
        assertEq(uint8(stored.version), uint8(PoolVersion.V4));
    }

    function testUpdateRouteOnlyUpdatesSpecifiedSwapType() public {
        // Update ASSET0_USDC only — ASSET1_USDC and ASSET0_ASSET1 must stay unchanged
        SwapRoute memory originalAsset1Usdc = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET1_USDC
        );
        SwapRoute memory originalAsset0Asset1 = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET0_ASSET1
        );

        SwapRoute memory newRoute = _buildV3Route(
            address(mockWeth),
            address(mockUsdc)
        );
        vm.prank(address(indexManager));
        swapManager.updateRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            newRoute
        );

        SwapRoute memory afterAsset1Usdc = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET1_USDC
        );
        SwapRoute memory afterAsset0Asset1 = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET0_ASSET1
        );

        assertEq(
            uint8(afterAsset1Usdc.version),
            uint8(originalAsset1Usdc.version)
        );
        assertEq(
            uint8(afterAsset0Asset1.version),
            uint8(originalAsset0Asset1.version)
        );
    }

    function testUpdateRouteRevertsIfCallerNotOwner() public {
        SwapRoute memory route = _buildV4Route(
            address(mockWeth),
            address(mockUsdc)
        );

        vm.prank(user1);
        vm.expectRevert();
        swapManager.updateRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            route
        );
    }

    function testUpdateRouteRevertsIfIndexNotRegistered() public {
        // nonInitializedIndex has NO routes in SwapManager yet
        SwapRoute memory route = _buildV4Route(
            address(mockWbtc),
            address(mockUsdc)
        );

        vm.prank(address(indexManager));
        vm.expectRevert(SwapManager.SwapManager__IndexNotRegistered.selector);
        swapManager.updateRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            route
        );
    }

    function testUpdateRouteRevertsIfNewV4RouteIsInvalid() public {
        SwapRoute memory invalidRoute = SwapRoute({
            version: PoolVersion.V4,
            poolKey: PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(0)),
                fee: DEFAULT_V4_POOL_FEE,
                tickSpacing: DEFAULT_V4_TICK_SPACING,
                hooks: IHooks(address(0))
            }),
            v3Path: bytes("")
        });

        vm.prank(address(indexManager));
        vm.expectRevert(SwapManager.SwapManager__InvalidV4PoolKey.selector);
        swapManager.updateRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            invalidRoute
        );
    }

    function testUpdateRouteRevertsIfNewV3RoutePathTooShort() public {
        bytes memory shortPath = new bytes(MIN_V3_PATH_LENGTH - 1);
        SwapRoute memory invalidRoute = SwapRoute({
            version: PoolVersion.V3,
            poolKey: PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(0)),
                fee: 0,
                tickSpacing: 0,
                hooks: IHooks(address(0))
            }),
            v3Path: shortPath
        });

        vm.prank(address(indexManager));
        vm.expectRevert(SwapManager.SwapManager__InvalidV3Path.selector);
        swapManager.updateRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            invalidRoute
        );
    }

    // =========================================================================
    //  buildSingleSwapParams — V4
    // =========================================================================

    function testBuildSingleSwapParamsV4ReturnsCorrectCommandLength()
        public
        view
    {
        // initializedIndex has V4 routes registered
        (bytes memory commands, bytes[] memory inputs, , ) = swapManager
            .buildSingleSwapParams(
                address(initializedIndex),
                SwapType.ASSET0_USDC,
                address(mockWeth),
                1e18
            );

        assertEq(commands.length, SINGLE_SWAP_COMMANDS_LENGTH);
        assertEq(inputs.length, SINGLE_SWAP_COMMANDS_LENGTH);
    }

    function testBuildSingleSwapParamsV4UsesCorrectCommandByte() public view {
        (bytes memory commands, , , ) = swapManager.buildSingleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWeth),
            1e18
        );

        assertEq(uint8(commands[0]), V4_SWAP_COMMAND);
    }

    function testBuildSingleSwapParamsV4ReturnsCorrectTokenIn() public view {
        (, , address tokenIn, ) = swapManager.buildSingleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWeth),
            1e18
        );

        assertEq(tokenIn, address(mockWeth));
    }

    function testBuildSingleSwapParamsV4ZeroForOneReturnsCorrectTokenOut()
        public
        view
    {
        // ASSET0_USDC route: pool between WETH and USDC
        // tokenIn = WETH → zeroForOne depends on sorted order
        SwapRoute memory route = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC
        );
        address c0 = Currency.unwrap(route.poolKey.currency0);
        address c1 = Currency.unwrap(route.poolKey.currency1);

        // tokenIn = WETH, expected tokenOut = the other token (USDC)
        address expectedTokenOut = (address(mockWeth) == c0) ? c1 : c0;

        (, , , address tokenOut) = swapManager.buildSingleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWeth),
            1e18
        );

        assertEq(tokenOut, expectedTokenOut);
        // The tokenOut must be USDC in this route
        assertEq(tokenOut, address(mockUsdc));
    }

    function testBuildSingleSwapParamsV4OneForZeroReturnsCorrectTokenOut()
        public
        view
    {
        // Swap direction reversed: tokenIn = USDC → tokenOut = WETH
        (, , , address tokenOut) = swapManager.buildSingleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            address(mockUsdc),
            1e6
        );

        assertEq(tokenOut, address(mockWeth));
    }

    function testBuildSingleSwapParamsV4Asset1UsdcRouteReturnsCorrectTokens()
        public
        view
    {
        // ASSET1_USDC route: WBTC ↔ USDC
        (, , address tokenIn, address tokenOut) = swapManager
            .buildSingleSwapParams(
                address(initializedIndex),
                SwapType.ASSET1_USDC,
                address(mockWbtc),
                1e8
            );

        assertEq(tokenIn, address(mockWbtc));
        assertEq(tokenOut, address(mockUsdc));
    }

    function testBuildSingleSwapParamsV4Asset0Asset1RouteReturnsCorrectTokens()
        public
        view
    {
        // ASSET0_ASSET1 route: WETH ↔ WBTC
        (, , address tokenIn, address tokenOut) = swapManager
            .buildSingleSwapParams(
                address(initializedIndex),
                SwapType.ASSET0_ASSET1,
                address(mockWeth),
                1e18
            );

        assertEq(tokenIn, address(mockWeth));
        assertEq(tokenOut, address(mockWbtc));
    }

    function testBuildSingleSwapParamsV4ReversedAsset0Asset1Route()
        public
        view
    {
        // Swap WBTC → WETH using the same route
        (, , address tokenIn, address tokenOut) = swapManager
            .buildSingleSwapParams(
                address(initializedIndex),
                SwapType.ASSET0_ASSET1,
                address(mockWbtc),
                1e8
            );

        assertEq(tokenIn, address(mockWbtc));
        assertEq(tokenOut, address(mockWeth));
    }

    function testBuildSingleSwapParamsRevertsIfIndexNotRegistered() public {
        vm.expectRevert(SwapManager.SwapManager__IndexNotRegistered.selector);
        swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWbtc),
            1e8
        );
    }

    function testBuildSingleSwapParamsRevertsIfUnknownAddress() public {
        address unknownIndex = makeAddr("unknownIndex");

        vm.expectRevert(SwapManager.SwapManager__IndexNotRegistered.selector);
        swapManager.buildSingleSwapParams(
            unknownIndex,
            SwapType.ASSET0_USDC,
            address(mockWeth),
            1e18
        );
    }

    // =========================================================================
    //  buildSingleSwapParams — V3
    // =========================================================================

    function testBuildSingleSwapParamsV3ReturnsCorrectCommandByte() public {
        _registerNonInitializedIndexWithV3Routes();

        (bytes memory commands, , , ) = swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWbtc),
            1e8
        );

        assertEq(uint8(commands[0]), V3_SWAP_EXACT_IN_COMMAND);
    }

    function testBuildSingleSwapParamsV3ReturnsCorrectCommandLength() public {
        _registerNonInitializedIndexWithV3Routes();

        (bytes memory commands, bytes[] memory inputs, , ) = swapManager
            .buildSingleSwapParams(
                address(nonInitializedIndex),
                SwapType.ASSET0_USDC,
                address(mockWbtc),
                1e8
            );

        assertEq(commands.length, SINGLE_SWAP_COMMANDS_LENGTH);
        assertEq(inputs.length, SINGLE_SWAP_COMMANDS_LENGTH);
    }

    function testBuildSingleSwapParamsV3ReturnsCorrectTokenIn() public {
        _registerNonInitializedIndexWithV3Routes();

        (, , address tokenIn, ) = swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWbtc),
            1e8
        );

        assertEq(tokenIn, address(mockWbtc));
    }

    function testBuildSingleSwapParamsV3ExtractsTokenOutFromPathLastBytes()
        public
    {
        // V3 path for ASSET0_USDC: WBTC → fee → USDC
        // tokenOut must be the last 20 bytes of the path = USDC
        _registerNonInitializedIndexWithV3Routes();

        (, , , address tokenOut) = swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWbtc),
            1e8
        );

        assertEq(tokenOut, address(mockUsdc));
    }

    function testBuildSingleSwapParamsV3Asset1UsdcRouteTokenOut() public {
        _registerNonInitializedIndexWithV3Routes();

        (, , , address tokenOut) = swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET1_USDC,
            address(mockLink),
            1e18
        );

        assertEq(tokenOut, address(mockUsdc));
    }

    function testBuildSingleSwapParamsV3Asset0Asset1RouteTokenOut() public {
        _registerNonInitializedIndexWithV3Routes();

        (, , , address tokenOut) = swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_ASSET1,
            address(mockWbtc),
            1e8
        );

        assertEq(tokenOut, address(mockLink));
    }

    function testBuildSingleSwapParamsV3MultihopPathExtractsCorrectTokenOut()
        public
    {
        // Build a multi-hop V3 path: WBTC → fee → LINK → fee → USDC (66 bytes)
        bytes memory multihopPath = abi.encodePacked(
            address(mockWbtc),
            V3_POOL_FEE,
            address(mockLink),
            V3_POOL_FEE,
            address(mockUsdc)
        );
        // path length = 20+3+20+3+20 = 66 bytes

        SwapRoute memory multihopRoute = SwapRoute({
            version: PoolVersion.V3,
            poolKey: PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(0)),
                fee: 0,
                tickSpacing: 0,
                hooks: IHooks(address(0))
            }),
            v3Path: multihopPath
        });

        vm.prank(address(indexManager));
        swapManager.registerIndex(
            address(nonInitializedIndex),
            multihopRoute,
            _buildV3Route(address(mockLink), address(mockUsdc)),
            _buildV3Route(address(mockWbtc), address(mockLink))
        );

        (, , , address tokenOut) = swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWbtc),
            1e8
        );

        // Last 20 bytes of multihopPath = USDC
        assertEq(tokenOut, address(mockUsdc));
    }

    // =========================================================================
    //  buildDoubleSwapParams
    // =========================================================================

    function testBuildDoubleSwapParamsReturnsCommandsOfLengthTwo() public view {
        (bytes memory commands, ) = swapManager.buildDoubleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            SwapType.ASSET1_USDC,
            address(mockWeth),
            address(mockWbtc),
            1e18,
            1e8
        );

        assertEq(commands.length, DOUBLE_SWAP_COMMANDS_LENGTH);
    }

    function testBuildDoubleSwapParamsReturnsInputsArrayOfLengthTwo()
        public
        view
    {
        (, bytes[] memory inputs) = swapManager.buildDoubleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            SwapType.ASSET1_USDC,
            address(mockWeth),
            address(mockWbtc),
            1e18,
            1e8
        );

        assertEq(inputs.length, DOUBLE_SWAP_COMMANDS_LENGTH);
    }

    function testBuildDoubleSwapParamsCommandsAreConcatenationOfTwoV4Commands()
        public
        view
    {
        (bytes memory commands, ) = swapManager.buildDoubleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            SwapType.ASSET1_USDC,
            address(mockWeth),
            address(mockWbtc),
            1e18,
            1e8
        );

        // Both routes are V4, so both command bytes must be V4_SWAP_COMMAND
        assertEq(uint8(commands[0]), V4_SWAP_COMMAND);
        assertEq(uint8(commands[1]), V4_SWAP_COMMAND);
    }

    function testBuildDoubleSwapParamsMixedV4AndV3Commands() public {
        // Register nonInitializedIndex with V4 for ASSET0_USDC and V3 for ASSET1_USDC
        SwapRoute memory v4Route = _buildV4Route(
            address(mockWbtc),
            address(mockUsdc)
        );
        SwapRoute memory v3Route1 = _buildV3Route(
            address(mockLink),
            address(mockUsdc)
        );
        SwapRoute memory v3Route01 = _buildV3Route(
            address(mockWbtc),
            address(mockLink)
        );

        vm.prank(address(indexManager));
        swapManager.registerIndex(
            address(nonInitializedIndex),
            v4Route,
            v3Route1,
            v3Route01
        );

        (bytes memory commands, ) = swapManager.buildDoubleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            SwapType.ASSET1_USDC,
            address(mockWbtc),
            address(mockLink),
            1e8,
            1e18
        );

        assertEq(commands.length, DOUBLE_SWAP_COMMANDS_LENGTH);
        assertEq(uint8(commands[0]), V4_SWAP_COMMAND); // First: V4
        assertEq(uint8(commands[1]), V3_SWAP_EXACT_IN_COMMAND); // Second: V3
    }

    function testBuildDoubleSwapParamsInputsAreIndependentOfEachOther()
        public
        view
    {
        // Each inputs[i] must be non-empty and independently decodable
        (, bytes[] memory inputs) = swapManager.buildDoubleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            SwapType.ASSET1_USDC,
            address(mockWeth),
            address(mockWbtc),
            1e18,
            1e8
        );

        assertGt(inputs[0].length, 0, "inputs[0] must not be empty");
        assertGt(inputs[1].length, 0, "inputs[1] must not be empty");
    }

    function testBuildDoubleSwapParamsRevertsIfIndexNotRegistered() public {
        vm.expectRevert(SwapManager.SwapManager__IndexNotRegistered.selector);
        swapManager.buildDoubleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            SwapType.ASSET1_USDC,
            address(mockWbtc),
            address(mockLink),
            1e8,
            1e18
        );
    }

    // =========================================================================
    //  getRoute
    // =========================================================================

    function testGetRouteReturnsCorrectV4RouteForRegisteredIndex() public view {
        SwapRoute memory route = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC
        );

        assertEq(uint8(route.version), uint8(PoolVersion.V4));

        // Pool key must contain the two sorted token addresses
        address c0 = Currency.unwrap(route.poolKey.currency0);
        address c1 = Currency.unwrap(route.poolKey.currency1);

        bool containsWeth = (c0 == address(mockWeth)) ||
            (c1 == address(mockWeth));
        bool containsUsdc = (c0 == address(mockUsdc)) ||
            (c1 == address(mockUsdc));

        assertTrue(containsWeth, "pool key must contain WETH");
        assertTrue(containsUsdc, "pool key must contain USDC");
    }

    function testGetRouteReturnsCorrectV3RouteForRegisteredIndex() public {
        _registerNonInitializedIndexWithV3Routes();

        SwapRoute memory route = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC
        );

        assertEq(uint8(route.version), uint8(PoolVersion.V3));
        assertGe(route.v3Path.length, MIN_V3_PATH_LENGTH);
    }

    function testGetRouteReturnsDefaultValuesForUnregisteredIndex() public {
        // Unregistered → default storage: PoolVersion.V3 (= 0), empty path
        SwapRoute memory route = swapManager.getRoute(
            makeAddr("unregistered"),
            SwapType.ASSET0_USDC
        );

        // Default version (0) = V3, empty path
        assertEq(uint8(route.version), uint8(PoolVersion.V3));
        assertEq(route.v3Path.length, 0);
    }

    function testGetRouteReturnsDifferentRoutesForDifferentSwapTypes() public view {
        SwapRoute memory r0 = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC
        );
        SwapRoute memory r1 = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET1_USDC
        );
        SwapRoute memory r01 = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET0_ASSET1
        );

        // All three routes are V4 but must have different pool keys (different token pairs)
        address r0c0 = Currency.unwrap(r0.poolKey.currency0);
        address r1c0 = Currency.unwrap(r1.poolKey.currency0);
        address r01c0 = Currency.unwrap(r01.poolKey.currency0);

        // At least two of the three pool keys must differ
        bool atLeastOneDifferent = (r0c0 != r1c0) ||
            (r0c0 != r01c0) ||
            (r1c0 != r01c0);
        assertTrue(
            atLeastOneDifferent,
            "the three routes must have different pool keys"
        );
    }

    function testGetRouteAllThreeSwapTypesAreStoredForInitializedIndex()
        public view
    {
        SwapRoute memory r0 = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC
        );
        SwapRoute memory r1 = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET1_USDC
        );
        SwapRoute memory r01 = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET0_ASSET1
        );

        // All must be V4 (registered by deployAndInitNewIndex in Base.setUp)
        assertEq(uint8(r0.version), uint8(PoolVersion.V4));
        assertEq(uint8(r1.version), uint8(PoolVersion.V4));
        assertEq(uint8(r01.version), uint8(PoolVersion.V4));
    }

    // =========================================================================
    //  Integration: buildSingleSwapParams matches getRoute data
    // =========================================================================

    function testBuildSingleSwapParamsV4CommandBytesMatchExpectedEncoding()
        public
        view
    {
        // Verify that the returned commands can be decoded back to a V4 command byte
        (bytes memory commands, bytes[] memory inputs, , ) = swapManager
            .buildSingleSwapParams(
                address(initializedIndex),
                SwapType.ASSET0_USDC,
                address(mockWeth),
                1e18
            );

        // Commands must be 1 byte = V4_SWAP_COMMAND
        assertEq(commands.length, SINGLE_SWAP_COMMANDS_LENGTH);
        assertEq(uint8(commands[0]), V4_SWAP_COMMAND);

        // Input must be abi.encode(bytes actions, bytes[] actionParams)
        // We just verify it's decodable and non-trivially sized
        assertGt(inputs[0].length, 0);
        (bytes memory actions, bytes[] memory actionParams) = abi.decode(
            inputs[0],
            (bytes, bytes[])
        );
        assertEq(actionParams.length, 3); // SWAP_EXACT_IN_SINGLE + SETTLE_ALL + TAKE_ALL
        assertEq(actions.length, 3);
    }

    function testBuildSingleSwapParamsV3InputEncodesExpectedFields() public {
        _registerNonInitializedIndexWithV3Routes();

        (, bytes[] memory inputs, , ) = swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWbtc),
            1e8
        );

        // V3 input: abi.encode(address recipient, uint256 amountIn, uint256 amountOutMin, bytes path, bool payerIsUser)
        (
            address recipient,
            uint256 amountIn,
            uint256 amountOutMin,
            bytes memory path,
            bool payerIsUser
        ) = abi.decode(inputs[0], (address, uint256, uint256, bytes, bool));

        assertGt(path.length, 0, "path must not be empty");
        assertEq(amountIn, 1e8, "amountIn must match the value passed");
        assertEq(
            amountOutMin,
            0,
            "amountOutMin must be 0 (slippage handled elsewhere)"
        );
        assertFalse(payerIsUser, "payerIsUser must be false");
        assertNotEq(recipient, address(0), "recipient must not be address(0)");
    }

    function testBuildDoubleSwapParamsInputsMatchIndividualSingleSwapInputs()
        public
        view
    {
        (, bytes[] memory inputsDouble) = swapManager.buildDoubleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            SwapType.ASSET1_USDC,
            address(mockWeth),
            address(mockWbtc),
            1e18,
            1e8
        );

        (, bytes[] memory inputs0, , ) = swapManager.buildSingleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWeth),
            1e18
        );
        (, bytes[] memory inputs1, , ) = swapManager.buildSingleSwapParams(
            address(initializedIndex),
            SwapType.ASSET1_USDC,
            address(mockWbtc),
            1e8
        );

        assertEq(
            keccak256(inputsDouble[0]),
            keccak256(inputs0[0]),
            "inputs[0] of double must match single swap 0"
        );
        assertEq(
            keccak256(inputsDouble[1]),
            keccak256(inputs1[0]),
            "inputs[1] of double must match single swap 1"
        );
    }
}
