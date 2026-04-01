//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {Index} from "../../../src/Index.sol";
import {IndexAsset, SwapRoute, AssetAvailable} from "../../../src/types.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    DeployAndInitNewIndex,
    RunParams
} from "../../../script/DeployAndInitNewIndex.s.sol";

import "../../../src/errors/IndexManagerErrors.sol";
import "../../../src/events/IndexManagerEvents.sol";
import "../../../src/errors/IndexErrors.sol";

contract IndexManagerRebalanceTest is BaseTest {
    IIndex public newIndexLinkWeth;
    IIndex public newIndexUsdcWeth;

    function setUp() public override {
        super.setUp();

        RunParams memory firstIndexParams = RunParams({
            assetA: AssetAvailable.WETH,
            assetB: AssetAvailable.LINK,
            weightA: 60 * WEIGHT_PRECISION,
            weightB: 40 * WEIGHT_PRECISION,
            feePercentage: 1 * PERCENTAGE_FEE_PRECISION, // 1%
            initialAssetADeposit: 0, // computed by the script via retrieveAmountFromAmount
            initialAssetBDeposit: 1000 * 10 ** 18 // 1000 units of assetB
        });

        DeployAndInitNewIndex deployScript = new DeployAndInitNewIndex();
        newIndexLinkWeth = deployScript.run(
            helperConfig,
            address(indexManager),
            firstIndexParams
        );
        // asset0 = newIndex.getAsset0();
        // asset1 = newIndex.getAsset1();

        RunParams memory secondIndexParams = RunParams({
            assetA: AssetAvailable.WETH,
            assetB: AssetAvailable.USDC,
            weightA: 60 * WEIGHT_PRECISION,
            weightB: 40 * WEIGHT_PRECISION,
            feePercentage: 1 * PERCENTAGE_FEE_PRECISION, // 1%
            initialAssetADeposit: 0,
            initialAssetBDeposit: 1_000_000 * 10 ** 6 // 1,000,000 USDC
        });

        newIndexUsdcWeth = deployScript.run(
            helperConfig,
            address(indexManager),
            secondIndexParams
        );
    }

    // =========================================================================
    //  rebalanceSingleIndex
    // =========================================================================

    function testRebalanceSingleIndexRevertIfIndexNotInitialized() public {
        vm.prank(deployer);
        vm.expectRevert(IndexManager__NotIndexInitialized.selector);
        indexManager.rebalanceSingleIndex(address(nonInitializedIndex));
    }

    function testRebalanceSingleIndexRevertIfSwapManagerNotSet() public {
        //set swaprouter to address(0) to trigger the revert
        vm.prank(deployer);
        indexManager.setSwapManagerAddress(address(0));

        vm.prank(deployer);
        vm.expectRevert(IndexManager__SwapManagerAddressNotSet.selector);
        indexManager.rebalanceSingleIndex(address(initializedIndex));
    }

    function testRebalanceSingleIndexRevertIfCallerNotRebalancer() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                keccak256("REBALANCER_ROLE")
            )
        );
        indexManager.rebalanceSingleIndex(address(initializedIndex));
    }

    function testRebalanceIndexEmitsIndexRebalanceFailedWhenBalanced() public {
        vm.prank(deployer);
        vm.recordLogs();
        indexManager.rebalanceSingleIndex(address(initializedIndex));

        bytes32 expectedSig = IndexRebalanceFailed.selector;
        bytes32 expectedReason = Index__RebalanceNotNeeded.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool rebalanceFailedEmitted = false;
        bytes memory reason;
        address indexEmitter;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSig) {
                rebalanceFailedEmitted = true;
                indexEmitter = address(uint160(uint256(logs[i].topics[1])));
                reason = logs[i].data;
                break;
            }
        }

        assertTrue(
            rebalanceFailedEmitted,
            "IndexRebalanceFailed event not emitted"
        );
        assertEq(
            indexEmitter,
            address(initializedIndex),
            "Event emitted by wrong index"
        );
        // `reason` is the raw log data, which ABI-encodes the `bytes` field
        // (offset + length + value). Decode it first to get the raw bytes.
        bytes memory decodedReason = abi.decode(reason, (bytes));
        assertEq(
            bytes4(decodedReason),
            expectedReason,
            "Event emitted with wrong reason"
        );
    }

    function testRebalanceIndexEmitsIndexRebalanceWhenBalancedSuccessfully()
        public
    {
        // change price of unerlying assets to make index unbalanced and trigger rebalance logic
        vm.warp(block.timestamp + 3600);
        _refreshPriceFeeds();
        int256 newWethPrice = WETH_INITIAL_PRICE * 6; // $12000
        mockWethPriceFeed.updateAnswer(newWethPrice);

        // Update mock router rates to reflect the new WETH price.
        // Without this, the slippage check fails because the router swaps at the
        // old rate (15 WETH = 1 WBTC) while the post-swap USD check uses $12000/WETH.
        // New WETH/WBTC rate: WBTC_PRICE / WETH_NEW_PRICE = 30000/12000 = 2.5 WETH per WBTC
        uint256 wethPerWbtc = (uint256(WBTC_INITIAL_PRICE) * 1e18) /
            uint256(newWethPrice); // 2.5e18
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockWbtc),
            mockUniRouter.computeRate(wethPerWbtc, 1e8)
        );
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockWeth),
            mockUniRouter.computeRate(1e8, wethPerWbtc)
        );
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockUsdc),
            mockUniRouter.computeRate(1e18, uint256(newWethPrice) / 1e2)
        );
        mockUniRouter.setExchangeRate(
            address(mockUsdc),
            address(mockWeth),
            mockUniRouter.computeRate(uint256(newWethPrice) / 1e2, 1e18)
        );

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.rebalanceSingleIndex(address(initializedIndex));

        bytes32 expectedSig = IndexRebalanced.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool rebalanceEmitted = false;
        address indexFromEvent;
        address rebalancerFromEvent;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSig) {
                rebalanceEmitted = true;
                indexFromEvent = address(uint160(uint256(logs[i].topics[1])));
                rebalancerFromEvent = address(
                    uint160(uint256(logs[i].topics[2]))
                );
                break;
            }
        }

        assertTrue(rebalanceEmitted, "IndexRebalanced event not emitted");
        assertEq(
            indexFromEvent,
            address(initializedIndex),
            "Event emitted by wrong index"
        );
        assertEq(
            rebalancerFromEvent,
            deployer,
            "Event emitted by wrong rebalancer"
        );
    }

    // =========================================================================
    //  rebalanceMultipleIndexes
    // =========================================================================

    function testRebalanceMultipleIndexesRevertIfAnyIndexNotInitialized()
        public
    {
        address[] memory indexes = new address[](2);
        indexes[0] = address(initializedIndex);
        indexes[1] = address(nonInitializedIndex);

        vm.prank(deployer);
        vm.expectRevert(IndexManager__NotIndexInitialized.selector);
        indexManager.rebalanceMultipleIndexes(indexes);
    }

    function testRebalanceMultipleIndexesDoesNotRevertWhenIndexIsBalanced()
        public
    {
        address[] memory indexes = new address[](2);
        indexes[0] = address(initializedIndex);
        indexes[1] = address(newIndexLinkWeth);
        vm.prank(deployer);
        vm.recordLogs();
        indexManager.rebalanceMultipleIndexes(indexes);

        bytes32 expectedSig = IndexRebalanceFailed.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 rebalanceFailedCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSig) {
                rebalanceFailedCount++;
            }
        }

        // Both indexes are balanced, so both emit IndexRebalanceFailed with reason Index__RebalanceNotNeeded but the transaction does not revert
        assertEq(
            rebalanceFailedCount,
            indexes.length,
            "IndexRebalanceFailed event should be emitted for both balanced indexes"
        );
    }

    function testRebalanceMultipleIndexesRevertIfCallerNotRebalancer() public {
        address[] memory indexes = new address[](2);
        indexes[0] = address(newIndexLinkWeth);
        indexes[1] = address(initializedIndex);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                keccak256("REBALANCER_ROLE")
            )
        );
        indexManager.rebalanceMultipleIndexes(indexes);
    }

    // =========================================================================
    //  rebalanceAllIndexes
    // =========================================================================

    function testRebalanceAllIndexesEmitEventForEveryIndex() public {
        uint256 indexAmount = indexManager.getInitializedIndexes().length;

        vm.prank(deployer);
        vm.recordLogs();
        indexManager.rebalanceAllIndexes();

        bytes32 rebalanceFailedSig = IndexRebalanceFailed.selector;
        bytes32 rebalanceSuccessSig = IndexRebalanced.selector;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 rebalanceFailedCount = 0;
        uint256 rebalanceSuccessCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == rebalanceFailedSig) {
                rebalanceFailedCount++;
            } else if (logs[i].topics[0] == rebalanceSuccessSig) {
                rebalanceSuccessCount++;
            }
        }

        assertEq(
            rebalanceFailedCount + rebalanceSuccessCount,
            indexAmount,
            "Event count does not match initialized index count"
        );
    }
}
