//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Index} from "../src/contracts/core/Index.sol";
import {IndexManager} from "../src/contracts/periphery/IndexManager.sol";
import {MultiSigWallet} from "../src/contracts/periphery/MultiSigWallet.sol";
import {HelperConfig, AssetConfig, NetworkConfig} from "./HelperConfig.s.sol";
import {IndexAsset, AssetAvailable, SwapRoute} from "../src/contracts/types.sol";
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
    MultiSigWallet public multiSig;
    address[] public owners;
    uint256 public requiredConfirmations;

    using SafeERC20 for IERC20;

    function run(
        HelperConfig _helperConfig,
        address _indexManager,
        address _multiSig,
        RunParams memory _params
    ) external returns (Index) {
        helperConfig = _helperConfig;
        indexManager = IndexManager(_indexManager);
        multiSig = MultiSigWallet(payable(_multiSig));
        owners = multiSig.getOwners();
        requiredConfirmations = multiSig.getRequiredConfirmations();

        console.log("================== Deploying New Index =================");

        //  1. Create the index via MultiSig
        address newIndex = _createIndexViaMultiSig(_params);
        console.log("New Index Address:", newIndex);

        //  2. Approve tokens & initialize the index via MultiSig
        _approveAndInitializeIndex(_params, newIndex);

        console.log(
            "=============== New Index Deployed and Initialized =============="
        );
        return (Index(newIndex));
    }

    // =========================================================================
    //  Internal helpers
    // =========================================================================

    function _createIndexViaMultiSig(
        RunParams memory _params
    ) internal returns (address newIndex) {
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

        bytes memory createIndexData = abi.encodeCall(
            IndexManager.createIndex,
            (_params.feePercentage, indexAssetA, indexAssetB)
        );

        _submitConfirmAndExecute(address(indexManager), 0, createIndexData);

        address[] memory deployedIndexes = indexManager.getDeployedIndexes();
        newIndex = deployedIndexes[deployedIndexes.length - 1];
    }

    /**
     * @dev Computes deposits, funds the multisig with the underlying tokens,
     *      then has the multisig approve and initialize the index.
     */
    function _approveAndInitializeIndex(
        RunParams memory _params,
        address _newIndex
    ) internal {
        NetworkConfig memory config = helperConfig.getActiveNetworkConfig();
        address token0 = Index(_newIndex).getAsset0();
        address token1 = Index(_newIndex).getAsset1();

        (
            SwapRoute memory routeAsset0Usdc,
            SwapRoute memory routeAsset1Usdc,
            SwapRoute memory routeAsset0Asset1
        ) = helperConfig.getDefaultSwapRoutes(token0, token1);

        (
            uint256 initialAsset0Deposit,
            uint256 initialAsset1Deposit
        ) = _computeInitialDeposits(_params, token0, _newIndex);

        vm.startBroadcast(config.deployerAccount);
        IERC20(token0).safeTransfer(address(multiSig), initialAsset0Deposit);
        IERC20(token1).safeTransfer(address(multiSig), initialAsset1Deposit);
        vm.stopBroadcast();

        bytes memory approveAsset0Data = abi.encodeCall(
            IERC20.approve,
            (_newIndex, initialAsset0Deposit)
        );
        _submitConfirmAndExecute(token0, 0, approveAsset0Data);

        bytes memory approveAsset1Data = abi.encodeCall(
            IERC20.approve,
            (_newIndex, initialAsset1Deposit)
        );
        _submitConfirmAndExecute(token1, 0, approveAsset1Data);

        bytes memory initIndexData = abi.encodeCall(
            IndexManager.initializeIndex,
            (
                address(multiSig),
                _newIndex,
                initialAsset0Deposit,
                routeAsset0Usdc,
                routeAsset1Usdc,
                routeAsset0Asset1
            )
        );

        _submitConfirmAndExecute(address(indexManager), 0, initIndexData);
    }

    /**
     * @dev Submits a tx to the MultiSig, collects the required confirmations
     *      from distinct owners, and executes it.  Each step is its own
     *      broadcast so that on a real network each owner signs independently.
     */
    function _submitConfirmAndExecute(
        address _target,
        uint256 _value,
        bytes memory _data
    ) internal {
        vm.startBroadcast(owners[0]);
        uint256 txId = multiSig.submitTransaction(_target, _value, _data);
        multiSig.confirmTransaction(txId);
        vm.stopBroadcast();

        for (uint256 i = 1; i < requiredConfirmations; i++) {
            vm.startBroadcast(owners[i]);
            multiSig.confirmTransaction(txId);
            vm.stopBroadcast();
        }

        vm.startBroadcast(owners[0]);
        multiSig.executeTransaction(txId);
        vm.stopBroadcast();
    }

    /**
     * @dev Resolves which raw deposit amount to use as token0 seed,
     *      then computes the proportional token1 amount.
     */
    function _computeInitialDeposits(
        RunParams memory _params,
        address _token0,
        address _newIndex
    ) internal view returns (uint256 asset0Deposit, uint256 asset1Deposit) {
        AssetConfig memory assetAConfig = helperConfig.getActiveAssetConfig(
            _params.assetA
        );
        if (_token0 == assetAConfig.token) {
            asset0Deposit = _params.initialAssetADeposit > 0
                ? _params.initialAssetADeposit
                : indexManager.retrieveAmountFromAmount(
                    _params.initialAssetBDeposit,
                    _newIndex,
                    false
                );
        } else {
            asset0Deposit = _params.initialAssetBDeposit > 0
                ? _params.initialAssetBDeposit
                : indexManager.retrieveAmountFromAmount(
                    _params.initialAssetADeposit,
                    _newIndex,
                    false
                );
        }
        asset1Deposit = indexManager.retrieveAmountFromAmount(
            asset0Deposit,
            _newIndex,
            true
        );
    }
}
