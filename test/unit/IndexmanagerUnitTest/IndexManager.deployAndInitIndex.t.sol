// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {PriceFeedManager} from "../../../src/PriceFeedManager.sol";
import {Router} from "../../../src/Router.sol";
import {Index} from "../../../src/Index.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute, IndexAction} from "../../../src/types.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

import "../../../src/errors/IndexManagerErrors.sol";
import "../../../src/events/IndexManagerEvents.sol";
import "../../../src/errors/IndexErrors.sol";

contract IndexManagerTest is BaseTest {
    // Fixed addresses below / above every deployed token, so the sorted position
    // (asset0 or asset1) of an unregistered asset is deterministic.
    address internal constant LOW_UNREGISTERED_ASSET = address(0x1000);
    address internal constant HIGH_UNREGISTERED_ASSET =
        address(type(uint160).max - 0x1000);

    IndexAsset wethAsset60;
    IndexAsset linkAsset40;

    function setUp() public override {
        super.setUp();

        wethAsset60 = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: weight60
        });

        linkAsset40 = IndexAsset({
            asset: address(mockLink),
            weightPercentage: weight40
        });
    }

    /// @dev Deploys an ERC20 mock with no price feed registered at a fixed address.
    function _deployUnregisteredAssetAt(
        address _target
    ) internal returns (address) {
        deployCodeTo(
            "AssetTokenMock.sol:AssetTokenMock",
            abi.encode("Unregistered", "UNREG", uint8(18)),
            _target
        );
        return _target;
    }

    /// @dev Deploys a fresh IndexManager (deployer as admin) whose PriceFeedManager has no USDC feed.
    function _deployIndexManagerWithoutUsdcFeed()
        internal
        returns (IndexManager freshIndexManager)
    {
        SwapManager swapManagerImplementation = new SwapManager();
        PriceFeedManager priceFeedManagerImplementation = new PriceFeedManager();
        Router routerImplementation = new Router();
        vm.prank(deployer);
        freshIndexManager = new IndexManager(
            address(mockUsdc),
            address(mockUniRouter),
            address(swapManagerImplementation),
            address(priceFeedManagerImplementation),
            address(routerImplementation),
            address(timelock)
        );
    }

    function _createDefaultIndex(
        address _assetA,
        address _assetB
    ) internal returns (address indexAddress, address token0, address token1) {
        IndexAsset memory assetA = IndexAsset({
            asset: _assetA,
            weightPercentage: weight60
        });
        IndexAsset memory assetB = IndexAsset({
            asset: _assetB,
            weightPercentage: weight40
        });

        vm.prank(deployer);
        (indexAddress, token0, token1) = indexManager.createIndex(
            validFeePercentage,
            assetA,
            assetB
        );
    }

    // =========================================================================
    //  createIndex
    // =========================================================================

    function testCreateIndexRegistersIndexInIsIndexMappingsAndArrays() public view{
        assertTrue(indexManager.isIndexAddress(address(nonInitializedIndex)));
        assertFalse(
            indexManager.checkIsIndexInitialized(address(nonInitializedIndex))
        );
        address[] memory allIndexes = indexManager.getDeployedIndexes();
        assertEq(allIndexes[1], address(nonInitializedIndex));
        assertEq(
            indexManager.getIndexByAssetsAddresses(
                nonInitializedToken0,
                nonInitializedToken1
            ),
            address(nonInitializedIndex)
        );
        address[] memory initializedIndexes = indexManager
            .getInitializedIndexes();
        // Only indexWethWbtc from Base.setUp() is initialized; nonInitializedIndex is not.
        assertEq(initializedIndexes.length, 1);
        (address asset0, address asset1) = indexManager.getIndexAssets(
            address(nonInitializedIndex)
        );
        assertEq(asset0, nonInitializedToken0);
        assertEq(asset1, nonInitializedToken1);
    }

    function testCreateIndexIndexNotMarkedInitializedAfterCreate() public {
        (address indexAddress, , ) = _createDefaultIndex(
            address(mockWeth),
            address(mockLink)
        );

        assertTrue(indexManager.isIndexAddress(indexAddress));
        assertFalse(indexManager.checkIsIndexInitialized(indexAddress));
    }

    function testCreateIndexIndexLookupIsOrderIndependent() public {
        (address indexAddress, , ) = _createDefaultIndex(
            address(mockWeth),
            address(mockLink)
        );

        address lookupAB = indexManager.getIndexByAssetsAddresses(
            address(mockWeth),
            address(mockLink)
        );
        address lookupBA = indexManager.getIndexByAssetsAddresses(
            address(mockLink),
            address(mockWeth)
        );

        assertEq(lookupAB, indexAddress);
        assertEq(lookupBA, indexAddress);
    }

    function testCreateIndexToken0IsLessThanToken1() public {
        (, address token0, address token1) = _createDefaultIndex(
            address(mockWeth),
            address(mockLink)
        );

        assertTrue(token0 < token1, "token0 must be < token1 after sorting");
    }

    function testCreateIndexEmitsIndexCreatedEvent() public {
        // sortAssets is internal in the IndexManager: sort locally (asset0 = lower address).
        (address sortedToken0, address sortedToken1) = address(mockWeth) <
            address(mockLink)
            ? (address(mockWeth), address(mockLink))
            : (address(mockLink), address(mockWeth));

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.createIndex(validFeePercentage, wethAsset60, linkAsset40);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        // The Index constructor emits no events (no AccessControl RoleGranted):
        // IndexCreated is the only log of createIndex.
        assertEq(entries.length, 1);
        Vm.Log memory fullEvent = entries[0];
        bytes32 eventSignature = fullEvent.topics[0]; //event signature hashed
        address testIndex;
        address testToken0;
        address testToken1;
        address testCaller;
        {
            bytes32 topic1 = fullEvent.topics[1]; //is indexed
            bytes32 topic2 = fullEvent.topics[2]; //is indexed
            bytes32 topic3 = fullEvent.topics[3]; //is indexed

            testIndex = address(uint160(uint256(topic1)));
            testToken0 = address(uint160(uint256(topic2)));
            testToken1 = address(uint160(uint256(topic3)));
        }
        {
            (
                uint128 testWeight0,
                uint128 testWeight1,
                uint32 testFee,
                address caller
            ) = abi.decode(
                    fullEvent.data,
                    (uint128, uint128, uint32, address)
                );
            testCaller = caller;
            uint128 expectedWeight0 = sortedToken0 == address(mockWeth)
                ? wethAsset60.weightPercentage
                : linkAsset40.weightPercentage;
            assertEq(testWeight0, expectedWeight0, "asset0 weight mismatch");
            assertEq(
                testWeight1,
                MAX_WEIGHT - expectedWeight0,
                "asset1 weight mismatch"
            );
            assertEq(testFee, validFeePercentage, "fee percentage mismatch");
        }

        assertEq(fullEvent.emitter, address(indexManager));
        assertEq(
            eventSignature,
            keccak256(
                "IndexCreated(address,address,address,uint128,uint128,uint32,address)"
            )
        );
        assertEq(
            testIndex,
            indexManager.getIndexByAssetsAddresses(sortedToken0, sortedToken1)
        );
        assertEq(testToken0, sortedToken0);
        assertEq(testToken1, sortedToken1);
        assertEq(testCaller, deployer);
    }

    function testCreateIndexRevertIfSameAssets() public {
        IndexAsset memory sameAsset = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: weight50
        });

        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidIndexAssetsAddress.selector);
        indexManager.createIndex(validFeePercentage, sameAsset, sameAsset);
    }

    function testCreateIndexRevertIfFeePercentageIsNotValid() public {
        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidFeePercentage.selector);
        indexManager.createIndex(
            invalidFeePercentage,
            wethAsset60,
            linkAsset40
        );
    }

    function testCreateIndexRevertIfWeightsDoNotSumToMaxPercentage() public {
        uint128 weight00 = (0 * WEIGHT_PRECISION); // 0%
        uint128 weight20 = (20 * WEIGHT_PRECISION); // 20%
        uint128 weight100 = (100 * WEIGHT_PRECISION); // 100%
        uint128 weight120 = (120 * WEIGHT_PRECISION); // 120%

        IndexAsset memory wethAssetA = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: weight20
        });
        IndexAsset memory wethAssetB = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: weight100
        });
        IndexAsset memory wethAssetC = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: weight120
        });
        IndexAsset memory linkAssetA = IndexAsset({
            asset: address(mockLink),
            weightPercentage: weight30
        });
        IndexAsset memory linkAssetB = IndexAsset({
            asset: address(mockLink),
            weightPercentage: weight00
        });

        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidIndexAssetsPercentages.selector);
        indexManager.createIndex(validFeePercentage, wethAssetA, linkAssetA);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidIndexAssetsPercentages.selector);
        indexManager.createIndex(validFeePercentage, wethAssetB, linkAssetA);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidIndexAssetsPercentages.selector);
        indexManager.createIndex(validFeePercentage, wethAssetA, linkAssetB);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidIndexAssetsPercentages.selector);
        indexManager.createIndex(validFeePercentage, wethAssetC, linkAssetB);
    }

    function testCreateIndexRevertIfSingleWeightOutOfBounds() public {
        // Weights sum to 100% but one of them is outside (MIN_WEIGHT, MAX_WEIGHT).
        uint128[2] memory invalidWeights0 = [uint128(0), MIN_WEIGHT];

        for (uint256 i = 0; i < invalidWeights0.length; i++) {
            IndexAsset memory wethAsset = IndexAsset({
                asset: address(mockWeth),
                weightPercentage: invalidWeights0[i]
            });
            IndexAsset memory linkAsset = IndexAsset({
                asset: address(mockLink),
                weightPercentage: MAX_WEIGHT - invalidWeights0[i]
            });

            vm.prank(deployer);
            vm.expectRevert(
                IndexManager__InvalidIndexAssetsPercentages.selector
            );
            indexManager.createIndex(validFeePercentage, wethAsset, linkAsset);

            // Same weights with swapped roles: the out-of-bounds weight is on the other asset.
            vm.prank(deployer);
            vm.expectRevert(
                IndexManager__InvalidIndexAssetsPercentages.selector
            );
            indexManager.createIndex(validFeePercentage, linkAsset, wethAsset);
        }
    }

    function testCreateIndexAcceptsWeightsJustInsideBounds() public {
        IndexAsset memory wethAsset = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: MIN_WEIGHT + 1
        });
        IndexAsset memory linkAsset = IndexAsset({
            asset: address(mockLink),
            weightPercentage: MAX_WEIGHT - MIN_WEIGHT - 1
        });

        vm.prank(deployer);
        (address index, , ) = indexManager.createIndex(
            validFeePercentage,
            wethAsset,
            linkAsset
        );
        assertTrue(indexManager.isIndexAddress(index));
    }

    function testCreateIndexRevertIfIndexAlreadyExists() public {
        IndexAsset memory wethAsset = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: weight50
        });
        IndexAsset memory wbtcAsset = IndexAsset({
            asset: address(mockWbtc),
            weightPercentage: weight50
        });

        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__IndexAlreadyExists.selector,
                address(initializedIndex)
            )
        );
        indexManager.createIndex(validFeePercentage, wethAsset, wbtcAsset);
    }

    function testCreateIndexRevertIfAsset0PriceFeedNotRegistered() public {
        address unregisteredAsset = _deployUnregisteredAssetAt(
            LOW_UNREGISTERED_ASSET
        );
        IndexAsset memory unregistered = IndexAsset({
            asset: unregisteredAsset,
            weightPercentage: weight60
        });

        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__PriceFeedNotRegistered.selector,
                unregisteredAsset
            )
        );
        indexManager.createIndex(validFeePercentage, unregistered, linkAsset40);
    }

    function testCreateIndexRevertIfAsset1PriceFeedNotRegistered() public {
        address unregisteredAsset = _deployUnregisteredAssetAt(
            HIGH_UNREGISTERED_ASSET
        );
        IndexAsset memory unregistered = IndexAsset({
            asset: unregisteredAsset,
            weightPercentage: weight40
        });

        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__PriceFeedNotRegistered.selector,
                unregisteredAsset
            )
        );
        indexManager.createIndex(validFeePercentage, wethAsset60, unregistered);
    }

    function testCreateIndexRevertIfUsdcPriceFeedNotRegistered() public {
        IndexManager freshIndexManager = _deployIndexManagerWithoutUsdcFeed();
        PriceFeedManager freshPriceFeedManager = PriceFeedManager(
            freshIndexManager.getPriceFeedManagerAddress()
        );

        // Register both index assets but not USDC, so only the USDC check can fail.
        vm.startPrank(deployer);
        freshPriceFeedManager.registerPriceFeed(
            address(mockWeth),
            address(mockWethPriceFeed),
            assetPriceFeedMaxDelay
        );
        freshPriceFeedManager.registerPriceFeed(
            address(mockLink),
            address(mockLinkPriceFeed),
            assetPriceFeedMaxDelay
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__PriceFeedNotRegistered.selector,
                address(mockUsdc)
            )
        );
        freshIndexManager.createIndex(
            validFeePercentage,
            wethAsset60,
            linkAsset40
        );
        vm.stopPrank();
    }

    function testCreateIndexRevertIfAsset0IsNotErc20() public {
        IndexAsset memory wethAsset = IndexAsset({
            asset: address(mockWbtcPriceFeed), // invalid
            weightPercentage: weight60
        });

        vm.prank(deployer);
        // No feed can be registered for it (PriceFeedManager validates the asset), so the
        // feed check rejects it.
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__PriceFeedNotRegistered.selector,
                address(mockWbtcPriceFeed)
            )
        );
        indexManager.createIndex(validFeePercentage, wethAsset, linkAsset40);
    }

    function testCreateIndexRevertIfAsset0IsAddress0() public {
        IndexAsset memory wethAsset = IndexAsset({
            asset: address(0), // invalid
            weightPercentage: weight60
        });

        vm.prank(deployer);
        // No feed can be registered for it (PriceFeedManager validates the asset), so the
        // feed check rejects it.
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__PriceFeedNotRegistered.selector,
                address(0)
            )
        );
        indexManager.createIndex(validFeePercentage, wethAsset, linkAsset40);
    }

    function testCreateIndexRevertIfAsset1IsNotErc20() public {
        IndexAsset memory linkAsset = IndexAsset({
            asset: address(mockWethPriceFeed), // invalid
            weightPercentage: weight40
        });

        vm.prank(deployer);
        // No feed can be registered for it (PriceFeedManager validates the asset), so the
        // feed check rejects it.
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__PriceFeedNotRegistered.selector,
                address(mockWethPriceFeed)
            )
        );
        indexManager.createIndex(validFeePercentage, wethAsset60, linkAsset);
    }

    function testCreateIndexRevertIfAsset1IsUsdc() public {
        IndexAsset memory linkAsset = IndexAsset({
            asset: address(mockUsdc), // invalid
            weightPercentage: weight40
        });

        vm.prank(deployer);
        vm.expectRevert(IndexManager__UsdcCannotBeIndexAsset.selector);
        indexManager.createIndex(validFeePercentage, wethAsset60, linkAsset);
    }


    function testCreateIndexRevertIfAsset1IsAddress0() public {
        IndexAsset memory linkAsset = IndexAsset({
            asset: address(0), // invalid
            weightPercentage: weight40
        });

        vm.prank(deployer);
        // No feed can be registered for it (PriceFeedManager validates the asset), so the
        // feed check rejects it.
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexManager__PriceFeedNotRegistered.selector,
                address(0)
            )
        );
        indexManager.createIndex(validFeePercentage, wethAsset60, linkAsset);
    }

    function testCreateIndexSetsRouterProxyAsIndexRouter() public {
        address routerProxy = indexManager.getRouterAddress();

        (address indexAddress, , ) = _createDefaultIndex(
            address(mockWeth),
            address(mockLink)
        );

        Index newIndex = Index(indexAddress);
        assertEq(
            newIndex.getRouter(),
            routerProxy,
            "new index router must be the router proxy"
        );
        assertEq(
            initializedIndex.getRouter(),
            routerProxy,
            "initialized index router must be the router proxy"
        );
        assertEq(
            nonInitializedIndex.getRouter(),
            routerProxy,
            "non initialized index router must be the router proxy"
        );
        assertNotEq(
            newIndex.getRouter(),
            Router(routerProxy).getImplementation(),
            "the router implementation must not be the index router"
        );
    }

    function testCreateIndexSetsIndexManagerAsIndexManagerOfIndex() public {
        (address indexAddress, , ) = _createDefaultIndex(
            address(mockWeth),
            address(mockLink)
        );

        assertEq(
            Index(indexAddress).getIndexManager(),
            address(indexManager),
            "new index manager must be the deploying IndexManager"
        );
        assertEq(
            initializedIndex.getIndexManager(),
            address(indexManager),
            "initialized index manager must be the deploying IndexManager"
        );
        assertEq(
            nonInitializedIndex.getIndexManager(),
            address(indexManager),
            "non initialized index manager must be the deploying IndexManager"
        );
    }

    function testCreateIndexRevertIfCallerNotAssetManager() public {
        vm.prank(user1);
        vm.expectRevert();
        indexManager.createIndex(validFeePercentage, wethAsset60, linkAsset40);
    }

    // =========================================================================
    //  initializeIndex
    // =========================================================================

    function testInitializeIndexMarksIndexAsInitialized() public view{
        assertTrue(indexManager.isIndexAddress(address(initializedIndex)));
        assertTrue(
            indexManager.checkIsIndexInitialized(address(initializedIndex))
        );
        address[] memory allIndexes = indexManager.getDeployedIndexes();
        assertEq(allIndexes[0], address(initializedIndex));
        assertEq(
            indexManager.getIndexByAssetsAddresses(
                address(mockWeth),
                address(mockWbtc)
            ),
            address(initializedIndex)
        );
        address[] memory initializedIndexes = indexManager
            .getInitializedIndexes();
        assertEq(initializedIndexes[0], address(initializedIndex));
        (address asset0, address asset1) = indexManager.getIndexAssets(
            address(initializedIndex)
        );
        assertEq(asset0, address(mockWeth));
        assertEq(asset1, address(mockWbtc));
    }

    function testInitializeIndexEmitsIndexInitializedEvent() public {
        (uint8 dec0, , ) = nonInitializedIndex.getAssetsAndUsdcDecimals();
        uint256 initAmount = 1 * 10 ** dec0;
        vm.prank(deployer);
        IERC20(nonInitializedToken0).approve(
            address(nonInitializedIndex),
            type(uint256).max
        );
        vm.prank(deployer);
        IERC20(nonInitializedToken1).approve(
            address(nonInitializedIndex),
            type(uint256).max
        );

        (
            SwapRoute memory r0,
            SwapRoute memory r1,
            SwapRoute memory r01
        ) = helperConfig.getDefaultSwapRoutes(
                nonInitializedToken0,
                nonInitializedToken1
            );

        // Record all logs to capture IndexInitialized event from both IndexManager and Index.
        vm.recordLogs();
        vm.prank(deployer);
        indexManager.initializeIndex(
            deployer,
            address(nonInitializedIndex),
            initAmount,
            r0,
            r1,
            r01
        );

        Vm.Log[] memory vmLogs = vm.getRecordedLogs();
        // Initialization data is logged by the Index, with the depositor;
        // the IndexManager only logs IndexActionTriggered(INITIALIZE).
        bytes32 expectedSignature = keccak256(
            "IndexInitialized(address,uint256,uint256,uint256,uint256,uint256)"
        );

        bool found;
        for (uint256 i = 0; i < vmLogs.length; i++) {
            if (
                vmLogs[i].emitter == address(nonInitializedIndex) &&
                vmLogs[i].topics[0] == expectedSignature
            ) {
                found = true;
                address depositorFromEvent = address(
                    uint160(uint256(vmLogs[i].topics[1]))
                );
                (uint256 amount0FromEvent, , , , uint256 sharesFromEvent) = abi
                    .decode(
                        vmLogs[i].data,
                        (uint256, uint256, uint256, uint256, uint256)
                    );

                assertEq(depositorFromEvent, deployer);
                assertEq(amount0FromEvent, initAmount);
                assertEq(
                    sharesFromEvent,
                    nonInitializedIndex.balanceOf(deployer)
                );
            }
        }

        assertTrue(found, "IndexInitialized not emitted by Index");
        _assertOnlyActionTriggered(
            vmLogs,
            address(nonInitializedIndex),
            deployer,
            IndexAction.INITIALIZE
        );
    }

    function testInitializeIndexRevertIfAmountIsZero() public {
        (
            SwapRoute memory r0,
            SwapRoute memory r1,
            SwapRoute memory r01
        ) = helperConfig.getDefaultSwapRoutes(
                nonInitializedToken0,
                nonInitializedToken1
            );

        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidIndexAssetsAmount.selector);
        indexManager.initializeIndex(
            msg.sender,
            address(nonInitializedIndex),
            0,
            r0,
            r1,
            r01
        );
    }

    function testInitializeIndexRevertIfAddressIsNotAnIndex() public {
        address notAnIndex = makeAddr("notAnIndex");
        (
            SwapRoute memory r0,
            SwapRoute memory r1,
            SwapRoute memory r01
        ) = helperConfig.getDefaultSwapRoutes(
                address(mockWeth),
                address(mockLink)
            );

        vm.prank(deployer);
        vm.expectRevert(IndexManager__IsNotIndex.selector);
        indexManager.initializeIndex(msg.sender, notAnIndex, 1e18, r0, r1, r01);
    }

    function testInitializeIndexRevertIfAlreadyInitialized() public {
        (
            SwapRoute memory r0,
            SwapRoute memory r1,
            SwapRoute memory r01
        ) = helperConfig.getDefaultSwapRoutes(
                address(mockWeth),
                address(mockLink)
            );

        vm.prank(deployer);
        vm.expectRevert(IndexManager__IndexAlreadyInitialized.selector);
        indexManager.initializeIndex(
            msg.sender,
            address(initializedIndex),
            1e18,
            r0,
            r1,
            r01
        );
    }

    function testInitializeIndexRevertIfCallerNotAssetManager() public {
        (
            SwapRoute memory r0,
            SwapRoute memory r1,
            SwapRoute memory r01
        ) = helperConfig.getDefaultSwapRoutes(
                nonInitializedToken0,
                nonInitializedToken1
            );

        bytes32 assetManagerRole = indexManager.ASSET_MANAGER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "AccessControlUnauthorizedAccount(address,bytes32)"
                    )
                ),
                user1,
                assetManagerRole
            )
        );
        vm.prank(user1);
        indexManager.initializeIndex(
            msg.sender,
            address(nonInitializedIndex),
            1e18,
            r0,
            r1,
            r01
        );
    }
}
