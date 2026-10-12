// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PriceFeedManager} from "../../src/PriceFeedManager.sol";

/**
 * @dev PriceFeedManager V2 used to test UUPS upgrades. Inherits the storage layout and logic unchanged and adds:
 *      - `version()` to prove the proxy now delegates to the new implementation;
 *      - `initializeV2(marker)` (reinitializer(2)) writing a marker into its own ERC-7201 namespace, used as
 *        upgrade calldata to prove the `data` of a timelocked upgrade is executed on the proxy.
 */
contract PriceFeedManagerV2Mock is PriceFeedManager {
    /// @custom:storage-location erc7201:onchainassetmanager.storage.PriceFeedManagerV2Mock
    struct PriceFeedManagerV2MockStorage {
        uint256 marker;
    }

    bytes32 private constant V2_MOCK_STORAGE_LOCATION =
        keccak256(
            abi.encode(
                uint256(keccak256("onchainassetmanager.storage.PriceFeedManagerV2Mock")) -
                    1
            )
        ) & ~bytes32(uint256(0xff));

    function initializeV2(uint256 _marker) external reinitializer(2) {
        _getV2MockStorage().marker = _marker;
    }

    function version() external pure returns (uint256) {
        return 2;
    }

    function getV2Marker() external view returns (uint256) {
        return _getV2MockStorage().marker;
    }

    function _getV2MockStorage()
        private
        pure
        returns (PriceFeedManagerV2MockStorage storage $)
    {
        bytes32 location = V2_MOCK_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }
}
