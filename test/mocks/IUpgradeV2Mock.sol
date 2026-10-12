// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Functions shared by SwapManagerV2Mock, PriceFeedManagerV2Mock and RouterV2Mock, so the upgrade tests
 *      can drive the three proxies through one interface after an upgrade.
 */
interface IUpgradeV2Mock {
    function initializeV2(uint256 _marker) external;

    function version() external pure returns (uint256);

    function getV2Marker() external view returns (uint256);

    function getImplementation() external view returns (address);

    function getUpgrader() external view returns (address);
}
