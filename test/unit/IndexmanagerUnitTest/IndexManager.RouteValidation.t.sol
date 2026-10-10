// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {SwapType, SwapRoute, PoolVersion} from "../../../src/types.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev L-04: initializeIndex forwards the three routes to SwapManager.registerIndex, which must
 *      reject any route that does not connect the index tokens expected for its SwapType.
 *      A rejected route reverts the whole initialization (the index stays uninitialized).
 */
contract IndexManagerRouteValidationTest is BaseTest {
    // =========================================================================
    //  Constants
    // =========================================================================

    uint24 constant V3_POOL_FEE = 3000;
    uint24 constant V4_POOL_FEE = 3000;
    int24 constant V4_TICK_SPACING = 60;

    // =========================================================================
    //  Values derived from the deployed contracts (assigned in setUp)
    // =========================================================================

    address s_asset0;
    address s_asset1;
    address s_usdc;
    /// Token that is neither asset nor USDC of nonInitializedIndex
    address s_outsiderToken;
    /// Seed amount of asset0 (one whole token in its own decimals)
    uint256 s_initAmount;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();

        s_asset0 = nonInitializedIndex.getAsset0();
        s_asset1 = nonInitializedIndex.getAsset1();
        s_usdc = nonInitializedIndex.getUsdc();
        s_outsiderToken = address(mockComp);

        (uint8 decimals0, , ) = nonInitializedIndex.getAssetsAndUsdcDecimals();
        s_initAmount = 10 ** decimals0;

        // The depositor (deployer) funds the seed of both assets.
        vm.startPrank(deployer);
        IERC20(s_asset0).approve(
            address(nonInitializedIndex),
            type(uint256).max
        );
        IERC20(s_asset1).approve(
            address(nonInitializedIndex),
            type(uint256).max
        );
        vm.stopPrank();
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

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

    function _v3SingleHop(
        address _tokenIn,
        address _tokenOut
    ) internal pure returns (SwapRoute memory) {
        return _v3Route(abi.encodePacked(_tokenIn, V3_POOL_FEE, _tokenOut));
    }

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

    /// @dev Initializes `nonInitializedIndex` through the IndexManager as the asset manager.
    function _initializeWithRoutes(
        SwapRoute memory _r0,
        SwapRoute memory _r1,
        SwapRoute memory _r01
    ) internal {
        vm.prank(deployer);
        indexManager.initializeIndex(
            deployer,
            address(nonInitializedIndex),
            s_initAmount,
            _r0,
            _r1,
            _r01
        );
    }

    function _assertNotInitialized() internal view {
        assertFalse(
            indexManager.checkIsIndexInitialized(address(nonInitializedIndex)),
            "index must stay uninitialized after a rejected route"
        );
        assertFalse(
            nonInitializedIndex.getInitializationStatus(),
            "Index contract must stay uninitialized"
        );
    }

    function _assertStoredRoute(
        SwapType _swapType,
        SwapRoute memory _expected
    ) internal view {
        assertEq(
            keccak256(
                abi.encode(
                    swapManager.getRoute(address(nonInitializedIndex), _swapType)
                )
            ),
            keccak256(abi.encode(_expected)),
            "stored route must match the one passed to initializeIndex"
        );
    }

    // =========================================================================
    //  initializeIndex — wrong pair per SwapType
    // =========================================================================

    function testInitializeIndexRevertsIfAsset0UsdcRouteConnectsWrongPair()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_usdc
            )
        );
        _initializeWithRoutes(
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );
        _assertNotInitialized();
    }

    function testInitializeIndexRevertsIfAsset1UsdcRouteConnectsWrongPair()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset1,
                s_usdc
            )
        );
        _initializeWithRoutes(
            _v3SingleHop(s_asset0, s_usdc),
            _v3SingleHop(s_outsiderToken, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );
        _assertNotInitialized();
    }

    function testInitializeIndexRevertsIfAsset0Asset1RouteConnectsWrongPair()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_asset1
            )
        );
        _initializeWithRoutes(
            _v3SingleHop(s_asset0, s_usdc),
            _v3SingleHop(s_asset1, s_usdc),
            _v4Route(s_asset0, s_usdc)
        );
        _assertNotInitialized();
    }

    function testInitializeIndexRevertsIfRoutesAreSwappedBetweenTypes()
        public
    {
        // The ASSET1_USDC route passed where ASSET0_USDC is expected
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_usdc
            )
        );
        _initializeWithRoutes(
            _v3SingleHop(s_asset1, s_usdc),
            _v3SingleHop(s_asset0, s_usdc),
            _v3SingleHop(s_asset0, s_asset1)
        );
        _assertNotInitialized();
    }

    // =========================================================================
    //  initializeIndex — V4
    // =========================================================================

    function testInitializeIndexRevertsIfV4RouteUsesNativeEth() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_usdc
            )
        );
        _initializeWithRoutes(
            _v4Route(address(0), s_usdc),
            _v4Route(s_asset1, s_usdc),
            _v4Route(s_asset0, s_asset1)
        );
        _assertNotInitialized();
    }

    function testInitializeIndexAcceptsV4RoutesWithCurrenciesInEitherOrder()
        public
    {
        SwapRoute memory r0 = _v4Route(s_usdc, s_asset0);
        SwapRoute memory r1 = _v4Route(s_asset1, s_usdc);
        SwapRoute memory r01 = _v4Route(s_asset1, s_asset0);

        assertFalse(
            indexManager.checkIsIndexInitialized(address(nonInitializedIndex))
        );

        _initializeWithRoutes(r0, r1, r01);

        assertTrue(
            indexManager.checkIsIndexInitialized(address(nonInitializedIndex)),
            "index must be initialized"
        );
        _assertStoredRoute(SwapType.ASSET0_USDC, r0);
        _assertStoredRoute(SwapType.ASSET1_USDC, r1);
        _assertStoredRoute(SwapType.ASSET0_ASSET1, r01);
    }

    // =========================================================================
    //  initializeIndex — V3
    // =========================================================================

    function testInitializeIndexAcceptsReversedV3Paths() public {
        SwapRoute memory r0 = _v3SingleHop(s_usdc, s_asset0);
        SwapRoute memory r1 = _v3SingleHop(s_usdc, s_asset1);
        SwapRoute memory r01 = _v3SingleHop(s_asset1, s_asset0);

        _initializeWithRoutes(r0, r1, r01);

        assertTrue(
            indexManager.checkIsIndexInitialized(address(nonInitializedIndex)),
            "index must be initialized"
        );
        _assertStoredRoute(SwapType.ASSET0_USDC, r0);
        _assertStoredRoute(SwapType.ASSET1_USDC, r1);
        _assertStoredRoute(SwapType.ASSET0_ASSET1, r01);
    }

    function testInitializeIndexAcceptsMultiHopV3PathWithCorrectEndpoints()
        public
    {
        SwapRoute memory r0 = _v3TwoHop(s_asset0, s_outsiderToken, s_usdc);
        SwapRoute memory r1 = _v3SingleHop(s_asset1, s_usdc);
        SwapRoute memory r01 = _v3TwoHop(s_asset0, s_usdc, s_asset1);

        _initializeWithRoutes(r0, r1, r01);

        assertTrue(
            indexManager.checkIsIndexInitialized(address(nonInitializedIndex)),
            "index must be initialized"
        );
        _assertStoredRoute(SwapType.ASSET0_USDC, r0);
        _assertStoredRoute(SwapType.ASSET0_ASSET1, r01);
    }

    function testInitializeIndexRevertsIfMultiHopV3PathHasWrongEndpoint()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapManager.SwapManager__RouteTokensMismatch.selector,
                s_asset0,
                s_asset1
            )
        );
        _initializeWithRoutes(
            _v3SingleHop(s_asset0, s_usdc),
            _v3SingleHop(s_asset1, s_usdc),
            _v3TwoHop(s_asset0, s_asset1, s_outsiderToken)
        );
        _assertNotInitialized();
    }

    function testInitializeIndexRevertsIfV3PathLengthIsMalformed() public {
        // 44 bytes: valid single hop + 1 trailing byte
        bytes memory malformedPath = abi.encodePacked(
            s_asset1,
            V3_POOL_FEE,
            s_usdc,
            bytes1(0x00)
        );

        vm.expectRevert(SwapManager.SwapManager__InvalidV3Path.selector);
        _initializeWithRoutes(
            _v3SingleHop(s_asset0, s_usdc),
            _v3Route(malformedPath),
            _v3SingleHop(s_asset0, s_asset1)
        );
        _assertNotInitialized();
    }
}
