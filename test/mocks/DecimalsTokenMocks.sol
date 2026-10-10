// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev ERC20 whose `decimals()` always reverts, like a token with broken or missing metadata
 *      behind a proxy. `symbol()` works, so only the decimals validation can reject it.
 */
contract DecimalsRevertingTokenMock is ERC20 {
    error DecimalsRevertingTokenMock__DecimalsUnavailable();

    constructor() ERC20("Decimals Reverting", "DREV") {}

    function decimals() public pure override returns (uint8) {
        revert DecimalsRevertingTokenMock__DecimalsUnavailable();
    }
}

/**
 * @dev Token exposing `symbol()` but no `decimals()` function at all (and no fallback),
 *      so a `decimals()` call fails at the dispatcher.
 */
contract NoDecimalsTokenMock {
    function symbol() external pure returns (string memory) {
        return "NODEC";
    }

    function name() external pure returns (string memory) {
        return "No Decimals";
    }
}

/**
 * @dev Token whose `decimals()` succeeds but returns a single byte instead of a 32-byte word,
 *      like a non-compliant token with a hand-written return. `symbol()` works.
 */
contract ShortDecimalsReturnTokenMock {
    uint8 private constant TOKEN_DECIMALS = 18;

    function symbol() external pure returns (string memory) {
        return "SHORT";
    }

    function decimals() external pure {
        assembly {
            mstore(0x00, TOKEN_DECIMALS)
            // return only the last byte of the word
            return(0x1f, 0x01)
        }
    }
}

/**
 * @dev ERC20 whose `decimals()` returns a valid value to callers with deployed code and reverts
 *      for callers without code — i.e. a contract still running its constructor.
 *      It passes the IndexManager validation (caller = IndexManager) and then makes the Index
 *      constructor revert (caller = the Index under construction), so create2 returns address(0).
 *      A storage counter cannot be used: both calls are STATICCALLs (view), so no state can change.
 */
contract ConstructorDecimalsRevertingTokenMock is ERC20 {
    error ConstructorDecimalsRevertingTokenMock__CallerUnderConstruction();

    uint8 private constant TOKEN_DECIMALS = 18;

    constructor() ERC20("Constructor Decimals Reverting", "CDREV") {}

    function decimals() public view override returns (uint8) {
        if (msg.sender.code.length == 0) {
            revert ConstructorDecimalsRevertingTokenMock__CallerUnderConstruction();
        }
        return TOKEN_DECIMALS;
    }
}
