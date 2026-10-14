// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseIndexFactoryTest} from "./BaseIndexFactory.t.sol";

/**
 * @dev getCodePointers and the two data contracts holding the halves of the Index creation code.
 */
contract IndexFactoryCodePointersTest is BaseIndexFactoryTest {
    uint8 internal constant STOP_OPCODE = 0x00;
    bytes internal constant ARBITRARY_CALLDATA = hex"deadbeef0000000000000000000000000000000000000000000000000000000000000001";

    address internal s_codeA;
    address internal s_codeB;

    function setUp() public override {
        super.setUp();
        (s_codeA, s_codeB) = indexFactory.getCodePointers();
    }

    // =========================================================================
    //  getCodePointers
    // =========================================================================

    function testCodePointersAreDistinctContracts() public view {
        assertTrue(s_codeA != address(0), "codeA must be set");
        assertTrue(s_codeB != address(0), "codeB must be set");
        assertTrue(s_codeA != s_codeB, "pointers must differ");
        assertTrue(s_codeA != address(indexFactory), "codeA is not the factory");
        assertTrue(s_codeB != address(indexFactory), "codeB is not the factory");
    }

    function testCodeARuntimeIsStopByteFollowedByFirstHalf() public view {
        bytes memory runtime = s_codeA.code;
        assertEq(runtime.length, s_sizeA + s_dataOffset, "length must be half + 1");
        assertEq(uint8(runtime[0]), STOP_OPCODE, "first byte must be STOP");
        assertEq(
            _slice(runtime, s_dataOffset, s_sizeA),
            _slice(s_indexCreationCode, 0, s_sizeA),
            "data must be the first half"
        );
    }

    function testCodeBRuntimeIsStopByteFollowedBySecondHalf() public view {
        bytes memory runtime = s_codeB.code;
        assertEq(runtime.length, s_sizeB + s_dataOffset, "length must be half + 1");
        assertEq(uint8(runtime[0]), STOP_OPCODE, "first byte must be STOP");
        assertEq(
            _slice(runtime, s_dataOffset, s_sizeB),
            _slice(s_indexCreationCode, s_sizeA, s_sizeB),
            "data must be the second half"
        );
    }

    function testHalvesAreWithinTheEip170Limit() public view {
        assertLe(s_codeA.code.length, s_maxCodeSize, "codeA within EIP-170");
        assertLe(s_codeB.code.length, s_maxCodeSize, "codeB within EIP-170");
    }

    // =========================================================================
    //  direct calls to the data contracts
    // =========================================================================

    function testDirectCallToCodeASucceedsAndDoesNothing() public {
        _assertDirectCallIsNoOp(s_codeA);
    }

    function testDirectCallToCodeBSucceedsAndDoesNothing() public {
        _assertDirectCallIsNoOp(s_codeB);
    }

    function _assertDirectCallIsNoOp(address _pointer) internal {
        bytes32 codeHashBefore = _pointer.codehash;
        bytes32 slot0Before = vm.load(_pointer, bytes32(0));
        uint256 balanceBefore = _pointer.balance;
        bytes memory creationCodeBefore = indexFactory.getIndexCreationCode();

        vm.recordLogs();
        vm.prank(s_attacker);
        (bool emptyOk, bytes memory emptyRet) = _pointer.call("");
        vm.prank(s_attacker);
        (bool dataOk, bytes memory dataRet) = _pointer.call(ARBITRARY_CALLDATA);

        assertTrue(emptyOk, "empty call must succeed");
        assertEq(emptyRet.length, 0, "empty call must return no data");
        assertTrue(dataOk, "call with data must succeed");
        assertEq(dataRet.length, 0, "call with data must return no data");
        assertEq(vm.getRecordedLogs().length, 0, "no log must be emitted");

        assertEq(_pointer.codehash, codeHashBefore, "code must not change");
        assertEq(vm.load(_pointer, bytes32(0)), slot0Before, "storage must not change");
        assertEq(_pointer.balance, balanceBefore, "balance must not change");
        assertEq(
            indexFactory.getIndexCreationCode(),
            creationCodeBefore,
            "factory code must not change"
        );
    }
}
