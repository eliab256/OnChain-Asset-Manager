// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Deploys arbitrary initcode with CREATE and bubbles up the constructor revert data,
 *      so a test can assert the exact custom error raised by a constructor without encoding
 *      a long `new Contract(...)` expression (stack-too-deep with the optimizer off).
 */
contract RawCreateDeployerMock {
    function deploy(bytes memory _initCode) external returns (address deployed) {
        assembly {
            deployed := create(0, add(_initCode, 0x20), mload(_initCode))
            if iszero(deployed) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }
}
