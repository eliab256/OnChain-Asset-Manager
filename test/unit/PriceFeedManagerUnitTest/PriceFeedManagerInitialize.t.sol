// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BasePriceFeedManagerTest} from "./BasePriceFeedManager.t.sol";
import {PriceFeedManager} from "../../../src/PriceFeedManager.sol";
import {PriceFeedManagerV2Mock} from "../../mocks/PriceFeedManagerV2Mock.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    UpgraderAuth__Unauthorized
} from "../../../src/errors/UpgraderAuthErrors.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract PriceFeedManagerInitializeTest is BasePriceFeedManagerTest {
    /// ERC-7201 base slot hardcoded in PriceFeedManager (PRICE_FEED_MANAGER_STORAGE_LOCATION is private)
    bytes32 internal constant EXPECTED_STORAGE_LOCATION =
        0xce69fe7798ad1848e1ae89d57160a977b401d63b647be25f32ddbfedfac2a000;

    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _namespaceBaseSlot() internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(uint256(keccak256(bytes(STORAGE_NAMESPACE))) - 1)
            ) & ~bytes32(uint256(0xff));
    }

    /// @dev Slot of `mapping[_key]` for a mapping declared at `_mappingSlot`.
    function _mappingSlot(
        address _key,
        uint256 _mappingSlot
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_key, _mappingSlot));
    }

    // =========================================================================
    //  initialize
    // =========================================================================

    function testInitializeSetsIndexManagerAsOwner() public view {
        assertEq(priceFeedManager.owner(), address(indexManager));
    }

    function testAssetManagerRoleMatchesIndexManagerRole() public view {
        assertEq(
            priceFeedManager.ASSET_MANAGER_ROLE(),
            indexManager.ASSET_MANAGER_ROLE()
        );
    }

    function testInitializeRevertsIfCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        priceFeedManager.initialize(user1, address(timelock));
    }

    function testInitializeRevertsOnBareImplementation() public {
        PriceFeedManager implementation = PriceFeedManager(
            priceFeedManager.getImplementation()
        );

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(user1, address(timelock));
    }

    function testInitializeRevertsOnFreshImplementation() public {
        PriceFeedManager implementation = new PriceFeedManager();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(user1, address(timelock));
    }

    function testInitializeSetsTimelockAsUpgrader() public view {
        assertEq(priceFeedManager.getUpgrader(), address(timelock));
    }

    function testInitializeThroughNewProxySetsOwner() public {
        PriceFeedManager implementation = new PriceFeedManager();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(PriceFeedManager.initialize, (user1, user2))
        );

        assertEq(PriceFeedManager(address(proxy)).owner(), user1);
        assertEq(PriceFeedManager(address(proxy)).getUpgrader(), user2);
        assertEq(
            PriceFeedManager(address(proxy)).getImplementation(),
            address(implementation)
        );
    }

    function testGetImplementationMatchesErc1967Slot() public view {
        address slotValue = address(
            uint160(
                uint256(
                    vm.load(
                        address(priceFeedManager),
                        ERC1967Utils.IMPLEMENTATION_SLOT
                    )
                )
            )
        );
        assertTrue(slotValue != address(0), "implementation slot must be set");
        assertTrue(
            slotValue != address(priceFeedManager),
            "implementation must differ from the proxy"
        );
        assertEq(priceFeedManager.getImplementation(), slotValue);
    }

    // =========================================================================
    //  ERC-7201 storage layout
    // =========================================================================

    function testStorageLocationMatchesErc7201Formula() public pure {
        assertEq(_namespaceBaseSlot(), EXPECTED_STORAGE_LOCATION);
    }

    function testFeedConfigIsStoredUnderNamespace() public {
        _register(s_asset, address(s_feed8Decimals), s_validMaxDelay);

        // assetToFeedConfig is the first member of the namespaced struct (base slot + 0).
        // FeedConfig packs feed (20 bytes) and maxDelay (uint32) in one slot.
        bytes32 raw = vm.load(
            address(priceFeedManager),
            _mappingSlot(s_asset, uint256(_namespaceBaseSlot()))
        );
        assertEq(
            address(uint160(uint256(raw))),
            address(s_feed8Decimals),
            "feed stored under the namespace"
        );
        assertEq(
            uint32(uint256(raw) >> 160),
            s_validMaxDelay,
            "maxDelay stored under the namespace"
        );
    }

    function testPendingFeedIsStoredUnderNamespace() public {
        uint256 executableAt = _registerAndProposeNewFeed();

        // assetToPendingFeed is the second member of the namespaced struct (base slot + 1).
        // PendingFeed packs feed (20 bytes), maxDelay (uint32) and executableAt (uint64) in one slot.
        bytes32 raw = vm.load(
            address(priceFeedManager),
            _mappingSlot(s_asset, uint256(_namespaceBaseSlot()) + 1)
        );
        assertEq(address(uint160(uint256(raw))), address(s_newFeed));
        assertEq(uint32(uint256(raw) >> 160), s_validMaxDelay);
        assertEq(uint64(uint256(raw) >> 192), executableAt);
    }

    function testLowSequentialSlotsAreEmpty() public {
        _registerAndProposeNewFeed();

        for (uint256 i = 0; i < LOW_SLOTS_CHECKED; i++) {
            assertEq(
                vm.load(address(priceFeedManager), bytes32(i)),
                bytes32(0),
                "no state may live in sequential slots"
            );
        }
    }

    // =========================================================================
    //  Direct upgrade bypassing the TimelockController
    // =========================================================================

    function testDirectUpgradeToAndCallByAssetManagerReverts() public {
        PriceFeedManagerV2Mock newImplementation = new PriceFeedManagerV2Mock();

        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(UpgraderAuth__Unauthorized.selector, deployer)
        );
        priceFeedManager.upgradeToAndCall(address(newImplementation), "");
    }

    function testDirectUpgradeToAndCallByMultiSigReverts() public {
        PriceFeedManagerV2Mock newImplementation = new PriceFeedManagerV2Mock();

        vm.prank(address(multiSigWallet));
        vm.expectRevert(
            abi.encodeWithSelector(
                UpgraderAuth__Unauthorized.selector,
                address(multiSigWallet)
            )
        );
        priceFeedManager.upgradeToAndCall(address(newImplementation), "");
    }

    function testDirectUpgradeToAndCallByOwnerIndexManagerReverts() public {
        PriceFeedManagerV2Mock newImplementation = new PriceFeedManagerV2Mock();

        // Ownership no longer grants upgrade rights: only the upgrader (timelock) can upgrade.
        vm.prank(address(indexManager));
        vm.expectRevert(
            abi.encodeWithSelector(
                UpgraderAuth__Unauthorized.selector,
                address(indexManager)
            )
        );
        priceFeedManager.upgradeToAndCall(address(newImplementation), "");
    }

    function testDirectUpgradeToAndCallOnImplementationReverts() public {
        PriceFeedManagerV2Mock newImplementation = new PriceFeedManagerV2Mock();
        address implementation = priceFeedManager.getImplementation();

        // UUPS onlyProxy guard: the bare implementation cannot be upgraded directly
        vm.prank(address(indexManager));
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        PriceFeedManager(implementation).upgradeToAndCall(
            address(newImplementation),
            ""
        );
    }
}
