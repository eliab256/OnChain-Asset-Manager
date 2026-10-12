// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IUpgraderAuth} from "./Interface/IUpgraderAuth.sol";
import {
    UpgraderAuth__ZeroAddress,
    UpgraderAuth__Unauthorized
} from "./errors/UpgraderAuthErrors.sol";

/**
 * @title UpgraderAuth
 * @notice UUPS upgrade authorization bound to a single "upgrader" account, independent from ownership.
 * @dev Inherited by the SwapManager, PriceFeedManager and Router proxies. The upgrader is a TimelockController,
 *      so every upgrade is delayed, while the IndexManager stays the owner of the proxies.
 *      Storage follows ERC-7201 namespaced layout.
 */
abstract contract UpgraderAuth is IUpgraderAuth, Initializable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////
    ///////////////////////////// storage //////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /// @custom:storage-location erc7201:onchainassetmanager.storage.UpgraderAuth
    struct UpgraderAuthStorage {
        address upgrader;
    }

    // keccak256(abi.encode(uint256(keccak256("onchainassetmanager.storage.UpgraderAuth")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant UPGRADER_AUTH_STORAGE_LOCATION =
        0x05011ce772e66a30662b8c3c51042b29edbc4be89267b5cce22eaefae38d4700;

    ////////////////////////////////////////////////////////////////////
    //////////////////////////// initializer ///////////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice Sets the only account allowed to upgrade the proxy.
     * @dev Must be called from the initializer of the inheriting contract.
     *      Reverts with UpgraderAuth__ZeroAddress if `_upgrader` is address(0).
     * @param _upgrader The upgrader address (the TimelockController).
     */
    function __UpgraderAuth_init(address _upgrader) internal onlyInitializing {
        if (_upgrader == address(0)) revert UpgraderAuth__ZeroAddress();
        _getUpgraderAuthStorage().upgrader = _upgrader;
    }

    ////////////////////////////////////////////////////////////////////
    ////////////////////////////// getters /////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /// @dev Inherit from IUpgraderAuth. See interface for details.
    function getUpgrader() external view returns (address) {
        return _getUpgraderAuthStorage().upgrader;
    }

    ////////////////////////////////////////////////////////////////////
    ////////////////////////// upgradeability //////////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice Restricts upgrades to the upgrader.
     * @dev Reverts with UpgraderAuth__Unauthorized(caller) for any other caller, including the owner.
     */
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != _getUpgraderAuthStorage().upgrader)
            revert UpgraderAuth__Unauthorized(msg.sender);
    }

    /**
     * @notice Returns the ERC-7201 namespaced storage struct of UpgraderAuth.
     * @return $ Storage pointer at UPGRADER_AUTH_STORAGE_LOCATION.
     */
    function _getUpgraderAuthStorage()
        private
        pure
        returns (UpgraderAuthStorage storage $)
    {
        assembly {
            $.slot := UPGRADER_AUTH_STORAGE_LOCATION
        }
    }
}
