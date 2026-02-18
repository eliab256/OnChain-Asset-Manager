// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct IndexAsset{
    address asset;
    uint256 weightPercentage;
    address priceFeed;
}