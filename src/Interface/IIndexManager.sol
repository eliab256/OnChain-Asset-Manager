// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IndexAsset, SwapRoute} from "../types.sol";

interface IIndexManager {
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

    /**
     * @notice Rebalances a single initialized index towards its target weights.
     * @dev Callable only by REBALANCER_ROLE. Reverts with IndexManager__NotIndexInitialized if the index is not initialized.
     *      Does not revert if the rebalance fails: emits IndexActionFailed (REBALANCE) with the raw revert data instead;
     *      emits IndexActionTriggered (REBALANCE) on success.
     * @param _indexAddress The address of the index to rebalance.
     */
    function rebalanceSingleIndex(address _indexAddress) external;

    /**
     * @notice Rebalances several initialized indexes in a single transaction.
     * @dev Callable only by REBALANCER_ROLE. Reverts with IndexManager__NotIndexInitialized if any index is not initialized.
     *      A failing index does not revert the batch: it emits IndexActionFailed (REBALANCE) and the loop continues.
     *      To act on every index, pass getInitializedIndexes().
     * @param _indexAddresses The addresses of the indexes to rebalance.
     */
    function rebalanceMultipleIndexes(
        address[] calldata _indexAddresses
    ) external;

    function proposeNewWeights(
        address _indexAddress,
        uint128 _newWeightAsset0
    ) external;

    /**
     * @notice Executes the pending target weights update of a single initialized index.
     * @dev Callable only by ASSET_MANAGER_ROLE. Reverts with IndexManager__NotIndexInitialized if the index is not initialized.
     *      Does not revert if the execution fails: emits IndexActionFailed (EXECUTE_WEIGHTS) with the raw revert data instead;
     *      emits IndexActionTriggered (EXECUTE_WEIGHTS) on success.
     * @param _indexAddress The address of the index whose weights update is executed.
     */
    function executeSingleWeightUpdate(address _indexAddress) external;

    function cancelWeightUpdate(address _indexAddress) external;

    /**
     * @notice Executes the pending target weights update of several initialized indexes in a single transaction.
     * @dev Callable only by ASSET_MANAGER_ROLE. Reverts with IndexManager__NotIndexInitialized if any index is not initialized.
     *      A failing index does not revert the batch: it emits IndexActionFailed (EXECUTE_WEIGHTS) and the loop continues.
     *      To act on every index, pass getInitializedIndexes().
     * @param _indexAddresses The addresses of the indexes whose weights update is executed.
     */
    function executeWeightUpdateForMultipleIndexes(
        address[] calldata _indexAddresses
    ) external;

    /**
     * @notice Collects the accrued fees of a single initialized index and sends them to the caller.
     * @dev Callable only by FEE_COLLECTOR_ROLE. Reverts with IndexManager__NotIndexInitialized if the index is not initialized.
     *      Does not revert if the collection fails: emits IndexActionFailed (COLLECT_FEES) with the raw revert data instead;
     *      on success emits IndexActionTriggered (COLLECT_FEES) and adds the amount, in USDC units (6 decimals),
     *      to getTotalFeesCollected().
     * @param _indexAddress The address of the index to collect fees from.
     */
    function collectFeesFromSingleIndex(address _indexAddress) external;

    /**
     * @notice Collects the accrued fees of several initialized indexes in a single transaction and sends them to the caller.
     * @dev Callable only by FEE_COLLECTOR_ROLE. Reverts with IndexManager__NotIndexInitialized if any index is not initialized.
     *      A failing index does not revert the batch: it emits IndexActionFailed (COLLECT_FEES) and the loop continues.
     *      The sum collected, in USDC units (6 decimals), is added to getTotalFeesCollected(). To act on every index,
     *      pass getInitializedIndexes().
     * @param _indexAddresses The addresses of the indexes to collect fees from.
     */
    function collectFeesFromMultipleIndexes(
        address[] calldata _indexAddresses
    ) external;

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

    /**
     * @notice Returns the address of the shared Router proxy, deployed by the constructor.
     * @dev Never changes: every index stores this address as its router; the logic is upgraded behind it.
     * @return The Router proxy address.
     */
    function getRouterAddress() external view returns (address);

    function getSwapManagerAddress() external view returns (address);

    /**
     * @notice Returns the address of the shared PriceFeedManager proxy, deployed by the constructor.
     * @return The PriceFeedManager proxy address.
     */
    function getPriceFeedManagerAddress() external view returns (address);

    function getTotalFeesCollected() external view returns (uint256);

    function getUniswapUniversalRouter() external view returns (address);
}
