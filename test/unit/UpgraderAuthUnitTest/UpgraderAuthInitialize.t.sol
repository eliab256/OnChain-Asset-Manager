// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseUpgraderAuthTest} from "./BaseUpgraderAuth.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {PriceFeedManager} from "../../../src/PriceFeedManager.sol";
import {Router} from "../../../src/Router.sol";
import {IUpgraderAuth} from "../../../src/Interface/IUpgraderAuth.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgraderAuth__ZeroAddress} from "../../../src/errors/UpgraderAuthErrors.sol";
import {IndexManager__ZeroAddress} from "../../../src/errors/IndexManagerErrors.sol";

/**
 * @dev UpgraderAuth initialization and ERC-7201 storage on the three proxies,
 *      and the IndexManager constructor check on the upgrader.
 */
contract UpgraderAuthInitializeTest is BaseUpgraderAuthTest {
    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  getUpgrader
    // =========================================================================

    function testGetUpgraderIsTimelockForAllProxies() public view {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            assertEq(IUpgraderAuth(s_proxies[i]).getUpgrader(), address(timelock));
        }
    }

    function testImplementationsHaveNoUpgrader() public view {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            assertEq(IUpgraderAuth(s_initialImplementations[i]).getUpgrader(), address(0));
        }
    }

    // =========================================================================
    //  ERC-7201 storage
    // =========================================================================

    function testUpgraderStorageLocationMatchesErc7201Formula() public pure {
        bytes32 expected = keccak256(
            abi.encode(uint256(keccak256(bytes(UPGRADER_AUTH_NAMESPACE))) - 1)
        ) & ~bytes32(uint256(0xff));
        assertEq(UPGRADER_AUTH_STORAGE_LOCATION, expected);
    }

    function testUpgraderIsStoredInNamespacedSlotOnEachProxy() public view {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            assertEq(_storedUpgrader(s_proxies[i]), address(timelock), "namespaced slot must hold the timelock");
            assertEq(_storedUpgrader(s_initialImplementations[i]), address(0), "implementation slot must be empty");
        }
    }

    function testUpgraderSlotFollowsGetUpgrader() public {
        // Writing the namespaced slot changes the upgrader read by getUpgrader: the slot is the one in use.
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            vm.store(s_proxies[i], UPGRADER_AUTH_STORAGE_LOCATION, bytes32(uint256(uint160(s_freshUpgrader))));
            assertEq(IUpgraderAuth(s_proxies[i]).getUpgrader(), s_freshUpgrader);
        }
    }

    // =========================================================================
    //  initialize
    // =========================================================================

    function testInitializeWithZeroUpgraderReverts() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            address implementation = _freshImplementation(i);
            bytes memory data = _initializeCalldata(i, address(0));

            vm.expectRevert(UpgraderAuth__ZeroAddress.selector);
            new ERC1967Proxy(implementation, data);
        }
    }

    function testInitializeStoresUpgraderOnFreshProxy() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            address proxy = address(
                new ERC1967Proxy(_freshImplementation(i), _initializeCalldata(i, s_freshUpgrader))
            );

            assertEq(IUpgraderAuth(proxy).getUpgrader(), s_freshUpgrader);
            assertEq(_storedUpgrader(proxy), s_freshUpgrader);
        }
    }

    // =========================================================================
    //  IndexManager constructor
    // =========================================================================

    function testIndexManagerConstructorRevertsWithZeroUpgrader() public {
        address swapImplementation = address(new SwapManager());
        address priceFeedImplementation = address(new PriceFeedManager());
        address routerImplementation = address(new Router());

        vm.expectRevert(IndexManager__ZeroAddress.selector);
        new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            swapImplementation,
            priceFeedImplementation,
            routerImplementation,
            address(0)
        );
    }

    function testIndexManagerConstructorChecksUpgraderBeforeImplementations() public {
        vm.expectRevert(IndexManager__ZeroAddress.selector);
        new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            s_noCodeImplementation,
            s_noCodeImplementation,
            s_noCodeImplementation,
            address(0)
        );
    }

    function testIndexManagerConstructorSetsUpgraderOnAllProxies() public {
        address swapImplementation = address(new SwapManager());
        address priceFeedImplementation = address(new PriceFeedManager());
        address routerImplementation = address(new Router());

        IndexManager freshManager = new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            swapImplementation,
            priceFeedImplementation,
            routerImplementation,
            s_freshUpgrader
        );

        assertEq(IUpgraderAuth(freshManager.getSwapManagerAddress()).getUpgrader(), s_freshUpgrader);
        assertEq(IUpgraderAuth(freshManager.getPriceFeedManagerAddress()).getUpgrader(), s_freshUpgrader);
        assertEq(IUpgraderAuth(freshManager.getRouterAddress()).getUpgrader(), s_freshUpgrader);
    }
}
