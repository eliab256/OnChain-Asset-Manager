// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {PriceFeedManager} from "../../../src/PriceFeedManager.sol";
import {Router} from "../../../src/Router.sol";
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
        Router routerImplementation = new Router();
        vm.prank(deployer);
        IndexManager newIndexManager = new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            address(implementation),
            address(priceFeedManagerImplementation),
            address(routerImplementation),
            address(timelock)
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
        Router routerImplementation = new Router();
        vm.prank(deployer);
        IndexManager newIndexManager = new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            address(implementation),
            address(priceFeedManagerImplementation),
            address(routerImplementation),
            address(timelock)
        );

        SwapManager proxy = SwapManager(newIndexManager.getSwapManagerAddress());
        assertTrue(address(proxy) != address(implementation));
        assertEq(proxy.owner(), address(newIndexManager));
        assertEq(proxy.getUpgrader(), address(timelock));
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
        Router routerImplementation = new Router();
        vm.prank(deployer);
        IndexManager newIndexManager = new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            address(swapManagerImplementation),
            address(implementation),
            address(routerImplementation),
            address(timelock)
        );

        PriceFeedManager proxy = PriceFeedManager(
            newIndexManager.getPriceFeedManagerAddress()
        );
        assertTrue(address(proxy) != address(implementation));
        assertTrue(
            address(proxy) != newIndexManager.getSwapManagerAddress()
        );
        assertEq(proxy.owner(), address(newIndexManager));
        assertEq(proxy.getUpgrader(), address(timelock));
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
        Router routerImplementation = new Router();
        address noCode = makeAddr("noCode");
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__InvalidImplementation.selector,
                noCode
            )
        );
        new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            noCode,
            address(priceFeedManagerImplementation),
            address(routerImplementation),
            address(timelock)
        );
    }

    function testConstructorRevertIfPriceFeedManagerImplementationHasNoCode()
        public
    {
        SwapManager swapManagerImplementation = new SwapManager();
        Router routerImplementation = new Router();
        address noCode = makeAddr("noCode");
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__InvalidImplementation.selector,
                noCode
            )
        );
        new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            address(swapManagerImplementation),
            noCode,
            address(routerImplementation),
            address(timelock)
        );
    }

    function testConstructorRevertIfRouterImplementationHasNoCode() public {
        SwapManager swapManagerImplementation = new SwapManager();
        PriceFeedManager priceFeedManagerImplementation = new PriceFeedManager();
        address noCode = makeAddr("noCode");
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__InvalidImplementation.selector,
                noCode
            )
        );
        new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            address(swapManagerImplementation),
            address(priceFeedManagerImplementation),
            noCode,
            address(timelock)
        );
    }

    function testConstructorDeploysAndInitializesRouterProxy() public {
        SwapManager swapManagerImplementation = new SwapManager();
        PriceFeedManager priceFeedManagerImplementation = new PriceFeedManager();
        Router implementation = new Router();
        vm.prank(deployer);
        IndexManager newIndexManager = new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            address(swapManagerImplementation),
            address(priceFeedManagerImplementation),
            address(implementation),
            address(timelock)
        );

        Router proxy = Router(newIndexManager.getRouterAddress());
        assertTrue(address(proxy) != address(implementation));
        assertTrue(address(proxy) != newIndexManager.getSwapManagerAddress());
        assertTrue(
            address(proxy) != newIndexManager.getPriceFeedManagerAddress()
        );
        assertEq(proxy.getUpgrader(), address(timelock));
        assertEq(proxy.getImplementation(), address(implementation));
        assertEq(proxy.getIndexManager(), address(newIndexManager));
        assertEq(proxy.getUsdc(), address(mockUsdc));
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

    // =========================================================================
    //  getRouterAddress
    // =========================================================================

    function testGetRouterAddressReturnsRouterProxyFromDeployScript()
        public
        view
    {
        assertEq(indexManager.getRouterAddress(), address(router));
        assertEq(router.getIndexManager(), address(indexManager));
        assertEq(router.getUpgrader(), address(timelock));
        assertTrue(
            router.getImplementation() != address(router),
            "router must be a proxy"
        );
    }
}
