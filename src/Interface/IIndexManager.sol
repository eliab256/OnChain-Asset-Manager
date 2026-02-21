// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IndexAsset} from "../types.sol";

interface IIndexManager {
    function createIndex(
        uint256 feePercentage,
        IndexAsset memory assetA,
        IndexAsset memory assetB
    ) external;

    function initializeIndex(
        address indexAddress,
        uint256 underlyingAmount0
    ) external;

    function rebalanceIndex(address indexAddress) external;

    function changeWeights(
        address indexAddress,
        uint256 newWeightAsset0
    ) external;

    function collectFees(address indexAddress) external;

    function sortAssets(
        address assetAddressA,
        address assetAddressB
    ) external pure returns (address token0, address token1);

    function getAllIndexes() external view returns (address[] memory);

    function getIndexByAssetsAddresses(
        address assetAddressA,
        address assetAddressB
    ) external view returns (address index);

    function isIndexAddress(address indexAddress) external view returns (bool);

    function checkIsIndexInitialized(
        address indexAddress
    ) external view returns (bool);

    function getUsdcAddress() external view returns (address);
}
