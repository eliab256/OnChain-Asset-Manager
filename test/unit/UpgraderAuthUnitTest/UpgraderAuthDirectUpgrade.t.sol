// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseUpgraderAuthTest} from "./BaseUpgraderAuth.t.sol";
import {IUpgradeV2Mock} from "../../mocks/IUpgradeV2Mock.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import {UpgraderAuth__Unauthorized} from "../../../src/errors/UpgraderAuthErrors.sol";

/**
 * @dev _authorizeUpgrade of UpgraderAuth: every caller other than the upgrader is rejected, including the
 *      owner (IndexManager) and the timelock operator (MultiSigWallet); UUPS context guard on the implementation;
 *      invalid implementations rejected at timelock execute with the OZ error bubbled through the timelock.
 */
contract UpgraderAuthDirectUpgradeTest is BaseUpgraderAuthTest {
    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _expectUnauthorizedDirectUpgrade(address _caller) internal {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            vm.prank(_caller);
            vm.expectRevert(abi.encodeWithSelector(UpgraderAuth__Unauthorized.selector, _caller));
            UUPSUpgradeable(s_proxies[i]).upgradeToAndCall(s_newImplementations[i], "");

            assertEq(_implementationOf(s_proxies[i]), s_initialImplementations[i]);
        }
    }

    /// @dev Schedules the upgrade of proxy `_id` to `_implementation`, waits and expects `_revertData` at execute.
    function _expectExecuteRevert(
        uint256 _id,
        address _implementation,
        bytes memory _revertData
    ) internal {
        bytes memory payload = _scheduleUpgradeAndWait(_id, _implementation, "");

        vm.prank(s_timelockOperator);
        vm.expectRevert(_revertData);
        timelock.execute(s_proxies[_id], 0, payload, bytes32(0), UPGRADE_SALT);

        assertEq(_implementationOf(s_proxies[_id]), s_initialImplementations[_id]);
    }

    // =========================================================================
    //  Direct upgradeToAndCall on the proxies
    // =========================================================================

    function testDirectUpgradeByOwnerIndexManagerReverts() public {
        _expectUnauthorizedDirectUpgrade(address(indexManager));
    }

    function testDirectUpgradeByMultiSigReverts() public {
        _expectUnauthorizedDirectUpgrade(address(multiSigWallet));
    }

    function testDirectUpgradeByIndexManagerAdminEoaReverts() public {
        _expectUnauthorizedDirectUpgrade(deployer);
    }

    function testDirectUpgradeByOutsiderEoaReverts() public {
        _expectUnauthorizedDirectUpgrade(s_outsider);
    }

    function testDirectUpgradeByUpgraderSucceeds() public {
        // Authorization is msg.sender == upgrader: the timelock calling directly passes the check.
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            vm.prank(address(timelock));
            UUPSUpgradeable(s_proxies[i]).upgradeToAndCall(s_newImplementations[i], "");

            assertEq(_implementationOf(s_proxies[i]), s_newImplementations[i]);
        }
    }

    function testFreshProxyIsUpgradeableOnlyByItsOwnUpgrader() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            address proxy = address(
                new ERC1967Proxy(_freshImplementation(i), _initializeCalldata(i, s_freshUpgrader))
            );

            vm.prank(s_freshUpgrader);
            UUPSUpgradeable(proxy).upgradeToAndCall(s_newImplementations[i], "");

            assertEq(IUpgradeV2Mock(proxy).getImplementation(), s_newImplementations[i]);
            assertEq(IUpgradeV2Mock(proxy).getUpgrader(), s_freshUpgrader);
        }
    }

    function testFreshProxyRejectsTheDeployedTimelock() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            address proxy = address(
                new ERC1967Proxy(_freshImplementation(i), _initializeCalldata(i, s_freshUpgrader))
            );

            vm.prank(address(timelock));
            vm.expectRevert(abi.encodeWithSelector(UpgraderAuth__Unauthorized.selector, address(timelock)));
            UUPSUpgradeable(proxy).upgradeToAndCall(s_newImplementations[i], "");
        }
    }

    // =========================================================================
    //  upgradeToAndCall on the implementations
    // =========================================================================

    function testUpgradeToAndCallOnImplementationReverts() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            // UUPS onlyProxy guard runs before _authorizeUpgrade, so even the upgrader is rejected.
            vm.prank(address(timelock));
            vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
            UUPSUpgradeable(s_initialImplementations[i]).upgradeToAndCall(s_newImplementations[i], "");
        }
    }

    // =========================================================================
    //  Invalid implementations rejected at execute
    // =========================================================================

    function testExecuteWithWrongUuidImplementationReverts() public {
        bytes32 wrongUuid = s_wrongUuidImplementation.WRONG_UUID();
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            _expectExecuteRevert(
                i,
                address(s_wrongUuidImplementation),
                abi.encodeWithSelector(UUPSUpgradeable.UUPSUnsupportedProxiableUUID.selector, wrongUuid)
            );
        }
    }

    function testExecuteWithNonUupsContractReverts() public {
        // A contract without proxiableUUID (the USDC mock) makes the UUPS try/catch fail.
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            _expectExecuteRevert(
                i,
                address(mockUsdc),
                abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(mockUsdc))
            );
        }
    }

    function testExecuteWithProxyAsImplementationReverts() public {
        // proxiableUUID is notDelegated: called through a proxy it reverts, so the proxy is rejected.
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            _expectExecuteRevert(
                i,
                s_proxies[i],
                abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, s_proxies[i])
            );
        }
    }

    function testExecuteWithNoCodeImplementationReverts() public {
        // Calling proxiableUUID on an address without code returns empty data: the ABI decoding fails in the
        // proxy (outside the try/catch) with empty revert data, which the timelock turns into Errors.FailedCall.
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            _expectExecuteRevert(
                i,
                s_noCodeImplementation,
                abi.encodeWithSelector(Errors.FailedCall.selector)
            );
        }
    }
}
