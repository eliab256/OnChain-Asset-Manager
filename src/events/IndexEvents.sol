// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @notice Emitted once, when the index is seeded with its initial reserves and the first shares are minted.
 * @param depositor Address that provided the seed tokens and received the initial shares.
 * @param asset0Amount Amount of asset0 deposited, in asset0 token decimals.
 * @param asset1Amount Amount of asset1 deposited, in asset1 token decimals.
 * @param asset0UsdValue USD value of the asset0 deposit, 18 decimals.
 * @param asset1UsdValue USD value of the asset1 deposit, 18 decimals.
 * @param sharesMinted Initial shares minted to the depositor, 18 decimals (1 share = 1 USD at initialization).
 */
event IndexInitialized(
    address indexed depositor,
    uint256 asset0Amount,
    uint256 asset1Amount,
    uint256 asset0UsdValue,
    uint256 asset1UsdValue,
    uint256 sharesMinted
);

/**
 * @notice Emitted when shares are minted against a USDC deposit.
 * @param user Address that paid the USDC and received the shares.
 * @param sharesMinted Shares minted, 18 decimals.
 * @param asset0Amount Amount of asset0 added to the reserves, in asset0 token decimals.
 * @param asset1Amount Amount of asset1 added to the reserves, in asset1 token decimals.
 * @param usdcAmountIn Gross USDC paid by the user (fee included), in USDC token decimals.
 * @param feeAmount Fee retained by the index and added to the accrued fees, in USDC token decimals.
 */
event SharesMinted(
    address indexed user,
    uint256 sharesMinted,
    uint256 asset0Amount,
    uint256 asset1Amount,
    uint256 usdcAmountIn,
    uint256 feeAmount
);

/**
 * @notice Emitted when shares are redeemed for USDC.
 * @param user Address whose shares were burned and who received the USDC.
 * @param sharesBurned Shares burned, 18 decimals.
 * @param asset0Amount Amount of asset0 removed from the reserves, in asset0 token decimals.
 * @param asset1Amount Amount of asset1 removed from the reserves, in asset1 token decimals.
 * @param usdcAmountOut Net USDC sent to the user (fee excluded), in USDC token decimals.
 * @param feeAmount Fee retained by the index and added to the accrued fees, in USDC token decimals.
 */
event SharesBurned(
    address indexed user,
    uint256 sharesBurned,
    uint256 asset0Amount,
    uint256 asset1Amount,
    uint256 usdcAmountOut,
    uint256 feeAmount
);

/**
 * @notice Emitted when the index swaps between its assets to restore the target weights.
 * @param asset0ReserveBefore Asset0 reserve before the rebalance, in asset0 token decimals.
 * @param asset1ReserveBefore Asset1 reserve before the rebalance, in asset1 token decimals.
 * @param asset0ReserveAfter Asset0 reserve after the rebalance, in asset0 token decimals.
 * @param asset1ReserveAfter Asset1 reserve after the rebalance, in asset1 token decimals.
 */
event IndexRebalanced(
    uint256 asset0ReserveBefore,
    uint256 asset1ReserveBefore,
    uint256 asset0ReserveAfter,
    uint256 asset1ReserveAfter
);

/**
 * @notice Emitted when a new target weights update is proposed.
 * @param oldAsset0Weight Current asset0 target weight, in weight units (1_000_000 = 100%).
 * @param oldAsset1Weight Current asset1 target weight, in weight units (1_000_000 = 100%).
 * @param newAsset0Weight Proposed asset0 target weight, in weight units (1_000_000 = 100%).
 * @param newAsset1Weight Proposed asset1 target weight, in weight units (1_000_000 = 100%).
 * @param executableAt Unix timestamp (seconds) from which the update can be executed.
 */
event WeightsUpdateProposed(
    uint128 oldAsset0Weight,
    uint128 oldAsset1Weight,
    uint128 newAsset0Weight,
    uint128 newAsset1Weight,
    uint256 executableAt
);

/**
 * @notice Emitted when a pending weights update is executed and becomes the new target.
 * @param asset0Weight New asset0 target weight, in weight units (1_000_000 = 100%).
 * @param asset1Weight New asset1 target weight, in weight units (1_000_000 = 100%).
 */
event WeightsUpdated(uint128 asset0Weight, uint128 asset1Weight);

/**
 * @notice Emitted when the rebalance attempted after a weights update reverts with a custom error other than Index__RebalanceNotNeeded.
 * @dev The weights update itself is kept. Not emitted for common errors (revert data shorter than 4 bytes, e.g. out of gas,
 *      Error(string) or Panic(uint256)): in that case executeWeightUpdate reverts with the same revert data.
 * @param reasonData Raw revert data of the rebalance call, unchanged: always an ABI-encoded custom error (at least 4 bytes,
 *        selector other than Index__RebalanceNotNeeded, Error(string) and Panic(uint256)), never empty.
 */
event WeightsUpdateRebalanceFailed(bytes reasonData);

/**
 * @notice Emitted when the rebalance attempted after a weights update is skipped because the index is already within the rebalance threshold.
 */
event WeightsUpdateRebalanceSkipped();

/**
 * @notice Emitted when a pending weights update is cancelled, either explicitly or because a new proposal overwrites an executable or expired one.
 * @param cancelledAsset0Weight Cancelled asset0 weight, in weight units (1_000_000 = 100%).
 * @param cancelledAsset1Weight Cancelled asset1 weight, in weight units (1_000_000 = 100%).
 */
event WeightsUpdateCancelled(
    uint128 cancelledAsset0Weight,
    uint128 cancelledAsset1Weight
);

/**
 * @notice Emitted when the accrued fees are transferred out of the index.
 * @param feeCollector Address that received the fees.
 * @param feeAmount Fees transferred, in USDC token decimals.
 */
event FeesCollected(address indexed feeCollector, uint256 feeAmount);
