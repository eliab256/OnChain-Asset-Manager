// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error IndexManager__InvalidIndexAssetsAddress();
error IndexManager__InvalidIndexAssetsAmount();
error IndexManager__InvalidIndexAssetsPercentages();
error IndexManager__UnderlyingAssetNotERC20();
error IndexManager__PriceFeedNotAvailable(address priceFeed);
error IndexManager__IndexAlreadyExists(address index);
error IndexManager__IsNotIndex();
error IndexManager__IndexAlreadyInitialized();
error IndexManager__NotIndexInitialized(address index);
error IndexManager__InvalidPercentage();
error IndexManager__InvalidFeePercentage();
error IndexManager__UsdcCannotBeIndexAsset();
error IndexManager__PriceFeedNotRegistered(address asset);
// Raised by the constructor when a SwapManager, PriceFeedManager or Router implementation has no code.
error IndexManager__InvalidImplementation(address implementation);
error IndexManager__ZeroAddress();
// Raised by the constructor when the IndexFactory has no code.
error IndexManager__InvalidIndexFactory(address indexFactory);
