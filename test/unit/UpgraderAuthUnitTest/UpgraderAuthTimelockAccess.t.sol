// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseUpgraderAuthTest} from "./BaseUpgraderAuth.t.sol";
import {
    TimelockController
} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @dev Timelock guards on the proxy upgrades: delay, operation state, cancel, role checks,
 *      admin-less setup and min-delay changes reachable only through a timelocked self-call.
 */
contract UpgraderAuthTimelockAccessTest is BaseUpgraderAuthTest {
    /// New min delay set through the timelock self-call (3 days)
    uint256 internal constant NEW_MIN_DELAY = 3 days;

    /// Callers that must not hold any timelock role (assigned in setUp)
    address[] internal s_unauthorizedCallers;

    function setUp() public override {
        super.setUp();
        s_unauthorizedCallers.push(s_outsider);
        s_unauthorizedCallers.push(deployer);
        s_unauthorizedCallers.push(address(indexManager));
        s_unauthorizedCallers.push(user1);
    }

    // =========================================================================
    //  Delay
    // =========================================================================

    function testExecuteBeforeDelayReverts() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            bytes memory payload = _upgradePayload(s_newImplementations[i], "");
            bytes32 id = _schedule(s_proxies[i], payload);

            vm.prank(s_timelockOperator);
            vm.expectRevert(
                abi.encodeWithSelector(
                    TimelockController.TimelockUnexpectedOperationState.selector,
                    id,
                    s_readyStateBitmap
                )
            );
            timelock.execute(s_proxies[i], 0, payload, bytes32(0), UPGRADE_SALT);
        }
    }

    function testExecuteOneSecondBeforeReadyTimestampReverts() public {
        bytes memory payload = _upgradePayload(s_newImplementations[ROUTER_ID], "");
        bytes32 id = _schedule(s_proxies[ROUTER_ID], payload);
        vm.warp(timelock.getTimestamp(id) - 1);

        vm.prank(s_timelockOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                s_readyStateBitmap
            )
        );
        timelock.execute(s_proxies[ROUTER_ID], 0, payload, bytes32(0), UPGRADE_SALT);
    }

    function testExecuteAtExactReadyTimestampSucceeds() public {
        bytes memory payload = _upgradePayload(s_newImplementations[ROUTER_ID], "");
        bytes32 id = _schedule(s_proxies[ROUTER_ID], payload);
        vm.warp(timelock.getTimestamp(id));

        _execute(s_proxies[ROUTER_ID], payload);

        assertEq(_implementationOf(s_proxies[ROUTER_ID]), s_newImplementations[ROUTER_ID]);
    }

    function testScheduleWithDelayBelowMinimumReverts() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            bytes memory payload = _upgradePayload(s_newImplementations[i], "");

            vm.prank(s_timelockOperator);
            vm.expectRevert(
                abi.encodeWithSelector(
                    TimelockController.TimelockInsufficientDelay.selector,
                    s_belowMinDelay,
                    s_minDelay
                )
            );
            timelock.schedule(s_proxies[i], 0, payload, bytes32(0), UPGRADE_SALT, s_belowMinDelay);
        }
    }

    function testScheduleWithLongerDelayWaitsTheLongerDelay() public {
        uint256 longerDelay = s_minDelay * 2;
        bytes memory payload = _upgradePayload(s_newImplementations[ROUTER_ID], "");
        bytes32 id = _operationId(s_proxies[ROUTER_ID], payload);

        vm.prank(s_timelockOperator);
        timelock.schedule(s_proxies[ROUTER_ID], 0, payload, bytes32(0), UPGRADE_SALT, longerDelay);
        vm.warp(block.timestamp + s_minDelay);

        assertFalse(timelock.isOperationReady(id), "min delay must not be enough");
        assertEq(timelock.getTimestamp(id), block.timestamp - s_minDelay + longerDelay);
    }

    function testScheduleSameOperationTwiceReverts() public {
        bytes memory payload = _upgradePayload(s_newImplementations[ROUTER_ID], "");
        bytes32 id = _schedule(s_proxies[ROUTER_ID], payload);

        vm.prank(s_timelockOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                s_unsetStateBitmap
            )
        );
        timelock.schedule(s_proxies[ROUTER_ID], 0, payload, bytes32(0), UPGRADE_SALT, s_minDelay);
    }

    function testExecuteDoneOperationAgainReverts() public {
        bytes memory payload = _scheduleUpgradeAndWait(ROUTER_ID, s_newImplementations[ROUTER_ID], "");
        _execute(s_proxies[ROUTER_ID], payload);
        bytes32 id = _operationId(s_proxies[ROUTER_ID], payload);

        vm.prank(s_timelockOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                s_readyStateBitmap
            )
        );
        timelock.execute(s_proxies[ROUTER_ID], 0, payload, bytes32(0), UPGRADE_SALT);
    }

    function testExecuteUnscheduledUpgradeReverts() public {
        bytes memory payload = _upgradePayload(s_newImplementations[ROUTER_ID], "");
        bytes32 id = _operationId(s_proxies[ROUTER_ID], payload);

        vm.prank(s_timelockOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                s_readyStateBitmap
            )
        );
        timelock.execute(s_proxies[ROUTER_ID], 0, payload, bytes32(0), UPGRADE_SALT);
    }

    // =========================================================================
    //  cancel
    // =========================================================================

    function testCancelByProposerClearsOperation() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            bytes memory payload = _upgradePayload(s_newImplementations[i], "");
            bytes32 id = _schedule(s_proxies[i], payload);
            assertTrue(timelock.isOperationPending(id));

            vm.prank(s_timelockOperator);
            timelock.cancel(id);

            assertFalse(timelock.isOperation(id), "cancelled operation must be unset");
            assertEq(timelock.getTimestamp(id), 0, "cancelled operation timestamp");
            assertEq(_implementationOf(s_proxies[i]), s_initialImplementations[i]);
        }
    }

    function testExecuteAfterCancelReverts() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            bytes memory payload = _upgradePayload(s_newImplementations[i], "");
            bytes32 id = _schedule(s_proxies[i], payload);
            vm.prank(s_timelockOperator);
            timelock.cancel(id);
            vm.warp(block.timestamp + s_minDelay);

            vm.prank(s_timelockOperator);
            vm.expectRevert(
                abi.encodeWithSelector(
                    TimelockController.TimelockUnexpectedOperationState.selector,
                    id,
                    s_readyStateBitmap
                )
            );
            timelock.execute(s_proxies[i], 0, payload, bytes32(0), UPGRADE_SALT);
        }
    }

    function testCancelledUpgradeCanBeRescheduled() public {
        bytes memory payload = _upgradePayload(s_newImplementations[ROUTER_ID], "");
        bytes32 id = _schedule(s_proxies[ROUTER_ID], payload);
        vm.prank(s_timelockOperator);
        timelock.cancel(id);

        _schedule(s_proxies[ROUTER_ID], payload);
        vm.warp(block.timestamp + s_minDelay);
        _execute(s_proxies[ROUTER_ID], payload);

        assertEq(_implementationOf(s_proxies[ROUTER_ID]), s_newImplementations[ROUTER_ID]);
    }

    function testCancelUnknownOperationReverts() public {
        bytes32 id = _operationId(s_proxies[ROUTER_ID], _upgradePayload(s_newImplementations[ROUTER_ID], ""));

        vm.prank(s_timelockOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                s_pendingStateBitmap
            )
        );
        timelock.cancel(id);
    }

    function testCancelDoneOperationReverts() public {
        bytes memory payload = _scheduleUpgradeAndWait(ROUTER_ID, s_newImplementations[ROUTER_ID], "");
        _execute(s_proxies[ROUTER_ID], payload);
        bytes32 id = _operationId(s_proxies[ROUTER_ID], payload);

        vm.prank(s_timelockOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                s_pendingStateBitmap
            )
        );
        timelock.cancel(id);
    }

    // =========================================================================
    //  Role checks
    // =========================================================================

    function testScheduleByNonProposerReverts() public {
        bytes memory payload = _upgradePayload(s_newImplementations[ROUTER_ID], "");
        for (uint256 i = 0; i < s_unauthorizedCallers.length; i++) {
            address caller = s_unauthorizedCallers[i];
            vm.prank(caller);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector,
                    caller,
                    s_proposerRole
                )
            );
            timelock.schedule(s_proxies[ROUTER_ID], 0, payload, bytes32(0), UPGRADE_SALT, s_minDelay);
        }
    }

    function testScheduleBatchByNonProposerReverts() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        ) = _batchUpgradeAll();

        vm.prank(s_outsider);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                s_outsider,
                s_proposerRole
            )
        );
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), UPGRADE_SALT, s_minDelay);
    }

    function testExecuteByNonExecutorReverts() public {
        bytes memory payload = _scheduleUpgradeAndWait(ROUTER_ID, s_newImplementations[ROUTER_ID], "");
        for (uint256 i = 0; i < s_unauthorizedCallers.length; i++) {
            address caller = s_unauthorizedCallers[i];
            vm.prank(caller);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector,
                    caller,
                    s_executorRole
                )
            );
            timelock.execute(s_proxies[ROUTER_ID], 0, payload, bytes32(0), UPGRADE_SALT);
        }
    }

    function testExecuteBatchByNonExecutorReverts() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        ) = _batchUpgradeAll();
        vm.prank(s_timelockOperator);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), UPGRADE_SALT, s_minDelay);
        vm.warp(block.timestamp + s_minDelay);

        vm.prank(s_outsider);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                s_outsider,
                s_executorRole
            )
        );
        timelock.executeBatch(targets, values, payloads, bytes32(0), UPGRADE_SALT);
    }

    function testCancelByNonCancellerReverts() public {
        bytes32 id = _schedule(s_proxies[ROUTER_ID], _upgradePayload(s_newImplementations[ROUTER_ID], ""));
        for (uint256 i = 0; i < s_unauthorizedCallers.length; i++) {
            address caller = s_unauthorizedCallers[i];
            vm.prank(caller);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector,
                    caller,
                    s_cancellerRole
                )
            );
            timelock.cancel(id);
        }
    }

    function testUnauthorizedCallersHoldNoTimelockRole() public view {
        for (uint256 i = 0; i < s_unauthorizedCallers.length; i++) {
            address caller = s_unauthorizedCallers[i];
            assertFalse(timelock.hasRole(s_proposerRole, caller));
            assertFalse(timelock.hasRole(s_executorRole, caller));
            assertFalse(timelock.hasRole(s_cancellerRole, caller));
            assertFalse(timelock.hasRole(s_timelockAdminRole, caller));
        }
        assertFalse(timelock.hasRole(s_executorRole, address(0)), "executor role must not be open");
        assertFalse(timelock.hasRole(s_proposerRole, address(0)), "proposer role must not be open");
    }

    // =========================================================================
    //  Admin and min delay
    // =========================================================================

    function testTimelockAdminRoleIsHeldOnlyByTheTimelock() public view {
        assertTrue(timelock.hasRole(s_timelockAdminRole, address(timelock)), "OZ v5 self-admin");
        assertFalse(timelock.hasRole(s_timelockAdminRole, s_timelockOperator), "multisig must not be admin");
        assertFalse(timelock.hasRole(s_timelockAdminRole, address(0)), "no external admin");
        assertEq(timelock.getRoleAdmin(s_proposerRole), s_timelockAdminRole);
        assertEq(timelock.getRoleAdmin(s_executorRole), s_timelockAdminRole);
        assertEq(timelock.getRoleAdmin(s_cancellerRole), s_timelockAdminRole);
    }

    function testGrantRoleByMultiSigReverts() public {
        vm.prank(s_timelockOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                s_timelockOperator,
                s_timelockAdminRole
            )
        );
        timelock.grantRole(s_proposerRole, s_outsider);
    }

    function testGrantRoleThroughTimelockSelfCallSucceeds() public {
        bytes memory payload = abi.encodeCall(IAccessControl.grantRole, (s_proposerRole, s_outsider));
        _schedule(address(timelock), payload);
        vm.warp(block.timestamp + s_minDelay);

        _execute(address(timelock), payload);

        assertTrue(timelock.hasRole(s_proposerRole, s_outsider));
    }

    function testUpdateDelayFromMultiSigReverts() public {
        vm.prank(s_timelockOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnauthorizedCaller.selector,
                s_timelockOperator
            )
        );
        timelock.updateDelay(NEW_MIN_DELAY);
    }

    function testUpdateDelayFromOutsiderReverts() public {
        vm.prank(s_outsider);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnauthorizedCaller.selector,
                s_outsider
            )
        );
        timelock.updateDelay(NEW_MIN_DELAY);
    }

    function testUpdateDelayThroughTimelockSelfCallChangesMinDelay() public {
        bytes memory payload = abi.encodeCall(TimelockController.updateDelay, (NEW_MIN_DELAY));
        _schedule(address(timelock), payload);
        vm.warp(block.timestamp + s_minDelay);

        _execute(address(timelock), payload);

        assertEq(timelock.getMinDelay(), NEW_MIN_DELAY, "min delay must change");
    }
}
