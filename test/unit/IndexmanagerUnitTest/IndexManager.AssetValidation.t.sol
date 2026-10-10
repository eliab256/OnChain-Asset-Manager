// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Index} from "../../../src/Index.sol";
import {IndexAsset} from "../../../src/types.sol";
import {AssetTokenMock} from "../../mocks/AssetTokenMock.sol";
import {
    DecimalsRevertingTokenMock,
    NoDecimalsTokenMock,
    ShortDecimalsReturnTokenMock,
    ConstructorDecimalsRevertingTokenMock
} from "../../mocks/DecimalsTokenMocks.sol";

import "../../../src/errors/IndexManagerErrors.sol";

/**
 * @dev L-04: createIndex validates `decimals()` of both assets (must succeed, return a full word
 *      and be <= DECIMALS_STANDARD) and reverts IndexManager__IndexDeployFailed when create2
 *      returns address(0) because the Index constructor reverted.
 */
contract IndexManagerAssetValidationTest is BaseTest {
    // Fixed addresses below / above every deployed token, so the sorted position
    // (asset0 or asset1) of the token under test is deterministic.
    address internal constant LOW_TOKEN_ADDRESS = address(0x2000);
    address internal constant HIGH_TOKEN_ADDRESS =
        address(type(uint160).max - 0x2000);

    // =========================================================================
    //  Values derived from the contracts (assigned in setUp)
    // =========================================================================

    /// Largest accepted decimals (DECIMALS_STANDARD) and the first rejected value
    uint8 s_maxValidDecimals;
    uint8 s_invalidDecimals;
    /// Valid counterpart asset with a registered price feed
    address s_validAsset;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();
        s_maxValidDecimals = DECIMALS_STANDARD;
        s_invalidDecimals = DECIMALS_STANDARD + 1;
        s_validAsset = address(mockWeth);
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev Deploys an AssetTokenMock with `_decimals` at `_target`.
    function _deployAssetTokenAt(
        address _target,
        uint8 _decimals
    ) internal returns (address) {
        deployCodeTo(
            "AssetTokenMock.sol:AssetTokenMock",
            abi.encode("Decimals Test", "DEC", _decimals),
            _target
        );
        return _target;
    }

    /// @dev Registers a working price feed for `_asset` (the feed is not tied to the token).
    function _registerFeedFor(address _asset) internal {
        _registerPriceFeedIfMissing(
            _asset,
            address(mockLinkPriceFeed),
            assetPriceFeedMaxDelay
        );
    }

    /// @dev Calls createIndex as the asset manager with `_assetA` (60%) and `_assetB` (40%).
    function _createIndex(
        address _assetA,
        address _assetB
    ) internal returns (address indexAddress, address token0, address token1) {
        vm.prank(deployer);
        (indexAddress, token0, token1) = indexManager.createIndex(
            validFeePercentage,
            IndexAsset({asset: _assetA, weightPercentage: weight60}),
            IndexAsset({asset: _assetB, weightPercentage: weight40})
        );
    }

    // =========================================================================
    //  createIndex — decimals validation
    // =========================================================================

    function testCreateIndexRevertsIfAsset0HasMoreThanStandardDecimals()
        public
    {
        address token = _deployAssetTokenAt(
            LOW_TOKEN_ADDRESS,
            s_invalidDecimals
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__InvalidAssetDecimals.selector,
                token
            )
        );
        _createIndex(token, s_validAsset);
    }

    function testCreateIndexRevertsIfAsset1HasMoreThanStandardDecimals()
        public
    {
        address token = _deployAssetTokenAt(
            HIGH_TOKEN_ADDRESS,
            s_invalidDecimals
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__InvalidAssetDecimals.selector,
                token
            )
        );
        _createIndex(s_validAsset, token);
    }

    function testCreateIndexRevertsIfAssetDecimalsReverts() public {
        address token = address(new DecimalsRevertingTokenMock());

        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__InvalidAssetDecimals.selector,
                token
            )
        );
        _createIndex(token, s_validAsset);
    }

    function testCreateIndexRevertsIfAssetHasSymbolButNoDecimals() public {
        address token = address(new NoDecimalsTokenMock());

        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__InvalidAssetDecimals.selector,
                token
            )
        );
        _createIndex(token, s_validAsset);
    }

    function testCreateIndexRevertsIfAssetDecimalsReturnsLessThanOneWord()
        public
    {
        address token = address(new ShortDecimalsReturnTokenMock());

        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__InvalidAssetDecimals.selector,
                token
            )
        );
        _createIndex(token, s_validAsset);
    }

    function testCreateIndexAcceptsAssetWithStandardDecimals() public {
        address token = address(
            new AssetTokenMock("Standard", "STD", s_maxValidDecimals)
        );
        _registerFeedFor(token);
        uint256 deployedBefore = indexManager.getDeployedIndexes().length;

        (address indexAddress, address token0, address token1) = _createIndex(
            token,
            s_validAsset
        );

        assertTrue(indexManager.isIndexAddress(indexAddress), "index must be registered");
        assertEq(
            indexManager.getDeployedIndexes().length,
            deployedBefore + 1,
            "deployed indexes must grow by one"
        );
        assertEq(
            indexManager.getIndexByAssetsAddresses(token, s_validAsset),
            indexAddress
        );
        (uint8 decimals0, uint8 decimals1, ) = Index(indexAddress)
            .getAssetsAndUsdcDecimals();
        uint8 tokenDecimals = token0 == token ? decimals0 : decimals1;
        assertEq(
            tokenDecimals,
            s_maxValidDecimals,
            "index must store the token decimals"
        );
        assertTrue(token1 == token || token0 == token);
    }

    // =========================================================================
    //  createIndex — create2 failure
    // =========================================================================

    function testCreateIndexRevertsIfIndexConstructorReverts() public {
        // decimals() is valid for the IndexManager validation but reverts when called by the
        // Index under construction, so create2 returns address(0).
        address token = address(new ConstructorDecimalsRevertingTokenMock());
        _registerFeedFor(token);

        vm.expectRevert(IndexManager__IndexDeployFailed.selector);
        _createIndex(token, s_validAsset);
    }

    function testCreateIndexStoresNothingWhenIndexDeployFails() public {
        address token = address(new ConstructorDecimalsRevertingTokenMock());
        _registerFeedFor(token);
        uint256 deployedBefore = indexManager.getDeployedIndexes().length;

        vm.expectRevert(IndexManager__IndexDeployFailed.selector);
        _createIndex(token, s_validAsset);

        assertEq(
            indexManager.getDeployedIndexes().length,
            deployedBefore,
            "no index must be recorded"
        );
        assertEq(
            indexManager.getIndexByAssetsAddresses(token, s_validAsset),
            address(0),
            "pair lookup must stay empty"
        );
    }
}
