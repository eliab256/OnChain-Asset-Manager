// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error Router__InvalidAmounts();
error Router__InvalidIndexAddress();
error Router__CannotSpecifyBothAmounts();
error Router__InvalidTolerance();
error Router__InsufficientUsdcBalance(uint256 userBalance, uint256 requiredAmount);
error Router__InsufficientSharesBalance(uint256 userBalance, uint256 requiredAmount);   