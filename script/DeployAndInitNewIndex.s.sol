//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Index} from "../src/Index.sol";
import {IndexManager} from "../src/IndexManager.sol";
import {HelperConfig, TokenConfig, NetworkConfig} from "./HelperConfig.s.sol";
import {IndexAsset, TokenAvailable} from "../src/types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployAndInitNewIndex is Script {
    IndexManager public indexManager;
    HelperConfig public helperConfig;

    function run(
        HelperConfig _helperConfig,
        address _indexManager,
        TokenAvailable _tokenA,
        TokenAvailable _tokenB,
        uint112 _weightA,
        uint112 _weightB,
        uint256 _feePercentage,
        uint256 _initialTokenADeposit,
        uint256 _initialTokenBDeposit
    ) external returns (Index) {
        helperConfig = _helperConfig;
        NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        address deployer = config.deployerAccount;
        indexManager = IndexManager(_indexManager);

        console.log("================== Deploying New Index =================");
        // prepare index assets configuration
        TokenConfig memory tokenAConfig = helperConfig.getActiveTokenConfig(
            _tokenA
        );
        TokenConfig memory tokenBConfig = helperConfig.getActiveTokenConfig(
            _tokenB
        );

        IndexAsset memory indexAssetA = IndexAsset({
            asset: tokenAConfig.token,
            weightPercentage: _weightA,
            priceFeed: tokenAConfig.priceFeed
        });

        IndexAsset memory indexAssetB = IndexAsset({
            asset: tokenBConfig.token,
            weightPercentage: _weightB,
            priceFeed: tokenBConfig.priceFeed
        });
        vm.startBroadcast(deployer);

        //deploy new Index
        (address newIndex, address token0, address token1) = indexManager
            .createIndex(_feePercentage, indexAssetA, indexAssetB);

        uint256 initialToken0Deposit;
        uint256 initialToken1Deposit;
        if (token0 == indexAssetA.asset) {
            //Sets allowances for index underlying assets
            initialToken0Deposit = _initialTokenADeposit;
            initialToken1Deposit = type(uint256).max; // approve max for the token with variable deposit to simplify testing
        } else {
            initialToken0Deposit = _initialTokenBDeposit;
            initialToken1Deposit = type(uint256).max; // approve max for the token with variable deposit to simplify testing
        }

        IERC20(token0).approve(address(indexManager), initialToken0Deposit);
        IERC20(token1).approve(address(indexManager), initialToken1Deposit);
        // initialize new index
        indexManager.initializeIndex(newIndex, initialToken0Deposit);
        vm.stopBroadcast();
        console.log(
            "=============== New Index Deployed and Initialized =============="
        );
        console.log("New Index Address:", address(newIndex));
        return (Index(newIndex));
    }
}
