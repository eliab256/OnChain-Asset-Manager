// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

event RouterAddressSet(address indexed newRouter, address indexed setter);

event SwapManagerUpgradeProposed(
    address indexed newImplementation,
    uint256 executableAt,
    address indexed proposer
);

event SwapManagerUpgraded(
    address indexed newImplementation,
    address indexed executor
);

event SwapManagerUpgradeCancelled(
    address indexed cancelledImplementation,
    address indexed canceller
);

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

event IndexRebalanceFailed(address indexed indexAddress, bytes reasonData);

event NewIndexWeightsProposed(
    address indexed indexAddress,
    address indexed assetManager,
    uint128 oldWeightAsset0,
    uint128 oldWeightAsset1,
    uint128 newWeightAsset0,
    uint128 newWeightAsset1,
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
    bytes reasonData
);

event WeightUpdateExecuted(address indexed indexAddress);

event WeightUpdateCancelled(
    address indexed indexAddress,
    address indexed assetManager
);

event WeightUpdateFailed(address indexed indexAddress, bytes reasonData);
