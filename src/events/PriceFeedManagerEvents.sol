// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library PriceFeedManagerEvents {
    /**
     * @notice Emitted when a price feed is registered for an asset that had none.
     * @param asset Asset the feed prices.
     * @param feed Chainlink aggregator address.
     * @param maxDelay Maximum accepted staleness of the feed answer, in seconds.
     */
    event PriceFeedRegistered(
        address indexed asset,
        address indexed feed,
        uint32 maxDelay
    );

    /**
     * @notice Emitted when a timelocked price feed update is proposed.
     * @param asset Asset whose feed will change.
     * @param feed Proposed Chainlink aggregator address.
     * @param maxDelay Proposed maximum staleness, in seconds.
     * @param executableAt Unix timestamp (seconds) from which the update can be executed.
     */
    event PriceFeedUpdateProposed(
        address indexed asset,
        address indexed feed,
        uint32 maxDelay,
        uint256 executableAt
    );

    /**
     * @notice Emitted when a pending price feed update is executed.
     * @param asset Asset whose feed changed.
     * @param oldFeed Previous Chainlink aggregator address.
     * @param newFeed New Chainlink aggregator address.
     * @param maxDelay New maximum staleness, in seconds.
     */
    event PriceFeedUpdated(
        address indexed asset,
        address indexed oldFeed,
        address indexed newFeed,
        uint32 maxDelay
    );

    /**
     * @notice Emitted when a pending price feed update is cancelled, either explicitly or because a new proposal overwrites an executable or expired one.
     * @param asset Asset whose pending update was cancelled.
     * @param cancelledFeed Feed of the cancelled proposal.
     * @param cancelledMaxDelay Maximum staleness of the cancelled proposal, in seconds.
     */
    event PriceFeedUpdateCancelled(
        address indexed asset,
        address indexed cancelledFeed,
        uint32 cancelledMaxDelay
    );
}
