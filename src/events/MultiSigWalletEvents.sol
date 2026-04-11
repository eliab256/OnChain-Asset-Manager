// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

event TransactionSubmitted(
    uint256 indexed txId,
    address indexed proposer,
    address indexed target,
    uint256 value,
    bytes data
);
event TransactionConfirmed(uint256 indexed txId, address indexed owner);
event ConfirmationRevoked(uint256 indexed txId, address indexed owner);
event TransactionExecuted(uint256 indexed txId, address indexed executor);
