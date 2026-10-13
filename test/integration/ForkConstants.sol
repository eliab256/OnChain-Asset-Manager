// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Ethereum mainnet block every mainnet fork test is pinned to.
// Block 26178000, mined 2026-10-12 17:50:59 UTC (timestamp 1791827459).
// Forking "latest" made the fork suites depend on live market state: the
// rebalance tests swap WBTC->WETH through the real Uniswap V3 pool with a
// Chainlink-derived minOut (1% REBALANCE_SWAP_SLIPPAGE), so they reverted
// with V3TooLittleReceived whenever the pool price drifted more than 1% from
// the feeds. At this block the pool price is within that tolerance and the
// Chainlink feeds used by the tests are fresh, so the suites are deterministic.
// Requires an archive-capable MAINNET_RPC_URL.
uint256 constant MAINNET_FORK_BLOCK = 26_178_000;
