// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseUpgraderAuthTest} from "./BaseUpgraderAuth.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    TimelockController
} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

/**
 * @dev Event-only tests of the timelocked proxy upgrades: CallScheduled / CallSalt / CallExecuted / Cancelled /
 *      MinDelayChange on the timelock and IERC1967.Upgraded on the proxy.
 */
contract UpgraderAuthTimelockEventsTest is BaseUpgraderAuthTest {
    /// New min delay set through the timelock self-call (3 days)
    uint256 internal constant NEW_MIN_DELAY = 3 days;

    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  schedule
    // =========================================================================

    function testScheduleEmitsCallScheduledAndCallSalt() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            bytes memory payload = _upgradePayload(s_newImplementations[i], s_initializeV2Data);
            bytes32 expectedId = _operationId(s_proxies[i], payload);

            vm.recordLogs();
            _schedule(s_proxies[i], payload);
            Vm.Log[] memory logs = vm.getRecordedLogs();

            _assertCallScheduled(logs, expectedId, 0, s_proxies[i], payload);
            _assertCallSalt(logs, expectedId);
        }
    }

    // =========================================================================
    //  execute
    // =========================================================================

    function testExecuteEmitsUpgradedOnProxyAndCallExecutedOnTimelock() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            bytes memory payload = _scheduleUpgradeAndWait(i, s_newImplementations[i], "");
            bytes32 expectedId = _operationId(s_proxies[i], payload);

            vm.recordLogs();
            _execute(s_proxies[i], payload);
            Vm.Log[] memory logs = vm.getRecordedLogs();

            _assertUpgraded(logs, s_proxies[i], s_newImplementations[i]);
            _assertCallExecuted(logs, expectedId, 0, s_proxies[i], payload);
        }
    }

    function testExecuteBatchEmitsUpgradedAndCallExecutedForEachProxy() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        ) = _batchUpgradeAll();
        bytes32 expectedId = timelock.hashOperationBatch(
            targets,
            values,
            payloads,
            bytes32(0),
            UPGRADE_SALT
        );
        vm.prank(s_timelockOperator);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), UPGRADE_SALT, s_minDelay);
        vm.warp(block.timestamp + s_minDelay);

        vm.recordLogs();
        vm.prank(s_timelockOperator);
        timelock.executeBatch(targets, values, payloads, bytes32(0), UPGRADE_SALT);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            _assertUpgraded(logs, s_proxies[i], s_newImplementations[i]);
            _assertCallExecuted(logs, expectedId, i, s_proxies[i], payloads[i]);
        }
    }

    // =========================================================================
    //  cancel
    // =========================================================================

    function testCancelEmitsCancelled() public {
        bytes memory payload = _upgradePayload(s_newImplementations[ROUTER_ID], "");
        bytes32 id = _schedule(s_proxies[ROUTER_ID], payload);

        vm.recordLogs();
        vm.prank(s_timelockOperator);
        timelock.cancel(id);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 count, uint256 index) = _findLogs(
            logs,
            address(timelock),
            TimelockController.Cancelled.selector
        );
        assertEq(count, 1, "Cancelled must be emitted once");
        assertEq(logs[index].topics[1], id, "Cancelled id");
        assertEq(logs[index].data.length, 0, "Cancelled has no data");
    }

    // =========================================================================
    //  updateDelay
    // =========================================================================

    function testUpdateDelayThroughTimelockEmitsMinDelayChange() public {
        bytes memory payload = abi.encodeCall(TimelockController.updateDelay, (NEW_MIN_DELAY));
        _schedule(address(timelock), payload);
        vm.warp(block.timestamp + s_minDelay);

        vm.recordLogs();
        _execute(address(timelock), payload);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 count, uint256 index) = _findLogs(
            logs,
            address(timelock),
            TimelockController.MinDelayChange.selector
        );
        assertEq(count, 1, "MinDelayChange must be emitted once");
        (uint256 oldDuration, uint256 newDuration) = abi.decode(logs[index].data, (uint256, uint256));
        assertEq(oldDuration, s_minDelay, "old delay");
        assertEq(newDuration, NEW_MIN_DELAY, "new delay");
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _assertCallScheduled(
        Vm.Log[] memory _logs,
        bytes32 _id,
        uint256 _index,
        address _target,
        bytes memory _payload
    ) internal view {
        bool eventFound;
        for (uint256 i = 0; i < _logs.length; i++) {
            if (
                _logs[i].emitter != address(timelock) ||
                _logs[i].topics[0] != TimelockController.CallScheduled.selector ||
                uint256(_logs[i].topics[2]) != _index
            ) continue;
            eventFound = true;
            assertEq(_logs[i].topics[1], _id, "CallScheduled id");
            (
                address target,
                uint256 value,
                bytes memory data,
                bytes32 predecessor,
                uint256 delay
            ) = abi.decode(_logs[i].data, (address, uint256, bytes, bytes32, uint256));
            assertEq(target, _target, "CallScheduled target");
            assertEq(value, 0, "CallScheduled value");
            assertEq(data, _payload, "CallScheduled data");
            assertEq(predecessor, bytes32(0), "CallScheduled predecessor");
            assertEq(delay, s_minDelay, "CallScheduled delay");
        }
        assertTrue(eventFound, "CallScheduled was not emitted");
    }

    function _assertCallSalt(Vm.Log[] memory _logs, bytes32 _id) internal view {
        (uint256 count, uint256 index) = _findLogs(
            _logs,
            address(timelock),
            TimelockController.CallSalt.selector
        );
        assertEq(count, 1, "CallSalt must be emitted once");
        assertEq(_logs[index].topics[1], _id, "CallSalt id");
        assertEq(abi.decode(_logs[index].data, (bytes32)), UPGRADE_SALT, "CallSalt salt");
    }

    function _assertCallExecuted(
        Vm.Log[] memory _logs,
        bytes32 _id,
        uint256 _index,
        address _target,
        bytes memory _payload
    ) internal view {
        bool eventFound;
        for (uint256 i = 0; i < _logs.length; i++) {
            if (
                _logs[i].emitter != address(timelock) ||
                _logs[i].topics[0] != TimelockController.CallExecuted.selector ||
                uint256(_logs[i].topics[2]) != _index
            ) continue;
            eventFound = true;
            assertEq(_logs[i].topics[1], _id, "CallExecuted id");
            (address target, uint256 value, bytes memory data) = abi.decode(
                _logs[i].data,
                (address, uint256, bytes)
            );
            assertEq(target, _target, "CallExecuted target");
            assertEq(value, 0, "CallExecuted value");
            assertEq(data, _payload, "CallExecuted data");
        }
        assertTrue(eventFound, "CallExecuted was not emitted");
    }

    function _assertUpgraded(
        Vm.Log[] memory _logs,
        address _proxy,
        address _implementation
    ) internal pure {
        (uint256 count, uint256 index) = _findLogs(_logs, _proxy, IERC1967.Upgraded.selector);
        assertEq(count, 1, "Upgraded must be emitted once by the proxy");
        assertEq(_topicToAddress(_logs[index].topics[1]), _implementation, "Upgraded implementation");
        assertEq(_logs[index].data.length, 0, "Upgraded has no data");
    }
}
