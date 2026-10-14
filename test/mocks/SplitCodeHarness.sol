// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SplitCode} from "../../src/libraries/SplitCode.sol";

/**
 * @dev Test harness exposing the internal SplitCode library functions as external calls,
 *      so their reverts can be asserted with vm.expectRevert.
 */
contract SplitCodeHarness {
    function exposed_maxCodeSize() external pure returns (uint256) {
        return SplitCode.MAX_CODE_SIZE;
    }

    function exposed_dataOffset() external pure returns (uint256) {
        return SplitCode.DATA_OFFSET;
    }

    function exposed_write(bytes memory _data) external returns (address) {
        return SplitCode.write(_data);
    }

    function exposed_read(
        address _pointer,
        uint256 _size
    ) external view returns (bytes memory data) {
        data = new bytes(_size);
        uint256 destination;
        assembly {
            destination := add(data, 0x20)
        }
        SplitCode.copyTo(_pointer, destination, _size);
    }
}
