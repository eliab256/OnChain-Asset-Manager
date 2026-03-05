//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library SharesMath {
    function calculateSharesToMintFromUsdcAmount(
        uint256 _usdcAmount,
        uint256 _totalAssetUsdValue,
        uint256 _totalShares
    ) internal pure returns (uint256 sharesToMint) {
        if (_totalShares == 0) {
            sharesToMint = _usdcAmount;
        } else {
            sharesToMint = (_usdcAmount * _totalShares) / _totalAssetUsdValue;
        }
    }

    function calculateShareValueInUsd(
        uint256 _sharesAmount,
        uint256 _totalAssetUsdValue,
        uint256 _totalShares
    ) internal pure returns (uint256 shareValueInUsd) {
        if (_totalAssetUsdValue == 0) {
            shareValueInUsd = 0;
        } else {
            shareValueInUsd =
                (_sharesAmount * _totalAssetUsdValue) /
                _totalShares;
        }
    }
}
