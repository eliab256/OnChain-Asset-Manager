// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

struct IndexAsset {
    address asset;
    uint128 weightPercentage; // With 4 decimals, e.g. 500000 = 50%
    address priceFeed;
}

struct InitStateCache {
    uint256 priceAsset0;
    uint256 priceAsset1;
    uint256 priceUsdc;
    uint128 initialAsset0Reserve;
    uint128 initialAsset1Reserve;
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

enum SwapType {
    ASSET0_USDC,
    ASSET1_USDC,
    ASSET0_ASSET1
}
