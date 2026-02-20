// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IndexAsset} from "../types.sol";

interface IIndexFactory {
    function createIndex(
        uint256 feePercentage,
        IndexAsset memory assetA,
        IndexAsset memory assetB
    ) external;

    function initializeIndex(
        address indexAddress,
        uint256 underlyingAmount0
    ) external;

    function isIndexAddress(address indexAddress) external view returns (bool);
    function isIndexInitialized(
        address indexAddress
    ) external view returns (bool);
}
