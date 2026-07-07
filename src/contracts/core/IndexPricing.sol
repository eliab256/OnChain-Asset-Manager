// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {UnderlyingMath} from "../../libraries/UnderlyingMath.sol";
import "../../errors/IndexErrors.sol";
import {IndexSwapper} from "./IndexSwapper.sol";
import {IndexConfigStorage} from "./IndexConfigStorage.sol";
import {IndexAccountingStorage} from "./IndexAccountingStorage.sol";

/**
 * @title IndexPricing
 * @notice Price-feed reads and reserve accounting. Inherits IndexSwapper purely to provide
 *         the real implementation of the `_getLatestPrice` virtual hook — this is the only
 *         reason for the inheritance relationship between the two modules. Storage access is
 *         via the IndexConfigStorage / IndexAccountingStorage libraries, no inheritance needed.
 */
abstract contract IndexPricing is IndexSwapper {
    using UnderlyingMath for uint256;
    using SafeCast for uint256;

    function _getLatestPrice(
        address _asset
    ) internal view override returns (uint256) {
        IndexConfigStorage.Layout storage $ = IndexConfigStorage.layout();

        AggregatorV3Interface feed;
        if (_asset == address($.asset0)) feed = $.asset0PriceFeed;
        else if (_asset == address($.asset1)) feed = $.asset1PriceFeed;
        else if (_asset == address($.usdc)) feed = $.usdcPriceFeed;
        else revert Index__AssetNotSupported();

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (answer <= 0) revert Index__PriceFeedNotAvailable();
        if (answeredInRound < roundId) revert Index__PriceFeedRoundStale();
        if (_asset == address($.usdc)) {
            if (block.timestamp - updatedAt > MAX_USDC_DELAY)
                revert Index__PriceIsStale();
        } else {
            if (block.timestamp - updatedAt > MAX_DELAY)
                revert Index__PriceIsStale();
        }
        return _convertToDecimalStandard(uint256(answer), feed.decimals());
    }

    function _getAssetsReserves()
        internal
        view
        returns (uint128 reserve0, uint128 reserve1)
    {
        IndexAccountingStorage.Layout storage $ = IndexAccountingStorage.layout();
        assembly {
            let value := sload($.slot)
            reserve0 := and(value, sub(shl(128, 1), 1))
            reserve1 := shr(128, value)
        }
    }

    function _initFunctionValues()
        internal
        view
        returns (
            uint256 priceAsset0,
            uint256 priceAsset1,
            uint256 priceUsdc,
            uint128 initialAsset0Reserve,
            uint128 initialAsset1Reserve,
            uint256 asset0UsdValue,
            uint256 asset1UsdValue,
            uint256 totalAssetUsdValue
        )
    {
        IndexConfigStorage.Layout storage $ = IndexConfigStorage.layout();

        priceAsset0 = _getLatestPrice(address($.asset0));
        priceAsset1 = _getLatestPrice(address($.asset1));
        priceUsdc = _getLatestPrice(address($.usdc));

        (uint128 rawReserve0, uint128 rawReserve1) = _getAssetsReserves();

        initialAsset0Reserve = _convertToDecimalStandard(
            rawReserve0,
            $.decimals0
        ).toUint128();
        initialAsset1Reserve = _convertToDecimalStandard(
            rawReserve1,
            $.decimals1
        ).toUint128();

        asset0UsdValue = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                initialAsset0Reserve,
                priceAsset0,
                DECIMALS_STANDARD
            );
        asset1UsdValue = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                initialAsset1Reserve,
                priceAsset1,
                DECIMALS_STANDARD
            );
        totalAssetUsdValue = asset0UsdValue + asset1UsdValue;
    }
}