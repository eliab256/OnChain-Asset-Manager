// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Transaction} from "../types.sol";

interface IMultiSigWallet {
    // =========================================================================
    //  External Functions
    // =========================================================================

    function submitTransaction(
        address _target,
        uint256 _value,
        bytes calldata _data
    ) external returns (uint256 txId);

    function confirmTransaction(uint256 _txId) external;

    function executeTransaction(uint256 _txId) external;

    /**
     * @notice Revoke a previously given confirmation.
     * @dev Also increments the caller's confirm nonce for _txId, so any confirmation
     *      signature collected before the revoke can no longer be replayed.
     * @param _txId The transaction id to revoke confirmation for.
     */
    function revokeConfirmation(uint256 _txId) external;

    /**
     * @notice Confirm a transaction on behalf of an owner using an EIP-712 signature produced off-chain.
     * @dev The signer signs the struct
     *      Confirm(uint256 txId,address target,uint256 value,bytes32 dataHash,uint256 nonce)
     *      under the domain EIP712("MultiSigWallet", "2") of this contract, where target, value and
     *      dataHash = keccak256(data) are read from the stored transaction and nonce is
     *      getConfirmNonce(_txId, _signer). The signature is therefore bound to the transaction
     *      content and is independent from signatures for other txIds. The nonce is incremented
     *      on success. Callable by anyone. Reverts if the tx does not exist or is executed, if the
     *      signer is not an owner or already confirmed, or if the signature does not recover to _signer.
     * @param _txId The transaction ID to confirm.
     * @param _signer The address of the owner who signed.
     * @param _signature The ECDSA signature (65 bytes) produced off-chain.
     */
    function confirmTransactionWithSig(
        uint256 _txId,
        address _signer,
        bytes calldata _signature
    ) external;

    /**
     * @notice Returns the EIP-712 digest an owner must sign to confirm a transaction off-chain.
     * @dev Digest of Confirm(txId, target, value, keccak256(data), getConfirmNonce(_txId, _signer))
     *      built from the stored transaction. Reverts with MultiSig__TxDoesNotExist for an unknown _txId.
     * @param _txId The transaction ID to get the digest for.
     * @param _signer The address of the owner who will sign.
     * @return The EIP-712 digest ready to be signed.
     */
    function getConfirmDigest(
        uint256 _txId,
        address _signer
    ) external view returns (bytes32);

    // =========================================================================
    //  View / Getters
    // =========================================================================

    function getTransactionCount() external view returns (uint256);

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
        );

    function getOwners() external view returns (address[] memory);

    function isOwner(address _addr) external view returns (bool);

    function getRequiredConfirmations() external view returns (uint256);

    function getOwnerAt(uint256 _index) external view returns (address);

    /**
     * @notice Returns the current confirm nonce of an owner for a given transaction.
     * @dev Incremented each time a confirmation signature is consumed and on revokeConfirmation.
     * @param _txId The transaction ID.
     * @param _owner The owner address.
     * @return The nonce to include in the next Confirm signature for (_txId, _owner).
     */
    function getConfirmNonce(
        uint256 _txId,
        address _owner
    ) external view returns (uint256);

    function isTransactionConfirmed(
        uint256 _txId,
        address _owner
    ) external view returns (bool);
}
