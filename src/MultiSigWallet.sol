// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./events/MultiSigEvents.sol";
import "./errors/MultiSigErrors.sol";
import {Transaction} from "./types.sol";

contract MultiSigWallet {
    // =========================================================================
    //  State
    // =========================================================================
    address[] public s_owners;
    mapping(address => bool) public s_isOwner;
    uint256 public immutable i_requiredConfirmations;

    Transaction[] public s_transactions;

    ///txId => owner => confirmed
    mapping(uint256 => mapping(address => bool)) public s_isConfirmed;

    // =========================================================================
    //  Modifiers
    // =========================================================================
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    modifier txExists(uint256 _txId) {
        _checkTxExists(_txId);
        _;
    }

    modifier notExecuted(uint256 _txId) {
        _checkNotExecuted(_txId);
        _;
    }

    modifier notConfirmed(uint256 _txId) {
        _checkNotConfirmed(_txId);
        _;
    }

    // =========================================================================
    //  Constructor
    // =========================================================================
    /**
     * @param _owners  Array of signer addresses.
     * @param _required  Number of confirmations required to execute a tx.
     */
    constructor(address[] memory _owners, uint256 _required) {
        if (_owners.length == 0 || _required == 0 || _required > _owners.length)
            revert MultiSig__InvalidRequirement();

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            if (owner == address(0)) revert MultiSig__ZeroAddress();
            if (s_isOwner[owner]) revert MultiSig__OwnerNotUnique();

            s_isOwner[owner] = true;
            s_owners.push(owner);
        }

        i_requiredConfirmations = _required;
    }

    // =========================================================================
    //  External functions
    // =========================================================================

    /**
     * @notice Submit a new transaction proposal.
     * @param _target  The contract to call.
     * @param _value   ETH value to send (typically 0).
     * @param _data    The calldata (e.g., abi.encodeWithSelector(...)).
     * @return txId    The id of the submitted transaction.
     */
    function submitTransaction(
        address _target,
        uint256 _value,
        bytes calldata _data
    ) external onlyOwner returns (uint256 txId) {
        txId = s_transactions.length;

        s_transactions.push(
            Transaction({
                target: _target,
                value: _value,
                data: _data,
                executed: false,
                confirmations: 0
            })
        );

        emit TransactionSubmitted(txId, msg.sender, _target, _value, _data);
    }

    /**
     * @notice Confirm a pending transaction.
     * @param _txId  The transaction id to confirm.
     */
    function confirmTransaction(
        uint256 _txId
    )
        external
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
        notConfirmed(_txId)
    {
        Transaction storage txn = s_transactions[_txId];
        txn.confirmations += 1;
        s_isConfirmed[_txId][msg.sender] = true;

        emit TransactionConfirmed(_txId, msg.sender);
    }

    /**
     * @notice Execute a transaction once enough confirmations are reached.
     * @param _txId  The transaction id to execute.
     */
    function executeTransaction(
        uint256 _txId
    ) external onlyOwner txExists(_txId) notExecuted(_txId) {
        Transaction storage txn = s_transactions[_txId];

        if (txn.confirmations < i_requiredConfirmations)
            revert MultiSig__ConfirmationsNotMet();

        txn.executed = true;

        (bool success, ) = txn.target.call{value: txn.value}(txn.data);
        if (!success) revert MultiSig__TxFailed();

        emit TransactionExecuted(_txId, msg.sender);
    }

    /**
     * @notice Revoke a previously given confirmation.
     * @param _txId  The transaction id to revoke confirmation for.
     */
    function revokeConfirmation(
        uint256 _txId
    ) external onlyOwner txExists(_txId) notExecuted(_txId) {
        if (!s_isConfirmed[_txId][msg.sender])
            revert MultiSig__TxNotConfirmed();

        Transaction storage txn = s_transactions[_txId];
        txn.confirmations -= 1;
        s_isConfirmed[_txId][msg.sender] = false;

        emit ConfirmationRevoked(_txId, msg.sender);
    }

    // =========================================================================
    //  Internal validation functions
    // =========================================================================
    function _checkOwner() internal view {
        if (!s_isOwner[msg.sender]) revert MultiSig__NotOwner();
    }

    function _checkTxExists(uint256 _txId) internal view {
        if (_txId >= s_transactions.length) revert MultiSig__TxDoesNotExist();
    }

    function _checkNotExecuted(uint256 _txId) internal view {
        if (s_transactions[_txId].executed)
            revert MultiSig__TxAlreadyExecuted();
    }

    function _checkNotConfirmed(uint256 _txId) internal view {
        if (s_isConfirmed[_txId][msg.sender])
            revert MultiSig__TxAlreadyConfirmed();
    }

    // =========================================================================
    //  View / Getters
    // =========================================================================

    function getTransactionCount() external view returns (uint256) {
        return s_transactions.length;
    }

    function getTransaction(
        uint256 _txId
    )
        external
        view
        returns (
            address target,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 confirmations
        )
    {
        Transaction storage txn = s_transactions[_txId];
        return (
            txn.target,
            txn.value,
            txn.data,
            txn.executed,
            txn.confirmations
        );
    }

    function getOwners() external view returns (address[] memory) {
        return s_owners;
    }

    function isOwner(address _addr) external view returns (bool) {
        return s_isOwner[_addr];
    }

    function getRequiredConfirmations() external view returns (uint256) {
        return i_requiredConfirmations;
    }

    receive() external payable {}
}
