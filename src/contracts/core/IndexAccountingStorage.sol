// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IndexAccountingStorage
 * @notice ERC-7201 namespaced storage for the Index's mutable accounting state: target/pending
 *         weights, reserves, and fees. Layout mirrors the packing of the original linear storage
 *         layout so the single-SLOAD assembly reads/writes stay valid (weight0/weight1 share a
 *         slot, asset0Reserve/asset1Reserve share a slot, totalFees/feePercentage/initialized
 *         share a slot).
 */
library IndexAccountingStorage {
    struct Layout {
        uint128 weight0;
        uint128 weight1;
        uint128 pendingWeight0;
        uint128 pendingWeight1;
        uint256 weightUpdateExecutableAt;
        uint128 asset0Reserve; // token decimals of asset0
        uint128 asset1Reserve; // token decimals of asset1
        uint128 totalFees; // usdc decimals
        uint32 feePercentage;
        bool initialized;
    }

    // keccak256(abi.encode(uint256(keccak256("onchainassetmanager.storage.IndexAccounting")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0xecb0129d2847ff0ccd7a2ec58779f7b0b40e417ce1fe1689d561aa484a3f6700;

    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}