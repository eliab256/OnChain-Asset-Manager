// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UpgraderAuth} from "./UpgraderAuth.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IPriceFeedManager} from "./Interface/IPriceFeedManager.sol";
import {ContractCodeConstants} from "./ContractCodeConstants.sol";
import {FeedConfig, PendingFeed} from "./types.sol";
import {PriceFeedManagerEvents} from "./events/PriceFeedManagerEvents.sol";
import {
    PriceFeedManager__CallerNotAssetManager,
    PriceFeedManager__InvalidAsset,
    PriceFeedManager__InvalidPriceFeed,
    PriceFeedManager__InvalidMaxDelay,
    PriceFeedManager__PriceFeedAlreadySet,
    PriceFeedManager__PriceFeedNotSet,
    PriceFeedManager__SamePriceFeedConfig,
    PriceFeedManager__PriceFeedUpdatePending,
    PriceFeedManager__NoPendingPriceFeedUpdate,
    PriceFeedManager__PriceFeedUpdateExpired,
    PriceFeedManager__PriceFeedNotAvailable,
    PriceFeedManager__PriceFeedRoundStale,
    PriceFeedManager__PriceIsStale
} from "./errors/PriceFeedManagerErrors.sol";

/**
 * @title PriceFeedManager
 * @notice Shared registry of Chainlink price feeds (asset => feed + maxDelay) used by every Index.
 * @dev UUPS upgradeable. Deployed behind an ERC1967Proxy created by the IndexManager, which is the owner.
 *      Only the upgrader (the TimelockController) can upgrade it, see UpgraderAuth.
 *      Feed operations are restricted to the ASSET_MANAGER_ROLE holders of the IndexManager.
 *      Storage follows ERC-7201 namespaced layout.
 */
contract PriceFeedManager is
    IPriceFeedManager,
    Initializable,
    OwnableUpgradeable,
    UpgraderAuth,
    ContractCodeConstants
{
    ////////////////////////////////////////////////////////////////////
    ///////////////////////////// storage //////////////////////////////
    ////////////////////////////////////////////////////////////////////

    bytes32 public constant ASSET_MANAGER_ROLE =
        keccak256("ASSET_MANAGER_ROLE");

    /// @custom:storage-location erc7201:onchainassetmanager.storage.PriceFeedManager
    struct PriceFeedManagerStorage {
        // Mapping from asset to its active price feed configuration
        mapping(address => FeedConfig) assetToFeedConfig;
        // Mapping from asset to its pending (timelocked) price feed replacement
        mapping(address => PendingFeed) assetToPendingFeed;
    }

    // keccak256(abi.encode(uint256(keccak256("onchainassetmanager.storage.PriceFeedManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PRICE_FEED_MANAGER_STORAGE_LOCATION =
        0xce69fe7798ad1848e1ae89d57160a977b401d63b647be25f32ddbfedfac2a000;

    ////////////////////////////////////////////////////////////////////
    //////////////////////////// modifiers /////////////////////////////
    ////////////////////////////////////////////////////////////////////

    modifier onlyAssetManager() {
        _onlyAssetManager();
        _;
    }

    ////////////////////////////////////////////////////////////////////
    ///////////////////// constructor / initializer ////////////////////
    ////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Inherit from IPriceFeedManager. See interface for details.
    function initialize(
        address _indexManager,
        address _upgrader
    ) external initializer {
        __Ownable_init(_indexManager);
        __UpgraderAuth_init(_upgrader);
    }

    ////////////////////////////////////////////////////////////////////
    ////////////////////////// feed management /////////////////////////
    ////////////////////////////////////////////////////////////////////

    /// @dev Inherit from IPriceFeedManager. See interface for details.
    function registerPriceFeed(
        address _asset,
        address _feed,
        uint32 _maxDelay
    ) external onlyAssetManager {
        PriceFeedManagerStorage storage $ = _getPriceFeedManagerStorage();

        // 1. Check the asset is valid and has no feed yet.
        if (_asset == address(0)) revert PriceFeedManager__InvalidAsset();
        if ($.assetToFeedConfig[_asset].feed != address(0))
            revert PriceFeedManager__PriceFeedAlreadySet(_asset);

        // 2. Validate the feed and its maxDelay.
        _validatePriceFeed(_feed, _maxDelay);

        // 3. Store the configuration.
        $.assetToFeedConfig[_asset] = FeedConfig({
            feed: _feed,
            maxDelay: _maxDelay
        });

        emit PriceFeedManagerEvents.PriceFeedRegistered(
            _asset,
            _feed,
            _maxDelay
        );
    }

    /// @dev Inherit from IPriceFeedManager. See interface for details.
    function proposePriceFeedUpdate(
        address _asset,
        address _feed,
        uint32 _maxDelay
    ) external onlyAssetManager returns (uint256) {
        PriceFeedManagerStorage storage $ = _getPriceFeedManagerStorage();
        FeedConfig memory current = $.assetToFeedConfig[_asset];

        // 1. Check the asset already has a feed.
        if (current.feed == address(0))
            revert PriceFeedManager__PriceFeedNotSet(_asset);

        // 2. Check there is no proposal still within its delay.
        PendingFeed memory pending = $.assetToPendingFeed[_asset];
        if (pending.executableAt != 0 && block.timestamp < pending.executableAt)
            revert PriceFeedManager__PriceFeedUpdatePending();

        // 3. Check the configuration changes and is valid.
        if (current.feed == _feed && current.maxDelay == _maxDelay)
            revert PriceFeedManager__SamePriceFeedConfig();
        _validatePriceFeed(_feed, _maxDelay);

        // 4. Close an executable or expired proposal that is about to be overwritten.
        if (pending.executableAt != 0)
            emit PriceFeedManagerEvents.PriceFeedUpdateCancelled(
                _asset,
                pending.feed,
                pending.maxDelay
            );

        // 5. Store the pending update.
        uint256 executableAt = block.timestamp + PRICE_FEED_UPDATE_DELAY;
        $.assetToPendingFeed[_asset] = PendingFeed({
            feed: _feed,
            maxDelay: _maxDelay,
            executableAt: uint64(executableAt)
        });

        emit PriceFeedManagerEvents.PriceFeedUpdateProposed(
            _asset,
            _feed,
            _maxDelay,
            executableAt
        );

        return executableAt;
    }

    /// @dev Inherit from IPriceFeedManager. See interface for details.
    function executePriceFeedUpdate(address _asset) external onlyAssetManager {
        PriceFeedManagerStorage storage $ = _getPriceFeedManagerStorage();
        PendingFeed memory pending = $.assetToPendingFeed[_asset];

        // 1. Check there is a pending update past its delay and not expired.
        if (
            pending.executableAt == 0 || block.timestamp < pending.executableAt
        ) revert PriceFeedManager__NoPendingPriceFeedUpdate();
        if (
            block.timestamp >
            pending.executableAt + PRICE_FEED_UPDATE_EXECUTION_WINDOW
        ) revert PriceFeedManager__PriceFeedUpdateExpired();

        // 2. Re-validate the proposed feed: it may have been deprecated during the delay.
        _validatePriceFeed(pending.feed, pending.maxDelay);

        // 3. Apply the new configuration and clear the pending update.
        address oldFeed = $.assetToFeedConfig[_asset].feed;
        $.assetToFeedConfig[_asset] = FeedConfig({
            feed: pending.feed,
            maxDelay: pending.maxDelay
        });
        delete $.assetToPendingFeed[_asset];

        emit PriceFeedManagerEvents.PriceFeedUpdated(
            _asset,
            oldFeed,
            pending.feed,
            pending.maxDelay
        );
    }

    /// @dev Inherit from IPriceFeedManager. See interface for details.
    function cancelPriceFeedUpdate(address _asset) external onlyAssetManager {
        PriceFeedManagerStorage storage $ = _getPriceFeedManagerStorage();
        PendingFeed memory pending = $.assetToPendingFeed[_asset];

        // 1. Check there is a pending update.
        if (pending.executableAt == 0)
            revert PriceFeedManager__NoPendingPriceFeedUpdate();

        // 2. Clear the pending update.
        delete $.assetToPendingFeed[_asset];

        emit PriceFeedManagerEvents.PriceFeedUpdateCancelled(
            _asset,
            pending.feed,
            pending.maxDelay
        );
    }

    ////////////////////////////////////////////////////////////////////
    ////////////////////////////// pricing /////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /// @dev Inherit from IPriceFeedManager. See interface for details.
    function getPrice(address _asset) external view returns (uint256) {
        FeedConfig memory config = _getPriceFeedManagerStorage()
            .assetToFeedConfig[_asset];
        if (config.feed == address(0))
            revert PriceFeedManager__PriceFeedNotSet(_asset);

        AggregatorV3Interface feed = AggregatorV3Interface(config.feed);
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (answer <= 0) revert PriceFeedManager__PriceFeedNotAvailable();
        if (answeredInRound < roundId)
            revert PriceFeedManager__PriceFeedRoundStale();
        if (block.timestamp - updatedAt > config.maxDelay)
            revert PriceFeedManager__PriceIsStale();

        // decimals() <= DECIMALS_STANDARD is enforced at registration, so this never underflows.
        return uint256(answer) * 10 ** (DECIMALS_STANDARD - feed.decimals());
    }

    ////////////////////////////////////////////////////////////////////
    ////////////////////////////// getters /////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /// @dev Inherit from IPriceFeedManager. See interface for details.
    function getPriceFeedConfig(
        address _asset
    ) external view returns (FeedConfig memory) {
        return _getPriceFeedManagerStorage().assetToFeedConfig[_asset];
    }

    /// @dev Inherit from IPriceFeedManager. See interface for details.
    function getPendingPriceFeedUpdate(
        address _asset
    ) external view returns (PendingFeed memory) {
        return _getPriceFeedManagerStorage().assetToPendingFeed[_asset];
    }

    /// @dev Inherit from IPriceFeedManager. See interface for details.
    function hasPriceFeed(address _asset) external view returns (bool) {
        return
            _getPriceFeedManagerStorage().assetToFeedConfig[_asset].feed !=
            address(0);
    }

    /// @dev Inherit from IPriceFeedManager. See interface for details.
    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    ////////////////////////////////////////////////////////////////////
    ///////////////////////////// internals ////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice Restricts a call to the ASSET_MANAGER_ROLE holders of the owner (IndexManager).
     * @dev Reverts with PriceFeedManager__CallerNotAssetManager otherwise.
     */
    function _onlyAssetManager() internal view {
        if (!IAccessControl(owner()).hasRole(ASSET_MANAGER_ROLE, msg.sender))
            revert PriceFeedManager__CallerNotAssetManager();
    }

    /**
     * @notice Validates a Chainlink price feed and its maxDelay before it is stored.
     * @dev Reverts with PriceFeedManager__InvalidPriceFeed if the feed is address(0), has no code,
     *      latestRoundData() reverts or returns answer <= 0, or decimals() reverts or is above DECIMALS_STANDARD.
     *      Reverts with PriceFeedManager__InvalidMaxDelay if maxDelay is 0 or above MAX_FEED_DELAY_LIMIT.
     * @param _feed The Chainlink price feed address to validate.
     * @param _maxDelay The maximum age, in seconds, of the latest answer.
     */
    function _validatePriceFeed(address _feed, uint32 _maxDelay) internal view {
        if (_feed == address(0) || _feed.code.length == 0)
            revert PriceFeedManager__InvalidPriceFeed(_feed);
        if (_maxDelay == 0 || _maxDelay > MAX_FEED_DELAY_LIMIT)
            revert PriceFeedManager__InvalidMaxDelay();

        try AggregatorV3Interface(_feed).latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        ) {
            if (answer <= 0) revert PriceFeedManager__InvalidPriceFeed(_feed);
        } catch {
            revert PriceFeedManager__InvalidPriceFeed(_feed);
        }

        try AggregatorV3Interface(_feed).decimals() returns (uint8 decimals) {
            if (decimals > DECIMALS_STANDARD)
                revert PriceFeedManager__InvalidPriceFeed(_feed);
        } catch {
            revert PriceFeedManager__InvalidPriceFeed(_feed);
        }
    }

    /**
     * @notice Returns the ERC-7201 namespaced storage struct.
     * @return $ The PriceFeedManagerStorage pointer.
     */
    function _getPriceFeedManagerStorage()
        internal
        pure
        returns (PriceFeedManagerStorage storage $)
    {
        assembly {
            $.slot := PRICE_FEED_MANAGER_STORAGE_LOCATION
        }
    }
}
