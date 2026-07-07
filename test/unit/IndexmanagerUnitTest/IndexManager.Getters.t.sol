// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/contracts/periphery/IndexManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute} from "../../../src/contracts/types.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";

import "../../../src/errors/IndexManagerErrors.sol";
import "../../../src/events/IndexManagerEvents.sol";
import "../../../src/errors/IndexErrors.sol";

contract IndexManagerTest is BaseTest {

    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  Getter functions
    // =========================================================================

    function testIsIndexAddressReturnsTrueForDeployedIndex() public view {
        assertTrue(
            indexManager.isIndexAddress(address(initializedIndex)),
            "Initialized index must be recognized"
        );
    }

    function testIsIndexAddressReturnsTrueForNonInitializedIndex() public view {
        assertTrue(
            indexManager.isIndexAddress(address(nonInitializedIndex)),
            "Non-initialized but deployed index must be recognized"
        );
    }

    function testIsIndexAddressReturnsFalseForRandomAddress() public view {
        assertFalse(
            indexManager.isIndexAddress(user1),
            "Random address must not be recognized as index"
        );
    }

    function testIsIndexAddressReturnsFalseForZeroAddress() public view {
        assertFalse(
            indexManager.isIndexAddress(address(0)),
            "Zero address must not be recognized as index"
        );
    }

    // ── checkIsIndexInitialized ──

    function testCheckIsIndexInitializedReturnsTrueForInitializedIndex()
        public
        view
    {
        assertTrue(
            indexManager.checkIsIndexInitialized(address(initializedIndex)),
            "Initialized index must return true"
        );
    }

    function testCheckIsIndexInitializedReturnsFalseForNonInitializedIndex()
        public
        view
    {
        assertFalse(
            indexManager.checkIsIndexInitialized(address(nonInitializedIndex)),
            "Non-initialized index must return false"
        );
    }

    function testCheckIsIndexInitializedReturnsFalseForRandomAddress()
        public
        view
    {
        assertFalse(
            indexManager.checkIsIndexInitialized(user1),
            "Random address must return false"
        );
    }

    function testGetIndexAssetsReturnsCorrectAssetsForInitializedIndex()
        public
        view
    {
        (address asset0, address asset1) = indexManager.getIndexAssets(
            address(initializedIndex)
        );
        assertEq(asset0, initializedToken0, "asset0 must match");
        assertEq(asset1, initializedToken1, "asset1 must match");
    }

    function testGetIndexAssetsReturnsCorrectAssetsForNonInitializedIndex()
        public
        view
    {
        (address asset0, address asset1) = indexManager.getIndexAssets(
            address(nonInitializedIndex)
        );
        assertEq(asset0, nonInitializedToken0, "asset0 must match");
        assertEq(asset1, nonInitializedToken1, "asset1 must match");
    }

    function testGetIndexAssetsReturnsZerosForUnknownAddress() public view {
        (address asset0, address asset1) = indexManager.getIndexAssets(user2);
        assertEq(asset0, address(0), "asset0 must be zero");
        assertEq(asset1, address(0), "asset1 must be zero");
    }

    function testGetIndexByAssetsAddressesReturnsCorrectIndex() public view {
        address index = indexManager.getIndexByAssetsAddresses(
            initializedToken0,
            initializedToken1
        );
        assertEq(
            index,
            address(initializedIndex),
            "Must return the initialized index"
        );
    }

    function testGetIndexByAssetsAddressesWorksRegardlessOfOrder() public view {
        address indexAB = indexManager.getIndexByAssetsAddresses(
            initializedToken0,
            initializedToken1
        );
        address indexBA = indexManager.getIndexByAssetsAddresses(
            initializedToken1,
            initializedToken0
        );
        assertEq(indexAB, indexBA, "Order must not matter");
    }

    function testGetIndexByAssetsAddressesReturnsZeroForNonExistentPair()
        public
        view
    {
        address index = indexManager.getIndexByAssetsAddresses(user2, user3);
        assertEq(index, address(0), "Must return zero for non-existent pair");
    }

    function testGetRouterAddressReturnsCorrectAddress() public view {
        assertEq(
            indexManager.getRouterAddress(),
            address(router),
            "Router address must match"
        );
    }

    function testGetSwapManagerAddressReturnsCorrectAddress() public view {
        assertEq(
            indexManager.getSwapManagerAddress(),
            address(swapManager),
            "Swap manager address must match"
        );
    }

    function testGetDeployedIndexesIncludesAllDeployedIndexes() public view {
        address[] memory deployed = indexManager.getDeployedIndexes();
        // BaseTest deploys 2 indexes: initializedIndex + nonInitializedIndex
        assertEq(deployed.length, 2, "Must have 2 deployed indexes");
        assertEq(
            deployed[0],
            address(initializedIndex),
            "First must be initializedIndex"
        );
        assertEq(
            deployed[1],
            address(nonInitializedIndex),
            "Second must be nonInitializedIndex"
        );
    }

    // ── getInitializedIndexes ──

    function testGetInitializedIndexesOnlyIncludesInitialized() public view {
        address[] memory initialized = indexManager.getInitializedIndexes();
        assertEq(initialized.length, 1, "Must have 1 initialized index");
        assertEq(
            initialized[0],
            address(initializedIndex),
            "Must be the initializedIndex"
        );
    }

    function testGetTotalFeesCollectedIsZeroAtStart() public view {
        assertEq(
            indexManager.getTotalFeesCollected(),
            0,
            "Total fees must be zero at start"
        );
    }

    function testGetUsdcReturnsCorrectAddress() public view {
        assertEq(
            indexManager.getUsdc(),
            address(mockUsdc),
            "USDC address must match mock"
        );
    }

    function testGetUsdcPriceFeedReturnsCorrectAddress() public view {
        assertEq(
            indexManager.getUsdcPriceFeed(),
            address(mockUsdcPriceFeed),
            "USDC price feed must match mock"
        );
    }

    function testGetUniswapUniversalRouterReturnsCorrectAddress() public view {
        assertEq(
            indexManager.getUniswapUniversalRouter(),
            address(mockUniRouter),
            "Uniswap router must match mock"
        );
    }
}
