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
error IndexManager__InvalidPriceFeedAddress();
error IndexManager__NotIndexInitialized();
error IndexManager__InvalidPercentage();
error IndexManager__RouterAddressNotSet();
