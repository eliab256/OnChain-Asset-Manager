// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct IndexAsset {
    address asset;
    uint112 weightPercentage; // With 4 decimals, e.g. 50000 = 5%
    address priceFeed;
}
