// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

event RouterAddressSet(address indexed newRouter, address indexed setter);

event IndexCreated(
    address indexed indexAddress,
    address indexed asset0,
    address indexed asset1,
    address assetManager
);

event IndexInitialized(
    address indexed indexAddress,
    address indexed assetManager
);
event IndexRebalanced(address indexed indexAddress, address indexed rebalancer);

event IndexRebalanceFailed(address indexed indexAddress, string reason);

event NewIndexWeightsProposed(
    address indexed indexAddress,
    address indexed assetManager,
    uint112 oldWeightAsset0,
    uint112 oldWeightAsset1,
    uint112 newWeightAsset0,
    uint112 newWeightAsset1,
    uint256 implementationTimestamp
);
event FeesCollected(
    address indexed indexAddress,
    address indexed feeCollector,
    uint256 feeAmount
);

event FeesCollectionFailed(
    address indexed indexAddress,
    address indexed feeCollector,
    string reason
);

event WeightUpdateExecuted(address indexed indexAddress);

event WeightUpdateFailed(address indexed indexAddress, string reason);
