// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRouter {
    // External functions
    function buyExactUsdcAmountOfShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    ) external;

    function sellExactAmountOfSharesForUsdc(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) external;

    // View functions
    function getMinRedeemPreview(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) external view returns (uint256 minUsdcAmount);

    function getMinMintPreview(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    ) external view returns (uint256 minSharesAmount);

    // Getter functions
    function getIndexManager() external view returns (address);

    function getUsdc() external view returns (address);
}
