// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Contract exposing the index token getters (getAsset0 / getAsset1 / getUsdc) but reverting
 *      on every call. Used to prove the SwapManager maps a reverting getter to `NotAnIndex`.
 */
contract RevertingIndexGettersMock {
    error RevertingIndexGettersMock__GetterReverted();

    function getAsset0() external pure returns (address) {
        revert RevertingIndexGettersMock__GetterReverted();
    }

    function getAsset1() external pure returns (address) {
        revert RevertingIndexGettersMock__GetterReverted();
    }

    function getUsdc() external pure returns (address) {
        revert RevertingIndexGettersMock__GetterReverted();
    }
}

/**
 * @dev Contract exposing the index token getters with the same selectors as `IIndex`, but returning
 *      a raw 32-byte word instead of an address. Setting a word above type(uint160).max ("dirty" upper
 *      bits) simulates a getter whose return value is not a valid ABI-encoded address.
 */
contract RawWordIndexGettersMock {
    uint256 private immutable i_asset0Word;
    uint256 private immutable i_asset1Word;
    uint256 private immutable i_usdcWord;

    constructor(uint256 _asset0Word, uint256 _asset1Word, uint256 _usdcWord) {
        i_asset0Word = _asset0Word;
        i_asset1Word = _asset1Word;
        i_usdcWord = _usdcWord;
    }

    function getAsset0() external view returns (uint256) {
        return i_asset0Word;
    }

    function getAsset1() external view returns (uint256) {
        return i_asset1Word;
    }

    function getUsdc() external view returns (uint256) {
        return i_usdcWord;
    }
}
