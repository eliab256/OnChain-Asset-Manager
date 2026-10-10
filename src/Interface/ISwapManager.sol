// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SwapType, SwapRoute} from "../types.sol";

interface ISwapManager {
    function registerIndex(
        address _indexAddress,
        SwapRoute memory _routeAsset0Usdc,
        SwapRoute memory _routeAsset1Usdc,
        SwapRoute memory _routeAsset0Asset1
    ) external;

    function updateRoute(
        address _indexAddress,
        SwapType _swapType,
        SwapRoute memory _newRoute
    ) external;

    function initialize(address _indexManager) external;

    function getImplementation() external view returns (address);

    function buildSingleSwapParams(
        address _indexAddress,
        SwapType _swapType,
        address _tokenIn,
        uint128 _amountIn,
        uint128 _amountOutMinimum
    )
        external
        view
        returns (
            bytes memory commands,
            bytes[] memory inputs,
            address tokenIn,
            address tokenOut
        );

    function buildDoubleSwapParams(
        address _indexAddress,
        SwapType _swapType0,
        SwapType _swapType1,
        address _tokenIn0,
        address _tokenIn1,
        uint128 _amountIn0,
        uint128 _amountIn1,
        uint128 _amountOutMinimum0,
        uint128 _amountOutMinimum1
    ) external view returns (bytes memory commands, bytes[] memory inputs);

    function getRoute(
        address _indexAddress,
        SwapType _swapType
    ) external view returns (SwapRoute memory);
}
