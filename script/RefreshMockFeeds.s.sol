//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {
    MockV3Aggregator
} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {DeploymentFile} from "./DeploymentFile.sol";
import {CodeConstants} from "./CodeConstants.sol";

/**
 * @notice Re-publishes the current answer of every mock price feed of the anvil deployment.
 * @dev After `anvil --load-state` the chain time jumps to the wall clock and the mock feeds become
 *      stale for the PriceFeedManager. Re-publishing the same answer moves `updatedAt` to the
 *      current block timestamp without changing any price.
 */
contract RefreshMockFeeds is Script, CodeConstants {
    error RefreshMockFeeds__UnsupportedChain(uint256 chainId);
    error RefreshMockFeeds__DeploymentFileNotFound(string path);

    ////////////////////////////////////////////////////////////////////
    ///////////////////////////// entry point //////////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice Calls `updateAnswer(latestAnswer())` on the USDC feed and on the feed of every mock
     *         listed in `deployments/31337.json`.
     * @dev Feeds: `.config.usdcPriceFeed` and `.mocks.<SYMBOL>.priceFeed` for every key under `.mocks`.
     *      Needs `--broadcast --private-key`. Reverts with RefreshMockFeeds__UnsupportedChain outside
     *      ANVIL_CHAIN_ID and with RefreshMockFeeds__DeploymentFileNotFound if nothing is deployed.
     */
    function run() external {
        if (block.chainid != ANVIL_CHAIN_ID) {
            revert RefreshMockFeeds__UnsupportedChain(block.chainid);
        }
        string memory path = DeploymentFile.getPath();
        if (!vm.exists(path)) {
            revert RefreshMockFeeds__DeploymentFileNotFound(path);
        }
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(path);
        string[] memory symbols = vm.parseJsonKeys(json, ".mocks");

        vm.startBroadcast();
        _refreshFeed(
            "USDC",
            vm.parseJsonAddress(json, ".config.usdcPriceFeed")
        );
        for (uint256 i = 0; i < symbols.length; i++) {
            _refreshFeed(
                symbols[i],
                vm.parseJsonAddress(
                    json,
                    string.concat(".mocks.", symbols[i], ".priceFeed")
                )
            );
        }
        vm.stopBroadcast();
    }

    ////////////////////////////////////////////////////////////////////
    /////////////////////////////// helpers ////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice Re-publishes the latest answer of a mock feed, so its `updatedAt` becomes the block timestamp.
     * @dev Must run inside a broadcast.
     * @param _symbol The asset symbol, used only for logging.
     * @param _feed The MockV3Aggregator to refresh.
     */
    function _refreshFeed(string memory _symbol, address _feed) internal {
        int256 answer = MockV3Aggregator(_feed).latestAnswer();
        MockV3Aggregator(_feed).updateAnswer(answer);
        console.log(
            string.concat(
                _symbol,
                " feed ",
                vm.toString(_feed),
                " answer (8 decimals) ",
                vm.toString(answer)
            )
        );
    }
}
