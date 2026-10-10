// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IndexAsset, SwapRoute} from "../types.sol";

interface IIndexManager {
    function setRouterAddress(address _newRouter) external;

    function proposeSwapManagerUpgrade(
        address _newImplementation,
        bytes calldata _data
    ) external returns (uint256 executableAt);

    function executeSwapManagerUpgrade() external;

    function cancelSwapManagerUpgrade() external;

    /**
     * @notice Proposes an upgrade of the PriceFeedManager implementation, executable after PROXY_UPGRADE_DELAY.
     * @dev Callable only by DEFAULT_ADMIN_ROLE. Reverts with IndexManager__PriceFeedManagerUpgradePending if a
     *      proposal is still within its delay, and with IndexManager__InvalidPriceFeedManagerImplementation if the
     *      implementation has no code, equals the current one or is not a UUPS implementation.
     * @param _newImplementation The new UUPS-compatible PriceFeedManager implementation.
     * @param _data Optional calldata executed on the proxy after the upgrade (e.g. a reinitializer). Empty for none.
     * @return executableAt Timestamp from which the upgrade can be executed.
     */
    function proposePriceFeedManagerUpgrade(
        address _newImplementation,
        bytes calldata _data
    ) external returns (uint256 executableAt);

    /**
     * @notice Executes the pending PriceFeedManager upgrade.
     * @dev Callable only by DEFAULT_ADMIN_ROLE. Executable only within PROXY_UPGRADE_EXECUTION_WINDOW after the delay;
     *      reverts with IndexManager__NoPendingPriceFeedManagerUpgrade before it and
     *      IndexManager__PriceFeedManagerUpgradeExpired after it.
     */
    function executePriceFeedManagerUpgrade() external;

    /**
     * @notice Cancels the pending PriceFeedManager upgrade, whether it is still in its delay, executable or expired.
     * @dev Callable only by DEFAULT_ADMIN_ROLE. Reverts with IndexManager__NoPendingPriceFeedManagerUpgrade if none.
     */
    function cancelPriceFeedManagerUpgrade() external;

    function createIndex(
        uint32 _feePercentage,
        IndexAsset memory _assetA,
        IndexAsset memory _assetB
    ) external returns (address index, address token0, address token1);

    function initializeIndex(
        address _depositor,
        address _indexAddress,
        uint256 _underlyingAmount0,
        SwapRoute memory _routeAsset0Usdc,
        SwapRoute memory _routeAsset1Usdc,
        SwapRoute memory _routeAsset0Asset1
    ) external;

    function retrieveAmountFromAmount(
        uint256 _amount0,
        address _indexAddress,
        bool _zeroToOne
    ) external view returns (uint256 amountToDeposit);

    function rebalanceSingleIndex(address _indexAddress) external;

    function rebalanceMultipleIndexes(
        address[] calldata _indexAddresses
    ) external;

    function rebalanceAllIndexes() external;

    function proposeNewWeights(
        address _indexAddress,
        uint128 _newWeightAsset0
    ) external;

    function executeSingleWeightUpdate(address _indexAddress) external;

    function cancelWeightUpdate(address _indexAddress) external;

    function executeWeightUpdateForMultipleIndexes(
        address[] calldata _indexAddresses
    ) external;

    function executeWeightUpdateForAllIndexes() external;

    function collectFeesFromSingleIndex(address _indexAddress) external;

    function collectFeesFromMultipleIndexes(
        address[] calldata _indexAddresses
    ) external;

    function collectFeesFromAllIndexes() external;

    function sortAssets(
        address _assetAddressA,
        address _assetAddressB
    ) external pure returns (address token0, address token1);

    function isIndexAddress(address indexAddress) external view returns (bool);

    function checkIsIndexInitialized(
        address indexAddress
    ) external view returns (bool);

    function getDeployedIndexes() external view returns (address[] memory);

    function getInitializedIndexes() external view returns (address[] memory);

    function getIndexAssets(
        address _indexAddress
    ) external view returns (address asset0, address asset1);

    function getIndexByAssetsAddresses(
        address _assetAddressA,
        address _assetAddressB
    ) external view returns (address index);

    function getRouterAddress() external view returns (address);

    function getSwapManagerAddress() external view returns (address);

    function getPendingSwapManagerUpgrade()
        external
        view
        returns (
            address implementation,
            bytes memory data,
            uint256 executableAt
        );

    /**
     * @notice Returns the address of the shared PriceFeedManager proxy, deployed by the constructor.
     * @return The PriceFeedManager proxy address.
     */
    function getPriceFeedManagerAddress() external view returns (address);

    /**
     * @notice Returns the pending PriceFeedManager upgrade.
     * @return implementation The proposed implementation (address(0) if none).
     * @return data The calldata executed after the upgrade.
     * @return executableAt Timestamp from which the upgrade can be executed (0 if none).
     */
    function getPendingPriceFeedManagerUpgrade()
        external
        view
        returns (
            address implementation,
            bytes memory data,
            uint256 executableAt
        );

    function getTotalFeesCollected() external view returns (uint256);

    function getUsdc() external view returns (address);

    function getUsdcPriceFeed() external view returns (address);

    function getUniswapUniversalRouter() external view returns (address);
}
