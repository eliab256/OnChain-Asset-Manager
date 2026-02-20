// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IIndex} from "./Interface/IIndex.sol";
import {IIndexFactory} from "./Interface/IIndexFactory.sol";

contract Router {
    error Router__InvalidAmounts();
    error Router__CannotSpecifyBothAmounts();

    IIndexFactory public immutable i_factory;

    constructor(address _factory) {
        i_factory = IIndexFactory(_factory);
    }

    function buyExactUsdcAmountOfShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxSlippage
    ) public {
        _buyShares(_indexAddress, _usdcAmount, 0, _maxSlippage);
    }

    function buyExactAmountOfSharesForUsdc(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    ) public {

        _buyShares(_indexAddress, 0, _sharesAmount, _maxSlippage);
    }

    function sellExactAmountOfSharesForUsdc(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    ) public {
        _sellShares(_indexAddress, 0 , _sharesAmount, _maxSlippage);
    }

    function sellSharesForExactUsdcAmount(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxSlippage
    ) public {
        _sellShares(_indexAddress, _usdcAmount, 0, _maxSlippage);
    }

    function _buyShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    ) internal {
        IIndex index = IIndex(_indexAddress);
        if (_usdcAmount > 0) {

            index.mintShares(msg.sender, _usdcAmount, _maxSlippage);
            // 1. Transfer USDC from the user to the index
            // 2. Call the mint function on the index to mint shares to the user
        }
        if (_sharesAmount > 0) {
           
            // 1. Transfer USDC from the user to the index
            // 2. Call the mint function on the index to mint shares to the user
        }
    }

    function _sellShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    ) internal {
         IIndex index = IIndex(_indexAddress);
        if (_usdcAmount > 0) {
            // 1. Calculate the amount of shares to redeem
            // 2. Call the redeem function
        }
        if (_sharesAmount > 0) {
            // 1.  fare transferFrom o approve.
            index.redeem(msg.sender, _sharesAmount, _maxSlippage);
        }
    }

    function getMinSharesAmountForExactUsdc(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxSlippage
    ) external view returns (uint256 minSharesAmount) {
        IIndex index = IIndex(_indexAddress);
        uint16 percentagePrecision = index.getPercentagePrecision();
        uint256 tempShareAmount = index.mintPreview(_usdcAmount);
        
        minSharesAmount = (tempShareAmount * (percentagePrecision - _maxSlippage)) / percentagePrecision;
    }

    function getMinUsdcAmountForExactShares(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    ) external view returns (uint256 minUsdcAmount) {
        IIndex index = IIndex(_indexAddress);
        uint16 percentagePrecision = index.getPercentagePrecision();
        uint256 tempUsdcAmount = index.redeemPreview(_sharesAmount);

        minUsdcAmount = (tempUsdcAmount * (percentagePrecision - _maxSlippage)) / percentagePrecision;
    }
}
