// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct IndexAsset {
    address asset;
    uint112 weightPercentage; // With 4 decimals, e.g. 500000 = 50%
    address priceFeed;
}

struct InitStateCache {
    uint256 priceAsset0;
    uint256 priceAsset1;
    uint112 initialAsset0Reserve;
    uint112 initialAsset1Reserve;
    uint256 asset0UsdValue;
    uint256 asset1UsdValue;
    uint256 totalAssetUsdValue;
}

enum AssetAvailable {
    WETH,
    USDC,
    WBTC,
    LINK
}
