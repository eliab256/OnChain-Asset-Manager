// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {PriceFeedManager} from "../../../src/PriceFeedManager.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
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

    // =========================================================================
    //  constructor
    // =========================================================================

    function testConstructorSetsInitialStateCorrectly() public {
        SwapManager implementation = new SwapManager();
        PriceFeedManager priceFeedManagerImplementation = new PriceFeedManager();
        vm.prank(deployer);
        IndexManager newIndexManager = new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            address(implementation),
            address(priceFeedManagerImplementation)
        );
        assertEq(newIndexManager.getUsdc(), address(mockUsdc));
        // The USDC feed is no longer a constructor argument: a fresh manager has none registered.
        assertEq(newIndexManager.getUsdcPriceFeed(), address(0));
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

    function testConstructorDeploysAndInitializesSwapManagerProxy() public {
        SwapManager implementation = new SwapManager();
        PriceFeedManager priceFeedManagerImplementation = new PriceFeedManager();
        vm.prank(deployer);
        IndexManager newIndexManager = new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            address(implementation),
            address(priceFeedManagerImplementation)
        );

        SwapManager proxy = SwapManager(newIndexManager.getSwapManagerAddress());
        assertTrue(address(proxy) != address(implementation));
        assertEq(proxy.owner(), address(newIndexManager));
        assertEq(proxy.getImplementation(), address(implementation));
        assertEq(
            address(
                uint160(
                    uint256(
                        vm.load(address(proxy), ERC1967Utils.IMPLEMENTATION_SLOT)
                    )
                )
            ),
            address(implementation)
        );
    }

    function testConstructorDeploysAndInitializesPriceFeedManagerProxy()
        public
    {
        SwapManager swapManagerImplementation = new SwapManager();
        PriceFeedManager implementation = new PriceFeedManager();
        vm.prank(deployer);
        IndexManager newIndexManager = new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            address(swapManagerImplementation),
            address(implementation)
        );

        PriceFeedManager proxy = PriceFeedManager(
            newIndexManager.getPriceFeedManagerAddress()
        );
        assertTrue(address(proxy) != address(implementation));
        assertTrue(
            address(proxy) != newIndexManager.getSwapManagerAddress()
        );
        assertEq(proxy.owner(), address(newIndexManager));
        assertEq(proxy.getImplementation(), address(implementation));
        assertEq(
            address(
                uint160(
                    uint256(
                        vm.load(address(proxy), ERC1967Utils.IMPLEMENTATION_SLOT)
                    )
                )
            ),
            address(implementation)
        );
        assertFalse(proxy.hasPriceFeed(address(mockUsdc)));
    }

    function testConstructorRevertIfSwapManagerImplementationHasNoCode()
        public
    {
        PriceFeedManager priceFeedManagerImplementation = new PriceFeedManager();
        vm.expectRevert(IndexManager__InvalidSwapManagerImplementation.selector);
        new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            makeAddr("noCode"),
            address(priceFeedManagerImplementation)
        );
    }

    function testConstructorRevertIfPriceFeedManagerImplementationHasNoCode()
        public
    {
        SwapManager swapManagerImplementation = new SwapManager();
        vm.expectRevert(
            IndexManager__InvalidPriceFeedManagerImplementation.selector
        );
        new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            address(swapManagerImplementation),
            makeAddr("noCode")
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
}
