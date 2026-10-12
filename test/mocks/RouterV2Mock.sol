// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Router} from "../../src/Router.sol";

/**
 * @dev Router V2 used to test UUPS upgrades. Inherits the Router storage layout and logic unchanged and adds:
 *      - `version()` to prove the proxy now delegates to the new implementation;
 *      - `initializeV2(marker)` (reinitializer(2)) writing a marker into its own ERC-7201 namespace, used as
 *        upgrade calldata to prove the `data` of a proposal is executed and lands outside the Router namespace.
 */
contract RouterV2Mock is Router {
    /// @custom:storage-location erc7201:onchainassetmanager.storage.RouterV2Mock
    struct RouterV2MockStorage {
        uint256 marker;
    }

    // keccak256(abi.encode(uint256(keccak256("onchainassetmanager.storage.RouterV2Mock")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ROUTER_V2_MOCK_STORAGE_LOCATION =
        keccak256(
            abi.encode(
                uint256(keccak256("onchainassetmanager.storage.RouterV2Mock")) -
                    1
            )
        ) & ~bytes32(uint256(0xff));

    function initializeV2(uint256 _marker) external reinitializer(2) {
        _getRouterV2MockStorage().marker = _marker;
    }

    function version() external pure returns (uint256) {
        return 2;
    }

    function getV2Marker() external view returns (uint256) {
        return _getRouterV2MockStorage().marker;
    }

    function _getRouterV2MockStorage()
        private
        pure
        returns (RouterV2MockStorage storage $)
    {
        bytes32 location = ROUTER_V2_MOCK_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }
}
