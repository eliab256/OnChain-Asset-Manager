// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUpgraderAuth {
    /**
     * @notice Returns the only account allowed to upgrade the proxy.
     * @dev Set once in the initializer (the TimelockController in production). There is no setter:
     *      it can change only through an upgrade, which itself must be performed by the current upgrader.
     * @return The upgrader address.
     */
    function getUpgrader() external view returns (address);
}
