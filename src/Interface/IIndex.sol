//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IIndex is IERC20, IERC20Metadata {
    // Functions
    function initialize(uint256 _underlyingAmount0) external;

    function mintShares(
        address _to,
        uint256 _usdcAmountIn,
        uint256 _maxTolerance
    ) external;

    function minMintPreview(
        uint256 _usdcAmountIn,
        uint256 _maxTolerance
    ) external view returns (uint256 minSharesToMint);

    function redeem(
        address _from,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) external;

    function minRedeemPreview(
        uint256 _sharesAmountIn,
        uint256 _maxTolerance
    ) external view returns (uint256 minUsdcToReceive);

    function getLatestPrice(address _asset) external view returns (uint256);

    function proposeUpdateWeights(
        uint112 _newWeightAsset0
    ) external returns (uint256 implementationTimestamp);

    function executeWeightUpdate() external;

    function collectFees(
        address _collector
    ) external returns (uint256 feesCollected);

    function rebalanceIndex() external;

    function getAssetsUsdValue()
        external
        view
        returns (
            uint256 asset0TotalUsdValue,
            uint256 asset1TotalUsdValue,
            uint256 totalUsdValue
        );

    function getAssetsEffectiveWeights()
        external
        view
        returns (uint256 effectiveWeight0, uint256 effectiveWeight1);

    function getAssetsAndUsdcDecimals()
        external
        view
        returns (
            uint8 asset0Decimals,
            uint8 asset1Decimals,
            uint8 usdcDecimals
        );

    function getAssetsWeights() external view returns (uint112, uint112);

    function getAssetsAmount() external view returns (uint112, uint112);

    function getAsset0() external view returns (address);

    function getAsset1() external view returns (address);

    function getFeesInfo()
        external
        view
        returns (uint32 feePercentage, uint112 totalFees);

    function getPercentagePrecision() external pure returns (uint112);

    function getWeightPrecision() external pure returns (uint112);
}
