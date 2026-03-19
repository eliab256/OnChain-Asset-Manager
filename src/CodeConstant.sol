// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract CodeConstant {

    /**
     * @dev The maximum delay to rethreive a price from the price feed, in seconds.
     * @dev This is used to ensure that the price data used for calculations is recent and not stale.
     */
    uint256 public constant MAX_DELAY = 1 hours;

    /**
     * @dev The standard number of decimals for tokens.
     * @dev This is used for normalizing token amounts and prices to a common decimal standard.
     */
    uint8 public constant DECIMALS_STANDARD = 18;

    /**
     * @dev The precision for percentage fee calculations, in basis points (1 basis point = 0.01%).
     */
    uint128 public constant PERCENTAGE_FEE_PRECISION = 10000;

    /**
     * @dev The maximum percentage value, in basis points.
     */
    uint128 public constant MAX_PERCENTAGE = 100 * PERCENTAGE_FEE_PRECISION;

    /**
     * @dev The delay between weight updates propose and execution. 
     * @dev This is used to ensure users have enough time to react to a proposed weight update.
     */
    uint256 internal constant WEIGHT_UPDATE_DELAY = 2 days;

    /**
     * @dev The precision for weight calculations.
     */
    uint128 internal constant WEIGHT_PRECISION = 10000;

    /**
     * @dev The maximum weight for an asset, in weight units (100%).
     */
    uint128 internal constant MAX_WEIGHT = 100 * WEIGHT_PRECISION;

    /**
     * @dev The weight deviation threshold for triggering a rebalance, in basis points
     */
    uint128 internal constant REBALANCE_THRESHOLD = 3 * WEIGHT_PRECISION;

    /**
     * @dev The maximum slippage tolerance for rebalancing, in basis points (1 basis point = 0.01%).
     * This is used to prevent excessive slippage during swaps in the rebalancing process.
     */
    uint256 internal constant MAX_SLIPPAGE_TOLERANCE =
        2 * PERCENTAGE_FEE_PRECISION;

    /**
     * @dev The deadline for swap operations, in seconds.
     */
    uint256 internal constant SWAP_DEADLINE = 30;
}
