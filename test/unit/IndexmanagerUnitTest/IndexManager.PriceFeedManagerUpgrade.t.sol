// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {PriceFeedManager} from "../../../src/PriceFeedManager.sol";
import {FeedConfig} from "../../../src/types.sol";
import {PriceFeedManagerV2Mock} from "../../mocks/PriceFeedManagerV2Mock.sol";
import {SwapManagerV2Mock} from "../../mocks/SwapManagerV2Mock.sol";
import {ProxiableWrongUuidMock} from "../../mocks/ProxiableWrongUuidMock.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    MockV3Aggregator
} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {Vm} from "forge-std/Vm.sol";

import "../../../src/errors/IndexManagerErrors.sol";
import "../../../src/events/IndexManagerEvents.sol";

contract IndexManagerPriceFeedManagerUpgradeTest is BaseTest {
    // =========================================================================
    //  Contracts and addresses
    // =========================================================================

    PriceFeedManagerV2Mock internal s_newImplementation;
    PriceFeedManagerV2Mock internal s_otherImplementation;
    SwapManagerV2Mock internal s_swapManagerNewImplementation;
    ProxiableWrongUuidMock internal s_wrongUuidImplementation;
    address internal s_noCodeImplementation = makeAddr("noCodeImplementation");
    address internal s_postUpgradeAsset = makeAddr("postUpgradeAsset");

    // =========================================================================
    //  Constants
    // =========================================================================

    /// USDC spent in the end-to-end buy after the upgrade
    uint256 constant BUY_USDC_AMOUNT = 4_000e6;

    /// Expected V2 version returned by PriceFeedManagerV2Mock
    uint256 constant V2_VERSION = 2;

    uint8 constant POST_UPGRADE_FEED_DECIMALS = 8;
    int256 constant POST_UPGRADE_FEED_PRICE = 10 * 10 ** 8;

    // =========================================================================
    //  Values derived from the contracts
    // =========================================================================

    bytes32 internal s_defaultAdminRole;
    address internal s_initialImplementation;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();
        s_newImplementation = new PriceFeedManagerV2Mock();
        s_otherImplementation = new PriceFeedManagerV2Mock();
        s_swapManagerNewImplementation = new SwapManagerV2Mock();
        s_wrongUuidImplementation = new ProxiableWrongUuidMock();

        s_defaultAdminRole = indexManager.DEFAULT_ADMIN_ROLE();
        s_initialImplementation = priceFeedManager.getImplementation();
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev Proposes an upgrade as the admin and returns executableAt.
    function _proposeUpgrade(
        address _implementation,
        bytes memory _data
    ) internal returns (uint256 executableAt) {
        vm.prank(deployer);
        executableAt = indexManager.proposePriceFeedManagerUpgrade(
            _implementation,
            _data
        );
    }

    /// @dev Executes the pending upgrade as the admin.
    function _executeUpgrade() internal {
        vm.prank(deployer);
        indexManager.executePriceFeedManagerUpgrade();
    }

    /// @dev Reads the ERC-1967 implementation slot of the PriceFeedManager proxy.
    function _implementationSlotValue() internal view returns (address) {
        return
            address(
                uint160(
                    uint256(
                        vm.load(
                            address(priceFeedManager),
                            ERC1967Utils.IMPLEMENTATION_SLOT
                        )
                    )
                )
            );
    }

    /// @dev Hash of the feed configuration of every mock asset.
    function _feedConfigHashes()
        internal
        view
        returns (bytes32[5] memory hashes)
    {
        address[5] memory assets = [
            address(mockWeth),
            address(mockWbtc),
            address(mockLink),
            address(mockComp),
            address(mockUsdc)
        ];
        for (uint256 i = 0; i < assets.length; i++) {
            hashes[i] = keccak256(
                abi.encode(priceFeedManager.getPriceFeedConfig(assets[i]))
            );
        }
    }

    /// @dev True if `_target` runtime code embeds `_needle` as a 32-byte word (immutable layout).
    function _codeEmbedsAddress(
        address _target,
        address _needle
    ) internal view returns (bool) {
        bytes memory code = _target.code;
        bytes32 word = bytes32(uint256(uint160(_needle)));
        if (code.length < 32) return false;
        for (uint256 i = 0; i <= code.length - 32; i++) {
            bytes32 chunk;
            assembly {
                chunk := mload(add(add(code, 0x20), i))
            }
            if (chunk == word) return true;
        }
        return false;
    }

    function _assertNoPendingUpgrade() internal view {
        (
            address implementation,
            bytes memory data,
            uint256 executableAt
        ) = indexManager.getPendingPriceFeedManagerUpgrade();
        assertEq(implementation, address(0), "pending implementation must be empty");
        assertEq(data.length, 0, "pending data must be empty");
        assertEq(executableAt, 0, "pending executableAt must be empty");
    }

    // =========================================================================
    //  Proxy wiring
    // =========================================================================

    function testPriceFeedManagerProxyMatchesIndexManagerGetter() public view {
        assertEq(
            address(priceFeedManager),
            indexManager.getPriceFeedManagerAddress(),
            "deploy script must return the IndexManager proxy"
        );
        assertTrue(
            indexManager.getPriceFeedManagerAddress() !=
                indexManager.getSwapManagerAddress(),
            "PriceFeedManager and SwapManager must be distinct proxies"
        );
    }

    function testAllIndexesUseTheSamePriceFeedManagerProxy() public view {
        address proxy = indexManager.getPriceFeedManagerAddress();
        assertEq(initializedIndex.getPriceFeedManager(), proxy);
        assertEq(nonInitializedIndex.getPriceFeedManager(), proxy);
        assertTrue(
            _codeEmbedsAddress(address(initializedIndex), proxy),
            "initializedIndex must embed the PriceFeedManager proxy"
        );
        assertTrue(
            _codeEmbedsAddress(address(nonInitializedIndex), proxy),
            "nonInitializedIndex must embed the PriceFeedManager proxy"
        );
        assertFalse(
            _codeEmbedsAddress(address(initializedIndex), s_initialImplementation),
            "index must not point at the bare implementation"
        );
    }

    function testIndexPriceFeedGettersReadFromPriceFeedManager() public view {
        assertEq(
            initializedIndex.getAsset0PriceFeed(),
            priceFeedManager.getPriceFeedConfig(initializedToken0).feed
        );
        assertEq(
            initializedIndex.getAsset1PriceFeed(),
            priceFeedManager.getPriceFeedConfig(initializedToken1).feed
        );
        assertEq(
            initializedIndex.getUsdcPriceFeed(),
            priceFeedManager.getPriceFeedConfig(address(mockUsdc)).feed
        );
        assertEq(indexManager.getUsdcPriceFeed(), address(mockUsdcPriceFeed));
    }

    function testPriceFeedManagerProxyOwnerIsIndexManager() public view {
        assertEq(
            priceFeedManager.owner(),
            address(indexManager),
            "IndexManager must own the PriceFeedManager proxy"
        );
    }

    function testPriceFeedManagerProxyCannotBeReinitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        priceFeedManager.initialize(user1);
    }

    function testGetPendingPriceFeedManagerUpgradeIsEmptyByDefault()
        public
        view
    {
        _assertNoPendingUpgrade();
    }

    // =========================================================================
    //  proposePriceFeedManagerUpgrade
    // =========================================================================

    function testProposePriceFeedManagerUpgradeRevertsIfCallerNotAdmin()
        public
    {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                s_defaultAdminRole
            )
        );
        indexManager.proposePriceFeedManagerUpgrade(
            address(s_newImplementation),
            ""
        );
    }

    function testProposePriceFeedManagerUpgradeRevertsIfImplementationHasNoCode()
        public
    {
        vm.prank(deployer);
        vm.expectRevert(
            IndexManager__InvalidPriceFeedManagerImplementation.selector
        );
        indexManager.proposePriceFeedManagerUpgrade(s_noCodeImplementation, "");
    }

    function testProposePriceFeedManagerUpgradeRevertsIfImplementationIsCurrent()
        public
    {
        vm.prank(deployer);
        vm.expectRevert(
            IndexManager__InvalidPriceFeedManagerImplementation.selector
        );
        indexManager.proposePriceFeedManagerUpgrade(s_initialImplementation, "");
    }

    function testProposePriceFeedManagerUpgradeRevertsIfImplementationHasNoProxiableUuid()
        public
    {
        vm.prank(deployer);
        vm.expectRevert(
            IndexManager__InvalidPriceFeedManagerImplementation.selector
        );
        indexManager.proposePriceFeedManagerUpgrade(address(mockUsdc), "");
    }

    function testProposePriceFeedManagerUpgradeRevertsIfProxiableUuidIsWrongSlot()
        public
    {
        vm.prank(deployer);
        vm.expectRevert(
            IndexManager__InvalidPriceFeedManagerImplementation.selector
        );
        indexManager.proposePriceFeedManagerUpgrade(
            address(s_wrongUuidImplementation),
            ""
        );
    }

    function testProposePriceFeedManagerUpgradeRevertsIfImplementationIsTheProxy()
        public
    {
        // proxiableUUID() reverts when called through a proxy (notDelegated)
        vm.prank(deployer);
        vm.expectRevert(
            IndexManager__InvalidPriceFeedManagerImplementation.selector
        );
        indexManager.proposePriceFeedManagerUpgrade(
            address(priceFeedManager),
            ""
        );
    }

    function testProposePriceFeedManagerUpgradeRevertsIfPendingWithinDelay()
        public
    {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt - 1);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__PriceFeedManagerUpgradePending.selector);
        indexManager.proposePriceFeedManagerUpgrade(
            address(s_otherImplementation),
            ""
        );
    }

    function testProposePriceFeedManagerUpgradeStoresPendingUpgrade() public {
        bytes memory data = abi.encodeCall(PriceFeedManagerV2Mock.version, ());
        uint256 expectedExecutableAt = block.timestamp + PROXY_UPGRADE_DELAY;

        uint256 executableAt = _proposeUpgrade(
            address(s_newImplementation),
            data
        );

        (
            address implementation,
            bytes memory storedData,
            uint256 storedExecutableAt
        ) = indexManager.getPendingPriceFeedManagerUpgrade();
        assertEq(executableAt, expectedExecutableAt, "returned executableAt");
        assertEq(implementation, address(s_newImplementation), "pending implementation");
        assertEq(storedData, data, "pending data");
        assertEq(storedExecutableAt, expectedExecutableAt, "stored executableAt");
        assertEq(
            _implementationSlotValue(),
            s_initialImplementation,
            "proposal must not touch the proxy"
        );
    }

    function testProposePriceFeedManagerUpgradeDoesNotTouchSwapManagerPending()
        public
    {
        _proposeUpgrade(address(s_newImplementation), "");

        (
            address implementation,
            bytes memory data,
            uint256 executableAt
        ) = indexManager.getPendingSwapManagerUpgrade();
        assertEq(implementation, address(0));
        assertEq(data.length, 0);
        assertEq(executableAt, 0);
    }

    function testPendingSwapManagerUpgradeDoesNotBlockPriceFeedManagerProposal()
        public
    {
        vm.prank(deployer);
        uint256 swapExecutableAt = indexManager.proposeSwapManagerUpgrade(
            address(s_swapManagerNewImplementation),
            ""
        );

        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");

        (address implementation, , ) = indexManager
            .getPendingPriceFeedManagerUpgrade();
        assertEq(implementation, address(s_newImplementation));
        assertEq(executableAt, swapExecutableAt);
        (address swapImplementation, , ) = indexManager
            .getPendingSwapManagerUpgrade();
        assertEq(swapImplementation, address(s_swapManagerNewImplementation));
    }

    function testProposePriceFeedManagerUpgradeEmitsEvent() public {
        uint256 expectedExecutableAt = block.timestamp + PROXY_UPGRADE_DELAY;

        vm.recordLogs();
        _proposeUpgrade(address(s_newImplementation), "");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(indexManager) ||
                logs[i].topics[0] != PriceFeedManagerUpgradeProposed.selector
            ) continue;

            eventFound = true;
            assertEq(
                address(uint160(uint256(logs[i].topics[1]))),
                address(s_newImplementation),
                "event must log the new implementation"
            );
            assertEq(
                address(uint160(uint256(logs[i].topics[2]))),
                deployer,
                "event must log the proposer"
            );
            uint256 executableAt = abi.decode(logs[i].data, (uint256));
            assertEq(executableAt, expectedExecutableAt, "event must log executableAt");
            break;
        }
        assertTrue(
            eventFound,
            "PriceFeedManagerUpgradeProposed event was not emitted"
        );
    }

    function testProposePriceFeedManagerUpgradeOverwritesExpiredProposal()
        public
    {
        uint256 firstExecutableAt = _proposeUpgrade(
            address(s_newImplementation),
            ""
        );
        vm.warp(firstExecutableAt + PROXY_UPGRADE_EXECUTION_WINDOW + 1);

        bytes memory data = abi.encodeCall(PriceFeedManagerV2Mock.version, ());
        uint256 secondExecutableAt = _proposeUpgrade(
            address(s_otherImplementation),
            data
        );

        (
            address implementation,
            bytes memory storedData,
            uint256 storedExecutableAt
        ) = indexManager.getPendingPriceFeedManagerUpgrade();
        assertEq(implementation, address(s_otherImplementation));
        assertEq(storedData, data);
        assertEq(storedExecutableAt, secondExecutableAt);
        assertEq(secondExecutableAt, block.timestamp + PROXY_UPGRADE_DELAY);
    }

    function testProposePriceFeedManagerUpgradeOverwritesExecutableProposal()
        public
    {
        uint256 firstExecutableAt = _proposeUpgrade(
            address(s_newImplementation),
            ""
        );
        vm.warp(firstExecutableAt);

        uint256 secondExecutableAt = _proposeUpgrade(
            address(s_otherImplementation),
            ""
        );

        (address implementation, , uint256 storedExecutableAt) = indexManager
            .getPendingPriceFeedManagerUpgrade();
        assertEq(implementation, address(s_otherImplementation));
        assertEq(storedExecutableAt, secondExecutableAt);
    }

    // =========================================================================
    //  executePriceFeedManagerUpgrade
    // =========================================================================

    function testExecutePriceFeedManagerUpgradeRevertsIfCallerNotAdmin()
        public
    {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                s_defaultAdminRole
            )
        );
        indexManager.executePriceFeedManagerUpgrade();
    }

    function testExecutePriceFeedManagerUpgradeRevertsIfNoPendingUpgrade()
        public
    {
        vm.prank(deployer);
        vm.expectRevert(IndexManager__NoPendingPriceFeedManagerUpgrade.selector);
        indexManager.executePriceFeedManagerUpgrade();
    }

    function testExecutePriceFeedManagerUpgradeRevertsBeforeDelay() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt - 1);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__NoPendingPriceFeedManagerUpgrade.selector);
        indexManager.executePriceFeedManagerUpgrade();
    }

    function testExecutePriceFeedManagerUpgradeRevertsAfterExecutionWindow()
        public
    {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt + PROXY_UPGRADE_EXECUTION_WINDOW + 1);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__PriceFeedManagerUpgradeExpired.selector);
        indexManager.executePriceFeedManagerUpgrade();
    }

    function testExecutePriceFeedManagerUpgradeSucceedsAtExecutableAt() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt);

        _executeUpgrade();

        assertEq(_implementationSlotValue(), address(s_newImplementation));
    }

    function testExecutePriceFeedManagerUpgradeSucceedsAtEndOfExecutionWindow()
        public
    {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt + PROXY_UPGRADE_EXECUTION_WINDOW);

        _executeUpgrade();

        assertEq(_implementationSlotValue(), address(s_newImplementation));
    }

    function testExecutePriceFeedManagerUpgradeUpgradesProxyAndKeepsFeedConfigs()
        public
    {
        bytes32[5] memory configsBefore = _feedConfigHashes();
        assertEq(_implementationSlotValue(), s_initialImplementation);

        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt);
        _executeUpgrade();

        PriceFeedManagerV2Mock upgraded = PriceFeedManagerV2Mock(
            address(priceFeedManager)
        );
        assertEq(
            _implementationSlotValue(),
            address(s_newImplementation),
            "ERC-1967 slot must point to the new implementation"
        );
        assertEq(upgraded.getImplementation(), address(s_newImplementation));
        assertEq(upgraded.version(), V2_VERSION, "V2 logic must be live");
        assertEq(
            upgraded.owner(),
            address(indexManager),
            "IndexManager must still own the proxy"
        );
        assertEq(
            indexManager.getPriceFeedManagerAddress(),
            address(priceFeedManager),
            "proxy address must not change"
        );
        assertEq(
            initializedIndex.getPriceFeedManager(),
            address(priceFeedManager),
            "indexes keep pointing at the same proxy"
        );

        bytes32[5] memory configsAfter = _feedConfigHashes();
        for (uint256 i = 0; i < configsAfter.length; i++) {
            assertEq(
                configsAfter[i],
                configsBefore[i],
                "feed config must survive the upgrade"
            );
        }
        _assertNoPendingUpgrade();
    }

    function testExecutePriceFeedManagerUpgradeDoesNotTouchSwapManager()
        public
    {
        address swapImplementationBefore = swapManager.getImplementation();
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt);

        _executeUpgrade();

        assertEq(swapManager.getImplementation(), swapImplementationBefore);
    }

    function testExecutePriceFeedManagerUpgradeEmitsEvent() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt);

        vm.recordLogs();
        _executeUpgrade();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(indexManager) ||
                logs[i].topics[0] != PriceFeedManagerUpgraded.selector
            ) continue;

            eventFound = true;
            assertEq(
                address(uint160(uint256(logs[i].topics[1]))),
                address(s_newImplementation),
                "event must log the new implementation"
            );
            assertEq(
                address(uint160(uint256(logs[i].topics[2]))),
                deployer,
                "event must log the executor"
            );
            break;
        }
        assertTrue(eventFound, "PriceFeedManagerUpgraded event was not emitted");
    }

    function testExecutePriceFeedManagerUpgradeWithDataSucceeds() public {
        bytes memory data = abi.encodeCall(PriceFeedManagerV2Mock.version, ());
        uint256 executableAt = _proposeUpgrade(
            address(s_newImplementation),
            data
        );
        vm.warp(executableAt);

        _executeUpgrade();

        assertEq(_implementationSlotValue(), address(s_newImplementation));
        assertEq(
            PriceFeedManagerV2Mock(address(priceFeedManager)).version(),
            V2_VERSION
        );
    }

    function testExecutePriceFeedManagerUpgradeRevertsIfDataCallReverts()
        public
    {
        // Re-running initialize on an already initialized proxy must revert,
        // rolling back the whole upgrade.
        bytes memory data = abi.encodeCall(PriceFeedManager.initialize, (user1));
        uint256 executableAt = _proposeUpgrade(
            address(s_newImplementation),
            data
        );
        vm.warp(executableAt);

        vm.prank(deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        indexManager.executePriceFeedManagerUpgrade();
    }

    function testFeedManagementWorksAfterPriceFeedManagerUpgrade() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt);
        _executeUpgrade();

        MockV3Aggregator postUpgradeFeed = new MockV3Aggregator(
            POST_UPGRADE_FEED_DECIMALS,
            POST_UPGRADE_FEED_PRICE
        );
        vm.prank(deployer);
        priceFeedManager.registerPriceFeed(
            s_postUpgradeAsset,
            address(postUpgradeFeed),
            assetPriceFeedMaxDelay
        );

        FeedConfig memory config = priceFeedManager.getPriceFeedConfig(
            s_postUpgradeAsset
        );
        assertEq(config.feed, address(postUpgradeFeed));
        assertEq(config.maxDelay, assetPriceFeedMaxDelay);
        assertEq(
            priceFeedManager.getPrice(s_postUpgradeAsset),
            uint256(POST_UPGRADE_FEED_PRICE) * 1e10
        );
    }

    function testIndexWorksEndToEndAfterPriceFeedManagerUpgrade() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt);
        _executeUpgrade();
        _refreshPriceFeeds();

        uint256 sharesBefore = initializedIndex.balanceOf(user1);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), BUY_USDC_AMOUNT);

        // the buy must price through the upgraded proxy (it reads the ERC-1967 slot)
        vm.record();
        vm.prank(user1);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            BUY_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        (bytes32[] memory proxyReads, ) = vm.accesses(address(priceFeedManager));
        bool implementationSlotRead;
        for (uint256 i = 0; i < proxyReads.length; i++) {
            if (proxyReads[i] == ERC1967Utils.IMPLEMENTATION_SLOT) {
                implementationSlotRead = true;
                break;
            }
        }
        assertTrue(
            implementationSlotRead,
            "index must call the PriceFeedManager proxy"
        );

        uint256 sharesBought = initializedIndex.balanceOf(user1) - sharesBefore;
        assertGt(sharesBought, 0, "buy must mint shares after the upgrade");

        uint256 usdcBefore = mockUsdc.balanceOf(user1);
        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            sharesBought,
            VALID_TOLERANCE
        );

        assertEq(
            initializedIndex.balanceOf(user1),
            sharesBefore,
            "sold shares must be burned"
        );
        assertGt(
            mockUsdc.balanceOf(user1),
            usdcBefore,
            "redeem must pay USDC after the upgrade"
        );
    }

    // =========================================================================
    //  cancelPriceFeedManagerUpgrade
    // =========================================================================

    function testCancelPriceFeedManagerUpgradeRevertsIfCallerNotAdmin() public {
        _proposeUpgrade(address(s_newImplementation), "");

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                s_defaultAdminRole
            )
        );
        indexManager.cancelPriceFeedManagerUpgrade();
    }

    function testCancelPriceFeedManagerUpgradeRevertsIfNoPendingUpgrade()
        public
    {
        vm.prank(deployer);
        vm.expectRevert(IndexManager__NoPendingPriceFeedManagerUpgrade.selector);
        indexManager.cancelPriceFeedManagerUpgrade();
    }

    function testCancelPriceFeedManagerUpgradeResetsPendingState() public {
        _proposeUpgrade(
            address(s_newImplementation),
            abi.encodeCall(PriceFeedManagerV2Mock.version, ())
        );

        vm.prank(deployer);
        indexManager.cancelPriceFeedManagerUpgrade();

        _assertNoPendingUpgrade();
        assertEq(_implementationSlotValue(), s_initialImplementation);
    }

    function testCancelPriceFeedManagerUpgradeWhenExpiredResetsPendingState()
        public
    {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt + PROXY_UPGRADE_EXECUTION_WINDOW + 1);

        vm.prank(deployer);
        indexManager.cancelPriceFeedManagerUpgrade();

        _assertNoPendingUpgrade();
    }

    function testCancelPriceFeedManagerUpgradeAllowsImmediateNewProposal()
        public
    {
        _proposeUpgrade(address(s_newImplementation), "");

        vm.prank(deployer);
        indexManager.cancelPriceFeedManagerUpgrade();

        uint256 executableAt = _proposeUpgrade(
            address(s_otherImplementation),
            ""
        );
        (address implementation, , ) = indexManager
            .getPendingPriceFeedManagerUpgrade();
        assertEq(implementation, address(s_otherImplementation));
        assertEq(executableAt, block.timestamp + PROXY_UPGRADE_DELAY);
    }

    function testCancelPriceFeedManagerUpgradeEmitsEvent() public {
        _proposeUpgrade(address(s_newImplementation), "");

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.cancelPriceFeedManagerUpgrade();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(indexManager) ||
                logs[i].topics[0] != PriceFeedManagerUpgradeCancelled.selector
            ) continue;

            eventFound = true;
            assertEq(
                address(uint160(uint256(logs[i].topics[1]))),
                address(s_newImplementation),
                "event must log the cancelled implementation"
            );
            assertEq(
                address(uint160(uint256(logs[i].topics[2]))),
                deployer,
                "event must log the canceller"
            );
            break;
        }
        assertTrue(
            eventFound,
            "PriceFeedManagerUpgradeCancelled event was not emitted"
        );
    }

    function testExecutePriceFeedManagerUpgradeRevertsAfterCancel() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.prank(deployer);
        indexManager.cancelPriceFeedManagerUpgrade();
        vm.warp(executableAt);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__NoPendingPriceFeedManagerUpgrade.selector);
        indexManager.executePriceFeedManagerUpgrade();
    }
}
