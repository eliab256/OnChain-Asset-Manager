// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract ContractCodeConstants {
    /**
     * @dev The upper bound for the per-feed maxDelay accepted by the PriceFeedManager, in seconds.
     * @dev Prevents registering a feed whose staleness check would be effectively disabled.
     */
    uint32 internal constant MAX_FEED_DELAY_LIMIT = 2 days;

    /**
     * @dev The delay between a price feed replacement proposal and its execution.
     * @dev Gives users time to react to a feed change, which affects the pricing of every index using the asset.
     */
    uint256 internal constant PRICE_FEED_UPDATE_DELAY = 2 days;

    /**
     * @dev The window after PRICE_FEED_UPDATE_DELAY during which a proposed feed replacement can be executed.
     */
    uint256 internal constant PRICE_FEED_UPDATE_EXECUTION_WINDOW = 3 days;

    /**
     * @dev The standard number of decimals for tokens.
     * @dev This is used for normalizing token amounts and prices to a common decimal standard.
     */
    uint8 public constant DECIMALS_STANDARD = 18;

    /**
     * @dev The precision for percentage fee calculations, in basis points (1 basis point = 0.01%).
     */
    uint32 public constant PERCENTAGE_FEE_PRECISION = 10000;

    /**
     * @dev The maximum percentage value, in basis points.
     */
    uint32 public constant MAX_PERCENTAGE = 100 * PERCENTAGE_FEE_PRECISION;

    /**
     * @dev The maximum tolerance allowed for mint/redeem operations.
     * @dev Expressed as a percentage (10 = 10%). The actual ceiling used in
     *      validation is MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION = 100_000.
     */
    uint256 internal constant MAX_TOLERANCE = 10; // 10%

    /**
     * @dev The delay between weight updates propose and execution.
     * @dev This is used to ensure users have enough time to react to a proposed weight update.
     */
    uint256 internal constant WEIGHT_UPDATE_DELAY = 2 days;

    /**
     * @dev The window after WEIGHT_UPDATE_DELAY during which a proposed weight update can be executed.
     * @dev After this window the proposal expires and must be proposed again.
     */
    uint256 internal constant WEIGHT_UPDATE_EXECUTION_WINDOW = 3 days;

    /**
     * @dev The precision for weight calculations.
     */
    uint128 internal constant WEIGHT_PRECISION = 10000;

    /**
     * @dev The maximum weight for an asset, in weight units (100%).
     */
    uint128 internal constant MAX_WEIGHT = 100 * WEIGHT_PRECISION;

    /**
     * @dev The minimum weight for an asset, in weight units (1%).
     * @dev This is used to prevent dust allocations that could cause issues with swaps and rebalances.
     */
    uint128 internal constant MIN_WEIGHT = 1 * WEIGHT_PRECISION;

    /**
     * @dev The weight deviation threshold for triggering a rebalance, in basis points
     */
    uint128 internal constant REBALANCE_THRESHOLD = 3 * WEIGHT_PRECISION;

    /**
     * @dev The maximum slippage tolerated on a rebalance swap, relative to the swapped notional (1%).
     * @dev Used both for the router amountOutMinimum (derived from oracle prices) and for the
     *      post-swap check on the total USD value. Must cover pool fee, price impact and oracle deviation.
     */
    uint256 internal constant REBALANCE_SWAP_SLIPPAGE =
        1 * PERCENTAGE_FEE_PRECISION;

    /**
     * @dev The deadline for swap operations, in seconds.
     */
    uint256 internal constant SWAP_DEADLINE = 30;
}
