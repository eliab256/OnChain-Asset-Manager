// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error Index__AlreadyInitialized();
error Index__InvalidUnderlyingAmount();
error Index__NotInitialized();
error Index__DecimalsStandardLowerThanCurrent();
error Index__DecimalsNotCorrect();
error Index__TransferFailed(address token, uint256 amount);
error Index__ToleranceExceeded();
error Index__RebalanceNotNeeded();
error Index__InvalidWeight();
error Index__PendingWeightUpdate();
error Index__NotPendingWeightUpdate();
error Index__WeightUpdateExpired();
error Index__UnauthorizedCallback();
error Index__RebalanceSlippageTooHigh();
error Index__NoFeesToCollect();
/// @notice Thrown when a function restricted to the IndexManager is called by any other address (the index itself excluded).
error Index__CallerNotIndexManager();
/// @notice Thrown when mintShares or redeem is called by an address other than the shared Router proxy.
error Index__CallerNotRouter();
/// @notice Thrown when the constructor receives a zero IndexManager address.
error Index__ZeroAddress();
