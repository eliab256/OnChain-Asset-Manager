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

    function revokeConfirmation(uint256 _txId) external;

    function confirmTransactionWithSig(
        uint256 _txId,
        address _signer,
        bytes calldata _signature
    ) external;

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

    function getNonce(address _owner) external view returns (uint256);

    function isTransactionConfirmed(
        uint256 _txId,
        address _owner
    ) external view returns (bool);
}
