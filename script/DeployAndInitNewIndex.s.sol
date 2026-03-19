//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Index} from "../src/Index.sol";
import {IndexManager} from "../src/IndexManager.sol";
import {HelperConfig, AssetConfig, NetworkConfig} from "./HelperConfig.s.sol";
import {IndexAsset, AssetAvailable, SwapRoute} from "../src/types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

struct RunParams {
    AssetAvailable assetA;
    AssetAvailable assetB;
    uint128 weightA;
    uint128 weightB;
    uint32 feePercentage;
    uint256 initialAssetADeposit;
    uint256 initialAssetBDeposit;
}

contract DeployAndInitNewIndex is Script {
    IndexManager public indexManager;
    HelperConfig public helperConfig;

    using SafeERC20 for IERC20;

    function run(
        HelperConfig _helperConfig,
        address _indexManager,
        RunParams memory _params
    ) external returns (Index) {
        helperConfig = _helperConfig;
        NetworkConfig memory config = helperConfig.getActiveNetworkConfig();
        indexManager = IndexManager(_indexManager);

        console.log("================== Deploying New Index =================");
        AssetConfig memory assetAConfig = helperConfig.getActiveAssetConfig(
            _params.assetA
        );
        AssetConfig memory assetBConfig = helperConfig.getActiveAssetConfig(
            _params.assetB
        );

        IndexAsset memory indexAssetA = IndexAsset({
            asset: assetAConfig.token,
            weightPercentage: _params.weightA,
            priceFeed: assetAConfig.priceFeed
        });

        IndexAsset memory indexAssetB = IndexAsset({
            asset: assetBConfig.token,
            weightPercentage: _params.weightB,
            priceFeed: assetBConfig.priceFeed
        });
        vm.startBroadcast(config.deployerAccount);

        (address newIndex, address token0, address token1) = indexManager
            .createIndex(_params.feePercentage, indexAssetA, indexAssetB);

        (
            SwapRoute memory routeAsset0Usdc,
            SwapRoute memory routeAsset1Usdc,
            SwapRoute memory routeAsset0Asset1
        ) = helperConfig.getDefaultSwapRoutes(token0, token1);

        uint256 initialAsset0Deposit;
        uint256 initialAsset1Deposit;
        if (token0 == indexAssetA.asset) {
            initialAsset0Deposit = _params.initialAssetADeposit;
            initialAsset1Deposit = type(uint256).max; // approve max for the token with variable deposit to simplify testing
        } else {
            initialAsset0Deposit = _params.initialAssetBDeposit;
            initialAsset1Deposit = type(uint256).max; // approve max for the token with variable deposit to simplify testing
        }

        IERC20(token0).forceApprove(
            address(indexManager),
            initialAsset0Deposit
        );
        IERC20(token1).forceApprove(
            address(indexManager),
            initialAsset1Deposit
        );
        // initialize new index
        indexManager.initializeIndex(
            newIndex,
            initialAsset0Deposit,
            routeAsset0Usdc,
            routeAsset1Usdc,
            routeAsset0Asset1
        );
        vm.stopBroadcast();
        console.log(
            "=============== New Index Deployed and Initialized =============="
        );
        console.log("New Index Address:", address(newIndex));
        return (Index(newIndex));
    }
}
