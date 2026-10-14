// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseIndexFactoryTest} from "./BaseIndexFactory.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {IndexFactory} from "../../../src/IndexFactory.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {PriceFeedManager} from "../../../src/PriceFeedManager.sol";
import {Router} from "../../../src/Router.sol";
import {IndexAsset, IndexDeployParams} from "../../../src/types.sol";
import {IndexManager__InvalidIndexFactory} from "../../../src/errors/IndexManagerErrors.sol";

/**
 * @dev Wiring between the IndexManager and the IndexFactory: constructor validation of the factory,
 *      getIndexFactory, and indexes created through createIndex.
 */
contract IndexFactoryIndexManagerTest is BaseIndexFactoryTest {
    address internal s_swapManagerImplementation;
    address internal s_priceFeedManagerImplementation;
    address internal s_routerImplementation;

    function setUp() public override {
        super.setUp();
        s_swapManagerImplementation = address(new SwapManager());
        s_priceFeedManagerImplementation = address(new PriceFeedManager());
        s_routerImplementation = address(new Router());
    }

    // =========================================================================
    //  IndexManager constructor
    // =========================================================================

    function testIndexManagerConstructorRevertsIfFactoryHasNoCode() public {
        address noCode = makeAddr("noCodeFactory");
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__InvalidIndexFactory.selector,
                noCode
            )
        );
        _deployIndexManager(noCode);
    }

    function testIndexManagerConstructorRevertsIfFactoryIsZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__InvalidIndexFactory.selector,
                address(0)
            )
        );
        _deployIndexManager(address(0));
    }

    function testIndexManagerConstructorStoresTheFactory() public {
        IndexFactory freshFactory = new IndexFactory(s_indexCreationCode);
        IndexManager freshManager = _deployIndexManager(address(freshFactory));
        assertEq(freshManager.getIndexFactory(), address(freshFactory));
    }

    // =========================================================================
    //  getIndexFactory
    // =========================================================================

    function testGetIndexFactoryReturnsConfiguredFactory() public view {
        assertEq(indexManager.getIndexFactory(), address(indexFactory));
        assertGt(address(indexFactory).code.length, 0, "factory must have code");
    }

    // =========================================================================
    //  createIndex through the factory
    // =========================================================================

    function testCreatedIndexIsManagedByTheIndexManager() public view {
        assertEq(nonInitializedIndex.getIndexManager(), address(indexManager));
        assertEq(initializedIndex.getIndexManager(), address(indexManager));
    }

    function testCreatedIndexIsDeployedByTheFactoryAtExpectedAddress() public view {
        // Rebuild the params the IndexManager passed to the factory for the base WBTC/LINK index.
        IndexDeployParams memory params = _defaultParams();
        params.name = nonInitializedIndex.name();
        params.symbol = nonInitializedIndex.symbol();
        (uint128 weight0, uint128 weight1) = nonInitializedIndex.getAssetsWeights();
        params.asset0 = IndexAsset({asset: nonInitializedToken0, weightPercentage: weight0});
        params.asset1 = IndexAsset({asset: nonInitializedToken1, weightPercentage: weight1});
        (params.feePercentage, ) = nonInitializedIndex.getFeesInfo();
        params.universalRouter = indexManager.getUniswapUniversalRouter();
        params.priceFeedManager = indexManager.getPriceFeedManagerAddress();
        params.swapManager = indexManager.getSwapManagerAddress();
        params.router = indexManager.getRouterAddress();
        bytes32 salt = keccak256(
            abi.encodePacked(nonInitializedToken0, nonInitializedToken1)
        );

        assertEq(
            address(nonInitializedIndex),
            _expectedIndexAddress(params, address(indexManager), salt),
            "index must be the factory CREATE2 output with the IndexManager as deployer-of-record"
        );
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _deployIndexManager(address _factory) internal returns (IndexManager) {
        return
            new IndexManager(
                address(mockUsdc),
                address(mockUniRouter),
                s_swapManagerImplementation,
                s_priceFeedManagerImplementation,
                s_routerImplementation,
                address(timelock),
                _factory
            );
    }
}
