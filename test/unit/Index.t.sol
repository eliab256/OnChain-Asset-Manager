//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {IIndexManager} from "../../src/Interface/IIndexManager.sol";
import {ISwapManager} from "../../src/Interface/ISwapManager.sol";
import {IIndex} from "../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute, AssetAvailable} from "../../src/types.sol";
import {Index} from "../../src/Index.sol";

import {
    HelperConfig,
    AssetConfig,
    NetworkConfig
} from "../../script/HelperConfig.s.sol";
import {
    DeployAndInitNewIndex,
    RunParams
} from "../../script/DeployAndInitNewIndex.s.sol";
import {console2} from "forge-std/console2.sol";

contract IndexTest is BaseTest {
    uint128 public weightA = (50 * WEIGHT_PRECISION) / 100; // 60%
    uint128 public weightB = (50 * WEIGHT_PRECISION) / 100; // 40%
    uint32 public feePercentage = 1 * PERCENTAGE_FEE_PRECISION; // 1%

    function setUp() public override {
        super.setUp();
    }

    function testIndexDeployment() public {
        indexManager.sortAssets(address(mockWeth), address(mockWbtc));

        //console2.log(" total weight: ", indexManager.MAX_WEIGHT());
        assertEq(indexWethWbtc.getAsset0(), address(mockWeth));
        assertEq(indexWethWbtc.getAsset1(), address(mockWbtc));
        assertEq(indexWethWbtc.getUsdc(), address(mockUsdc));
        assertEq(
            indexWethWbtc.getAsset0PriceFeed(),
            address(mockWethPriceFeed)
        );
        assertEq(
            indexWethWbtc.getAsset1PriceFeed(),
            address(mockWbtcPriceFeed)
        );
        assertEq(indexWethWbtc.getUsdcPriceFeed(), address(mockUsdcPriceFeed));
        (uint128 actualWeightA, uint128 actualWeightB) = indexWethWbtc
            .getAssetsWeights();
        assertEq(actualWeightA, weightA); // 60%
        assertEq(actualWeightB, weightB); // 40%
        (uint32 actualFeePercentage, uint128 actualTotalfees) = indexWethWbtc
            .getFeesInfo();
        assertEq(actualFeePercentage, feePercentage);
        assertEq(actualTotalfees, 0);
        (uint8 dec0, uint8 dec1, uint8 decUsdc) = indexWethWbtc
            .getAssetsAndUsdcDecimals();
        assertEq(dec0, mockWeth.decimals());
        assertEq(dec1, mockWbtc.decimals());
        assertEq(decUsdc, mockUsdc.decimals());
        assertEq(
            indexManager.checkIsIndexInitialized(address(indexWethWbtc)),
            true
        );
    }
}
