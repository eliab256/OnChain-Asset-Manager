// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error Index__AssetNotSupported();
error Index__PriceFeedNotAvailable();
error Index__PriceFeedRoundStale();
error Index__PriceIsStale();
error Index__AlreadyInitialized();
error Index__InvalidUnderlyingAmount();
error Index__NotInitialized();
error Index__DecimalsStandardLowerThanCurrent();
error Index__DecimalsNotCorrect();
error Index__TransferFailed(address token, uint256 amount);
error Index__ToleranceExceeded();
error Index__RebalanceNotNeeded();
