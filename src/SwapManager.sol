// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {
    Commands
} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {SwapType, PoolKey, Currency} from "./types.sol";

contract SwapManager is Ownable {
    error SwapManager__IndexNotRegistered();
    error SwapManager__PoolKeyNotRegistered();

    address internal immutable i_indexManager;

    // index address => tipo di swap => PoolKey
    mapping(address => mapping(SwapType => PoolKey)) internal s_poolKeys;

    modifier onlyRegisteredIndex(address _indexAddress) {
        _checkIfRegisteredIndex(_indexAddress);
        _;
    }

    constructor(address _indexManager) Ownable(_indexManager) {
        i_indexManager = _indexManager;
    }

    function registerIndex(
        address _indexAddress,
        PoolKey memory _poolKeyAsset0Usdc,
        PoolKey memory _poolKeyAsset1Usdc,
        PoolKey memory _poolKeyAsset0Asset1
    ) external onlyOwner {
        s_poolKeys[_indexAddress][SwapType.ASSET0_USDC] = _poolKeyAsset0Usdc;
        s_poolKeys[_indexAddress][SwapType.ASSET1_USDC] = _poolKeyAsset1Usdc;
        s_poolKeys[_indexAddress][
            SwapType.ASSET0_ASSET1
        ] = _poolKeyAsset0Asset1;
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
        PoolKey memory key = s_poolKeys[_indexAddress][_swapType];

        if (Currency.unwrap(key.currency0) == address(0)) {
            revert SwapManager__PoolKeyNotRegistered();
        }

        bool zeroForOne = _tokenIn == Currency.unwrap(key.currency0);

        tokenIn = _tokenIn;
        tokenOut = zeroForOne
            ? Currency.unwrap(key.currency1)
            : Currency.unwrap(key.currency0);

        IV4Router.ExactInputSingleParams memory swapParams = IV4Router
            .ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: _amountIn,
                amountOutMinimum: 0,
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

    function buildDoubleSwapParams(
        address _indexAddress,
        SwapType _swapType0,
        SwapType _swapType1,
        address _tokenIn0,
        address _tokenIn1,
        uint128 _amountIn0,
        uint128 _amountIn1
    ) external view returns (bytes memory commands, bytes[] memory inputs) {
        // first swap — zeroForOne derived from tokenIn0
        (, bytes[] memory inputs0, , ) = buildSingleSwapParams(
            _indexAddress,
            _swapType0,
            _tokenIn0,
            _amountIn0
        );

        // second swap — zeroForOne derived from tokenIn1
        (, bytes[] memory inputs1, , ) = buildSingleSwapParams(
            _indexAddress,
            _swapType1,
            _tokenIn1,
            _amountIn1
        );

        commands = abi.encodePacked(
            uint8(Commands.V4_SWAP),
            uint8(Commands.V4_SWAP)
        );
        inputs = new bytes[](2);
        inputs[0] = inputs0[0];
        inputs[1] = inputs1[0];
    }

    function getPoolKey(
        address _indexAddress,
        SwapType _swapType
    ) external view returns (PoolKey memory) {
        return s_poolKeys[_indexAddress][_swapType];
    }

    function _checkIfRegisteredIndex(address _indexAddress) internal view {
        PoolKey memory key = s_poolKeys[_indexAddress][SwapType.ASSET0_ASSET1];
        if (Currency.unwrap(key.currency0) == address(0)) {
            revert SwapManager__IndexNotRegistered();
        }
    }
}
