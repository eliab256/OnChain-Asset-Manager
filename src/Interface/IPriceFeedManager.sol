// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FeedConfig, PendingFeed} from "../types.sol";
import {IUpgraderAuth} from "./IUpgraderAuth.sol";

interface IPriceFeedManager is IUpgraderAuth {
    /**
     * @notice Initializes the proxy storage.
     * @dev Called once by the IndexManager constructor through the ERC1967Proxy deployment.
     *      Reverts with UpgraderAuth__ZeroAddress if `_upgrader` is zero.
     * @param _indexManager The IndexManager address, set as owner; its ASSET_MANAGER_ROLE holders manage the feeds.
     * @param _upgrader The only account allowed to upgrade the proxy (the TimelockController).
     */
    function initialize(address _indexManager, address _upgrader) external;

    /**
     * @notice Registers the first Chainlink price feed of an asset. Effective immediately.
     * @dev Callable only by accounts holding ASSET_MANAGER_ROLE on the IndexManager (owner).
     *      Reverts with PriceFeedManager__InvalidAsset if the asset is address(0) or its symbol() reverts or returns no data.
     *      Reverts with PriceFeedManager__InvalidAssetDecimals if the asset decimals() reverts or is above 18.
     *      Reverts with PriceFeedManager__PriceFeedAlreadySet if the asset already has a feed.
     *      Reverts if the feed/maxDelay are invalid (no code, latestRoundData() failing or answer <= 0,
     *      feed decimals() > 18, maxDelay == 0 or > MAX_FEED_DELAY_LIMIT).
     *      Since every index asset and USDC need a registered feed, this is where their ERC20 metadata is validated.
     * @param _asset The asset whose USD price the feed reports.
     * @param _feed The Chainlink AggregatorV3Interface price feed address.
     * @param _maxDelay Maximum age, in seconds, of the latest answer (feed heartbeat + margin).
     */
    function registerPriceFeed(
        address _asset,
        address _feed,
        uint32 _maxDelay
    ) external;

    /**
     * @notice Proposes the replacement of the price feed configuration of an asset, executable after PRICE_FEED_UPDATE_DELAY.
     * @dev Callable only by ASSET_MANAGER_ROLE holders on the IndexManager. Reverts if the asset has no feed,
     *      if a proposal is still within its delay, if (feed, maxDelay) equals the current configuration,
     *      or if the new configuration is invalid. Overwrites an executable or expired proposal,
     *      emitting PriceFeedUpdateCancelled for it first.
     * @param _asset The asset whose feed configuration is replaced.
     * @param _feed The new Chainlink price feed address.
     * @param _maxDelay The new maximum age, in seconds, of the latest answer.
     * @return Timestamp from which the update can be executed.
     */
    function proposePriceFeedUpdate(
        address _asset,
        address _feed,
        uint32 _maxDelay
    ) external returns (uint256);

    /**
     * @notice Executes the pending price feed update of an asset.
     * @dev Callable only by ASSET_MANAGER_ROLE holders on the IndexManager. Reverts if there is no pending update
     *      or its delay has not elapsed, if PRICE_FEED_UPDATE_EXECUTION_WINDOW has passed, or if the proposed feed
     *      no longer passes validation.
     * @param _asset The asset whose pending update is executed.
     */
    function executePriceFeedUpdate(address _asset) external;

    /**
     * @notice Cancels the pending price feed update of an asset, whether it is still in its delay, executable or expired.
     * @dev Callable only by ASSET_MANAGER_ROLE holders on the IndexManager. Reverts if there is no pending update.
     * @param _asset The asset whose pending update is cancelled.
     */
    function cancelPriceFeedUpdate(address _asset) external;

    /**
     * @notice Returns the latest Chainlink USD price of an asset, normalised to 18 decimals.
     * @dev Reverts if the asset has no feed, the answer is <= 0, the round is stale
     *      (answeredInRound < roundId) or the answer is older than the feed maxDelay.
     * @param _asset The asset to price.
     * @return The USD price of the asset with 18 decimals.
     */
    function getPrice(address _asset) external view returns (uint256);

    /**
     * @notice Returns the active price feed configuration of an asset.
     * @param _asset The asset to query.
     * @return The feed configuration (feed == address(0) if not registered). Check types.sol
     */
    function getPriceFeedConfig(
        address _asset
    ) external view returns (FeedConfig memory);

    /**
     * @notice Returns the pending price feed update of an asset.
     * @param _asset The asset to query.
     * @return The pending update (executableAt == 0 if none). Check types.sol
     */
    function getPendingPriceFeedUpdate(
        address _asset
    ) external view returns (PendingFeed memory);

    /**
     * @notice Returns whether an asset has a registered price feed.
     * @param _asset The asset to query.
     * @return True if a feed is registered for the asset.
     */
    function hasPriceFeed(address _asset) external view returns (bool);

    /**
     * @notice Returns the current implementation address of the proxy.
     * @return The implementation address stored in the ERC-1967 implementation slot.
     */
    function getImplementation() external view returns (address);
}
