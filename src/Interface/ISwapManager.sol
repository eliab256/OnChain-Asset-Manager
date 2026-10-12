// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SwapType, SwapRoute} from "../types.sol";
import {IUpgraderAuth} from "./IUpgraderAuth.sol";

interface ISwapManager is IUpgraderAuth {
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

    /**
     * @notice Initializes the proxy storage.
     * @dev Called once by the IndexManager constructor through the ERC1967Proxy deployment.
     *      Reverts with UpgraderAuth__ZeroAddress if `_upgrader` is zero.
     * @param _indexManager The IndexManager address, set as owner (only account allowed to register and update routes).
     * @param _upgrader The only account allowed to upgrade the proxy (the TimelockController).
     */
    function initialize(address _indexManager, address _upgrader) external;

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
