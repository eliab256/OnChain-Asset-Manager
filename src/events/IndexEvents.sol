// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

event IndexInitialized(
    uint256 underlyingAmount0,
    uint256 underlyingAmount1,
    uint256 underlying0UsdValue,
    uint256 underlying1UsdValue,
    uint256 initialShares
);

event Deposit(
    address indexed user,
    uint256 usdcAmountIn,
    uint256 sharesMinted,
    uint256 token0Added,
    uint256 token1Added
);

event Withdrawal(
    address indexed user,
    uint256 sharesBurned,
    uint256 token0Removed,
    uint256 token1Removed,
    uint256 usdcAmountOut
);

event IndexRebalanced(
    uint256 initAsset0Reserve,
    uint256 initAsset1Reserve,
    uint256 newAsset0Reserve,
    uint256 newAsset1Reserve,
    uint256 rebalanceTimestamp
);

event WeightsUpdateProposed(
    uint112 newWeightAsset0,
    uint112 newWeightAsset1,
    uint256 indexed implementationTimestamp
);

event IndexWeightsUpdated(
    uint112 newWeightAsset0,
    uint112 newWeightAsset1,
    uint256 indexed updateTimestamp
);

event FeesCollected(
    address indexed feeCollector,
    uint256 feeAmount
);