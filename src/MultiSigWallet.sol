// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IMultiSigWallet} from "./Interface/IMultiSigWallet.sol";
import "./events/MultiSigWalletEvents.sol";
import "./errors/MultiSigWalletErrors.sol";
import {Transaction} from "./types.sol";

contract MultiSigWallet is IMultiSigWallet,EIP712 {
    using ECDSA for bytes32;

    bytes32 constant CONFIRM_TYPEHASH =
        keccak256("Confirm(uint256 txId,address wallet,uint256 nonce)");

    // =========================================================================
    //  State
    // =========================================================================
    address[] private s_owners;
    mapping(address => bool) private s_isOwner;

    // owner => nonce (for replay protection in off-chain signatures)
    mapping(address => uint256) private s_nonces;
    uint256 private immutable i_requiredConfirmations;

    Transaction[] private s_transactions;

    /// @dev txId => owner => confirmed
    mapping(uint256 => mapping(address => bool)) private s_isConfirmed;

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
    constructor(
        address[] memory _owners,
        uint256 _required
    ) EIP712("MultiSigWallet", "1") {
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

    /**
     * @notice Confirm a transaction using an EIP-712 signature produced off-chain.
     * @param _txId       The transaction ID to confirm.
     * @param _signer     The address of the owner who signed.
     * @param _signature  The ECDSA signature (65 bytes) produced off-chain.
     */
    function confirmTransactionWithSig(
        uint256 _txId,
        address _signer,
        bytes calldata _signature
    ) external txExists(_txId) notExecuted(_txId) {
        // 1. Verify that the signer is an owner
        if (!s_isOwner[_signer]) revert MultiSig__NotOwner();

        // 2. Verify that they haven't already confirmed
        if (s_isConfirmed[_txId][_signer])
            revert MultiSig__TxAlreadyConfirmed();

        // 3. Reconstruct the EIP-712 digest
        bytes32 structHash = keccak256(
            abi.encode(
                CONFIRM_TYPEHASH,
                _txId,
                address(this),
                s_nonces[_signer]
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);

        // 4. Recover the signer and compare
        address recovered = digest.recover(_signature);
        if (recovered != _signer) revert MultiSig__InvalidSignature();

        // 5. Invalidate the nonce (replay protection)
        s_nonces[_signer]++;

        // 6. Record the confirmation
        Transaction storage txn = s_transactions[_txId];
        txn.confirmations += 1;
        s_isConfirmed[_txId][_signer] = true;

        emit TransactionConfirmed(_txId, _signer);
    }

    /**
     * @notice Returns the digest to be signed off-chain.
     * @dev Useful for the frontend to generate signatures.
     * @param _txId   The transaction ID to get the digest for.
     * @param _signer The address of the signer.
     * @return The EIP-712 digest ready to be signed.
     */
    function getConfirmDigest(
        uint256 _txId,
        address _signer
    ) external view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                CONFIRM_TYPEHASH,
                _txId,
                address(this),
                s_nonces[_signer]
            )
        );
        return _hashTypedDataV4(structHash);
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

    // =========================================================================
    //  Public Getters for State Variables
    // =========================================================================

    /**
     * @notice Get the address of an owner by index.
     * @param _index The index in the owners array.
     * @return The owner address at the given index.
     */
    function getOwnerAt(uint256 _index) external view returns (address) {
        return s_owners[_index];
    }

    /**
     * @notice Get the nonce for a given owner (for replay protection).
     * @param _owner The owner address.
     * @return The current nonce of the owner.
     */
    function getNonce(address _owner) external view returns (uint256) {
        return s_nonces[_owner];
    }

    /**
     * @notice Check if a transaction has been confirmed by a specific owner.
     * @param _txId The transaction ID.
     * @param _owner The owner address.
     * @return True if the owner has confirmed the transaction, false otherwise.
     */
    function isTransactionConfirmed(
        uint256 _txId,
        address _owner
    ) external view returns (bool) {
        return s_isConfirmed[_txId][_owner];
    }

    receive() external payable {}
}
