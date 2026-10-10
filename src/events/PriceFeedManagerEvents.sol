// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library PriceFeedManagerEvents {
    event PriceFeedRegistered(
        address indexed asset,
        address indexed feed,
        uint32 maxDelay
    );

    event PriceFeedUpdateProposed(
        address indexed asset,
        address indexed feed,
        uint32 maxDelay,
        uint256 executableAt
    );

    event PriceFeedUpdated(
        address indexed asset,
        address indexed oldFeed,
        address indexed newFeed,
        uint32 maxDelay
    );

    event PriceFeedUpdateCancelled(
        address indexed asset,
        address indexed cancelledFeed,
        uint32 cancelledMaxDelay
    );
}
