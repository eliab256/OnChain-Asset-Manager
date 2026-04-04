// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute} from "../../../src/types.sol";
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
    IndexAsset wethAsset60;
    IndexAsset linkAsset40;

    function setUp() public override {
        super.setUp();
    }



    // =========================================================================
    //  retreiveAmountFromAmount
    // =========================================================================

    // @audit-issue testare la funzione



    // // =========================================================================
    // //  sortAssets
    // // =========================================================================

    // function test_sortAssets_SmallAddressBecomesToken0() public view {
    //     address small = address(1);
    //     address large = address(2);

    //     (address t0, address t1) = indexManager.sortAssets(small, large);

    //     assertEq(t0, small);
    //     assertEq(t1, large);
    // }

    // function test_sortAssets_LargeAddressFirstGetsReordered() public view {
    //     address small = address(1);
    //     address large = address(2);

    //     (address t0, address t1) = indexManager.sortAssets(large, small);

    //     assertEq(t0, small);
    //     assertEq(t1, large);
    // }

    // function test_sortAssets_BothOrdersProduceSameResult() public view {
    //     (address t0A, address t1A) = indexManager.sortAssets(
    //         address(mockWeth),
    //         address(mockLink)
    //     );
    //     (address t0B, address t1B) = indexManager.sortAssets(
    //         address(mockLink),
    //         address(mockWeth)
    //     );

    //     assertEq(t0A, t0B);
    //     assertEq(t1A, t1B);
    // }

    // function test_sortAssets_ResultIsAlwaysOrdered() public view {
    //     (address t0, address t1) = indexManager.sortAssets(
    //         address(mockWbtc),
    //         address(mockWeth)
    //     );

    //     assertTrue(t0 < t1);
    // }

    // // =========================================================================
    // //  Getter functions
    // // =========================================================================

    // function test_getUsdcAddress_MatchesMockUsdc() public view {
    //     assertEq(indexManager.getUsdcAddress(), address(mockUsdc));
    // }

    // function test_getRouterAddress_MatchesDeployedRouter() public view {
    //     assertEq(indexManager.getRouterAddress(), address(router));
    // }

    // function test_getSwapManagerAddress_MatchesDeployedSwapManager()
    //     public
    //     view
    // {
    //     assertEq(indexManager.getSwapManagerAddress(), address(swapManager));
    // }

    // function test_getAllIndexes_IsEmptyOnDeploy() public view {
    //     assertEq(indexManager.getAllIndexes().length, 0);
    // }

    // function test_getAllIndexes_ReturnsOneAfterOneCreate() public {
    //     _createDefaultIndex();
    //     assertEq(indexManager.getAllIndexes().length, 1);
    // }

    // function test_getAllIndexes_ReturnsTwoAfterTwoCreates() public {
    //     _createDefaultIndex(); // WETH / LINK

    //     IndexAsset memory wethAsset = IndexAsset({
    //         asset: address(mockWeth),
    //         weightPercentage: WEIGHT_50,
    //         priceFeed: address(mockWethPriceFeed)
    //     });
    //     IndexAsset memory wbtcAsset = IndexAsset({
    //         asset: address(mockWbtc),
    //         weightPercentage: WEIGHT_50,
    //         priceFeed: address(mockWbtcPriceFeed)
    //     });

    //     vm.prank(deployer);
    //     indexManager.createIndex(DEFAULT_FEE, wethAsset, wbtcAsset);

    //     assertEq(indexManager.getAllIndexes().length, 2);
    // }

    // // function test_isIndexAddress_ReturnsFalse_ForUnknownAddress() public view {
    // //     assertFalse(indexManager.isIndexAddress(makeAddr("unknown")));
    // // }

    // function test_isIndexAddress_ReturnsTrue_AfterCreateIndex() public {
    //     (address indexAddress, , ) = _createDefaultIndex();
    //     assertTrue(indexManager.isIndexAddress(indexAddress));
    // }

    // function test_checkIsIndexInitialized_ReturnsFalse_BeforeInitialize()
    //     public
    // {
    //     (address indexAddress, , ) = _createDefaultIndex();
    //     assertFalse(indexManager.checkIsIndexInitialized(indexAddress));
    // }

    // function test_checkIsIndexInitialized_ReturnsTrue_AfterInitialize() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();
    //     assertTrue(indexManager.checkIsIndexInitialized(indexAddress));
    // }

    // function test_getIndexByAssetsAddresses_ReturnsZero_WhenPairDoesNotExist()
    //     public
    //     view
    // {
    //     assertEq(
    //         indexManager.getIndexByAssetsAddresses(
    //             address(mockWeth),
    //             address(mockLink)
    //         ),
    //         address(0)
    //     );
    // }

    // function test_getIndexByAssetsAddresses_ReturnsCorrectAddress_DirectOrder()
    //     public
    // {
    //     (address indexAddress, , ) = _createDefaultIndex();

    //     assertEq(
    //         indexManager.getIndexByAssetsAddresses(
    //             address(mockWeth),
    //             address(mockLink)
    //         ),
    //         indexAddress
    //     );
    // }

    // function test_getIndexByAssetsAddresses_ReturnsCorrectAddress_ReverseOrder()
    //     public
    // {
    //     (address indexAddress, , ) = _createDefaultIndex();

    //     assertEq(
    //         indexManager.getIndexByAssetsAddresses(
    //             address(mockLink),
    //             address(mockWeth)
    //         ),
    //         indexAddress
    //     );
    // }

    // function test_getTotalFeesCollected_IsZeroOnDeploy() public view {
    //     assertEq(indexManager.getTotalFeesCollected(), 0);
    // }

    // function test_getTotalFeesCollected_RemainsZeroWhenNoFeesAccrued() public {
    //     (address indexAddress, , ) = _createAndInitializeDefaultIndex();

    //     vm.prank(deployer);
    //     indexManager.collectFees(indexAddress);

    //     assertEq(indexManager.getTotalFeesCollected(), 0);
    // }
}
