//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIndex {
    // Functions
    function initialize(uint256 underlyingAmount0) external;

    function mintShares(
        address _to,
        uint256 _usdcAmount,
        uint256 _maxSlippage
    ) external;

    function mintPreview(
        uint256 _usdcAmount
    ) external view returns (uint256 sharesToMint);

    function redeem(
        address _from,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    ) external;

    function redeemPreview(
        uint256 _sharesAmount
    ) external view returns (uint256 usdcToReceive);

    function getLatestPrice(address _asset) external view returns (uint256);

    function getAsset0TotalUsdValue() external view returns (uint256);

    function getAsset1TotalUsdValue() external view returns (uint256);

    function getTotalAssetUsdValue() external view returns (uint256);

    function getAssetsAndUsdcDecimals()
        external
        view
        returns (
            uint8 asset0Decimals,
            uint8 asset1Decimals,
            uint8 usdcDecimals
        );

    function getAssetsWeights() external view returns (uint8, uint8);

    function getAssetsAmount() external view returns (uint256, uint256);

    function getFeesInfo()
        external
        view
        returns (uint16 feePercentage, uint112 totalFees);

    // Immutable getters
    function i_asset0() external view returns (address);

    function i_asset1() external view returns (address);

    function i_asset0PriceFeed() external view returns (address);

    function i_asset1PriceFeed() external view returns (address);

    function getPercentagePrecision() external pure returns (uint16);
}
