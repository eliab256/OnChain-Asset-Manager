// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {PriceFeedManager} from "../../../src/PriceFeedManager.sol";
import {Router} from "../../../src/Router.sol";
import {SwapType, FeedConfig} from "../../../src/types.sol";
import {SwapManagerV2Mock} from "../../mocks/SwapManagerV2Mock.sol";
import {PriceFeedManagerV2Mock} from "../../mocks/PriceFeedManagerV2Mock.sol";
import {RouterV2Mock} from "../../mocks/RouterV2Mock.sol";
import {IUpgradeV2Mock} from "../../mocks/IUpgradeV2Mock.sol";
import {ProxiableWrongUuidMock} from "../../mocks/ProxiableWrongUuidMock.sol";
import {
    TimelockController
} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/**
 * @dev Shared state and helpers for the UpgraderAuth tests: the SwapManager, PriceFeedManager and Router
 *      proxies are upgradeable only by the TimelockController deployed by DeployPeriphery, whose only
 *      proposer / executor / canceller is the MultiSigWallet. The three proxies are indexed
 *      SWAP_MANAGER_ID, PRICE_FEED_MANAGER_ID and ROUTER_ID so most tests loop over all of them.
 */
abstract contract BaseUpgraderAuthTest is BaseTest {
    // =========================================================================
    //  Contracts and addresses
    // =========================================================================

    /// Proxies under test, indexed by *_ID
    address[3] internal s_proxies;
    /// V2 implementations (one per proxy), each exposing IUpgradeV2Mock
    address[3] internal s_newImplementations;
    /// Implementations the proxies point to after DeployPeriphery
    address[3] internal s_initialImplementations;

    ProxiableWrongUuidMock internal s_wrongUuidImplementation;
    address internal s_noCodeImplementation = makeAddr("noCodeImplementation");
    address internal s_outsider = makeAddr("outsider");
    address internal s_freshUpgrader = makeAddr("freshUpgrader");
    /// MultiSigWallet: the only proposer, executor and canceller of the timelock
    address internal s_timelockOperator;

    // =========================================================================
    //  Constants
    // =========================================================================

    uint256 internal constant PROXY_COUNT = 3;
    uint256 internal constant SWAP_MANAGER_ID = 0;
    uint256 internal constant PRICE_FEED_MANAGER_ID = 1;
    uint256 internal constant ROUTER_ID = 2;

    /// Value returned by version() on every V2 mock
    uint256 internal constant V2_VERSION = 2;
    /// Marker written by initializeV2 when passed as upgrade calldata
    uint256 internal constant V2_MARKER = 42;

    /// ERC-7201 namespace id declared by UpgraderAuth
    string internal constant UPGRADER_AUTH_NAMESPACE =
        "onchainassetmanager.storage.UpgraderAuth";
    /// ERC-7201 slot hardcoded in UpgraderAuth (UPGRADER_AUTH_STORAGE_LOCATION is private)
    bytes32 internal constant UPGRADER_AUTH_STORAGE_LOCATION =
        0x05011ce772e66a30662b8c3c51042b29edbc4be89267b5cce22eaefae38d4700;

    /// Salt used by the timelock operations of the tests
    bytes32 internal constant UPGRADE_SALT = keccak256("UPGRADE_SALT");
    /// Extra time waited past the ready timestamp to prove there is no execution window
    uint256 internal constant LONG_WAIT = 365 days;

    // =========================================================================
    //  Values derived from the contracts
    // =========================================================================

    uint256 internal s_minDelay;
    uint256 internal s_belowMinDelay;
    bytes32 internal s_proposerRole;
    bytes32 internal s_executorRole;
    bytes32 internal s_cancellerRole;
    bytes32 internal s_timelockAdminRole;
    bytes32 internal s_unsetStateBitmap;
    bytes32 internal s_readyStateBitmap;
    bytes32 internal s_pendingStateBitmap;
    bytes internal s_initializeV2Data;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public virtual override {
        super.setUp();

        s_proxies[SWAP_MANAGER_ID] = address(swapManager);
        s_proxies[PRICE_FEED_MANAGER_ID] = address(priceFeedManager);
        s_proxies[ROUTER_ID] = address(router);

        s_newImplementations[SWAP_MANAGER_ID] = address(new SwapManagerV2Mock());
        s_newImplementations[PRICE_FEED_MANAGER_ID] = address(
            new PriceFeedManagerV2Mock()
        );
        s_newImplementations[ROUTER_ID] = address(new RouterV2Mock());

        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            s_initialImplementations[i] = _implementationOf(s_proxies[i]);
        }

        s_wrongUuidImplementation = new ProxiableWrongUuidMock();
        s_timelockOperator = address(multiSigWallet);

        s_minDelay = timelock.getMinDelay();
        s_belowMinDelay = s_minDelay - 1;
        s_proposerRole = timelock.PROPOSER_ROLE();
        s_executorRole = timelock.EXECUTOR_ROLE();
        s_cancellerRole = timelock.CANCELLER_ROLE();
        s_timelockAdminRole = timelock.DEFAULT_ADMIN_ROLE();
        s_unsetStateBitmap = _stateBitmap(TimelockController.OperationState.Unset);
        s_readyStateBitmap = _stateBitmap(TimelockController.OperationState.Ready);
        s_pendingStateBitmap =
            _stateBitmap(TimelockController.OperationState.Waiting) |
            s_readyStateBitmap;
        s_initializeV2Data = abi.encodeCall(
            IUpgradeV2Mock.initializeV2,
            (V2_MARKER)
        );

        vm.label(address(priceFeedManager), "PriceFeedManager");
        vm.label(s_newImplementations[SWAP_MANAGER_ID], "SwapManagerV2");
        vm.label(s_newImplementations[PRICE_FEED_MANAGER_ID], "PriceFeedManagerV2");
        vm.label(s_newImplementations[ROUTER_ID], "RouterV2");
    }

    // =========================================================================
    //  Helpers — timelock operations
    // =========================================================================

    /// @dev Same encoding as TimelockController._encodeStateBitmap (internal in OZ).
    function _stateBitmap(
        TimelockController.OperationState _state
    ) internal pure returns (bytes32) {
        return bytes32(uint256(1) << uint8(_state));
    }

    function _upgradePayload(
        address _newImplementation,
        bytes memory _data
    ) internal pure returns (bytes memory) {
        return
            abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall,
                (_newImplementation, _data)
            );
    }

    function _operationId(
        address _target,
        bytes memory _payload
    ) internal view returns (bytes32) {
        return
            timelock.hashOperation(_target, 0, _payload, bytes32(0), UPGRADE_SALT);
    }

    /// @dev Schedules `_payload` on `_target` as the proposer with the minimum delay; returns the operation id.
    function _schedule(
        address _target,
        bytes memory _payload
    ) internal returns (bytes32 id) {
        vm.prank(s_timelockOperator);
        timelock.schedule(_target, 0, _payload, bytes32(0), UPGRADE_SALT, s_minDelay);
        id = _operationId(_target, _payload);
    }

    function _execute(address _target, bytes memory _payload) internal {
        vm.prank(s_timelockOperator);
        timelock.execute(_target, 0, _payload, bytes32(0), UPGRADE_SALT);
    }

    /// @dev Schedules the upgrade of proxy `_id` to `_newImplementation` and warps to its ready timestamp.
    function _scheduleUpgradeAndWait(
        uint256 _id,
        address _newImplementation,
        bytes memory _data
    ) internal returns (bytes memory payload) {
        payload = _upgradePayload(_newImplementation, _data);
        _schedule(s_proxies[_id], payload);
        vm.warp(block.timestamp + s_minDelay);
    }

    /// @dev Full upgrade of proxy `_id` to its V2 implementation with `_data`.
    function _upgradeToV2(uint256 _id, bytes memory _data) internal {
        bytes memory payload = _scheduleUpgradeAndWait(
            _id,
            s_newImplementations[_id],
            _data
        );
        _execute(s_proxies[_id], payload);
    }

    /// @dev Builds the batch upgrading the three proxies to their V2 implementations (no calldata).
    function _batchUpgradeAll()
        internal
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        )
    {
        targets = new address[](PROXY_COUNT);
        values = new uint256[](PROXY_COUNT);
        payloads = new bytes[](PROXY_COUNT);
        for (uint256 i = 0; i < PROXY_COUNT; i++) {
            targets[i] = s_proxies[i];
            payloads[i] = _upgradePayload(s_newImplementations[i], "");
        }
    }

    // =========================================================================
    //  Helpers — proxies
    // =========================================================================

    function _implementationOf(address _proxy) internal view returns (address) {
        return
            address(
                uint160(uint256(vm.load(_proxy, ERC1967Utils.IMPLEMENTATION_SLOT)))
            );
    }

    function _storedUpgrader(address _target) internal view returns (address) {
        return
            address(
                uint160(uint256(vm.load(_target, UPGRADER_AUTH_STORAGE_LOCATION)))
            );
    }

    /// @dev Hash of the state each proxy must keep across an upgrade.
    function _proxyStateHash(uint256 _id) internal view returns (bytes32) {
        if (_id == SWAP_MANAGER_ID) {
            return
                keccak256(
                    abi.encode(
                        swapManager.owner(),
                        swapManager.getRoute(address(initializedIndex), SwapType.ASSET0_USDC),
                        swapManager.getRoute(address(initializedIndex), SwapType.ASSET1_USDC),
                        swapManager.getRoute(address(initializedIndex), SwapType.ASSET0_ASSET1)
                    )
                );
        }
        if (_id == PRICE_FEED_MANAGER_ID) {
            FeedConfig memory config0 = priceFeedManager.getPriceFeedConfig(initializedToken0);
            FeedConfig memory config1 = priceFeedManager.getPriceFeedConfig(initializedToken1);
            FeedConfig memory configUsdc = priceFeedManager.getPriceFeedConfig(address(mockUsdc));
            return
                keccak256(
                    abi.encode(priceFeedManager.owner(), config0, config1, configUsdc)
                );
        }
        return keccak256(abi.encode(router.getIndexManager(), router.getUsdc()));
    }

    /// @dev Fresh implementation of the same kind as proxy `_id` (initializers disabled).
    function _freshImplementation(uint256 _id) internal returns (address) {
        if (_id == SWAP_MANAGER_ID) return address(new SwapManager());
        if (_id == PRICE_FEED_MANAGER_ID) return address(new PriceFeedManager());
        return address(new Router());
    }

    /// @dev Initializer calldata of proxy kind `_id` with `_upgrader`.
    function _initializeCalldata(
        uint256 _id,
        address _upgrader
    ) internal view returns (bytes memory) {
        if (_id == SWAP_MANAGER_ID) {
            return
                abi.encodeCall(
                    SwapManager.initialize,
                    (address(indexManager), _upgrader)
                );
        }
        if (_id == PRICE_FEED_MANAGER_ID) {
            return
                abi.encodeCall(
                    PriceFeedManager.initialize,
                    (address(indexManager), _upgrader)
                );
        }
        return
            abi.encodeCall(
                Router.initialize,
                (address(indexManager), address(mockUsdc), _upgrader)
            );
    }

    // =========================================================================
    //  Helpers — logs
    // =========================================================================

    /// @dev Returns how many logs from `_emitter` match `_sig` and the position of the first one.
    function _findLogs(
        Vm.Log[] memory _logs,
        address _emitter,
        bytes32 _sig
    ) internal pure returns (uint256 count, uint256 firstIndex) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (_logs[i].emitter != _emitter || _logs[i].topics[0] != _sig)
                continue;
            if (count == 0) firstIndex = i;
            count++;
        }
    }

    function _topicToAddress(bytes32 _topic) internal pure returns (address) {
        return address(uint160(uint256(_topic)));
    }
}
