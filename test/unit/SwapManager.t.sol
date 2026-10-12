// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {SwapManager} from "../../src/SwapManager.sol";
import {SwapType, SwapRoute, PoolVersion} from "../../src/types.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UpgraderAuth__Unauthorized} from "../../src/errors/UpgraderAuthErrors.sol";
import {SwapManagerV2Mock} from "../mocks/SwapManagerV2Mock.sol";
import {SwapManagerHarness} from "../mocks/SwapManagerHarness.sol";
import {IndexTokensMock} from "../mocks/IndexTokensMock.sol";

contract SwapManagerTest is BaseTest {

    SwapManagerHarness harness;
    /// Index stand-in (WETH / WBTC / USDC) used for harness-only route registrations
    IndexTokensMock harnessIndexMock;

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

    /// ERC-7201 namespace id of SwapManager storage
    string constant SWAP_MANAGER_NAMESPACE_ID =
        "onchainassetmanager.storage.SwapManager";

    /// OZ v5 OwnableUpgradeable ERC-7201 slot (no public reader in OZ)
    bytes32 constant OZ_OWNABLE_STORAGE_LOCATION =
        0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;

    /// OZ v5 Initializable ERC-7201 slot (no public reader in OZ)
    bytes32 constant OZ_INITIALIZABLE_STORAGE_LOCATION =
        0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /// Number of low sequential slots checked to be empty on the proxy
    uint256 constant LOW_SLOTS_CHECKED = 10;

    /// Index address used for harness-only route registrations (assigned in setUp)
    address HARNESS_INDEX;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();
        // initializedIndex already has V4 routes registered via Base.setUp().
        // nonInitializedIndex has NO routes in SwapManager.
        harness = SwapManagerHarness(
            address(
                new ERC1967Proxy(
                    address(new SwapManagerHarness()),
                    abi.encodeCall(
                        SwapManager.initialize,
                        (address(this), address(this))
                    )
                )
            )
        );
        // registerIndex now reads the index tokens, so the harness needs a contract exposing them.
        harnessIndexMock = new IndexTokensMock(
            address(mockWeth),
            address(mockWbtc),
            address(mockUsdc)
        );
        HARNESS_INDEX = address(harnessIndexMock);
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
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
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
                1e18,
                0
            );

        assertEq(commands.length, SINGLE_SWAP_COMMANDS_LENGTH);
        assertEq(inputs.length, SINGLE_SWAP_COMMANDS_LENGTH);
    }

    function testBuildSingleSwapParamsV3UsesCorrectCommandByteForUsdcRoute()
        public
        view
    {
        (bytes memory commands, , , ) = swapManager.buildSingleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWeth),
            1e18,
            0
        );

        // USDC ↔ asset routes use V3
        assertEq(uint8(commands[0]), V3_SWAP_EXACT_IN_COMMAND);
    }

    function testBuildSingleSwapParamsV4ReturnsCorrectTokenIn() public view {
        (, , address tokenIn, ) = swapManager.buildSingleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWeth),
            1e18,
            0
        );

        assertEq(tokenIn, address(mockWeth));
    }

    function testBuildSingleSwapParamsV3ReturnsCorrectTokenOutForUsdcRoute()
        public
        view
    {
        // ASSET0_USDC route is V3: tokenIn = WETH → tokenOut = USDC
        (, , , address tokenOut) = swapManager.buildSingleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWeth),
            1e18,
            0
        );

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
            1e6,
            0
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
                1e8,
                0
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
                1e18,
                0
            );

        assertEq(tokenIn, address(mockWeth));
        assertEq(tokenOut, address(mockWbtc));
    }

    function testBuildSingleSwapParamsV4EncodesAmountOutMinimum() public {
        _registerNonInitializedIndexWithV4Routes();
        uint128 minOut = 123e6;
        (bytes memory commands, bytes[] memory inputs, , ) = swapManager
            .buildSingleSwapParams(
                address(nonInitializedIndex),
                SwapType.ASSET0_ASSET1,
                address(mockWbtc),
                1e8,
                minOut
            );
        assertEq(uint8(commands[0]), uint8(0x10)); // V4_SWAP

        (, bytes[] memory actionParams) = abi.decode(
            inputs[0],
            (bytes, bytes[])
        );
        IV4Router.ExactInputSingleParams memory swapParams = abi.decode(
            actionParams[0],
            (IV4Router.ExactInputSingleParams)
        );
        assertEq(swapParams.amountOutMinimum, minOut);
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
                1e8,
                0
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
            1e8,
            0
        );
    }

    function testBuildSingleSwapParamsRevertsIfUnknownAddress() public {
        address unknownIndex = makeAddr("unknownIndex");

        vm.expectRevert(SwapManager.SwapManager__IndexNotRegistered.selector);
        swapManager.buildSingleSwapParams(
            unknownIndex,
            SwapType.ASSET0_USDC,
            address(mockWeth),
            1e18,
            0
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
            1e8,
            0
        );

        assertEq(uint8(commands[0]), V3_SWAP_EXACT_IN_COMMAND);
    }

    function testBuildSingleSwapParamsV3EncodesAmountOutMinimum() public {
        _registerNonInitializedIndexWithV3Routes();
        uint128 minOut = 456e6;

        (, bytes[] memory inputs, , ) = swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWbtc),
            1e8,
            minOut
        );

        (, , uint256 amountOutMin, , ) = abi.decode(
            inputs[0],
            (address, uint256, uint256, bytes, bool)
        );
        assertEq(amountOutMin, minOut);
    }

    function testBuildSingleSwapParamsV3ReturnsCorrectCommandLength() public {
        _registerNonInitializedIndexWithV3Routes();

        (bytes memory commands, bytes[] memory inputs, , ) = swapManager
            .buildSingleSwapParams(
                address(nonInitializedIndex),
                SwapType.ASSET0_USDC,
                address(mockWbtc),
                1e8,
                0
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
            1e8,
            0
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
            1e8,
            0
        );

        assertEq(tokenOut, address(mockUsdc));
    }

    function testBuildSingleSwapParamsV3Asset1UsdcRouteTokenOut() public {
        _registerNonInitializedIndexWithV3Routes();

        (, , , address tokenOut) = swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET1_USDC,
            address(mockLink),
            1e18,
            0
        );

        assertEq(tokenOut, address(mockUsdc));
    }

    function testBuildSingleSwapParamsV3Asset0Asset1RouteTokenOut() public {
        _registerNonInitializedIndexWithV3Routes();

        (, , , address tokenOut) = swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_ASSET1,
            address(mockWbtc),
            1e8,
            0
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
            1e8,
            0
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
            1e8,
            0,
            0
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
            1e8,
            0,
            0
        );

        assertEq(inputs.length, DOUBLE_SWAP_COMMANDS_LENGTH);
    }

    function testBuildDoubleSwapParamsCommandsAreConcatenationOfTwoV3Commands()
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
            1e8,
            0,
            0
        );

        // Both USDC routes are V3
        assertEq(uint8(commands[0]), V3_SWAP_EXACT_IN_COMMAND);
        assertEq(uint8(commands[1]), V3_SWAP_EXACT_IN_COMMAND);
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
            1e18,
            0,
            0
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
            1e8,
            0,
            0
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
            1e18,
            0,
            0
        );
    }

    // =========================================================================
    //  getRoute
    // =========================================================================

    function testGetRouteReturnsCorrectV3RouteForRegisteredInitializedIndex()
        public
        view
    {
        SwapRoute memory route = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC
        );

        // USDC ↔ asset routes now use V3
        assertEq(uint8(route.version), uint8(PoolVersion.V3));
        assertGe(
            route.v3Path.length,
            MIN_V3_PATH_LENGTH,
            "v3Path must be at least 43 bytes"
        );
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

    function testGetRouteReturnsDifferentRoutesForDifferentSwapTypes()
        public
        view
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

        // All three routes are V3 — compare v3Path to verify distinctness
        bool atLeastOneDifferent = (keccak256(r0.v3Path) !=
            keccak256(r1.v3Path)) ||
            (keccak256(r0.v3Path) != keccak256(r01.v3Path)) ||
            (keccak256(r1.v3Path) != keccak256(r01.v3Path));
        assertTrue(
            atLeastOneDifferent,
            "the three routes must have different pool keys"
        );
    }

    function testGetRouteAllThreeSwapTypesAreStoredForInitializedIndex()
        public
        view
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

        // All three default routes are V3 (V4 pools lack mainnet liquidity)
        assertEq(uint8(r0.version), uint8(PoolVersion.V3));
        assertEq(uint8(r1.version), uint8(PoolVersion.V3));
        assertEq(uint8(r01.version), uint8(PoolVersion.V3));
    }

    // =========================================================================
    //  Integration: buildSingleSwapParams matches getRoute data
    // =========================================================================

    function testBuildSingleSwapParamsV3CommandBytesMatchExpectedEncoding()
        public
        view
    {
        // Verify that the returned commands can be decoded back to a V3 command byte
        (bytes memory commands, bytes[] memory inputs, , ) = swapManager
            .buildSingleSwapParams(
                address(initializedIndex),
                SwapType.ASSET0_USDC,
                address(mockWeth),
                1e18,
                0
            );

        // Commands must be 1 byte = V3_SWAP_EXACT_IN_COMMAND
        assertEq(commands.length, SINGLE_SWAP_COMMANDS_LENGTH);
        assertEq(uint8(commands[0]), V3_SWAP_EXACT_IN_COMMAND);

        // V3 input: abi.encode(recipient, amountIn, amountOutMin, path, payerIsUser)
        assertGt(inputs[0].length, 0);
        (
            address recipient,
            uint256 amountIn,
            ,
            bytes memory path,
            bool payerIsUser
        ) = abi.decode(inputs[0], (address, uint256, uint256, bytes, bool));
        assertNotEq(recipient, address(0), "recipient must not be zero");
        assertEq(amountIn, 1e18, "amountIn must match");
        assertGe(path.length, MIN_V3_PATH_LENGTH, "path too short");
        assertFalse(payerIsUser, "payerIsUser must be false");
    }

    function testBuildSingleSwapParamsV3InputEncodesExpectedFields() public {
        _registerNonInitializedIndexWithV3Routes();

        (, bytes[] memory inputs, , ) = swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWbtc),
            1e8,
            0
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
            "amountOutMin must match the value passed (0)"
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
            1e8,
            0,
            0
        );

        (, bytes[] memory inputs0, , ) = swapManager.buildSingleSwapParams(
            address(initializedIndex),
            SwapType.ASSET0_USDC,
            address(mockWeth),
            1e18,
            0
        );
        (, bytes[] memory inputs1, , ) = swapManager.buildSingleSwapParams(
            address(initializedIndex),
            SwapType.ASSET1_USDC,
            address(mockWbtc),
            1e8,
            0
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

    // =========================================================================
    //  _checkIfRegisteredIndex — V4 route with zero currencies
    // =========================================================================

    /// @dev Builds a minimal valid V4 SwapRoute for harness-based tests.
    /// @dev Builds the three valid V4 routes of the harness index (WETH / WBTC / USDC),
    ///      ordered by SwapType: ASSET0_USDC, ASSET1_USDC, ASSET0_ASSET1.
    function _harnessV4Routes()
        internal
        view
        returns (SwapRoute[3] memory routes)
    {
        routes[0] = _buildV4Route(address(mockWeth), address(mockUsdc));
        routes[1] = _buildV4Route(address(mockWbtc), address(mockUsdc));
        routes[2] = _buildV4Route(address(mockWeth), address(mockWbtc));
    }

    /// @dev Registers the harness index with the three valid V4 routes.
    function _registerHarnessIndexWithV4Routes() internal {
        SwapRoute[3] memory routes = _harnessV4Routes();
        harness.registerIndex(HARNESS_INDEX, routes[0], routes[1], routes[2]);
    }

    function testCheckIfRegisteredIndexRevertsOnV4WithZeroCurrencies() public {
        _registerHarnessIndexWithV4Routes();

        // Corrupt the ASSET0_ASSET1 route: version is V4 but both
        // currencies are zero → should revert.
        SwapRoute memory corruptRoute = SwapRoute({
            version: PoolVersion.V4,
            poolKey: PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(0)),
                fee: 3000,
                tickSpacing: 60,
                hooks: IHooks(address(0))
            }),
            v3Path: bytes("")
        });

        harness.forceSetRoute(
            HARNESS_INDEX,
            SwapType.ASSET0_ASSET1,
            abi.encode(corruptRoute)
        );

        vm.expectRevert(SwapManager.SwapManager__IndexNotRegistered.selector);
        harness.exposed_checkIfRegisteredIndex(HARNESS_INDEX);
    }

    // =========================================================================
    //  Upgradeability — initialize
    // =========================================================================

    function testInitializeRevertsIfCalledTwiceOnProxy() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        harness.initialize(user1, user1);
    }

    function testInitializeRevertsOnBareImplementation() public {
        SwapManager implementation = new SwapManager();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(user1, user1);
    }

    function testInitializeSetsOwnerOnProxy() public view {
        assertEq(harness.owner(), address(this), "proxy owner must be the initializer argument");
    }

    function testInitializeSetsUpgraderOnProxy() public view {
        assertEq(harness.getUpgrader(), address(this), "proxy upgrader must be the initializer argument");
        assertEq(swapManager.getUpgrader(), address(timelock), "deployed proxy upgrader must be the timelock");
    }

    // =========================================================================
    //  Upgradeability — ERC-7201 storage
    // =========================================================================

    /// @dev ERC-7201 formula applied to the SwapManager namespace id.
    function _erc7201SwapManagerLocation() internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    uint256(keccak256(bytes(SWAP_MANAGER_NAMESPACE_ID))) - 1
                )
            ) & ~bytes32(uint256(0xff));
    }

    /// @dev Storage slot of routes[_index][_swapType] (first word of the SwapRoute struct).
    function _routeSlot(
        address _index,
        SwapType _swapType
    ) internal pure returns (bytes32) {
        bytes32 innerMappingSlot = keccak256(
            abi.encode(_index, _erc7201SwapManagerLocation())
        );
        return keccak256(abi.encode(uint256(_swapType), innerMappingSlot));
    }

    function testStorageLocationMatchesErc7201Formula() public view {
        assertEq(
            harness.exposed_storageLocation(),
            _erc7201SwapManagerLocation(),
            "storage location must follow the ERC-7201 formula"
        );
    }

    function testRegisterIndexWritesRoutesUnderErc7201Namespace() public {
        SwapRoute[3] memory routes = _harnessV4Routes();

        for (uint256 i = 0; i < 3; i++) {
            bytes32 slot = _routeSlot(HARNESS_INDEX, SwapType(i));
            assertEq(vm.load(address(harness), slot), bytes32(0), "route slot must be empty before registration");
        }

        harness.registerIndex(HARNESS_INDEX, routes[0], routes[1], routes[2]);

        for (uint256 i = 0; i < 3; i++) {
            address currency0 = Currency.unwrap(routes[i].poolKey.currency0);
            bytes32 slot = _routeSlot(HARNESS_INDEX, SwapType(i));
            // word 0: version (enum, uint8)
            assertEq(
                uint256(vm.load(address(harness), slot)),
                uint256(PoolVersion.V4),
                "route.version must live in the namespaced slot"
            );
            // word 1: poolKey.currency0
            assertEq(
                address(
                    uint160(
                        uint256(
                            vm.load(address(harness), bytes32(uint256(slot) + 1))
                        )
                    )
                ),
                currency0,
                "route.poolKey.currency0 must live right after version"
            );
        }
    }

    function testRegisterIndexLeavesLowSequentialSlotsEmpty() public {
        _registerHarnessIndexWithV4Routes();

        for (uint256 i = 0; i < LOW_SLOTS_CHECKED; i++) {
            assertEq(
                vm.load(address(harness), bytes32(i)),
                bytes32(0),
                "no sequential storage slot must be used by the proxy"
            );
        }
    }

    function testOzNamespacedStorageHoldsOwnerAndInitializedVersion()
        public
        view
    {
        assertEq(
            address(
                uint160(
                    uint256(
                        vm.load(address(harness), OZ_OWNABLE_STORAGE_LOCATION)
                    )
                )
            ),
            address(this),
            "owner must be stored in the OZ Ownable namespace"
        );
        // _initialized (uint64) occupies the low bytes of the Initializable slot
        assertEq(
            uint64(
                uint256(
                    vm.load(address(harness), OZ_INITIALIZABLE_STORAGE_LOCATION)
                )
            ),
            1,
            "proxy must be initialized at version 1"
        );
    }

    // =========================================================================
    //  Upgradeability — upgradeToAndCall
    // =========================================================================

    function testUpgradeToAndCallRevertsIfCallerNotUpgrader() public {
        SwapManagerV2Mock newImplementation = new SwapManagerV2Mock();

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(UpgraderAuth__Unauthorized.selector, user1)
        );
        harness.upgradeToAndCall(address(newImplementation), "");
    }

    /// @dev The harness is initialized with this contract as both owner and upgrader.
    function testUpgradeToAndCallByUpgraderKeepsRoutesAndSwitchesImplementation()
        public
    {
        // Mixed versions: ASSET0_USDC and ASSET0_ASSET1 on V4, ASSET1_USDC on V3
        SwapRoute[3] memory v4Routes = _harnessV4Routes();
        SwapRoute memory v3Route = _buildV3Route(
            address(mockWbtc),
            address(mockUsdc)
        );
        harness.registerIndex(HARNESS_INDEX, v4Routes[0], v3Route, v4Routes[2]);

        bytes32[3] memory routesBefore;
        for (uint256 i = 0; i < 3; i++) {
            routesBefore[i] = keccak256(
                abi.encode(harness.getRoute(HARNESS_INDEX, SwapType(i)))
            );
        }
        address implementationBefore = harness.getImplementation();

        SwapManagerV2Mock newImplementation = new SwapManagerV2Mock();
        harness.upgradeToAndCall(address(newImplementation), "");

        SwapManagerV2Mock upgraded = SwapManagerV2Mock(address(harness));
        assertTrue(
            implementationBefore != address(newImplementation),
            "implementation must differ before upgrade"
        );
        assertEq(upgraded.getImplementation(), address(newImplementation), "getImplementation must return V2");
        assertEq(
            address(
                uint160(
                    uint256(
                        vm.load(address(harness), ERC1967Utils.IMPLEMENTATION_SLOT)
                    )
                )
            ),
            address(newImplementation),
            "ERC-1967 slot must point to V2"
        );
        assertEq(upgraded.version(), 2, "V2 logic must be reachable through the proxy");
        assertEq(upgraded.owner(), address(this), "owner must survive the upgrade");
        for (uint256 i = 0; i < 3; i++) {
            assertEq(
                keccak256(
                    abi.encode(upgraded.getRoute(HARNESS_INDEX, SwapType(i)))
                ),
                routesBefore[i],
                "routes must survive the upgrade"
            );
        }
    }
}

