// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Minimal stand-in for an Index exposing only the token getters the SwapManager reads
 *      (getAsset0 / getAsset1 / getUsdc) to compute the pair every route must connect.
 *      Lets harness tests register routes on a contract that is not a full Index.
 */
contract IndexTokensMock {
    address private immutable i_asset0;
    address private immutable i_asset1;
    address private immutable i_usdc;

    constructor(address _asset0, address _asset1, address _usdc) {
        i_asset0 = _asset0;
        i_asset1 = _asset1;
        i_usdc = _usdc;
    }

    function getAsset0() external view returns (address) {
        return i_asset0;
    }

    function getAsset1() external view returns (address) {
        return i_asset1;
    }

    function getUsdc() external view returns (address) {
        return i_usdc;
    }
}
