// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library RevertData {
    // Selector of Error(string), the revert data of require(cond, "msg") and revert("msg"): 0x08c379a0.
    bytes4 internal constant ERROR_STRING_SELECTOR =
        bytes4(keccak256("Error(string)"));
    // Selector of Panic(uint256), the revert data of failed asserts, arithmetic overflows and similar: 0x4e487b71.
    bytes4 internal constant PANIC_SELECTOR = bytes4(keccak256("Panic(uint256)"));

    /**
     * @notice Tells whether the revert data of a failed call is a common error rather than a custom error.
     * @dev Common errors are: revert data shorter than 4 bytes (empty when the call runs out of gas or on a bare
     *      revert()), Error(string) (require/revert with a message) and Panic(uint256) (assert, overflow, division by zero).
     *      Any other revert data of at least 4 bytes is treated as a custom error.
     * @param _reasonData The raw revert data returned by the call.
     * @return True if `_reasonData` is a common error, false if it is a custom error.
     */
    function isCommonError(
        bytes memory _reasonData
    ) internal pure returns (bool) {
        if (_reasonData.length < 4) return true;
        bytes4 selector = bytes4(_reasonData);
        return selector == ERROR_STRING_SELECTOR || selector == PANIC_SELECTOR;
    }
}
