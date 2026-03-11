// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SwapType, PoolKey} from "../types.sol";

interface ISwapManager {
    function registerIndex(
        address _indexAddress,
        PoolKey memory _poolKeyAsset0Usdc,
        PoolKey memory _poolKeyAsset1Usdc,
        PoolKey memory _poolKeyAsset0Asset1
    ) external;

    function swapExactInput(
        address _indexAddress,
        SwapType _swapType,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external returns (uint256 amountOut);
}
