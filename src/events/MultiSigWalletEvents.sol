// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @notice Emitted once at deployment with the initial signer set.
 * @param owners Addresses of the signers.
 * @param requiredConfirmations Number of confirmations required to execute a transaction.
 */
event MultiSigInitialized(address[] owners, uint256 requiredConfirmations);

/**
 * @notice Emitted when the wallet receives ETH through a plain transfer.
 * @dev Not emitted for zero-value transfers, which still succeed without a log.
 * @param sender Address that sent the ETH.
 * @param value Amount received, in wei.
 */
event Deposit(address indexed sender, uint256 value);

/**
 * @notice Emitted when an owner submits a new transaction proposal.
 * @param txId Id of the submitted transaction.
 * @param proposer Owner that submitted the transaction.
 * @param target Contract that will be called.
 * @param value ETH value to send, in wei.
 * @param data Calldata that will be sent to the target.
 */
event TransactionSubmitted(
    uint256 indexed txId,
    address indexed proposer,
    address indexed target,
    uint256 value,
    bytes data
);

/**
 * @notice Emitted when an owner confirms a transaction, directly or through an off-chain signature.
 * @param txId Id of the confirmed transaction.
 * @param owner Owner whose confirmation was recorded.
 */
event TransactionConfirmed(uint256 indexed txId, address indexed owner);

/**
 * @notice Emitted when an owner revokes a previous confirmation.
 * @param txId Id of the transaction.
 * @param owner Owner that revoked the confirmation.
 */
event ConfirmationRevoked(uint256 indexed txId, address indexed owner);

/**
 * @notice Emitted when a transaction is executed.
 * @param txId Id of the executed transaction.
 * @param executor Address that triggered the execution.
 */
event TransactionExecuted(uint256 indexed txId, address indexed executor);
