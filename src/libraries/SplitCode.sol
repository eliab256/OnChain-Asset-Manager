// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SplitCode__DataTooLarge, SplitCode__DeployFailed} from "../errors/SplitCodeErrors.sol";

/**
 * @title SplitCode
 * @notice Stores arbitrary bytes as the runtime code of a data contract (SSTORE2 style) and reads them back.
 * @dev The data contract runtime is `0x00 || data`: the leading STOP byte makes any call to it a no-op.
 */
library SplitCode {
    // EIP-170 maximum runtime code size, in bytes.
    uint256 internal constant MAX_CODE_SIZE = 24576;

    // Size, in bytes, of the leading STOP byte prepended to the stored data.
    uint256 internal constant DATA_OFFSET = 1;

    /**
     * @notice Deploys a data contract whose runtime code is `0x00 || _data`.
     * @dev Initcode = 12-byte constructor || 0x00 || _data. The constructor is
     *      PUSH2 len, DUP1, PUSH1 0x0C, PUSH1 0x00, CODECOPY, PUSH1 0x00, RETURN:
     *      it copies everything after itself to memory 0 and returns it as runtime code.
     *      Reverts with SplitCode__DataTooLarge if the runtime would exceed 24,576 bytes,
     *      or with SplitCode__DeployFailed if CREATE returns address(0).
     * @param _data The bytes to store.
     * @return pointer The address of the data contract.
     */
    function write(bytes memory _data) internal returns (address pointer) {
        uint256 runtimeSize = _data.length + DATA_OFFSET;
        if (runtimeSize > MAX_CODE_SIZE) {
            revert SplitCode__DataTooLarge(runtimeSize);
        }

        bytes memory initCode = abi.encodePacked(
            hex"61",
            uint16(runtimeSize),
            hex"80_60_0C_60_00_39_60_00_F3",
            hex"00",
            _data
        );

        assembly {
            pointer := create(0, add(initCode, 0x20), mload(initCode))
        }
        if (pointer == address(0)) revert SplitCode__DeployFailed();
    }

    /**
     * @notice Copies the data stored in a data contract into memory.
     * @dev Skips the leading STOP byte. The caller must have allocated at least `_size` bytes at `_destination`.
     * @param _pointer The data contract written by `write`.
     * @param _destination The memory offset to copy to.
     * @param _size The number of data bytes to copy (data length, STOP byte excluded).
     */
    function copyTo(
        address _pointer,
        uint256 _destination,
        uint256 _size
    ) internal view {
        assembly {
            extcodecopy(_pointer, _destination, DATA_OFFSET, _size)
        }
    }
}
