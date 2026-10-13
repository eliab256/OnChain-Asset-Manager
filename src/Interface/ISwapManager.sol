// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SwapType, SwapRoute} from "../types.sol";
import {IUpgraderAuth} from "./IUpgraderAuth.sol";

interface ISwapManager is IUpgraderAuth {
    /**
     * @notice Registers the swap routes for an index.
     * @dev Only callable by the owner (the IndexManager).
     *      Each route can independently use either Uniswap V3 or Uniswap V4.
     *      Each route must connect the expected tokens of the index, read from the index itself:
     *      ASSET0_USDC ↔ {asset0, usdc}, ASSET1_USDC ↔ {asset1, usdc}, ASSET0_ASSET1 ↔ {asset0, asset1}.
     *      Reverts with `SwapManager__NotAnIndex` before any route is validated if `_indexAddress`
     *      has no code or does not expose `getAsset0`, `getAsset1` and `getUsdc`.
     *      Reverts with `SwapManager__InvalidV3Path`, `SwapManager__InvalidV4PoolKey` or
     *      `SwapManager__RouteTokensMismatch` if a route is malformed or connects the wrong tokens.
     * @param _indexAddress The index contract address.
     * @param _routeAsset0Usdc The route used for Asset0 ↔ USDC swaps.
     * @param _routeAsset1Usdc The route used for Asset1 ↔ USDC swaps.
     * @param _routeAsset0Asset1 The route used for Asset0 ↔ Asset1 swaps.
     */
    function registerIndex(
        address _indexAddress,
        SwapRoute memory _routeAsset0Usdc,
        SwapRoute memory _routeAsset1Usdc,
        SwapRoute memory _routeAsset0Asset1
    ) external;

    /**
     * @notice Updates a single route for a registered index.
     * @dev Only callable by the owner (the IndexManager). Reverts with `SwapManager__IndexNotRegistered`
     *      if the index has no registered routes. The new route must connect the expected tokens of the
     *      index for `_swapType`, otherwise it reverts like `registerIndex`.
     * @param _indexAddress The index contract address.
     * @param _swapType The swap type to update.
     * @param _newRoute The new route definition, either V3 or V4.
     */
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

    /**
     * @notice Returns the current implementation address of the proxy.
     * @return The implementation address stored in the ERC-1967 implementation slot.
     */
    function getImplementation() external view returns (address);

    /**
     * @notice Builds the Universal Router parameters for a single swap of an index.
     * @dev Uses the route registered for `_indexAddress` and `_swapType`, either V3 or V4.
     *      V3 paths are stored in either direction and oriented so that they start with `_tokenIn`.
     *      Reverts with `SwapManager__IndexNotRegistered` if the index has no registered routes.
     * @param _indexAddress The index contract address.
     * @param _swapType The swap type whose route is used.
     * @param _tokenIn The input token address.
     * @param _amountIn The input amount, in input token decimals.
     * @param _amountOutMinimum Minimum output amount in output token decimals; the router reverts if not met (0 disables the check).
     * @return commands The encoded Universal Router command.
     * @return inputs The encoded Universal Router inputs (one element).
     * @return tokenIn The input token address.
     * @return tokenOut The output token address.
     */
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

    /**
     * @notice Builds the Universal Router parameters for two independent swaps executed in a single call.
     * @dev The two swaps can use different pool versions, for example V3 + V4.
     *      Reverts with `SwapManager__IndexNotRegistered` if the index has no registered routes.
     * @param _indexAddress The index contract address.
     * @param _swapType0 The swap type for the first swap.
     * @param _swapType1 The swap type for the second swap.
     * @param _tokenIn0 The input token address for the first swap.
     * @param _tokenIn1 The input token address for the second swap.
     * @param _amountIn0 The input amount for the first swap, in input token decimals.
     * @param _amountIn1 The input amount for the second swap, in input token decimals.
     * @param _amountOutMinimum0 Minimum output amount for the first swap, in output token decimals (0 disables the check).
     * @param _amountOutMinimum1 Minimum output amount for the second swap, in output token decimals (0 disables the check).
     * @return commands The concatenated Universal Router commands.
     * @return inputs The encoded Universal Router inputs for both swaps (two elements).
     */
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

    /**
     * @notice Returns the registered route for an index and swap type.
     * @dev Returns the zero-valued struct (version V3, empty path) if no route is registered.
     * @param _indexAddress The index contract address.
     * @param _swapType The swap type to query.
     * @return The stored swap route.
     */
    function getRoute(
        address _indexAddress,
        SwapType _swapType
    ) external view returns (SwapRoute memory);
}
