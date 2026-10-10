// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error PriceFeedManager__CallerNotAssetManager();
error PriceFeedManager__InvalidAsset();
error PriceFeedManager__InvalidPriceFeed(address feed);
error PriceFeedManager__InvalidMaxDelay();
error PriceFeedManager__PriceFeedAlreadySet(address asset);
error PriceFeedManager__PriceFeedNotSet(address asset);
error PriceFeedManager__SamePriceFeedConfig();
error PriceFeedManager__PriceFeedUpdatePending();
error PriceFeedManager__NoPendingPriceFeedUpdate();
error PriceFeedManager__PriceFeedUpdateExpired();
error PriceFeedManager__PriceFeedNotAvailable();
error PriceFeedManager__PriceFeedRoundStale();
error PriceFeedManager__PriceIsStale();
