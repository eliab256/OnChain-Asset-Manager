// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {SplitCodeHarness} from "../../mocks/SplitCodeHarness.sol";
import {
    SplitCode__DataTooLarge,
    SplitCode__DeployFailed
} from "../../../src/errors/SplitCodeErrors.sol";

/**
 * @dev SplitCode library (write / copyTo) through SplitCodeHarness.
 */
contract SplitCodeTest is Test {
    SplitCodeHarness internal s_harness;

    /// Data size whose code deposit (200 gas/byte) cannot fit in DEPLOY_FAILED_GAS_LIMIT.
    uint256 internal constant DEPLOY_FAILED_DATA_SIZE = 10_000;
    /// Gas forwarded to write(): enough to build the initcode, not enough for the code deposit.
    uint256 internal constant DEPLOY_FAILED_GAS_LIMIT = 500_000;
    uint256 internal constant SMALL_DATA_SIZE = 33;

    uint256 internal s_maxCodeSize;
    uint256 internal s_dataOffset;
    uint256 internal s_maxValidDataSize;
    uint256 internal s_invalidDataSize;

    function setUp() public {
        s_harness = new SplitCodeHarness();
        s_maxCodeSize = s_harness.exposed_maxCodeSize();
        s_dataOffset = s_harness.exposed_dataOffset();
        s_maxValidDataSize = s_maxCodeSize - s_dataOffset;
        s_invalidDataSize = s_maxValidDataSize + 1;
    }

    // =========================================================================
    //  write
    // =========================================================================

    function testWriteStoresStopByteFollowedByData() public {
        bytes memory data = _patternBytes(SMALL_DATA_SIZE);
        address pointer = s_harness.exposed_write(data);
        assertEq(pointer.code, abi.encodePacked(hex"00", data));
    }

    function testWriteEmptyData() public {
        address pointer = s_harness.exposed_write("");
        assertEq(pointer.code, hex"00", "runtime must be the STOP byte only");
    }

    function testWriteAcceptsDataAtTheSizeLimit() public {
        bytes memory data = _patternBytes(s_maxValidDataSize);
        address pointer = s_harness.exposed_write(data);
        assertEq(pointer.code.length, s_maxCodeSize);
        assertEq(keccak256(s_harness.exposed_read(pointer, data.length)), keccak256(data));
    }

    function testWriteRevertsIfDataTooLarge() public {
        bytes memory data = _patternBytes(s_invalidDataSize);
        vm.expectRevert(
            abi.encodeWithSelector(
                SplitCode__DataTooLarge.selector,
                s_invalidDataSize + s_dataOffset
            )
        );
        s_harness.exposed_write(data);
    }

    function testWriteRevertsIfCreateFails() public {
        // CREATE runs out of gas on the code deposit and returns address(0);
        // the 1/64 kept by the caller is enough to revert with the custom error.
        bytes memory data = _patternBytes(DEPLOY_FAILED_DATA_SIZE);
        vm.expectRevert(SplitCode__DeployFailed.selector);
        s_harness.exposed_write{gas: DEPLOY_FAILED_GAS_LIMIT}(data);
    }

    function testWriteDeploysANewPointerEachTime() public {
        bytes memory data = _patternBytes(SMALL_DATA_SIZE);
        address first = s_harness.exposed_write(data);
        address second = s_harness.exposed_write(data);
        assertTrue(first != second);
    }

    // =========================================================================
    //  copyTo
    // =========================================================================

    function testCopyToSkipsTheStopByte() public {
        bytes memory data = _patternBytes(SMALL_DATA_SIZE);
        address pointer = s_harness.exposed_write(data);
        assertEq(s_harness.exposed_read(pointer, data.length), data);
    }

    function testCopyToPartialSize() public {
        bytes memory data = _patternBytes(SMALL_DATA_SIZE);
        address pointer = s_harness.exposed_write(data);
        bytes memory head = s_harness.exposed_read(pointer, 1);
        assertEq(head.length, 1);
        assertEq(uint8(head[0]), uint8(data[0]));
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _patternBytes(uint256 _length) internal pure returns (bytes memory data) {
        data = new bytes(_length);
        for (uint256 i = 0; i < _length; i++) {
            data[i] = bytes1(uint8(i % 251) + 1);
        }
    }
}
