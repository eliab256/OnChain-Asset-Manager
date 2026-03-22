//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IIndexManager} from "../../../src/Interface/IIndexManager.sol";
import {ISwapManager} from "../../../src/Interface/ISwapManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute, AssetAvailable} from "../../../src/types.sol";
import {Index} from "../../../src/Index.sol";
import {
    HelperConfig,
    AssetConfig,
    NetworkConfig
} from "../../../script/HelperConfig.s.sol";
import {
    DeployAndInitNewIndex,
    RunParams
} from "../../../script/DeployAndInitNewIndex.s.sol";
import {console2} from "forge-std/console2.sol";

import "../../../src/errors/IndexErrors.sol";
import "../../../src/events/IndexEvents.sol";

contract IndexTest is BaseTest {
  

    function setUp() public override {
        super.setUp();
        
    }

    function testIndexDeployment() public {
        (address effectiveToken0, address effectiveToken1) = indexManager
            .sortAssets(address(mockLink), address(mockWbtc));

        assertEq(nonInitializedIndex.getAsset0(), effectiveToken0);
        assertEq(nonInitializedIndex.getAsset1(), effectiveToken1);
        assertEq(effectiveToken0, address(mockWbtc));
        assertEq(effectiveToken1, address(mockLink));
        assertEq(nonInitializedIndex.getUsdc(), address(mockUsdc));
        assertEq(
            nonInitializedIndex.getAsset0PriceFeed(),
            address(mockWbtcPriceFeed)
        );
        assertEq(
            nonInitializedIndex.getAsset1PriceFeed(),
            address(mockLinkPriceFeed)
        );
        assertEq(
            nonInitializedIndex.getUsdcPriceFeed(),
            address(mockUsdcPriceFeed)
        );
        (uint128 actualWeight0, uint128 actualWeight1) = nonInitializedIndex
            .getAssetsWeights();
        assertEq(actualWeight0, weight40);
        assertEq(actualWeight1, weight60);
        (
            uint32 actualFeePercentage,
            uint128 actualTotalfees
        ) = nonInitializedIndex.getFeesInfo();
        assertEq(actualFeePercentage, validFeePercentage);
        assertEq(actualTotalfees, 0);
        (uint8 dec0, uint8 dec1, uint8 decUsdc) = nonInitializedIndex
            .getAssetsAndUsdcDecimals();
        assertEq(
            dec0,
            mockWbtc.decimals(),
            "Asset0 decimals should match the mockWbtc decimals"
        );
        assertEq(
            dec1,
            mockLink.decimals(),
            "Asset1 decimals should match the mockLink decimals"
        );
        assertEq(
            decUsdc,
            mockUsdc.decimals(),
            "USDC decimals should match the mockUsdc decimals"
        );
        assertEq(
            indexManager.checkIsIndexInitialized(address(nonInitializedIndex)),
            false
        );
    }

    function testIndexInitializationRevertIfAlreadyInitialized() public {
        assertEq(
            indexManager.checkIsIndexInitialized(address(initializedIndex)),
            true
        );
        uint256 initAmount = 10 * 10 ** mockWeth.decimals();

        vm.expectRevert(Index__AlreadyInitialized.selector);
        vm.prank(address(indexManager));
        initializedIndex.initialize(address(deployer), initAmount);
    }

    
}
