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
error IndexManager__RouterAddressNotSet();
error IndexManager__InvalidSwapManagerImplementation();
error IndexManager__SwapManagerUpgradePending();
error IndexManager__NoPendingSwapManagerUpgrade();
error IndexManager__SwapManagerUpgradeExpired();
error IndexManager__InvalidFeePercentage();
error IndexManager__UsdcCannotBeIndexAsset();
error IndexManager__InvalidPriceFeedManagerImplementation();
error IndexManager__PriceFeedManagerUpgradePending();
error IndexManager__NoPendingPriceFeedManagerUpgrade();
error IndexManager__PriceFeedManagerUpgradeExpired();
error IndexManager__PriceFeedNotRegistered(address asset);
error IndexManager__IndexDeployFailed();
error IndexManager__InvalidAssetDecimals(address asset);
