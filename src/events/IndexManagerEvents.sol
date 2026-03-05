// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


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
    event IndexRebalanced(
        address indexed indexAddress,
        address indexed rebalancer
    );
    event IndexWeightsChanged(
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