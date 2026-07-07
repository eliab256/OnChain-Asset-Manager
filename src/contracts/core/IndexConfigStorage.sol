// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ISwapManager} from "../../Interface/ISwapManager.sol";
import {
    IUniversalRouter
} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";

/**
 * @title IndexConfigStorage
 * @notice ERC-7201 namespaced storage (Diamond Storage pattern) for the Index configuration.
 * @dev These fields were `immutable` in the monolithic Index contract. In an upgradeable,
 *      proxy-shared-implementation design they cannot be immutable anymore, so they become
 *      storage, set once in the constructor/initializer and never touched again afterwards.
 *      Exposed as a library — not an abstract contract — so consumers get storage access
 *      without being forced into an inheritance relationship they don't otherwise need.
 */
library IndexConfigStorage {
    struct Layout {
        IERC20 asset0;
        uint8 decimals0;
        uint8 decimals1;
        uint8 decimalsUsdc; // packs into the same slot as asset0 (20 + 1 + 1 + 1 = 23 bytes)
        IERC20 asset1;
        IERC20 usdc;
        AggregatorV3Interface asset0PriceFeed;
        AggregatorV3Interface asset1PriceFeed;
        AggregatorV3Interface usdcPriceFeed;
        ISwapManager swapManager;
        IUniversalRouter universalRouter;
    }

    // keccak256(abi.encode(uint256(keccak256("onchainassetmanager.storage.IndexConfig")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0xeb8392376b3d3e6a0c8de5fd5bbdb605535368ce0e4895e559c0aacded7f2c00;

    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}