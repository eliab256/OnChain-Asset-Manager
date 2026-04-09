// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC1643 {
    event DocumentUpdated(
        bytes32 indexed _name,
        string _uri,
        bytes32 _documentHash
    );
    event DocumentRemoved(bytes32 indexed _name);

    function setDocument(
        bytes32 _name,
        string calldata _uri,
        bytes32 _documentHash
    ) external;

    function removeDocument(bytes32 _name) external;

    function getDocument(bytes32 _name)
        external
        view
        returns (string memory, bytes32, uint256);

    function getAllDocuments() external view returns (bytes32[] memory);
}