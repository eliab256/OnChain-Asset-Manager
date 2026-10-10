// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Exposes `proxiableUUID()` but returns a slot different from the ERC-1967 implementation slot,
 *      reproducing a non-compatible UUPS implementation.
 */
contract ProxiableWrongUuidMock {
    bytes32 public constant WRONG_UUID = bytes32(uint256(1));

    function proxiableUUID() external pure returns (bytes32) {
        return WRONG_UUID;
    }
}
