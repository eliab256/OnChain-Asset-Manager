// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {SwapType} from "../../../src/types.sol";
import {SwapManagerV2Mock} from "../../mocks/SwapManagerV2Mock.sol";
import {ProxiableWrongUuidMock} from "../../mocks/ProxiableWrongUuidMock.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Vm} from "forge-std/Vm.sol";

import "../../../src/errors/IndexManagerErrors.sol";
import "../../../src/events/IndexManagerEvents.sol";

contract IndexManagerSwapManagerUpgradeTest is BaseTest {
    // =========================================================================
    //  Contracts and addresses
    // =========================================================================

    SwapManagerV2Mock internal s_newImplementation;
    SwapManagerV2Mock internal s_otherImplementation;
    ProxiableWrongUuidMock internal s_wrongUuidImplementation;
    address internal s_noCodeImplementation = makeAddr("noCodeImplementation");

    // =========================================================================
    //  Constants
    // =========================================================================

    /// Number of SwapType values (ASSET0_USDC, ASSET1_USDC, ASSET0_ASSET1)
    uint256 constant SWAP_TYPES_COUNT = 3;

    /// USDC spent in the end-to-end buy after the upgrade
    uint256 constant BUY_USDC_AMOUNT = 4_000e6;

    /// Expected V2 version returned by SwapManagerV2Mock
    uint256 constant V2_VERSION = 2;

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
        s_newImplementation = new SwapManagerV2Mock();
        s_otherImplementation = new SwapManagerV2Mock();
        s_wrongUuidImplementation = new ProxiableWrongUuidMock();

        s_defaultAdminRole = indexManager.DEFAULT_ADMIN_ROLE();
        s_initialImplementation = swapManager.getImplementation();
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
        executableAt = indexManager.proposeSwapManagerUpgrade(
            _implementation,
            _data
        );
    }

    /// @dev Executes the pending upgrade as the admin.
    function _executeUpgrade() internal {
        vm.prank(deployer);
        indexManager.executeSwapManagerUpgrade();
    }

    /// @dev Reads the ERC-1967 implementation slot of the SwapManager proxy.
    function _implementationSlotValue() internal view returns (address) {
        return
            address(
                uint160(
                    uint256(
                        vm.load(
                            address(swapManager),
                            ERC1967Utils.IMPLEMENTATION_SLOT
                        )
                    )
                )
            );
    }

    /// @dev Hash of every route stored for `_index`, one per SwapType.
    function _routeHashes(
        address _index
    ) internal view returns (bytes32[SWAP_TYPES_COUNT] memory hashes) {
        for (uint256 i = 0; i < SWAP_TYPES_COUNT; i++) {
            hashes[i] = keccak256(
                abi.encode(swapManager.getRoute(_index, SwapType(i)))
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

    // =========================================================================
    //  Proxy wiring
    // =========================================================================

    function testSwapManagerProxyMatchesIndexManagerGetter() public view {
        assertEq(
            address(swapManager),
            indexManager.getSwapManagerAddress(),
            "deploy script must return the IndexManager proxy"
        );
    }

    function testAllIndexesEmbedTheSameSwapManagerProxy() public view {
        address proxy = indexManager.getSwapManagerAddress();
        assertTrue(
            _codeEmbedsAddress(address(initializedIndex), proxy),
            "initializedIndex must use the SwapManager proxy"
        );
        assertTrue(
            _codeEmbedsAddress(address(nonInitializedIndex), proxy),
            "nonInitializedIndex must use the SwapManager proxy"
        );
        assertFalse(
            _codeEmbedsAddress(address(initializedIndex), s_initialImplementation),
            "index must not point at the bare implementation"
        );
    }

    function testSwapManagerProxyOwnerIsIndexManager() public view {
        assertEq(
            swapManager.owner(),
            address(indexManager),
            "IndexManager must own the SwapManager proxy"
        );
    }

    function testSwapManagerProxyCannotBeReinitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        swapManager.initialize(user1);
    }

    function testGetPendingSwapManagerUpgradeIsEmptyByDefault() public view {
        (
            address implementation,
            bytes memory data,
            uint256 executableAt
        ) = indexManager.getPendingSwapManagerUpgrade();
        assertEq(implementation, address(0));
        assertEq(data.length, 0);
        assertEq(executableAt, 0);
    }

    // =========================================================================
    //  proposeSwapManagerUpgrade
    // =========================================================================

    function testProposeSwapManagerUpgradeRevertsIfCallerNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                s_defaultAdminRole
            )
        );
        indexManager.proposeSwapManagerUpgrade(address(s_newImplementation), "");
    }

    function testProposeSwapManagerUpgradeRevertsIfImplementationHasNoCode()
        public
    {
        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidSwapManagerImplementation.selector);
        indexManager.proposeSwapManagerUpgrade(s_noCodeImplementation, "");
    }

    function testProposeSwapManagerUpgradeRevertsIfImplementationIsCurrent()
        public
    {
        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidSwapManagerImplementation.selector);
        indexManager.proposeSwapManagerUpgrade(s_initialImplementation, "");
    }

    function testProposeSwapManagerUpgradeRevertsIfImplementationHasNoProxiableUuid()
        public
    {
        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidSwapManagerImplementation.selector);
        indexManager.proposeSwapManagerUpgrade(address(mockUsdc), "");
    }

    function testProposeSwapManagerUpgradeRevertsIfProxiableUuidIsWrongSlot()
        public
    {
        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidSwapManagerImplementation.selector);
        indexManager.proposeSwapManagerUpgrade(
            address(s_wrongUuidImplementation),
            ""
        );
    }

    function testProposeSwapManagerUpgradeRevertsIfImplementationIsTheProxy()
        public
    {
        // proxiableUUID() reverts when called through a proxy (notDelegated)
        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidSwapManagerImplementation.selector);
        indexManager.proposeSwapManagerUpgrade(address(swapManager), "");
    }

    function testProposeSwapManagerUpgradeRevertsIfPendingWithinDelay() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt - 1);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__SwapManagerUpgradePending.selector);
        indexManager.proposeSwapManagerUpgrade(
            address(s_otherImplementation),
            ""
        );
    }

    function testProposeSwapManagerUpgradeStoresPendingUpgrade() public {
        bytes memory data = abi.encodeCall(SwapManagerV2Mock.version, ());
        uint256 expectedExecutableAt = block.timestamp +
            SWAP_MANAGER_UPGRADE_DELAY;

        uint256 executableAt = _proposeUpgrade(
            address(s_newImplementation),
            data
        );

        (
            address implementation,
            bytes memory storedData,
            uint256 storedExecutableAt
        ) = indexManager.getPendingSwapManagerUpgrade();
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

    function testProposeSwapManagerUpgradeEmitsEvent() public {
        uint256 expectedExecutableAt = block.timestamp +
            SWAP_MANAGER_UPGRADE_DELAY;

        vm.recordLogs();
        _proposeUpgrade(address(s_newImplementation), "");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(indexManager) ||
                logs[i].topics[0] != SwapManagerUpgradeProposed.selector
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
        assertTrue(eventFound, "SwapManagerUpgradeProposed event was not emitted");
    }

    function testProposeSwapManagerUpgradeOverwritesExpiredProposal() public {
        uint256 firstExecutableAt = _proposeUpgrade(
            address(s_newImplementation),
            ""
        );
        vm.warp(firstExecutableAt + SWAP_MANAGER_UPGRADE_EXECUTION_WINDOW + 1);

        bytes memory data = abi.encodeCall(SwapManagerV2Mock.version, ());
        uint256 secondExecutableAt = _proposeUpgrade(
            address(s_otherImplementation),
            data
        );

        (
            address implementation,
            bytes memory storedData,
            uint256 storedExecutableAt
        ) = indexManager.getPendingSwapManagerUpgrade();
        assertEq(implementation, address(s_otherImplementation));
        assertEq(storedData, data);
        assertEq(storedExecutableAt, secondExecutableAt);
        assertEq(
            secondExecutableAt,
            block.timestamp + SWAP_MANAGER_UPGRADE_DELAY
        );
    }

    function testProposeSwapManagerUpgradeOverwritesExecutableProposal() public {
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
            .getPendingSwapManagerUpgrade();
        assertEq(implementation, address(s_otherImplementation));
        assertEq(storedExecutableAt, secondExecutableAt);
    }

    // =========================================================================
    //  executeSwapManagerUpgrade
    // =========================================================================

    function testExecuteSwapManagerUpgradeRevertsIfCallerNotAdmin() public {
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
        indexManager.executeSwapManagerUpgrade();
    }

    function testExecuteSwapManagerUpgradeRevertsIfNoPendingUpgrade() public {
        vm.prank(deployer);
        vm.expectRevert(IndexManager__NoPendingSwapManagerUpgrade.selector);
        indexManager.executeSwapManagerUpgrade();
    }

    function testExecuteSwapManagerUpgradeRevertsBeforeDelay() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt - 1);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__NoPendingSwapManagerUpgrade.selector);
        indexManager.executeSwapManagerUpgrade();
    }

    function testExecuteSwapManagerUpgradeRevertsAfterExecutionWindow() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt + SWAP_MANAGER_UPGRADE_EXECUTION_WINDOW + 1);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__SwapManagerUpgradeExpired.selector);
        indexManager.executeSwapManagerUpgrade();
    }

    function testExecuteSwapManagerUpgradeSucceedsAtExecutableAt() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt);

        _executeUpgrade();

        assertEq(_implementationSlotValue(), address(s_newImplementation));
    }

    function testExecuteSwapManagerUpgradeSucceedsAtEndOfExecutionWindow()
        public
    {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt + SWAP_MANAGER_UPGRADE_EXECUTION_WINDOW);

        _executeUpgrade();

        assertEq(_implementationSlotValue(), address(s_newImplementation));
    }

    function testExecuteSwapManagerUpgradeUpgradesProxyAndKeepsRoutes() public {
        bytes32[SWAP_TYPES_COUNT] memory routesBefore = _routeHashes(
            address(initializedIndex)
        );
        assertEq(_implementationSlotValue(), s_initialImplementation);

        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt);
        _executeUpgrade();

        SwapManagerV2Mock upgraded = SwapManagerV2Mock(address(swapManager));
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
            indexManager.getSwapManagerAddress(),
            address(swapManager),
            "proxy address must not change"
        );

        bytes32[SWAP_TYPES_COUNT] memory routesAfter = _routeHashes(
            address(initializedIndex)
        );
        for (uint256 i = 0; i < SWAP_TYPES_COUNT; i++) {
            assertEq(routesAfter[i], routesBefore[i], "route must survive the upgrade");
        }

        (
            address implementation,
            bytes memory data,
            uint256 pendingExecutableAt
        ) = indexManager.getPendingSwapManagerUpgrade();
        assertEq(implementation, address(0), "pending implementation must be cleared");
        assertEq(data.length, 0, "pending data must be cleared");
        assertEq(pendingExecutableAt, 0, "pending executableAt must be cleared");
    }

    function testExecuteSwapManagerUpgradeEmitsEvent() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt);

        vm.recordLogs();
        _executeUpgrade();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(indexManager) ||
                logs[i].topics[0] != SwapManagerUpgraded.selector
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
        assertTrue(eventFound, "SwapManagerUpgraded event was not emitted");
    }

    function testExecuteSwapManagerUpgradeWithDataSucceeds() public {
        bytes memory data = abi.encodeCall(SwapManagerV2Mock.version, ());
        uint256 executableAt = _proposeUpgrade(
            address(s_newImplementation),
            data
        );
        vm.warp(executableAt);

        _executeUpgrade();

        assertEq(_implementationSlotValue(), address(s_newImplementation));
        assertEq(SwapManagerV2Mock(address(swapManager)).version(), V2_VERSION);
    }

    function testExecuteSwapManagerUpgradeRevertsIfDataCallReverts() public {
        // Re-running initialize on an already initialized proxy must revert,
        // rolling back the whole upgrade.
        bytes memory data = abi.encodeCall(SwapManager.initialize, (user1));
        uint256 executableAt = _proposeUpgrade(
            address(s_newImplementation),
            data
        );
        vm.warp(executableAt);

        vm.prank(deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        indexManager.executeSwapManagerUpgrade();
    }

    function testIndexWorksEndToEndAfterSwapManagerUpgrade() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.warp(executableAt);
        _executeUpgrade();
        _refreshPriceFeeds();

        uint256 sharesBefore = initializedIndex.balanceOf(user1);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), BUY_USDC_AMOUNT);

        // the buy must go through the upgraded proxy (it reads the ERC-1967 slot)
        vm.record();
        vm.prank(user1);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            BUY_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        (bytes32[] memory proxyReads, ) = vm.accesses(address(swapManager));
        bool implementationSlotRead;
        for (uint256 i = 0; i < proxyReads.length; i++) {
            if (proxyReads[i] == ERC1967Utils.IMPLEMENTATION_SLOT) {
                implementationSlotRead = true;
                break;
            }
        }
        assertTrue(implementationSlotRead, "index must call the SwapManager proxy");

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
    //  cancelSwapManagerUpgrade
    // =========================================================================

    function testCancelSwapManagerUpgradeRevertsIfCallerNotAdmin() public {
        _proposeUpgrade(address(s_newImplementation), "");

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                s_defaultAdminRole
            )
        );
        indexManager.cancelSwapManagerUpgrade();
    }

    function testCancelSwapManagerUpgradeRevertsIfNoPendingUpgrade() public {
        vm.prank(deployer);
        vm.expectRevert(IndexManager__NoPendingSwapManagerUpgrade.selector);
        indexManager.cancelSwapManagerUpgrade();
    }

    function testCancelSwapManagerUpgradeResetsPendingState() public {
        _proposeUpgrade(
            address(s_newImplementation),
            abi.encodeCall(SwapManagerV2Mock.version, ())
        );

        vm.prank(deployer);
        indexManager.cancelSwapManagerUpgrade();

        (
            address implementation,
            bytes memory data,
            uint256 executableAt
        ) = indexManager.getPendingSwapManagerUpgrade();
        assertEq(implementation, address(0));
        assertEq(data.length, 0);
        assertEq(executableAt, 0);
        assertEq(_implementationSlotValue(), s_initialImplementation);
    }

    function testCancelSwapManagerUpgradeAllowsImmediateNewProposal() public {
        _proposeUpgrade(address(s_newImplementation), "");

        vm.prank(deployer);
        indexManager.cancelSwapManagerUpgrade();

        uint256 executableAt = _proposeUpgrade(
            address(s_otherImplementation),
            ""
        );
        (address implementation, , ) = indexManager
            .getPendingSwapManagerUpgrade();
        assertEq(implementation, address(s_otherImplementation));
        assertEq(executableAt, block.timestamp + SWAP_MANAGER_UPGRADE_DELAY);
    }

    function testCancelSwapManagerUpgradeEmitsEvent() public {
        _proposeUpgrade(address(s_newImplementation), "");

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.cancelSwapManagerUpgrade();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(indexManager) ||
                logs[i].topics[0] != SwapManagerUpgradeCancelled.selector
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
        assertTrue(eventFound, "SwapManagerUpgradeCancelled event was not emitted");
    }

    function testExecuteSwapManagerUpgradeRevertsAfterCancel() public {
        uint256 executableAt = _proposeUpgrade(address(s_newImplementation), "");
        vm.prank(deployer);
        indexManager.cancelSwapManagerUpgrade();
        vm.warp(executableAt);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__NoPendingSwapManagerUpgrade.selector);
        indexManager.executeSwapManagerUpgrade();
    }

    // =========================================================================
    //  Direct upgrade bypassing the IndexManager timelock
    // =========================================================================

    function testDirectUpgradeToAndCallByAdminEoaReverts() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                deployer
            )
        );
        swapManager.upgradeToAndCall(address(s_newImplementation), "");
    }

    function testDirectUpgradeToAndCallByMultiSigReverts() public {
        vm.prank(address(multiSigWallet));
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                address(multiSigWallet)
            )
        );
        swapManager.upgradeToAndCall(address(s_newImplementation), "");
    }

    function testDirectUpgradeToAndCallOnImplementationReverts() public {
        // UUPS onlyProxy guard: the bare implementation cannot be upgraded directly
        vm.prank(address(indexManager));
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        SwapManager(s_initialImplementation).upgradeToAndCall(
            address(s_newImplementation),
            ""
        );
    }
}
