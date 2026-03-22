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

import "../../../src/errors/IndexManagerErrors.sol";
import "../../../src/events/IndexManagerEvents.sol";
import "../../../src/errors/IndexErrors.sol";

contract IndexManagerTest is BaseTest {
    IndexAsset wethAsset60;
    IndexAsset linkAsset40;

    function setUp() public override {
        super.setUp();
    }

    function _createDefaultIndex(
        address _assetA,
        address _assetB,
        address _priceFeedA,
        address _priceFeedB
    ) internal returns (address indexAddress, address token0, address token1) {
        IndexAsset memory assetA = IndexAsset({
            asset: _assetA,
            weightPercentage: weight60,
            priceFeed: _priceFeedA
        });
        IndexAsset memory assetB = IndexAsset({
            asset: _assetB,
            weightPercentage: weight40,
            priceFeed: _priceFeedB
        });

        vm.prank(deployer);
        (indexAddress, token0, token1) = indexManager.createIndex(
            validFeePercentage,
            assetA,
            assetB
        );
    }

    /**
     * @dev Creates AND initialises the default WETH/LINK index.
     *
     *      Index.initialize transfers assets FROM IndexManager, so we must:
     *        1. deal() → give IndexManager a balance of both assets.
     *        2. vm.prank(indexManager) + approve → allow the Index contract to
     *           pull those tokens from IndexManager via safeTransferFrom.
     *
     *      Amount rationale (50/50, WETH at 2000, LINK at 7):
     *        initAmount0 = 1e18 WETH  → USD value = 2 000e18
     *        initAmount1 ≈ 285.7e18 LINK → USD value ≈ 2 000e18
     */
    function _createAndInitializeDefaultIndex(
        address _assetA,
        address _assetB,
        address _priceFeedA,
        address _priceFeedB
    ) internal returns (address indexAddress, address token0, address token1) {
        (indexAddress, token0, token1) = _createDefaultIndex(
            _assetA,
            _assetB,
            _priceFeedA,
            _priceFeedB
        );

        uint256 initAmount = 1e18; // 1 unit of token0 in 18-decimal standard

        // Fund IndexManager with plenty of both assets.
        deal(token0, address(indexManager), initAmount * 10);
        deal(token1, address(indexManager), 10_000e18); // ~285 LINK needed

        // Grant Index an allowance to pull from IndexManager.
        vm.prank(address(indexManager));
        IERC20(token0).approve(indexAddress, type(uint256).max);
        vm.prank(address(indexManager));
        IERC20(token1).approve(indexAddress, type(uint256).max);

        (
            SwapRoute memory r0,
            SwapRoute memory r1,
            SwapRoute memory r01
        ) = helperConfig.getDefaultSwapRoutes(token0, token1);

        vm.prank(deployer);
        indexManager.initializeIndex(
            msg.sender,
            indexAddress,
            initAmount,
            r0,
            r1,
            r01
        );
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
