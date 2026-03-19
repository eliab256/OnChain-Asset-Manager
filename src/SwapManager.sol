// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {
    Commands
} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {SwapType, PoolKey, PoolVersion, SwapRoute} from "./types.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

contract SwapManager is Ownable {
    // Errors
    error SwapManager__IndexNotRegistered();
    error SwapManager__RouteNotRegistered();
    error SwapManager__InvalidPoolVersion();
    error SwapManager__InvalidV3Path();
    error SwapManager__InvalidV4PoolKey();

    // Immutable reference to the IndexManager
    address internal immutable i_indexManager;

    // Index address => swap type => swap route
    mapping(address => mapping(SwapType => SwapRoute)) internal s_routes;

    modifier onlyRegisteredIndex(address _indexAddress) {
        _checkIfRegisteredIndex(_indexAddress);
        _;
    }

    constructor(address _indexManager) Ownable(_indexManager) {
        i_indexManager = _indexManager;
    }

    /**
     * @notice Registers the swap routes for an index.
     * @dev Each route can independently use either Uniswap V3 or Uniswap V4.
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
    ) external onlyOwner {
        _validateRoute(_routeAsset0Usdc);
        _validateRoute(_routeAsset1Usdc);
        _validateRoute(_routeAsset0Asset1);

        s_routes[_indexAddress][SwapType.ASSET0_USDC] = _routeAsset0Usdc;
        s_routes[_indexAddress][SwapType.ASSET1_USDC] = _routeAsset1Usdc;
        s_routes[_indexAddress][SwapType.ASSET0_ASSET1] = _routeAsset0Asset1;
    }

    /**
     * @notice Updates a single route for a registered index.
     * @param _indexAddress The index contract address.
     * @param _swapType The swap type to update.
     * @param _newRoute The new route definition, either V3 or V4.
     */
    function updateRoute(
        address _indexAddress,
        SwapType _swapType,
        SwapRoute memory _newRoute
    ) external onlyOwner onlyRegisteredIndex(_indexAddress) {
        _validateRoute(_newRoute);
        s_routes[_indexAddress][_swapType] = _newRoute;
    }

    /**
     * @dev Builds the parameters for a single swap.
     * @param _indexAddress The address of the index.
     * @param _swapType The type of swap.
     * @param _tokenIn The address of the input token.
     * @param _amountIn The amount of the input token.
     * @return commands The encoded commands for the swap.
     * @return inputs The encoded inputs for the swap.
     * @return tokenIn The address of the input token.
     * @return tokenOut The address of the output token.
     */
    function buildSingleSwapParams(
        address _indexAddress,
        SwapType _swapType,
        address _tokenIn,
        uint128 _amountIn
    )
        public
        view
        onlyRegisteredIndex(_indexAddress)
        returns (
            bytes memory commands,
            bytes[] memory inputs,
            address tokenIn,
            address tokenOut
        )
    {
        SwapRoute memory route = s_routes[_indexAddress][_swapType];

        if (route.version == PoolVersion.V4) {
            return _buildV4Params(route.poolKey, _tokenIn, _amountIn);
        } else if (route.version == PoolVersion.V3) {
            return _buildV3Params(route.v3Path, _tokenIn, _amountIn);
        } else {
            revert SwapManager__InvalidPoolVersion();
        }
    }

    /**
     * @notice Builds the parameters for two independent swaps in a single call.
     * @dev The two swaps can use different pool versions, for example V3 + V4.
     * @param _indexAddress The index contract address.
     * @param _swapType0 The swap type for the first swap.
     * @param _swapType1 The swap type for the second swap.
     * @param _tokenIn0 The input token address for the first swap.
     * @param _tokenIn1 The input token address for the second swap.
     * @param _amountIn0 The input amount for the first swap.
     * @param _amountIn1 The input amount for the second swap.
     * @return commands The concatenated router commands.
     * @return inputs The encoded router inputs for both swaps.
     */
    function buildDoubleSwapParams(
        address _indexAddress,
        SwapType _swapType0,
        SwapType _swapType1,
        address _tokenIn0,
        address _tokenIn1,
        uint128 _amountIn0,
        uint128 _amountIn1
    ) external view returns (bytes memory commands, bytes[] memory inputs) {
        (
            bytes memory commands0,
            bytes[] memory inputs0,
            ,

        ) = buildSingleSwapParams(
                _indexAddress,
                _swapType0,
                _tokenIn0,
                _amountIn0
            );

        (
            bytes memory commands1,
            bytes[] memory inputs1,
            ,

        ) = buildSingleSwapParams(
                _indexAddress,
                _swapType1,
                _tokenIn1,
                _amountIn1
            );

        commands = abi.encodePacked(commands0, commands1);

        inputs = new bytes[](2);
        inputs[0] = inputs0[0];
        inputs[1] = inputs1[0];
    }

    /**
     * @notice Returns the registered route for an index and swap type.
     * @param _indexAddress The index contract address.
     * @param _swapType The swap type to query.
     * @return The stored swap route.
     */
    function getRoute(
        address _indexAddress,
        SwapType _swapType
    ) external view returns (SwapRoute memory) {
        return s_routes[_indexAddress][_swapType];
    }

    /**
     * @dev Builds the router parameters for a Uniswap V4 swap.
     * @param _key The V4 pool key.
     * @param _tokenIn The input token address.
     * @param _amountIn The input amount.
     * @return commands The encoded router command.
     * @return inputs The encoded router input array.
     * @return tokenIn The input token address.
     * @return tokenOut The output token address.
     */
    function _buildV4Params(
        PoolKey memory _key,
        address _tokenIn,
        uint128 _amountIn
    )
        internal
        pure
        returns (
            bytes memory commands,
            bytes[] memory inputs,
            address tokenIn,
            address tokenOut
        )
    {
        tokenIn = _tokenIn;
        bool zeroForOne = _tokenIn == Currency.unwrap(_key.currency0);
        tokenOut = zeroForOne
            ? Currency.unwrap(_key.currency1)
            : Currency.unwrap(_key.currency0);

        IV4Router.ExactInputSingleParams memory swapParams = IV4Router
            .ExactInputSingleParams({
                poolKey: _key,
                zeroForOne: zeroForOne,
                amountIn: _amountIn,
                amountOutMinimum: 0, // @audit-info: slippage should be handled in Index.sol
                hookData: ""
            });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory actionParams = new bytes[](3);
        actionParams[0] = abi.encode(swapParams);
        actionParams[1] = abi.encode(Currency.wrap(tokenIn), _amountIn);
        actionParams[2] = abi.encode(Currency.wrap(tokenOut), uint256(0));

        commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);
    }

    /**
     * @dev Builds the router parameters for a Uniswap V3 swap.
     * @param _v3Path  Path encoded: abi.encodePacked(tokenIn, fee, tokenOut)
     *                 For multi-hop: abi.encodePacked(tokenIn, fee, tokenMid, fee, tokenOut)
     * @param _tokenIn The input token address.
     * @param _amountIn The input amount.
     * @return commands The encoded router command.
     * @return inputs The encoded router input array.
     * @return tokenIn The input token address.
     * @return tokenOut The output token address.
     */
    function _buildV3Params(
        bytes memory _v3Path,
        address _tokenIn,
        uint128 _amountIn
    )
        internal
        view
        returns (
            bytes memory commands,
            bytes[] memory inputs,
            address tokenIn,
            address tokenOut
        )
    {
        tokenIn = _tokenIn;

        // Extract tokenOut from the last address in the path.
        // Path format: [address(20) | fee(3) | address(20) | ...]
        // The last token starts at offset: pathLen - 20.
        tokenOut = _extractTokenOutFromV3Path(_v3Path);

        // V3_SWAP_EXACT_IN params:
        // (address recipient, uint256 amountIn, uint256 amountOutMin, bytes path, bool payerIsUser)
        // payerIsUser = false because the tokens have already been transferred to the Universal Router.
        commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));

        inputs = new bytes[](1);
        inputs[0] = abi.encode(
            address(this), // recipient: the Index contract receives the tokens
            uint256(_amountIn),
            uint256(0), // amountOutMinimum — @audit-info: slippage handling still needed
            _v3Path,
            false // payerIsUser: false, tokens are already in the router via TRANSFER or PERMIT2
        );
    }

    /**
     * @dev Validates a swap route before registration.
     */
    function _validateRoute(SwapRoute memory _route) internal pure {
        if (_route.version == PoolVersion.V4) {
            // For V4, currency0 and currency1 cannot both be address(0).
            if (
                Currency.unwrap(_route.poolKey.currency0) == address(0) &&
                Currency.unwrap(_route.poolKey.currency1) == address(0)
            ) {
                revert SwapManager__InvalidV4PoolKey();
            }
        } else if (_route.version == PoolVersion.V3) {
            if (_route.v3Path.length < 43) {
                revert SwapManager__InvalidV3Path();
            }
        } else {
            revert SwapManager__InvalidPoolVersion();
        }
    }

    /**
     * @dev Checks whether an index is registered.
     * @dev An index is considered registered if the ASSET0_ASSET1 route is valid.
     * @param _indexAddress The index contract address to check.
     */
    function _checkIfRegisteredIndex(address _indexAddress) internal view {
        SwapRoute memory route = s_routes[_indexAddress][
            SwapType.ASSET0_ASSET1
        ];

        if (route.version == PoolVersion.V4) {
            // The index is not registered if both currencies are zero, which is the struct default.
            if (
                Currency.unwrap(route.poolKey.currency0) == address(0) &&
                Currency.unwrap(route.poolKey.currency1) == address(0)
            ) {
                revert SwapManager__IndexNotRegistered();
            }
        } else if (route.version == PoolVersion.V3) {
            if (route.v3Path.length < 43) {
                revert SwapManager__IndexNotRegistered();
            }
        } else {
            revert SwapManager__IndexNotRegistered();
        }
    }

    /**
     * @dev Extracts tokenOut from the last position of an encoded V3 path.
     */
    function _extractTokenOutFromV3Path(
        bytes memory _path
    ) internal pure returns (address tokenOut) {
        uint256 offset = _path.length - 20;
        assembly {
            tokenOut := shr(96, mload(add(add(_path, 0x20), offset)))
        }
    }
}
