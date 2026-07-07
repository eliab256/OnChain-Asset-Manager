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
    //  constructor
    // =========================================================================

    function testConstructorSetsInitialStateCorrectly() public {
        vm.prank(deployer);
        IndexManager newIndexManager = new IndexManager(
            address(mockUsdc),
            address(mockUsdcPriceFeed),
            address(mockUniRouter)
        );
        assertEq(newIndexManager.getUsdc(), address(mockUsdc));
        assertEq(
            newIndexManager.getUsdcPriceFeed(),
            address(mockUsdcPriceFeed)
        );
        assertEq(
            newIndexManager.getUniswapUniversalRouter(),
            address(mockUniRouter)
        );

        assertTrue(
            newIndexManager.hasRole(
                newIndexManager.DEFAULT_ADMIN_ROLE(),
                deployer
            )
        );
        assertTrue(
            newIndexManager.hasRole(
                newIndexManager.ASSET_MANAGER_ROLE(),
                deployer
            )
        );
        assertTrue(
            newIndexManager.hasRole(
                newIndexManager.FEE_COLLECTOR_ROLE(),
                deployer
            )
        );
        assertTrue(
            newIndexManager.hasRole(newIndexManager.REBALANCER_ROLE(), deployer)
        );
    }

    // =========================================================================
    //  setRouterAddress
    // =========================================================================

    function testSetRouterAddressUpdateStatAndEmitsEvent() public {
        address newRouter = makeAddr("newRouter");

        vm.prank(deployer);
        vm.expectEmit(true, true, false, false);
        emit RouterAddressSet(newRouter, deployer);
        indexManager.setRouterAddress(newRouter);
        assertEq(indexManager.getRouterAddress(), newRouter);
    }

    function testSetRouterAddressRevertIfCallerNotAssetManager() public {
        vm.prank(rebalancer);
        vm.expectRevert();
        indexManager.setRouterAddress(makeAddr("newRouter"));
    }

    // =========================================================================
    //  setSwapManagerAddress
    // =========================================================================

    function testSetSwapManagerAddressUpdatesStateAndEmitsEvent() public {
        address newSwapMgr = makeAddr("newSwapManager");

        vm.prank(deployer);
        vm.expectEmit(true, true, false, false);
        emit SwapManagerAddressSet(newSwapMgr, deployer);
        indexManager.setSwapManagerAddress(newSwapMgr);

        assertEq(indexManager.getSwapManagerAddress(), newSwapMgr);
    }

    function testSetSwapManagerAddressRevertIfCallerNotAssetManager() public {
        vm.prank(user1);
        vm.expectRevert();
        indexManager.setSwapManagerAddress(makeAddr("newSwapManager"));
    }
}
