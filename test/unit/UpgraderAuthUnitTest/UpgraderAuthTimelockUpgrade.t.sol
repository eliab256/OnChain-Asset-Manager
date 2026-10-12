// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseUpgraderAuthTest} from "./BaseUpgraderAuth.t.sol";
import {IUpgradeV2Mock} from "../../mocks/IUpgradeV2Mock.sol";
import {AggregatorConfigurableMock} from "../../mocks/AggregatorConfigurableMock.sol";
import {SwapType, SwapRoute, FeedConfig} from "../../../src/types.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PriceFeedManager__CallerNotAssetManager} from "../../../src/errors/PriceFeedManagerErrors.sol";

/**
 * @dev Happy paths of the timelocked upgrade of the SwapManager, PriceFeedManager and Router proxies:
 *      schedule -> wait min delay -> execute, single and batch, with and without upgrade calldata.
 */
contract UpgraderAuthTimelockUpgradeTest is BaseUpgraderAuthTest {
    /// Price of the feed registered after an upgrade (8 decimals)
    int256 internal constant NEW_FEED_PRICE = 2_000 * 10 ** 8;
    uint8 internal constant NEW_FEED_DECIMALS = 8;

    address internal s_newAsset = makeAddr("newAsset");

    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  schedule
    // =========================================================================

    function testScheduleStoresWaitingOperationWithoutUpgrading() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            bytes memory payload = _upgradePayload(s_newImplementations[i], "");
            bytes32 id = _operationId(s_proxies[i], payload);
            assertFalse(timelock.isOperation(id), "operation must not exist before schedule");

            _schedule(s_proxies[i], payload);

            assertTrue(timelock.isOperationPending(id), "operation must be pending");
            assertFalse(timelock.isOperationReady(id), "operation must not be ready yet");
            assertEq(timelock.getTimestamp(id), block.timestamp + s_minDelay, "ready timestamp");
            assertEq(
                _implementationOf(s_proxies[i]),
                s_initialImplementations[i],
                "schedule must not upgrade the proxy"
            );
        }
    }

    // =========================================================================
    //  execute
    // =========================================================================

    function testExecuteUpgradesEachProxyKeepingAddressAndState() public {
        address[3] memory proxiesFromManager = [
            indexManager.getSwapManagerAddress(),
            indexManager.getPriceFeedManagerAddress(),
            indexManager.getRouterAddress()
        ];
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            bytes32 stateBefore = _proxyStateHash(i);
            assertEq(proxiesFromManager[i], s_proxies[i], "IndexManager getter must return the proxy");
            assertTrue(
                s_initialImplementations[i] != s_newImplementations[i],
                "implementations must differ before the upgrade"
            );

            bytes memory payload = _scheduleUpgradeAndWait(i, s_newImplementations[i], "");
            bytes32 id = _operationId(s_proxies[i], payload);
            _execute(s_proxies[i], payload);

            IUpgradeV2Mock upgraded = IUpgradeV2Mock(s_proxies[i]);
            assertEq(_implementationOf(s_proxies[i]), s_newImplementations[i], "ERC-1967 slot");
            assertEq(upgraded.getImplementation(), s_newImplementations[i], "getImplementation");
            assertEq(upgraded.version(), V2_VERSION, "V2 logic must be live");
            assertEq(upgraded.getV2Marker(), 0, "no calldata: marker must stay unset");
            assertEq(upgraded.getUpgrader(), address(timelock), "upgrader must not change");
            assertEq(_proxyStateHash(i), stateBefore, "proxy state must survive the upgrade");
            assertTrue(timelock.isOperationDone(id), "operation must be done");
        }
        assertEq(indexManager.getSwapManagerAddress(), proxiesFromManager[SWAP_MANAGER_ID]);
        assertEq(indexManager.getPriceFeedManagerAddress(), proxiesFromManager[PRICE_FEED_MANAGER_ID]);
        assertEq(indexManager.getRouterAddress(), proxiesFromManager[ROUTER_ID]);
    }

    function testExecuteRunsUpgradeCalldataOnEachProxy() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            bytes32 stateBefore = _proxyStateHash(i);

            _upgradeToV2(i, s_initializeV2Data);

            assertEq(IUpgradeV2Mock(s_proxies[i]).getV2Marker(), V2_MARKER, "calldata must run on the proxy");
            assertEq(
                IUpgradeV2Mock(s_newImplementations[i]).getV2Marker(),
                0,
                "calldata must not touch the implementation"
            );
            assertEq(_proxyStateHash(i), stateBefore, "proxy state must survive the upgrade");
        }
    }

    function testReinitializerCannotRunTwiceAfterUpgrade() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            _upgradeToV2(i, s_initializeV2Data);

            vm.expectRevert(Initializable.InvalidInitialization.selector);
            IUpgradeV2Mock(s_proxies[i]).initializeV2(V2_MARKER + 1);
        }
    }

    function testExecuteRevertsWithBubbledErrorIfUpgradeCalldataReverts() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            // Re-running the V1 initializer on an initialized proxy reverts: the whole upgrade rolls back.
            bytes memory payload = _scheduleUpgradeAndWait(
                i,
                s_newImplementations[i],
                _initializeCalldata(i, s_outsider)
            );

            vm.prank(s_timelockOperator);
            vm.expectRevert(Initializable.InvalidInitialization.selector);
            timelock.execute(s_proxies[i], 0, payload, bytes32(0), UPGRADE_SALT);

            assertEq(_implementationOf(s_proxies[i]), s_initialImplementations[i], "upgrade must roll back");
            assertTrue(
                timelock.isOperationReady(_operationId(s_proxies[i], payload)),
                "a failed execution must leave the operation ready"
            );
        }
    }

    function testExecuteLongAfterReadyTimestampSucceeds() public {
        // No execution window: a ready operation never expires.
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            bytes memory payload = _scheduleUpgradeAndWait(i, s_newImplementations[i], "");
            vm.warp(block.timestamp + LONG_WAIT);

            _execute(s_proxies[i], payload);

            assertEq(_implementationOf(s_proxies[i]), s_newImplementations[i]);
        }
    }

    function testUpgradeToCurrentImplementationIsAllowed() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            bytes32 stateBefore = _proxyStateHash(i);
            bytes memory payload = _scheduleUpgradeAndWait(i, s_initialImplementations[i], "");

            _execute(s_proxies[i], payload);

            assertEq(_implementationOf(s_proxies[i]), s_initialImplementations[i]);
            assertEq(_proxyStateHash(i), stateBefore);
            assertTrue(timelock.isOperationDone(_operationId(s_proxies[i], payload)));
        }
    }

    function testSecondUpgradeRestoresPreviousImplementation() public {
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            _upgradeToV2(i, "");
            // Different payload, so a different operation id with the same salt.
            bytes memory rollback = _scheduleUpgradeAndWait(i, s_initialImplementations[i], "");
            _execute(s_proxies[i], rollback);

            assertEq(_implementationOf(s_proxies[i]), s_initialImplementations[i]);
            assertEq(IUpgradeV2Mock(s_proxies[i]).getUpgrader(), address(timelock));
        }
    }

    // =========================================================================
    //  scheduleBatch / executeBatch
    // =========================================================================

    function testExecuteBatchUpgradesAllThreeProxiesInOneOperation() public {
        bytes32[3] memory statesBefore = [
            _proxyStateHash(SWAP_MANAGER_ID),
            _proxyStateHash(PRICE_FEED_MANAGER_ID),
            _proxyStateHash(ROUTER_ID)
        ];
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        ) = _batchUpgradeAll();
        bytes32 id = timelock.hashOperationBatch(targets, values, payloads, bytes32(0), UPGRADE_SALT);

        vm.prank(s_timelockOperator);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), UPGRADE_SALT, s_minDelay);
        assertTrue(timelock.isOperationPending(id), "batch must be pending");
        vm.warp(block.timestamp + s_minDelay);

        vm.prank(s_timelockOperator);
        timelock.executeBatch(targets, values, payloads, bytes32(0), UPGRADE_SALT);

        assertTrue(timelock.isOperationDone(id), "batch must be done");
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            assertEq(_implementationOf(s_proxies[i]), s_newImplementations[i], "batch must upgrade every proxy");
            assertEq(IUpgradeV2Mock(s_proxies[i]).version(), V2_VERSION);
            assertEq(_proxyStateHash(i), statesBefore[i], "proxy state must survive the batch");
        }
    }

    function testExecuteBatchRollsBackEveryUpgradeIfOneFails() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        ) = _batchUpgradeAll();
        // The router upgrade points to a non-UUPS implementation: the whole batch must revert.
        payloads[ROUTER_ID] = _upgradePayload(address(s_wrongUuidImplementation), "");

        vm.prank(s_timelockOperator);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), UPGRADE_SALT, s_minDelay);
        vm.warp(block.timestamp + s_minDelay);

        bytes32 wrongUuid = s_wrongUuidImplementation.WRONG_UUID();
        vm.prank(s_timelockOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                UUPSUpgradeable.UUPSUnsupportedProxiableUUID.selector,
                wrongUuid
            )
        );
        timelock.executeBatch(targets, values, payloads, bytes32(0), UPGRADE_SALT);

        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            assertEq(_implementationOf(s_proxies[i]), s_initialImplementations[i], "batch must be atomic");
        }
    }

    // =========================================================================
    //  IndexManager keeps ownership after an upgrade
    // =========================================================================

    function testIndexManagerStillOwnsSwapManagerAfterUpgrade() public {
        _upgradeToV2(SWAP_MANAGER_ID, "");
        SwapRoute memory route = swapManager.getRoute(address(initializedIndex), SwapType.ASSET0_USDC);

        assertEq(swapManager.owner(), address(indexManager), "owner must not change");

        vm.prank(address(indexManager));
        swapManager.updateRoute(address(initializedIndex), SwapType.ASSET0_USDC, route);

        assertEq(
            keccak256(abi.encode(swapManager.getRoute(address(initializedIndex), SwapType.ASSET0_USDC))),
            keccak256(abi.encode(route)),
            "owner-only updateRoute must still work"
        );
    }

    function testSwapManagerOwnerFunctionRejectsOutsiderAfterUpgrade() public {
        _upgradeToV2(SWAP_MANAGER_ID, "");
        SwapRoute memory route = swapManager.getRoute(address(initializedIndex), SwapType.ASSET0_USDC);

        vm.prank(s_outsider);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, s_outsider)
        );
        swapManager.updateRoute(address(initializedIndex), SwapType.ASSET0_USDC, route);
    }

    function testIndexManagerStillOwnsPriceFeedManagerAfterUpgrade() public {
        _upgradeToV2(PRICE_FEED_MANAGER_ID, "");
        // Deployed after the warp, so its answer is fresh.
        AggregatorConfigurableMock feed = new AggregatorConfigurableMock(NEW_FEED_DECIMALS, NEW_FEED_PRICE);
        assertFalse(priceFeedManager.hasPriceFeed(s_newAsset));

        assertEq(priceFeedManager.owner(), address(indexManager), "owner must not change");

        // The asset-manager check reads the role on the owner (IndexManager).
        vm.prank(deployer);
        priceFeedManager.registerPriceFeed(s_newAsset, address(feed), assetPriceFeedMaxDelay);

        FeedConfig memory config = priceFeedManager.getPriceFeedConfig(s_newAsset);
        assertEq(config.feed, address(feed));
        assertEq(config.maxDelay, assetPriceFeedMaxDelay);
    }

    function testPriceFeedManagerAssetManagerCheckRejectsOutsiderAfterUpgrade() public {
        _upgradeToV2(PRICE_FEED_MANAGER_ID, "");
        AggregatorConfigurableMock feed = new AggregatorConfigurableMock(NEW_FEED_DECIMALS, NEW_FEED_PRICE);

        vm.prank(s_outsider);
        vm.expectRevert(PriceFeedManager__CallerNotAssetManager.selector);
        priceFeedManager.registerPriceFeed(s_newAsset, address(feed), assetPriceFeedMaxDelay);
    }
}
