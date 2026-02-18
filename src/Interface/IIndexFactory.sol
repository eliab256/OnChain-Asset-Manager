// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IndexAsset} from "../types.sol";

interface IIndexFactory {
    function createIndex(
        IndexAsset memory assetA, IndexAsset memory assetB
    ) external;
}