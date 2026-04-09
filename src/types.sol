// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/**
 * @notice Describes one of the two underlying assets that make up an index.
 * @param asset           ERC-20 token address of the underlying asset.
 * @param weightPercentage Target allocation weight in the index.
 *                        Uses 4 decimal places of precision where
 *                        MAX_WEIGHT (= 100 * WEIGHT_PRECISION = 1_000_000) represents 100%.
 *                        Example: 600_000 = 60%.
 * @param priceFeed       Chainlink AggregatorV3Interface price feed address
 *                        used to obtain the USD price of this asset.
 */
struct IndexAsset {
    address asset;
    uint128 weightPercentage;
    address priceFeed;
}

/**
 * @notice Snapshot of prices, reserves, and USD values captured at the start of
 *         a mint or redeem operation to avoid repeated storage reads and external
 *         price-feed calls throughout the function.
 * @param priceAsset0           USD price of asset0, in 18-decimal standard.
 * @param priceAsset1           USD price of asset1, in 18-decimal standard.
 * @param priceUsdc             USD price of USDC, in 18-decimal standard.
 * @param initialAsset0Reserve  Reserve of asset0 at the time of the snapshot,
 *                              normalised to 18 decimals.
 * @param initialAsset1Reserve  Reserve of asset1 at the time of the snapshot,
 *                              normalised to 18 decimals.
 * @param asset0UsdValue        Total USD value of the asset0 reserve, in 18-decimal standard.
 * @param asset1UsdValue        Total USD value of the asset1 reserve, in 18-decimal standard.
 * @param totalAssetUsdValue    Sum of asset0UsdValue and asset1UsdValue, in 18-decimal standard.
 */
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

/**
 * @notice Identifies the assets available for use in index creation.
 * @dev Used in HelperConfig to provide pre-configured IndexAsset structs for
 *      each supported token on a given network.
 */
enum AssetAvailable {
    WETH,
    WBTC,
    LINK,
    COMP
}

/**
 * @notice Identifies which pair of assets a swap route connects.
 * @dev Used as a key in the SwapManager route registry.
 * @param ASSET0_USDC   Route between asset0 and USDC (bidirectional).
 * @param ASSET1_USDC   Route between asset1 and USDC (bidirectional).
 * @param ASSET0_ASSET1 Route between asset0 and asset1 (used during rebalancing).
 */
enum SwapType {
    ASSET0_USDC,
    ASSET1_USDC,
    ASSET0_ASSET1
}

/**
 * @notice Indicates which version of the Uniswap protocol a swap route uses.
 * @param V3 Uniswap V3 — route encoded as an ABI-packed path
 *           (abi.encodePacked(tokenIn, fee, tokenOut)).
 * @param V4 Uniswap V4 — route identified by a PoolKey struct.
 */
enum PoolVersion {
    V3,
    V4
}

/**
 * @notice Fully describes a swap route for use with the Universal Router.
 * @dev Exactly one of `poolKey` or `v3Path` is meaningful depending on `version`.
 * @param version  Protocol version this route targets (V3 or V4).
 * @param poolKey  Uniswap V4 pool key. Populated only when version == V4;
 *                 ignored for V3 routes.
 * @param v3Path   ABI-packed Uniswap V3 path:
 *                 abi.encodePacked(tokenA, fee, tokenB) for a single-hop,
 *                 or abi.encodePacked(tokenA, fee, tokenMid, fee, tokenB) for multi-hop.
 *                 Populated only when version == V3; ignored for V4 routes.
 */
struct SwapRoute {
    PoolVersion version;
    PoolKey poolKey;
    bytes v3Path;
}
