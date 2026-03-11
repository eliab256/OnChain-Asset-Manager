//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Index} from "../src/Index.sol";
import {IndexManager} from "../src/IndexManager.sol";
import {HelperConfig, AssetConfig, NetworkConfig} from "./HelperConfig.s.sol";
import {IndexAsset, AssetAvailable} from "../src/types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DeployAndInitNewIndex is Script {
    IndexManager public indexManager;
    HelperConfig public helperConfig;

    using SafeERC20 for IERC20;

    function run(
        HelperConfig _helperConfig,
        address _indexManager,
        AssetAvailable _assetA,
        AssetAvailable _assetB,
        uint128 _weightA,
        uint128 _weightB,
        uint256 _feePercentage,
        uint256 _initialAssetADeposit,
        uint256 _initialAssetBDeposit
    ) external returns (Index) {
        helperConfig = _helperConfig;
        NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        address deployer = config.deployerAccount;
        indexManager = IndexManager(_indexManager);

        console.log("================== Deploying New Index =================");
        // prepare index assets configuration
        AssetConfig memory assetAConfig = helperConfig.getActiveAssetConfig(
            _assetA
        );
        AssetConfig memory assetBConfig = helperConfig.getActiveAssetConfig(
            _assetB
        );

        IndexAsset memory indexAssetA = IndexAsset({
            asset: assetAConfig.token,
            weightPercentage: _weightA,
            priceFeed: assetAConfig.priceFeed
        });

        IndexAsset memory indexAssetB = IndexAsset({
            asset: assetBConfig.token,
            weightPercentage: _weightB,
            priceFeed: assetBConfig.priceFeed
        });
        vm.startBroadcast(deployer);

        //deploy new Index
        (address newIndex, address token0, address token1) = indexManager
            .createIndex(_feePercentage, indexAssetA, indexAssetB);

        uint256 initialAsset0Deposit;
        uint256 initialAsset1Deposit;
        if (token0 == indexAssetA.asset) {
            //Sets allowances for index underlying assets
            initialAsset0Deposit = _initialAssetADeposit;
            initialAsset1Deposit = type(uint256).max; // approve max for the token with variable deposit to simplify testing
        } else {
            initialAsset0Deposit = _initialAssetBDeposit;
            initialAsset1Deposit = type(uint256).max; // approve max for the token with variable deposit to simplify testing
        }

        IERC20(token0).forceApprove(address(indexManager), initialAsset0Deposit);
        IERC20(token1).forceApprove(address(indexManager), initialAsset1Deposit);
        // initialize new index
        indexManager.initializeIndex(newIndex, initialAsset0Deposit);
        vm.stopBroadcast();
        console.log(
            "=============== New Index Deployed and Initialized =============="
        );
        console.log("New Index Address:", address(newIndex));
        return (Index(newIndex));
    }
}
