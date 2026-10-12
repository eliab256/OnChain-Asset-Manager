// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {stdError} from "forge-std/StdError.sol";
import {SwapManager} from "../../src/SwapManager.sol";
import {SwapType, SwapRoute, PoolVersion} from "../../src/types.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    Commands
} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {SwapManagerHarness} from "../mocks/SwapManagerHarness.sol";
import {IndexTokensMock} from "../mocks/IndexTokensMock.sol";
import {
    RevertingIndexGettersMock,
    RawWordIndexGettersMock
} from "../mocks/MalformedIndexMocks.sol";

/**
 * @dev L-04: every route registered / updated in the SwapManager must connect the pair of tokens
 *      the index expects for its SwapType (ASSET0_USDC ↔ {asset0, usdc}, ASSET1_USDC ↔ {asset1, usdc},
 *      ASSET0_ASSET1 ↔ {asset0, asset1}), read from the index itself.
 *      registerIndex is exercised on `nonInitializedIndex`, updateRoute on `initializedIndex`,
 *      both through the real owner (the IndexManager).
 */
contract SwapManagerRouteValidationTest is BaseTest {
    SwapManagerHarness harness;
    IndexTokensMock harnessIndexMock;
    RevertingIndexGettersMock revertingIndexMock;
    RawWordIndexGettersMock dirtyWordIndexMock;
    address eoaIndex = makeAddr("eoaIndex");

    // =========================================================================
    //  Constants
    // =========================================================================

    /// Fee tier used in V3 path encoding
    uint24 constant V3_POOL_FEE = 3000;
    /// V4 pool parameters (match HelperConfig defaults)
    uint24 constant V4_POOL_FEE = 3000;
    int24 constant V4_TICK_SPACING = 60;
    /// Bytes of one V3 hop (3-byte fee + 20-byte token)
    uint256 constant V3_HOP_LENGTH = 23;
    /// Trailing bytes appended to a valid path to make its length malformed (43 + 1 = 44)
    uint256 constant MALFORMED_PATH_EXTRA_BYTES = 1;
    /// Amounts passed to buildSingleSwapParams
    uint128 constant SWAP_AMOUNT_IN = 1e18;
    uint128 constant SWAP_AMOUNT_OUT_MIN = 0;

    // =========================================================================
    //  Values derived from the deployed contracts (assigned in setUp)
    // =========================================================================

    // nonInitializedIndex tokens
    address s_asset0;
    address s_asset1;
    address s_usdc;
    // initializedIndex tokens
    address s_initAsset0;
    address s_initAsset1;
    /// Token that is neither asset nor USDC of either index, used as intermediate/wrong hop
    address s_outsiderToken;
    /// First raw value outside the PoolVersion enum
    uint8 s_invalidPoolVersion;
    /// First 32-byte word that is not a valid address (one past type(uint160).max)
    uint256 s_dirtyAddressWord;
    /// Contract with code that does not expose the index getters (an ERC20 mock)
    address s_contractWithoutGetters;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();

        s_asset0 = nonInitializedIndex.getAsset0();
        s_asset1 = nonInitializedIndex.getAsset1();
        s_usdc = nonInitializedIndex.getUsdc();
        s_initAsset0 = initializedIndex.getAsset0();
        s_initAsset1 = initializedIndex.getAsset1();
        s_outsiderToken = address(mockComp);
        s_invalidPoolVersion = uint8(type(PoolVersion).max) + 1;
        s_dirtyAddressWord = uint256(type(uint160).max) + 1;
        s_contractWithoutGetters = address(mockUsdc);

        harness = SwapManagerHarness(
            address(
                new ERC1967Proxy(
                    address(new SwapManagerHarness()),
                    abi.encodeCall(SwapManager.initialize, (address(this), address(this)))
                )
            )
        );
        harnessIndexMock = new IndexTokensMock(s_asset0, s_asset1, s_usdc);
        revertingIndexMock = new RevertingIndexGettersMock();
        // asset0 / asset1 are valid addresses, only the last read (getUsdc) is dirty
        dirtyWordIndexMock = new RawWordIndexGettersMock(
            uint256(uint160(s_asset0)),
            uint256(uint160(s_asset1)),
            s_dirtyAddressWord
        );
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev V4 route with currencies stored exactly in the given order (no sorting).
    function _v4Route(
        address _currency0,
        address _currency1
    ) internal pure returns (SwapRoute memory) {
        return
            SwapRoute({
                version: PoolVersion.V4,
                poolKey: PoolKey({
                    currency0: Currency.wrap(_currency0),
                    currency1: Currency.wrap(_currency1),
                    fee: V4_POOL_FEE,
                    tickSpacing: V4_TICK_SPACING,
                    hooks: IHooks(address(0))
                }),
                v3Path: bytes("")
            });
    }

    /// @dev V3 route with an arbitrary encoded path.
    function _v3Route(
        bytes memory _path
    ) internal pure returns (SwapRoute memory) {
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
                v3Path: _path
            });
    }

    /// @dev Single-hop V3 route `_tokenIn → fee → _tokenOut`.
    function _v3SingleHop(
        address _tokenIn,
        address _tokenOut
    ) internal pure returns (SwapRoute memory) {
        return _v3Route(abi.encodePacked(_tokenIn, V3_POOL_FEE, _tokenOut));
    }

    /// @dev Two-hop V3 route `_tokenIn → fee → _tokenMid → fee → _tokenOut`.
    function _v3TwoHop(
        address _tokenIn,
        address _tokenMid,
        address _tokenOut
    ) internal pure returns (SwapRoute memory) {
        return
            _v3Route(
                abi.encodePacked(
                    _tokenIn,
                    V3_POOL_FEE,
                    _tokenMid,
                    V3_POOL_FEE,
                    _tokenOut
                )
            );
    }

    /// @dev Calls registerIndex on `nonInitializedIndex` as the owner (IndexManager).
    function _registerNonInitializedIndex(
        SwapRoute memory _r0,
        SwapRoute memory _r1,
        SwapRoute memory _r01
    ) internal {
        vm.prank(address(indexManager));
        swapManager.registerIndex(address(nonInitializedIndex), _r0, _r1, _r01);
    }

    /// @dev Calls updateRoute on `initializedIndex` as the owner (IndexManager).
    function _updateInitializedIndexRoute(
        SwapType _swapType,
        SwapRoute memory _route
    ) internal {
        vm.prank(address(indexManager));
        swapManager.updateRoute(address(initializedIndex), _swapType, _route);
    }

    /// @dev Calls registerIndex on `_index` as the owner with three routes valid for `nonInitializedIndex`.
    function _registerWithValidRoutes(address _index) internal {
        vm.prank(address(indexManager));
        swapManager.registerIndex(
            _index,
            _v3SingleHop(s_asset0, s_usdc),
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );
    }

    function _routeHash(
        address _index,
        SwapType _swapType
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(swapManager.getRoute(_index, _swapType)));
    }

    // =========================================================================
    //  registerIndex — wrong pair per SwapType
    // =========================================================================

    function testRegisterIndexRevertsIfAsset0UsdcRouteConnectsAsset1() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_usdc
            )
        );
        _registerNonInitializedIndex(
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );
    }

    function testRegisterIndexRevertsIfAsset1UsdcRouteConnectsAsset0() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset1,
                s_usdc
            )
        );
        _registerNonInitializedIndex(
            _v3SingleHop(s_asset0, s_usdc),
            _v3SingleHop(s_asset0, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );
    }

    function testRegisterIndexRevertsIfAsset0Asset1RouteConnectsUsdc() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_asset1
            )
        );
        _registerNonInitializedIndex(
            _v3SingleHop(s_asset0, s_usdc),
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset0, s_usdc)
        );
    }

    function testRegisterIndexRevertsIfV4RouteConnectsWrongPair() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_usdc
            )
        );
        _registerNonInitializedIndex(
            _v4Route(s_asset0, s_asset1),
            _v4Route(s_asset1, s_usdc),
            _v4Route(s_asset0, s_asset1)
        );
    }

    function testRegisterIndexRevertsIfRouteUsesAnOutsiderToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset1,
                s_usdc
            )
        );
        _registerNonInitializedIndex(
            _v3SingleHop(s_asset0, s_usdc),
            _v3SingleHop(s_outsiderToken, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );
    }

    // =========================================================================
    //  registerIndex — V4 specifics
    // =========================================================================

    function testRegisterIndexRevertsIfV4RouteUsesNativeEth() public {
        // currency0 = address(0) is native ETH: never an index token
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_usdc
            )
        );
        _registerNonInitializedIndex(
            _v4Route(address(0), s_usdc),
            _v4Route(s_asset1, s_usdc),
            _v4Route(s_asset0, s_asset1)
        );
    }

    function testRegisterIndexAcceptsV4RoutesWithCurrenciesInEitherOrder()
        public
    {
        // r0 in the given order, r1 and r01 reversed: validation is order-independent
        SwapRoute memory r0 = _v4Route(s_asset0, s_usdc);
        SwapRoute memory r1 = _v4Route(s_usdc, s_asset1);
        SwapRoute memory r01 = _v4Route(s_asset1, s_asset0);

        _registerNonInitializedIndex(r0, r1, r01);

        assertEq(
            _routeHash(address(nonInitializedIndex), SwapType.ASSET0_USDC),
            keccak256(abi.encode(r0)),
            "ASSET0_USDC route must be stored as given"
        );
        assertEq(
            _routeHash(address(nonInitializedIndex), SwapType.ASSET1_USDC),
            keccak256(abi.encode(r1)),
            "ASSET1_USDC route must be stored as given"
        );
        assertEq(
            _routeHash(address(nonInitializedIndex), SwapType.ASSET0_ASSET1),
            keccak256(abi.encode(r01)),
            "ASSET0_ASSET1 route must be stored as given"
        );
    }

    // =========================================================================
    //  registerIndex — V3 specifics
    // =========================================================================

    function testRegisterIndexAcceptsReversedV3Paths() public {
        SwapRoute memory r0 = _v3SingleHop(s_usdc, s_asset0);
        SwapRoute memory r1 = _v3SingleHop(s_usdc, s_asset1);
        SwapRoute memory r01 = _v3SingleHop(s_asset1, s_asset0);

        _registerNonInitializedIndex(r0, r1, r01);

        assertEq(
            keccak256(
                swapManager
                    .getRoute(address(nonInitializedIndex), SwapType.ASSET0_USDC)
                    .v3Path
            ),
            keccak256(r0.v3Path),
            "reversed ASSET0_USDC path must be stored unchanged"
        );
        assertEq(
            keccak256(
                swapManager
                    .getRoute(address(nonInitializedIndex), SwapType.ASSET1_USDC)
                    .v3Path
            ),
            keccak256(r1.v3Path),
            "reversed ASSET1_USDC path must be stored unchanged"
        );
        assertEq(
            keccak256(
                swapManager
                    .getRoute(
                        address(nonInitializedIndex),
                        SwapType.ASSET0_ASSET1
                    )
                    .v3Path
            ),
            keccak256(r01.v3Path),
            "reversed ASSET0_ASSET1 path must be stored unchanged"
        );
    }

    function testRegisterIndexAcceptsMultiHopV3PathWithCorrectEndpoints()
        public
    {
        // asset0 → outsider → usdc: intermediate hops are allowed
        SwapRoute memory r0 = _v3TwoHop(s_asset0, s_outsiderToken, s_usdc);

        _registerNonInitializedIndex(
            r0,
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );

        SwapRoute memory stored = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC
        );
        assertEq(
            stored.v3Path.length,
            r0.v3Path.length,
            "multi-hop path length must be preserved"
        );
        assertEq(
            keccak256(stored.v3Path),
            keccak256(r0.v3Path),
            "multi-hop path must be stored unchanged"
        );
    }

    function testRegisterIndexRevertsIfMultiHopV3PathEndsOnWrongToken()
        public
    {
        // asset0 → usdc → outsider: last token is not USDC
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_usdc
            )
        );
        _registerNonInitializedIndex(
            _v3TwoHop(s_asset0, s_usdc, s_outsiderToken),
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );
    }

    function testRegisterIndexRevertsIfMultiHopV3PathStartsOnWrongToken()
        public
    {
        // outsider → asset0 → usdc: first token is not asset0
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_usdc
            )
        );
        _registerNonInitializedIndex(
            _v3TwoHop(s_outsiderToken, s_asset0, s_usdc),
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );
    }

    function testRegisterIndexRevertsIfV3PathLengthIsMalformed() public {
        // 43 + 1 = 44 bytes: above the minimum but (44 - 20) % 23 != 0
        bytes memory malformedPath = abi.encodePacked(
            s_asset0,
            V3_POOL_FEE,
            s_usdc,
            bytes1(0x00)
        );
        assertEq(
            malformedPath.length,
            20 + V3_HOP_LENGTH + MALFORMED_PATH_EXTRA_BYTES,
            "fixture: path must be 44 bytes"
        );

        vm.expectRevert(SwapManager.SwapManager__InvalidV3Path.selector);
        _registerNonInitializedIndex(
            _v3Route(malformedPath),
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );
    }

    function testRegisterIndexRevertsIfMultiHopV3PathLengthIsMalformed()
        public
    {
        // valid two-hop (66 bytes) + 1 trailing byte = 67
        bytes memory malformedPath = abi.encodePacked(
            s_asset0,
            V3_POOL_FEE,
            s_outsiderToken,
            V3_POOL_FEE,
            s_usdc,
            bytes1(0x00)
        );

        vm.expectRevert(SwapManager.SwapManager__InvalidV3Path.selector);
        _registerNonInitializedIndex(
            _v3Route(malformedPath),
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );
    }

    function testRegisterIndexLeavesRoutesUnsetWhenValidationFails() public {
        bytes32 emptyRouteHash = _routeHash(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_asset1
            )
        );
        _registerNonInitializedIndex(
            _v3SingleHop(s_asset0, s_usdc),
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset1, s_usdc)
        );

        assertEq(
            _routeHash(address(nonInitializedIndex), SwapType.ASSET0_USDC),
            emptyRouteHash,
            "no route must be stored after a failed registration"
        );
    }

    // =========================================================================
    //  registerIndex — index address
    // =========================================================================

    function testRegisterIndexRevertsIfIndexAddressHasNoCode() public {
        // A staticcall to an EOA succeeds with empty return data (< 32 bytes) → NotAnIndex.
        assertEq(eoaIndex.code.length, 0, "fixture: eoaIndex must have no code");

        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__NotAnIndex.selector,
                eoaIndex
            )
        );
        _registerWithValidRoutes(eoaIndex);
    }

    function testRegisterIndexRevertsIfIndexContractLacksGetters() public {
        // An ERC20 has code but no getAsset0: the staticcall fails → NotAnIndex.
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__NotAnIndex.selector,
                s_contractWithoutGetters
            )
        );
        _registerWithValidRoutes(s_contractWithoutGetters);
    }

    function testRegisterIndexRevertsIfIndexGetterReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__NotAnIndex.selector,
                address(revertingIndexMock)
            )
        );
        _registerWithValidRoutes(address(revertingIndexMock));
    }

    function testRegisterIndexRevertsIfIndexGetterReturnsDirtyAddressWord()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__NotAnIndex.selector,
                address(dirtyWordIndexMock)
            )
        );
        _registerWithValidRoutes(address(dirtyWordIndexMock));
    }

    function testRegisterIndexNotAnIndexTakesPrecedenceOverInvalidRoutes()
        public
    {
        // Every route is invalid (malformed V3 path, zero V4 key, wrong pair), yet the index check
        // runs first, so the revert is NotAnIndex instead of a route error.
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__NotAnIndex.selector,
                eoaIndex
            )
        );
        vm.prank(address(indexManager));
        swapManager.registerIndex(
            eoaIndex,
            _v3Route(bytes("")),
            _v4Route(address(0), address(0)),
            _v3SingleHop(s_outsiderToken, s_usdc)
        );
    }

    function testRegisterIndexLeavesRoutesUnsetWhenIndexIsNotAnIndex()
        public
    {
        bytes32 emptyRouteHash = _routeHash(eoaIndex, SwapType.ASSET0_ASSET1);

        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__NotAnIndex.selector,
                eoaIndex
            )
        );
        _registerWithValidRoutes(eoaIndex);

        assertEq(
            _routeHash(eoaIndex, SwapType.ASSET0_ASSET1),
            emptyRouteHash,
            "no route must be stored for a non-index address"
        );
    }

    // =========================================================================
    //  updateRoute — index address
    // =========================================================================

    function testUpdateRouteRevertsIndexNotRegisteredOnEoa() public {
        // onlyRegisteredIndex runs before the getters are read: NotAnIndex is never reached.
        vm.expectRevert(SwapManager.SwapManager__IndexNotRegistered.selector);
        vm.prank(address(indexManager));
        swapManager.updateRoute(
            eoaIndex,
            SwapType.ASSET0_USDC,
            _v3SingleHop(s_asset0, s_usdc)
        );
    }

    function testUpdateRouteRevertsIndexNotRegisteredOnContractWithoutGetters()
        public
    {
        vm.expectRevert(SwapManager.SwapManager__IndexNotRegistered.selector);
        vm.prank(address(indexManager));
        swapManager.updateRoute(
            s_contractWithoutGetters,
            SwapType.ASSET0_ASSET1,
            _v3SingleHop(s_asset0, s_asset1)
        );
    }

    // =========================================================================
    //  updateRoute — wrong pair per SwapType
    // =========================================================================

    function testUpdateRouteRevertsIfAsset0UsdcRouteConnectsWrongPair()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_initAsset0,
                s_usdc
            )
        );
        _updateInitializedIndexRoute(
            SwapType.ASSET0_USDC,
            _v3SingleHop(s_initAsset1, s_usdc)
        );
    }

    function testUpdateRouteRevertsIfAsset1UsdcRouteConnectsWrongPair()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_initAsset1,
                s_usdc
            )
        );
        _updateInitializedIndexRoute(
            SwapType.ASSET1_USDC,
            _v3SingleHop(s_initAsset0, s_usdc)
        );
    }

    function testUpdateRouteRevertsIfAsset0Asset1RouteConnectsWrongPair()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_initAsset0,
                s_initAsset1
            )
        );
        _updateInitializedIndexRoute(
            SwapType.ASSET0_ASSET1,
            _v4Route(s_initAsset0, s_usdc)
        );
    }

    function testUpdateRouteRevertsIfV4RouteUsesNativeEth() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_initAsset0,
                s_usdc
            )
        );
        _updateInitializedIndexRoute(
            SwapType.ASSET0_USDC,
            _v4Route(address(0), s_usdc)
        );
    }

    function testUpdateRouteRevertsIfV3PathLengthIsMalformed() public {
        bytes memory malformedPath = abi.encodePacked(
            s_initAsset1,
            V3_POOL_FEE,
            s_usdc,
            bytes1(0x00)
        );

        vm.expectRevert(SwapManager.SwapManager__InvalidV3Path.selector);
        _updateInitializedIndexRoute(
            SwapType.ASSET1_USDC,
            _v3Route(malformedPath)
        );
    }

    function testUpdateRouteRevertsIfMultiHopV3PathEndsOnWrongToken()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_initAsset0,
                s_initAsset1
            )
        );
        _updateInitializedIndexRoute(
            SwapType.ASSET0_ASSET1,
            _v3TwoHop(s_initAsset0, s_initAsset1, s_outsiderToken)
        );
    }

    function testUpdateRouteKeepsPreviousRouteWhenValidationFails() public {
        bytes32 routeBefore = _routeHash(
            address(initializedIndex),
            SwapType.ASSET0_USDC
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_initAsset0,
                s_usdc
            )
        );
        _updateInitializedIndexRoute(
            SwapType.ASSET0_USDC,
            _v3SingleHop(s_outsiderToken, s_usdc)
        );

        assertEq(
            _routeHash(address(initializedIndex), SwapType.ASSET0_USDC),
            routeBefore,
            "stored route must not change after a rejected update"
        );
    }

    // =========================================================================
    //  updateRoute — accepted shapes
    // =========================================================================

    function testUpdateRouteAcceptsReversedV3Path() public {
        bytes32 asset0UsdcBefore = _routeHash(
            address(initializedIndex),
            SwapType.ASSET0_USDC
        );
        bytes32 asset0Asset1Before = _routeHash(
            address(initializedIndex),
            SwapType.ASSET0_ASSET1
        );
        SwapRoute memory reversed = _v3SingleHop(s_usdc, s_initAsset1);

        _updateInitializedIndexRoute(SwapType.ASSET1_USDC, reversed);

        assertEq(
            _routeHash(address(initializedIndex), SwapType.ASSET1_USDC),
            keccak256(abi.encode(reversed)),
            "reversed path must be stored"
        );
        assertEq(
            _routeHash(address(initializedIndex), SwapType.ASSET0_USDC),
            asset0UsdcBefore,
            "ASSET0_USDC must be unchanged"
        );
        assertEq(
            _routeHash(address(initializedIndex), SwapType.ASSET0_ASSET1),
            asset0Asset1Before,
            "ASSET0_ASSET1 must be unchanged"
        );
    }

    function testUpdateRouteAcceptsMultiHopV3PathWithCorrectEndpoints()
        public
    {
        // asset0 → usdc → asset1
        SwapRoute memory multiHop = _v3TwoHop(
            s_initAsset0,
            s_usdc,
            s_initAsset1
        );

        _updateInitializedIndexRoute(SwapType.ASSET0_ASSET1, multiHop);

        assertEq(
            _routeHash(address(initializedIndex), SwapType.ASSET0_ASSET1),
            keccak256(abi.encode(multiHop)),
            "multi-hop route must be stored"
        );
    }

    function testUpdateRouteAcceptsV4RouteWithCurrenciesReversed() public {
        SwapRoute memory v4Reversed = _v4Route(s_usdc, s_initAsset0);

        _updateInitializedIndexRoute(SwapType.ASSET0_USDC, v4Reversed);

        SwapRoute memory stored = swapManager.getRoute(
            address(initializedIndex),
            SwapType.ASSET0_USDC
        );
        assertEq(uint8(stored.version), uint8(PoolVersion.V4));
        assertEq(Currency.unwrap(stored.poolKey.currency0), s_usdc);
        assertEq(Currency.unwrap(stored.poolKey.currency1), s_initAsset0);
    }

    // =========================================================================
    //  _validateRoute (harness)
    // =========================================================================

    /// @dev _validateRoute treats every non-V4 version as V3. An out-of-range PoolVersion can never
    ///      reach that V3 branch: ABI decoding rejects it on every external entry point, and even a
    ///      raw value forced into memory makes the compiler-inserted enum check panic (0x21) first.
    function testValidateRouteOutOfRangePoolVersionPanicsWithEnumConversionError()
        public
    {
        vm.expectRevert(stdError.enumConversionError);
        harness.exposed_validateRouteWithRawVersion(
            _v3SingleHop(s_asset0, s_usdc),
            s_invalidPoolVersion,
            s_asset0,
            s_usdc
        );
    }

    function testValidateRouteRevertsIfV4Currency1IsNativeEth() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_usdc
            )
        );
        harness.exposed_validateRoute(
            _v4Route(s_asset0, address(0)),
            s_asset0,
            s_usdc
        );
    }

    function testValidateRouteRevertsIfV4RouteRepeatsOneExpectedToken()
        public
    {
        // {asset0, asset0} contains asset0 but not usdc
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_usdc
            )
        );
        harness.exposed_validateRoute(
            _v4Route(s_asset0, s_asset0),
            s_asset0,
            s_usdc
        );
    }

    function testValidateRouteAcceptsV3PathInBothDirections() public view {
        harness.exposed_validateRoute(
            _v3SingleHop(s_asset0, s_usdc),
            s_asset0,
            s_usdc
        );
        harness.exposed_validateRoute(
            _v3SingleHop(s_usdc, s_asset0),
            s_asset0,
            s_usdc
        );
    }

    // =========================================================================
    //  _getExpectedRouteTokens (harness)
    // =========================================================================

    function testGetExpectedRouteTokensReturnsPairForEverySwapType()
        public
        view
    {
        (address a, address b) = harness.exposed_getExpectedRouteTokens(
            address(harnessIndexMock),
            SwapType.ASSET0_USDC
        );
        assertEq(a, s_asset0, "ASSET0_USDC tokenA must be asset0");
        assertEq(b, s_usdc, "ASSET0_USDC tokenB must be usdc");

        (a, b) = harness.exposed_getExpectedRouteTokens(
            address(harnessIndexMock),
            SwapType.ASSET1_USDC
        );
        assertEq(a, s_asset1, "ASSET1_USDC tokenA must be asset1");
        assertEq(b, s_usdc, "ASSET1_USDC tokenB must be usdc");

        (a, b) = harness.exposed_getExpectedRouteTokens(
            address(harnessIndexMock),
            SwapType.ASSET0_ASSET1
        );
        assertEq(a, s_asset0, "ASSET0_ASSET1 tokenA must be asset0");
        assertEq(b, s_asset1, "ASSET0_ASSET1 tokenB must be asset1");
    }

    function testHarnessRegisterIndexAcceptsRoutesMatchingIndexTokensMock()
        public
    {
        SwapRoute memory r0 = _v4Route(s_asset0, s_usdc);
        SwapRoute memory r1 = _v3SingleHop(s_asset1, s_usdc);
        SwapRoute memory r01 = _v3SingleHop(s_asset0, s_asset1);

        harness.registerIndex(address(harnessIndexMock), r0, r1, r01);

        assertEq(
            keccak256(
                abi.encode(
                    harness.getRoute(
                        address(harnessIndexMock),
                        SwapType.ASSET0_USDC
                    )
                )
            ),
            keccak256(abi.encode(r0))
        );
        assertEq(
            keccak256(
                abi.encode(
                    harness.getRoute(
                        address(harnessIndexMock),
                        SwapType.ASSET1_USDC
                    )
                )
            ),
            keccak256(abi.encode(r1))
        );
        assertEq(
            keccak256(
                abi.encode(
                    harness.getRoute(
                        address(harnessIndexMock),
                        SwapType.ASSET0_ASSET1
                    )
                )
            ),
            keccak256(abi.encode(r01))
        );
    }

    // =========================================================================
    //  buildSingleSwapParams — V3 / V4 dispatch and registration check
    // =========================================================================

    function testBuildSingleSwapParamsBuildsV3RouteForRegisteredIndex()
        public
    {
        _registerNonInitializedIndex(
            _v3SingleHop(s_asset0, s_usdc),
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );

        (
            bytes memory commands,
            bytes[] memory inputs,
            address tokenIn,
            address tokenOut
        ) = swapManager.buildSingleSwapParams(
                address(nonInitializedIndex),
                SwapType.ASSET0_USDC,
                s_asset0,
                SWAP_AMOUNT_IN,
                SWAP_AMOUNT_OUT_MIN
            );

        assertEq(commands.length, 1, "single command expected");
        assertEq(
            uint8(commands[0]),
            uint8(Commands.V3_SWAP_EXACT_IN),
            "V3 route must encode V3_SWAP_EXACT_IN"
        );
        assertEq(inputs.length, 1, "single input expected");
        assertEq(tokenIn, s_asset0, "tokenIn must be asset0");
        assertEq(tokenOut, s_usdc, "tokenOut must be usdc");
    }

    function testBuildSingleSwapParamsBuildsV4RouteForRegisteredIndex()
        public
    {
        _registerNonInitializedIndex(
            _v4Route(s_asset0, s_usdc),
            _v4Route(s_asset1, s_usdc),
            _v4Route(s_asset0, s_asset1)
        );

        (
            bytes memory commands,
            bytes[] memory inputs,
            address tokenIn,
            address tokenOut
        ) = swapManager.buildSingleSwapParams(
                address(nonInitializedIndex),
                SwapType.ASSET1_USDC,
                s_usdc,
                SWAP_AMOUNT_IN,
                SWAP_AMOUNT_OUT_MIN
            );

        assertEq(commands.length, 1, "single command expected");
        assertEq(
            uint8(commands[0]),
            uint8(Commands.V4_SWAP),
            "V4 route must encode V4_SWAP"
        );
        assertEq(inputs.length, 1, "single input expected");
        assertEq(tokenIn, s_usdc, "tokenIn must be usdc");
        assertEq(tokenOut, s_asset1, "tokenOut must be asset1");
    }

    function testBuildSingleSwapParamsRevertsIfIndexHoldsDefaultRoute()
        public
    {
        // Unregistered index: ASSET0_ASSET1 is the default struct (V3, empty path).
        SwapRoute memory stored = swapManager.getRoute(
            address(nonInitializedIndex),
            SwapType.ASSET0_ASSET1
        );
        assertEq(uint8(stored.version), uint8(PoolVersion.V3));
        assertEq(stored.v3Path.length, 0);

        vm.expectRevert(SwapManager.SwapManager__IndexNotRegistered.selector);
        swapManager.buildSingleSwapParams(
            address(nonInitializedIndex),
            SwapType.ASSET0_USDC,
            s_asset0,
            SWAP_AMOUNT_IN,
            SWAP_AMOUNT_OUT_MIN
        );
    }

    function testBuildSingleSwapParamsRevertsIfAddressIsNotAnIndex() public {
        vm.expectRevert(SwapManager.SwapManager__IndexNotRegistered.selector);
        swapManager.buildSingleSwapParams(
            s_contractWithoutGetters,
            SwapType.ASSET0_USDC,
            s_asset0,
            SWAP_AMOUNT_IN,
            SWAP_AMOUNT_OUT_MIN
        );
    }
}
