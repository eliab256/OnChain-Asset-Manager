// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IndexAsset, SwapRoute} from "../types.sol";

interface IIndexManager {
    function setRouterAddress(address _newRouter) external;

    function setSwapManagerAddress(address _swapManager) external;

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

    function rebalanceIndex(address _indexAddress) external;

    function rebalanceMultipleIndexes(
        address[] calldata _indexAddresses
    ) external;

    function rebalanceAllIndexes() external;

    function proposeNewWeights(
        address _indexAddress,
        uint128 _newWeightAsset0
    ) external;

    function executeWeightUpdate(address _indexAddress) external;

    function executeWeightUpdateForMultipleIndexes(
        address[] calldata _indexAddresses
    ) external;

    function executeWeightUpdateForAllIndexes() external;

    function collectFees(address _indexAddress) external;

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

    function getAllIndexes() external view returns (address[] memory);

    function getIndexByAssetsAddresses(
        address _assetAddressA,
        address _assetAddressB
    ) external view returns (address index);

    function getRouterAddress() external view returns (address);

    function getSwapManagerAddress() external view returns (address);

    function getTotalFeesCollected() external view returns (uint256);

    function getUsdc() external view returns (address);

    function getUsdcPriceFeed() external view returns (address);

    function getUniswapUniversalRouter() external view returns (address);
}
