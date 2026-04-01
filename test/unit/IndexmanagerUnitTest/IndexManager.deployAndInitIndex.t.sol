// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute} from "../../../src/types.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

import "../../../src/errors/IndexManagerErrors.sol";
import "../../../src/events/IndexManagerEvents.sol";
import "../../../src/errors/IndexErrors.sol";

contract IndexManagerTest is BaseTest {
    IndexAsset wethAsset60;
    IndexAsset linkAsset40;

    function setUp() public override {
        super.setUp();

        wethAsset60 = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: weight60,
            priceFeed: address(mockWethPriceFeed)
        });

        linkAsset40 = IndexAsset({
            asset: address(mockLink),
            weightPercentage: weight40,
            priceFeed: address(mockLinkPriceFeed)
        });
    }

    function _createDefaultIndex(
        address _assetA,
        address _assetB,
        address _priceFeedA,
        address _priceFeedB
    ) internal returns (address indexAddress, address token0, address token1) {
        IndexAsset memory assetA = IndexAsset({
            asset: _assetA,
            weightPercentage: weight60,
            priceFeed: _priceFeedA
        });
        IndexAsset memory assetB = IndexAsset({
            asset: _assetB,
            weightPercentage: weight40,
            priceFeed: _priceFeedB
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

    function testCreateIndexRegistersIndexInIsIndexMappingsAndArrays() public {
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
            address(mockLink),
            address(mockWethPriceFeed),
            address(mockLinkPriceFeed)
        );

        assertTrue(indexManager.isIndexAddress(indexAddress));
        assertFalse(indexManager.checkIsIndexInitialized(indexAddress));
    }

    function testCreateIndexIndexLookupIsOrderIndependent() public {
        (address indexAddress, , ) = _createDefaultIndex(
            address(mockWeth),
            address(mockLink),
            address(mockWethPriceFeed),
            address(mockLinkPriceFeed)
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
            address(mockLink),
            address(mockWethPriceFeed),
            address(mockLinkPriceFeed)
        );

        assertTrue(token0 < token1, "token0 must be < token1 after sorting");
    }

    function testCreateIndexEmitsIndexCreatedEvent() public {
        (address sortedToken0, address sortedToken1) = indexManager.sortAssets(
            address(mockWeth),
            address(mockLink)
        );

        vm.recordLogs();
        vm.prank(deployer);
        indexManager.createIndex(validFeePercentage, wethAsset60, linkAsset40);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 5);
        Vm.Log memory fullEvent = entries[4];
        bytes32 eventSignature = fullEvent.topics[0]; //event signature hashed
        address testIndex;
        address testToken0;
        address testToken1;
        address testCaller;
        {
            bytes32 topic1 = fullEvent.topics[1]; //is indexed
            bytes32 topic2 = fullEvent.topics[2]; //is indexed
            bytes32 topic3 = fullEvent.topics[3]; //is indexed
            bytes memory data = fullEvent.data; //is not indexed

            testIndex = address(uint160(uint256(topic1)));
            testToken0 = address(uint160(uint256(topic2)));
            testToken1 = address(uint160(uint256(topic3)));
            testCaller = abi.decode(data, (address));
        }
        assertEq(
            eventSignature,
            keccak256("IndexCreated(address,address,address,address)")
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
            weightPercentage: weight50,
            priceFeed: address(mockWethPriceFeed)
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
            weightPercentage: weight20,
            priceFeed: address(mockWethPriceFeed)
        });
        IndexAsset memory wethAssetB = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: weight100,
            priceFeed: address(mockWethPriceFeed)
        });
        IndexAsset memory wethAssetC = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: weight120,
            priceFeed: address(mockWethPriceFeed)
        });
        IndexAsset memory linkAssetA = IndexAsset({
            asset: address(mockLink),
            weightPercentage: weight30,
            priceFeed: address(mockLinkPriceFeed)
        });
        IndexAsset memory linkAssetB = IndexAsset({
            asset: address(mockLink),
            weightPercentage: weight00,
            priceFeed: address(mockLinkPriceFeed)
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

    function testCreateIndexRevertIfIndexAlreadyExists() public {
        IndexAsset memory wethAsset = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: weight50,
            priceFeed: address(mockWethPriceFeed)
        });
        IndexAsset memory wbtcAsset = IndexAsset({
            asset: address(mockWbtc),
            weightPercentage: weight50,
            priceFeed: address(mockWbtcPriceFeed)
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

    function testCreateIndexRevertIfAsset0PriceFeedIsNotAPriceFeed() public {
        IndexAsset memory wethAsset = IndexAsset({
            asset: address(mockWeth),
            weightPercentage: weight60,
            priceFeed: address(mockWbtc) // invalid
        });
        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidPriceFeedAddress.selector);
        indexManager.createIndex(validFeePercentage, wethAsset, linkAsset40);
    }

    function testCreateIndexRevertIfAsset1PriceFeedIsNotAPriceFeed() public {
        IndexAsset memory linkAsset = IndexAsset({
            asset: address(mockLink),
            weightPercentage: weight40,
            priceFeed: address(mockLink) // invalid
        });

        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidPriceFeedAddress.selector);
        indexManager.createIndex(validFeePercentage, wethAsset60, linkAsset);
    }

    function testCreateIndexRevertIfAsset0IsNotErc20() public {
        IndexAsset memory wethAsset = IndexAsset({
            asset: address(mockWbtcPriceFeed), // invalid
            weightPercentage: weight60,
            priceFeed: address(mockWethPriceFeed)
        });

        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidIndexAssetsAddress.selector);
        indexManager.createIndex(validFeePercentage, wethAsset, linkAsset40);
    }

    function testCreateIndexRevertIfAsset1IsNotErc20() public {
        IndexAsset memory linkAsset = IndexAsset({
            asset: address(mockWethPriceFeed), // invalid
            weightPercentage: weight40,
            priceFeed: address(mockLinkPriceFeed)
        });

        vm.prank(deployer);
        vm.expectRevert(IndexManager__InvalidIndexAssetsAddress.selector);
        indexManager.createIndex(validFeePercentage, wethAsset60, linkAsset);
    }

    function testCreateIndexRevertIfRouterNotSet() public {
        // Remove the router so the guard triggers.
        vm.prank(deployer);
        indexManager.setRouterAddress(address(0));

        vm.prank(deployer);
        vm.expectRevert(IndexManager__RouterAddressNotSet.selector);
        indexManager.createIndex(validFeePercentage, wethAsset60, linkAsset40);
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
        bytes32 expectedSignature = keccak256(
            "IndexInitialized(address,address)"
        );

        bool found;
        for (uint256 i = 0; i < vmLogs.length; i++) {
            if (
                vmLogs[i].emitter == address(indexManager) &&
                vmLogs[i].topics[0] == expectedSignature
            ) {
                found = true;
                address indexAddressFromEvent = address(
                    uint160(uint256(vmLogs[i].topics[1]))
                );
                address callerFromEvent = address(
                    uint160(uint256(vmLogs[i].topics[2]))
                );

                assertEq(indexAddressFromEvent, address(nonInitializedIndex));
                assertEq(callerFromEvent, deployer);
                break;
            }
        }

        assertTrue(found, "IndexInitialized not emitted by IndexManager");
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
