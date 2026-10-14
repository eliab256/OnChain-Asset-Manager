// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseIndexFactoryTest} from "./BaseIndexFactory.t.sol";
import {IndexFactory} from "../../../src/IndexFactory.sol";
import {IndexFactory__EmptyCreationCode} from "../../../src/errors/IndexFactoryErrors.sol";
import {SplitCode__DataTooLarge} from "../../../src/errors/SplitCodeErrors.sol";

/**
 * @dev IndexFactory constructor (code splitting) and getIndexCreationCode (code reassembly).
 */
contract IndexFactoryConstructorTest is BaseIndexFactoryTest {
    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  getIndexCreationCode
    // =========================================================================

    function testGetIndexCreationCodeEqualsIndexCreationCode() public view {
        bytes memory stored = indexFactory.getIndexCreationCode();
        assertEq(stored.length, s_indexCreationCode.length, "length");
        assertEq(stored, s_indexCreationCode, "creation code");
    }

    function testFreshFactoryReturnsTheCodeItWasBuiltWith() public {
        IndexFactory freshFactory = new IndexFactory(s_indexCreationCode);
        assertEq(freshFactory.getIndexCreationCode(), s_indexCreationCode);
    }

    function testGetIndexCreationCodeWithOddLengthCode() public {
        // Odd length: the second half carries the extra byte.
        bytes memory code = _patternBytes(101);
        IndexFactory freshFactory = new IndexFactory(code);
        assertEq(freshFactory.getIndexCreationCode(), code);
    }

    function testGetIndexCreationCodeWithSingleByteCode() public {
        // sizeA == 0: the first data contract stores no data (runtime is the lone STOP byte).
        bytes memory code = _patternBytes(1);
        IndexFactory freshFactory = new IndexFactory(code);
        assertEq(freshFactory.getIndexCreationCode(), code);

        (address codeA, address codeB) = freshFactory.getCodePointers();
        assertEq(codeA.code, hex"00", "codeA runtime must be the STOP byte only");
        assertEq(codeB.code, abi.encodePacked(hex"00", code), "codeB runtime");
    }

    // =========================================================================
    //  constructor
    // =========================================================================

    function testConstructorRevertsWithEmptyCreationCode() public {
        vm.expectRevert(IndexFactory__EmptyCreationCode.selector);
        new IndexFactory("");
    }

    function testConstructorAcceptsCodeWithBothHalvesAtTheSizeLimit() public {
        // 2 * (MAX_CODE_SIZE - 1) bytes: each data contract runtime is exactly MAX_CODE_SIZE.
        bytes memory code = _patternBytes(2 * s_maxValidDataSize);
        IndexFactory freshFactory = new IndexFactory(code);

        (address codeA, address codeB) = freshFactory.getCodePointers();
        assertEq(codeA.code.length, s_maxCodeSize, "codeA at the limit");
        assertEq(codeB.code.length, s_maxCodeSize, "codeB at the limit");
        assertEq(
            keccak256(freshFactory.getIndexCreationCode()),
            keccak256(code),
            "reassembled code"
        );
    }

    function testConstructorRevertsIfAHalfExceedsTheSizeLimit() public {
        // 2 * (MAX_CODE_SIZE - 1) + 1 bytes: the second half gets MAX_CODE_SIZE bytes,
        // so its runtime (STOP byte + data) is MAX_CODE_SIZE + 1.
        bytes memory code = _patternBytes(2 * s_maxValidDataSize + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SplitCode__DataTooLarge.selector,
                s_maxCodeSize + 1
            )
        );
        new IndexFactory(code);
    }
}
