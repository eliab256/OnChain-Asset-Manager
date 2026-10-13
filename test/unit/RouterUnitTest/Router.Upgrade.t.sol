// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Router} from "../../../src/Router.sol";
import {Index} from "../../../src/Index.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {AssetAvailable, IndexAsset} from "../../../src/types.sol";
import {RunParams} from "../../../script/DeployAndInitNewIndex.s.sol";
import {RouterV2Mock} from "../../mocks/RouterV2Mock.sol";
import {ReentrantIndexMock} from "../../mocks/ReentrantIndexMock.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Router__ZeroAddress} from "../../../src/errors/RouterErrors.sol";
import {
    UpgraderAuth__Unauthorized,
    UpgraderAuth__ZeroAddress
} from "../../../src/errors/UpgraderAuthErrors.sol";

/**
 * @dev Router as a UUPS proxy deployed by the IndexManager and upgraded only by the TimelockController:
 *      - proxy wiring, ERC-7201 storage and initializer guards;
 *      - upgrades scheduled and executed through the timelock (state kept, upgrade data run on the proxy);
 *      - indexes created before an upgrade keep working through the same proxy, with no role migration;
 *      - nonReentrant still protects buy / sell behind the proxy.
 *      Timelock mechanics shared by the three proxies live in ProxyUpgradeViaTimelock.t.sol.
 */
contract RouterUpgradeTest is BaseTest {
    // =========================================================================
    //  Contracts and addresses
    // =========================================================================

    RouterV2Mock internal s_newImplementation;
    ReentrantIndexMock internal s_reentrantIndex;
    Index internal s_secondIndex;
    address internal s_freshIndexManager = makeAddr("freshIndexManager");
    address internal s_freshUsdc = makeAddr("freshUsdc");
    address internal s_freshUpgrader = makeAddr("freshUpgrader");

    // =========================================================================
    //  Constants
    // =========================================================================

    /// ERC-7201 slot of the Router namespace (onchainassetmanager.storage.Router), not exposed by the Router
    bytes32 constant ROUTER_STORAGE_LOCATION =
        0x1951d9b676cbf01f1a8948ead5c25acf648eb31d2c1dddaf6ed23e4243124c00;

    /// ERC-7201 slot of the OZ 5.x ReentrancyGuard status (openzeppelin.storage.ReentrancyGuard), private in OZ
    bytes32 constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    /// ReentrancyGuard NOT_ENTERED value (private in OZ)
    uint256 constant REENTRANCY_NOT_ENTERED = 1;

    /// Expected V2 version returned by RouterV2Mock
    uint256 constant V2_VERSION = 2;

    /// Marker written by RouterV2Mock.initializeV2 when passed as upgrade data
    uint256 constant V2_MARKER = 42;

    /// USDC spent on every buy through the router (6 decimals)
    uint256 constant MINT_USDC_AMOUNT = 1_000e6;

    // =========================================================================
    //  Values derived from the contracts
    // =========================================================================

    address internal s_initialImplementation;
    bytes internal s_initializeV2Data;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();

        s_newImplementation = new RouterV2Mock();
        s_reentrantIndex = new ReentrantIndexMock(address(router));

        s_initialImplementation = router.getImplementation();
        s_initializeV2Data = abi.encodeCall(
            RouterV2Mock.initializeV2,
            (V2_MARKER)
        );

        // Second initialized index (asset0 of initializedIndex / COMP), created before any router upgrade.
        bool asset0IsWeth = initializedToken0 == address(mockWeth);
        s_secondIndex = deployAndInitNewIndex.run(
            helperConfig,
            address(indexManager),
            address(multiSigWallet),
            RunParams({
                assetA: asset0IsWeth
                    ? AssetAvailable.WETH
                    : AssetAvailable.WBTC,
                assetB: AssetAvailable.COMP,
                weightA: weight50,
                weightB: weight50,
                feePercentage: validFeePercentage,
                initialAssetADeposit: asset0IsWeth
                    ? 10 * 10 ** mockWeth.decimals()
                    : 1 * 10 ** mockWbtc.decimals(),
                initialAssetBDeposit: 0
            })
        );

        vm.label(address(s_secondIndex), "SecondIndex");
        vm.label(address(s_reentrantIndex), "ReentrantIndex");
        vm.label(address(s_newImplementation), "RouterV2Implementation");
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev Upgrades the router proxy to `_implementation` through the timelock (with `_data`)
    ///      and refreshes the feeds, which went stale while waiting the timelock delay.
    function _upgradeRouterTo(
        address _implementation,
        bytes memory _data
    ) internal {
        _scheduleAndExecuteUpgrade(address(router), _implementation, _data);
        _refreshPriceFeeds();
    }

    /// @dev Reads the ERC-1967 implementation slot of the router proxy.
    function _implementationSlotValue() internal view returns (address) {
        return
            address(
                uint160(
                    uint256(
                        vm.load(address(router), ERC1967Utils.IMPLEMENTATION_SLOT)
                    )
                )
            );
    }

    /// @dev Reads the address stored at `ROUTER_STORAGE_LOCATION + _offset` on `_target`.
    function _routerStorageAddress(
        address _target,
        uint256 _offset
    ) internal view returns (address) {
        return
            address(
                uint160(
                    uint256(
                        vm.load(
                            _target,
                            bytes32(uint256(ROUTER_STORAGE_LOCATION) + _offset)
                        )
                    )
                )
            );
    }

    /// @dev Deploys a Router proxy initialized with the given addresses.
    function _deployRouterProxy(
        address _indexManager,
        address _usdc,
        address _upgrader
    ) internal returns (Router) {
        return
            Router(
                address(
                    new ERC1967Proxy(
                        address(new Router()),
                        abi.encodeCall(
                            Router.initialize,
                            (_indexManager, _usdc, _upgrader)
                        )
                    )
                )
            );
    }

    /// @dev Makes the IndexManager report the reentrant mock as an initialized index and funds it with USDC.
    function _wireReentrantIndex() internal {
        vm.mockCall(
            address(indexManager),
            abi.encodeCall(
                IndexManager.checkIsIndexInitialized,
                (address(s_reentrantIndex))
            ),
            abi.encode(true)
        );
        mockUsdc.mint(address(s_reentrantIndex), MINT_USDC_AMOUNT);
    }

    /// @dev Buys MINT_USDC_AMOUNT of `_index` shares for `_user` through the router; returns the shares bought.
    function _buyViaRouter(
        Index _index,
        address _user
    ) internal returns (uint256 sharesBought) {
        uint256 sharesBefore = _index.balanceOf(_user);
        vm.startPrank(_user);
        mockUsdc.approve(address(_index), MINT_USDC_AMOUNT);
        router.buyExactUsdcAmountOfShares(
            address(_index),
            MINT_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        vm.stopPrank();
        sharesBought = _index.balanceOf(_user) - sharesBefore;
    }

    /// @dev True if the router proxy read its ERC-1967 implementation slot in the recorded accesses.
    function _routerDelegatedToImplementationSlot()
        internal
        view
        returns (bool)
    {
        (bytes32[] memory reads, ) = vm.accesses(address(router));
        for (uint256 i = 0; i < reads.length; i++) {
            if (reads[i] == ERC1967Utils.IMPLEMENTATION_SLOT) return true;
        }
        return false;
    }

    /// @dev Mints then redeems shares of `_index` for `_user` through the router proxy,
    ///      asserting each leg went through the proxy and moved the balances.
    function _assertMintAndRedeemThroughProxy(
        Index _index,
        address _user
    ) internal {
        uint256 sharesBefore = _index.balanceOf(_user);
        uint256 usdcBeforeBuy = mockUsdc.balanceOf(_user);

        vm.record();
        uint256 sharesBought = _buyViaRouter(_index, _user);
        assertTrue(
            _routerDelegatedToImplementationSlot(),
            "buy must delegate through the router proxy"
        );
        assertGt(sharesBought, 0, "mint must work after the upgrade");
        assertEq(
            mockUsdc.balanceOf(_user),
            usdcBeforeBuy - MINT_USDC_AMOUNT,
            "buy must pull the exact USDC amount"
        );

        uint256 usdcBeforeSell = mockUsdc.balanceOf(_user);
        vm.record();
        vm.prank(_user);
        router.sellExactAmountOfSharesForUsdc(
            address(_index),
            sharesBought,
            VALID_TOLERANCE
        );
        assertTrue(
            _routerDelegatedToImplementationSlot(),
            "sell must delegate through the router proxy"
        );
        assertEq(
            _index.balanceOf(_user),
            sharesBefore,
            "redeem must burn the sold shares"
        );
        assertGt(
            mockUsdc.balanceOf(_user),
            usdcBeforeSell,
            "redeem must pay USDC after the upgrade"
        );
    }

    // =========================================================================
    //  Proxy wiring and storage
    // =========================================================================

    function testRouterProxyMatchesIndexManagerGetter() public view {
        assertEq(
            address(router),
            indexManager.getRouterAddress(),
            "deploy script must return the IndexManager router proxy"
        );
        assertTrue(
            address(router) != s_initialImplementation,
            "router must be a proxy, not the implementation"
        );
        assertEq(
            _implementationSlotValue(),
            s_initialImplementation,
            "getImplementation must match the ERC-1967 slot"
        );
    }

    function testRouterProxyUpgraderIsTimelock() public view {
        assertEq(
            router.getUpgrader(),
            address(timelock),
            "the timelock must be the only router upgrader"
        );
        assertEq(router.getIndexManager(), address(indexManager));
    }

    function testRouterStorageNamespaceHoldsIndexManagerAndUsdc() public view {
        assertEq(
            _routerStorageAddress(address(router), 0),
            address(indexManager),
            "ERC-7201 slot 0 must hold the IndexManager"
        );
        assertEq(
            _routerStorageAddress(address(router), 1),
            address(mockUsdc),
            "ERC-7201 slot 1 must hold USDC"
        );
        assertEq(router.getIndexManager(), address(indexManager));
        assertEq(router.getUsdc(), address(mockUsdc));
    }

    function testRouterProxyUsesNoSequentialStorageSlots() public view {
        assertEq(vm.load(address(router), bytes32(uint256(0))), bytes32(0));
        assertEq(vm.load(address(router), bytes32(uint256(1))), bytes32(0));
    }

    function testRouterImplementationStorageIsEmpty() public view {
        assertEq(
            _routerStorageAddress(s_initialImplementation, 0),
            address(0),
            "implementation must not store the IndexManager"
        );
        assertEq(
            _routerStorageAddress(s_initialImplementation, 1),
            address(0),
            "implementation must not store USDC"
        );
        assertEq(
            Router(s_initialImplementation).getUpgrader(),
            address(0),
            "implementation must not store an upgrader"
        );
    }

    function testAllIndexesUseTheProxyAsRouter() public view {
        assertEq(initializedIndex.getRouter(), address(router));
        assertEq(nonInitializedIndex.getRouter(), address(router));
        assertEq(s_secondIndex.getRouter(), address(router));
        assertNotEq(
            initializedIndex.getRouter(),
            s_initialImplementation,
            "the bare implementation must not be the index router"
        );
    }

    // =========================================================================
    //  initialize
    // =========================================================================

    function testRouterProxyCannotBeReinitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        router.initialize(user1, user1, user1);
    }

    function testRouterImplementationCannotBeInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        Router(s_initialImplementation).initialize(
            user1,
            address(mockUsdc),
            address(timelock)
        );
    }

    function testInitializeSetsUpgraderAndStorageOnFreshProxy() public {
        Router freshRouter = _deployRouterProxy(
            s_freshIndexManager,
            s_freshUsdc,
            s_freshUpgrader
        );

        assertEq(freshRouter.getUpgrader(), s_freshUpgrader);
        assertEq(freshRouter.getIndexManager(), s_freshIndexManager);
        assertEq(freshRouter.getUsdc(), s_freshUsdc);
        assertEq(
            _routerStorageAddress(address(freshRouter), 0),
            s_freshIndexManager
        );
        assertEq(_routerStorageAddress(address(freshRouter), 1), s_freshUsdc);
    }

    function testInitializeRevertsIfIndexManagerIsZero() public {
        Router implementation = new Router();
        vm.expectRevert(Router__ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                Router.initialize,
                (address(0), s_freshUsdc, s_freshUpgrader)
            )
        );
    }

    function testInitializeRevertsIfUsdcIsZero() public {
        Router implementation = new Router();
        vm.expectRevert(Router__ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                Router.initialize,
                (s_freshIndexManager, address(0), s_freshUpgrader)
            )
        );
    }

    function testInitializeRevertsIfUpgraderIsZero() public {
        Router implementation = new Router();
        vm.expectRevert(UpgraderAuth__ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                Router.initialize,
                (s_freshIndexManager, s_freshUsdc, address(0))
            )
        );
    }

    /// @dev The Router zero checks on IndexManager / USDC run before the upgrader check.
    function testInitializeChecksIndexManagerBeforeUpgrader() public {
        Router implementation = new Router();
        vm.expectRevert(Router__ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                Router.initialize,
                (address(0), s_freshUsdc, address(0))
            )
        );
    }

    // =========================================================================
    //  Upgrade through the timelock
    // =========================================================================

    function testUpgradeViaTimelockKeepsAddressUpgraderAndStorage() public {
        address proxyBefore = indexManager.getRouterAddress();
        assertEq(router.getImplementation(), s_initialImplementation);

        _upgradeRouterTo(address(s_newImplementation), "");

        RouterV2Mock upgraded = RouterV2Mock(address(router));
        assertEq(
            indexManager.getRouterAddress(),
            proxyBefore,
            "router proxy address must not change"
        );
        assertEq(
            upgraded.getImplementation(),
            address(s_newImplementation),
            "getImplementation must return the new implementation"
        );
        assertEq(_implementationSlotValue(), address(s_newImplementation));
        assertEq(upgraded.version(), V2_VERSION, "V2 logic must be live");
        assertEq(upgraded.getUpgrader(), address(timelock), "upgrader must not change");
        assertEq(upgraded.getIndexManager(), address(indexManager));
        assertEq(upgraded.getUsdc(), address(mockUsdc));
        assertEq(
            _routerStorageAddress(address(router), 0),
            address(indexManager),
            "ERC-7201 IndexManager slot must survive the upgrade"
        );
        assertEq(
            _routerStorageAddress(address(router), 1),
            address(mockUsdc),
            "ERC-7201 USDC slot must survive the upgrade"
        );
    }

    function testUpgradeViaTimelockRunsDataOnTheProxy() public {
        _upgradeRouterTo(address(s_newImplementation), s_initializeV2Data);

        RouterV2Mock upgraded = RouterV2Mock(address(router));
        assertEq(upgraded.getV2Marker(), V2_MARKER, "upgrade data must run on the proxy");
        assertEq(upgraded.getIndexManager(), address(indexManager));
        assertEq(upgraded.getUsdc(), address(mockUsdc));
        assertEq(
            s_newImplementation.getV2Marker(),
            0,
            "upgrade data must not touch the implementation"
        );
    }

    function testRouterV2ReinitializerCannotRunTwice() public {
        _upgradeRouterTo(address(s_newImplementation), s_initializeV2Data);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        RouterV2Mock(address(router)).initializeV2(V2_MARKER + 1);
    }

    function testUpgradeViaTimelockRevertsIfDataCallReverts() public {
        // Re-running initialize on an already initialized proxy must revert,
        // rolling back the whole upgrade; the timelock bubbles the original error.
        bytes memory payload = abi.encodeCall(
            UUPSUpgradeable.upgradeToAndCall,
            (
                address(s_newImplementation),
                abi.encodeCall(
                    Router.initialize,
                    (user1, address(mockUsdc), user1)
                )
            )
        );
        uint256 delay = timelock.getMinDelay();
        vm.prank(address(multiSigWallet));
        timelock.schedule(address(router), 0, payload, bytes32(0), bytes32(0), delay);
        vm.warp(block.timestamp + delay);

        vm.prank(address(multiSigWallet));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        timelock.execute(address(router), 0, payload, bytes32(0), bytes32(0));
    }

    // =========================================================================
    //  Direct upgrade bypassing the timelock
    // =========================================================================

    function testDirectUpgradeToAndCallByAdminEoaReverts() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(UpgraderAuth__Unauthorized.selector, deployer)
        );
        router.upgradeToAndCall(address(s_newImplementation), "");
    }

    function testDirectUpgradeToAndCallByMultiSigReverts() public {
        vm.prank(address(multiSigWallet));
        vm.expectRevert(
            abi.encodeWithSelector(
                UpgraderAuth__Unauthorized.selector,
                address(multiSigWallet)
            )
        );
        router.upgradeToAndCall(address(s_newImplementation), "");
    }

    function testDirectUpgradeToAndCallOnImplementationReverts() public {
        // UUPS onlyProxy guard: the bare implementation cannot be upgraded directly
        vm.prank(address(indexManager));
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        Router(s_initialImplementation).upgradeToAndCall(
            address(s_newImplementation),
            ""
        );
    }

    function testDirectUpgradeToAndCallByIndexManagerReverts() public {
        vm.prank(address(indexManager));
        vm.expectRevert(
            abi.encodeWithSelector(
                UpgraderAuth__Unauthorized.selector,
                address(indexManager)
            )
        );
        router.upgradeToAndCall(address(s_newImplementation), "");
    }

    // =========================================================================
    //  Indexes created before the upgrade keep working on the same proxy
    // =========================================================================

    function testIndexesCreatedBeforeUpgradeMintAndRedeemWithNewLogic()
        public
    {
        // Both indexes exist and point to the proxy before the upgrade.
        assertEq(initializedIndex.getRouter(), address(router));
        assertEq(s_secondIndex.getRouter(), address(router));
        assertEq(router.getImplementation(), s_initialImplementation);

        _upgradeRouterTo(address(s_newImplementation), "");

        // New logic is live on the same proxy address.
        assertEq(indexManager.getRouterAddress(), address(router));
        assertEq(RouterV2Mock(address(router)).version(), V2_VERSION);
        assertEq(_implementationSlotValue(), address(s_newImplementation));

        // No migration: the indexes still point to the proxy, not to the new implementation.
        assertEq(initializedIndex.getRouter(), address(router));
        assertEq(s_secondIndex.getRouter(), address(router));
        assertNotEq(
            initializedIndex.getRouter(),
            address(s_newImplementation)
        );
        assertNotEq(s_secondIndex.getRouter(), address(s_newImplementation));

        _assertMintAndRedeemThroughProxy(initializedIndex, user1);
        _assertMintAndRedeemThroughProxy(s_secondIndex, user2);
    }

    function testIndexCreatedAfterUpgradeUsesSameProxyAsRouter() public {
        _upgradeRouterTo(address(s_newImplementation), "");

        vm.prank(deployer);
        (address newIndexAddress, , ) = indexManager.createIndex(
            validFeePercentage,
            IndexAsset({asset: address(mockLink), weightPercentage: weight50}),
            IndexAsset({asset: address(mockComp), weightPercentage: weight50})
        );

        Index newIndex = Index(newIndexAddress);
        assertEq(newIndex.getRouter(), address(router));
        assertNotEq(newIndex.getRouter(), address(s_newImplementation));
    }

    function testRouterPreviewsWorkAfterUpgrade() public {
        uint256 minSharesBefore = router.getMinMintPreview(
            address(initializedIndex),
            MINT_USDC_AMOUNT,
            VALID_TOLERANCE
        );

        // _upgradeRouterTo refreshes the feeds at the same answers, so the preview is comparable.
        _upgradeRouterTo(address(s_newImplementation), "");

        uint256 minSharesAfter = router.getMinMintPreview(
            address(initializedIndex),
            MINT_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        assertEq(minSharesAfter, minSharesBefore, "preview must not change with the upgrade");
    }

    // =========================================================================
    //  nonReentrant behind the proxy
    // =========================================================================

    function testReentrancyGuardStatusIsStoredOnTheProxy() public {
        _buyViaRouter(initializedIndex, user1);

        assertEq(
            uint256(vm.load(address(router), REENTRANCY_GUARD_STORAGE)),
            REENTRANCY_NOT_ENTERED,
            "proxy guard must be back to NOT_ENTERED after a buy"
        );
        assertEq(
            uint256(vm.load(s_initialImplementation, REENTRANCY_GUARD_STORAGE)),
            REENTRANCY_NOT_ENTERED,
            "implementation guard is set by its own constructor and never used"
        );
    }

    function testBuyReentrancyThroughProxyReverts() public {
        _wireReentrantIndex();

        vm.prank(user1);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        router.buyExactUsdcAmountOfShares(
            address(s_reentrantIndex),
            MINT_USDC_AMOUNT,
            VALID_TOLERANCE
        );
    }

    function testSellReentrancyThroughProxyReverts() public {
        _wireReentrantIndex();

        vm.prank(user1);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        router.sellExactAmountOfSharesForUsdc(
            address(s_reentrantIndex),
            MINT_USDC_AMOUNT,
            VALID_TOLERANCE
        );
    }

    function testBuyReentrancyRevertsAfterUpgrade() public {
        _upgradeRouterTo(address(s_newImplementation), "");
        _wireReentrantIndex();

        vm.prank(user1);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        router.buyExactUsdcAmountOfShares(
            address(s_reentrantIndex),
            MINT_USDC_AMOUNT,
            VALID_TOLERANCE
        );
    }
}
