//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library UnderlyingMath {
    
    // function calculateTokenAmountToBalanceIndexStdDecimals(uint256 _amount0USD, uint256 )

    function calculateAmount1USDFromAmount0USDAndIndexWeights(
        uint256 _amount0USD,
        uint8 _weight0,
        uint8 _weight1
    ) internal pure returns (uint256) {
        return (_amount0USD * _weight1) / _weight0;
    }

    function calculateUSDValueOfTokenAmount(
        uint256 _amount,
        uint256 _price,
        uint256 _priceDecimals,
        uint256 _tokenDecimals,
        uint256 _decimalsPrecision
    ) internal pure returns (uint256) {
        uint256 value;
        if (_decimalsPrecision == _tokenDecimals) {
            value = (_amount * _price) / (10 ** _priceDecimals);
        } else if (_decimalsPrecision > _tokenDecimals) {
            value =
                (_amount *
                    _price *
                    (10 ** (_decimalsPrecision - _tokenDecimals))) /
                (10 ** _priceDecimals);
        } else {
            value =
                (_amount * _price * (10 ** _decimalsPrecision)) /
                (10 ** _priceDecimals * 10 ** _tokenDecimals);
        }

        return value;
    }

    function calculateUSDValueOfTokenAmountStdDecimals(
        uint256 _amount,
        uint256 _price,
        uint256 _stdDecimals
    ) internal pure returns (uint256) {
        return ( _amount * _price ) / (10 ** _stdDecimals);
    }

    function calculateTokenAmountFromUSDValue(
        uint256 _usdValue,
        uint256 _price,
        uint256 _priceDecimals
    ) internal pure returns (uint256) {
        uint256 amount = (_usdValue * (10 ** _priceDecimals)) / _price;
        return amount;
    }

    function convertToSpecificDecimal(
        uint256 _amount,
        uint8 _currentDecimals,
        uint8 _targetDecimals
    ) internal pure returns (uint256 convertedAmount, uint256 decimalsDiff) {
        if (_currentDecimals == _targetDecimals) {
            return (_amount, 0);
        }
        if (_targetDecimals > _currentDecimals) {
            decimalsDiff = _targetDecimals - _currentDecimals;
            return (_amount * (10 ** decimalsDiff), decimalsDiff);
        }
        // implement revert to protect precision loss on the contract
        if(_targetDecimals < _currentDecimals) {
            decimalsDiff = _currentDecimals - _targetDecimals;
            return (_amount / (10 ** decimalsDiff), decimalsDiff);
        }
    }
}
