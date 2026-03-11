//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library UnderlyingMath {
    // function calculateTokenAmountToBalanceIndexStdDecimals(uint256 _amount0USD, uint256 )

    function calculateAmount1UsdFromAmount0UsdAndIndexWeights(
        uint256 _amount0Usd,
        uint128 _weight0,
        uint128 _weight1
    ) internal pure returns (uint256) {
        return (_amount0Usd * _weight1) / _weight0;
    }

    function calculateUsdValueOfTokenAmount(
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
    ) internal pure returns (uint256 usdValue) {
        usdValue = (_amount * _price) / (10 ** _stdDecimals);
    }

    function calculateTokenAmountFromUsdValue(
        uint256 _usdValue,
        uint256 _price,
        uint256 _priceDecimals
    ) internal pure returns (uint256 tokenAmount) {
        tokenAmount = (_usdValue * (10 ** _priceDecimals)) / _price;
    }

    /**
     * @dev Converts an amount from one decimal precision to another.
     * @dev It doesn't check if the conversion will cause precision loss, it just performs the conversion
     * it's the caller's responsibility to ensure that the conversion is safe and doesn't cause precision loss,
     * if the target decimals is less than the current decimals, it will perform a division which can cause
     * precision loss, in this case the function will return the converted amount and the difference in decimals,
     * so the caller can decide how to handle the precision loss, e.g. by reverting or by accepting the loss.
     * @param _amount The amount to convert.
     * @param _currentDecimals The current decimal precision of the amount.
     * @param _targetDecimals The target decimal precision to convert to.
     * @return convertedAmount The amount converted to the target decimal precision.
     * @return decimalsDiff The difference in decimals between the current and target precision.
     */
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
        if (_targetDecimals < _currentDecimals) {
            decimalsDiff = _currentDecimals - _targetDecimals;
            return (_amount / (10 ** decimalsDiff), decimalsDiff);
        }
    }

    /**
     * @dev assume all values has the same decimals standard
     * @dev assume weights together do total 100%
     * @dev this function calculates the amount of token0 and token1 to swap in order to rebalance the index according to the target weights of the index, it returns the amount of token0 to swap and the amount of token1 to swap, one of them will be 0 depending on which asset is overweighted or underweighted
     * @param _totalAssetUsdValue the total USD value of the assets in the index
     * @param _token0UsdValueBefore the USD value of token0 before the rebalance
     * @param _token1UsdValueBefore the USD value of token1 before the rebalance
     * @param _weight0 the target weight of token0 in the index with 4 decimals precision, e.g. 50000 = 5%
     * @param _weight1 the target weight of token1 in the index with 4 decimals precision, e.g. 50000 = 5%
     * @param _token0Price the price of token0 in USD with 18 decimals
     * @param _token1Price the price of token1 in USD with 18 decimals
     * @param _decimals the decimals standard used for the calculations, all values should be in this decimals standard, e.g. 18 decimals
     */
    function calculateRebalanceAmounts(
        uint256 _totalAssetUsdValue,
        uint256 _token0UsdValueBefore,
        uint256 _token1UsdValueBefore,
        uint128 _weight0,
        uint128 _weight1,
        uint256 _token0Price,
        uint256 _token1Price,
        uint8 _decimals
    ) internal pure returns (uint256 amount0ToSwap, uint256 amount1ToSwap) {
        uint256 totalWeight = _weight0 + _weight1;
        (uint256 effectiveWeight0, ) = calculateEffectiveWeights(
            _token0UsdValueBefore,
            _totalAssetUsdValue,
            totalWeight
        );
        if (effectiveWeight0 > _weight0) {
            // need to swap token0 for token1
            uint256 desiredToken0UsdValue = (_totalAssetUsdValue * _weight0) /
                totalWeight;

            uint256 token0UsdValueDiff = _token0UsdValueBefore -
                desiredToken0UsdValue;

            amount0ToSwap = calculateTokenAmountFromUsdValue(
                token0UsdValueDiff,
                _token0Price,
                _decimals
            );
            amount1ToSwap = 0;
        } else {
            // need to swap token1 for token0
            uint256 desiredToken1UsdValue = (_totalAssetUsdValue * _weight1) /
                totalWeight;

            uint256 token1UsdValueDiff = _token1UsdValueBefore -
                desiredToken1UsdValue;

            amount1ToSwap = calculateTokenAmountFromUsdValue(
                token1UsdValueDiff,
                _token1Price,
                _decimals
            );
            amount0ToSwap = 0;
        }
    }

    function calculateSwapFromUsdcAmount(
        uint256 _usdcAmount,
        uint128 _weight0,
        uint128 _weight1
    )
        internal
        pure
        returns (uint256 amountToSwapToToken0, uint256 amountToSwapToToken1)
    {
        amountToSwapToToken0 = (_usdcAmount * _weight0) / (_weight0 + _weight1);
        amountToSwapToToken1 = (_usdcAmount * _weight1) / (_weight0 + _weight1);
    }

    function calculateDepositAllocationInUsd(
        uint256 _initTotalAssetUsdValue,
        uint256 _depositAmountUsd,
        uint128 _targetWeight0,
        uint128 _targetWeight1,
        uint128 _effectiveWeight0
    )
        internal
        pure
        returns (uint256 token0DepositAmountUsd, uint256 token1DepositAmountUsd)
    {
        uint256 updatedTotalAssetUsdValue = _initTotalAssetUsdValue +
            _depositAmountUsd;
        uint256 maxPercentage = _targetWeight0 + _targetWeight1;

        uint256 targetToken0UsdValue = (updatedTotalAssetUsdValue *
            _targetWeight0) / maxPercentage;
        uint256 currentToken0UsdValue = (_initTotalAssetUsdValue *
            _effectiveWeight0) / maxPercentage;

        if (targetToken0UsdValue <= currentToken0UsdValue) {
            // asset0 overweight, buy only asset1
            token0DepositAmountUsd = 0;
            token1DepositAmountUsd = _depositAmountUsd;
        } else {
            // asset1 overweight or weights are balanced, buy only asset0
            token0DepositAmountUsd =
                targetToken0UsdValue -
                currentToken0UsdValue;
            token1DepositAmountUsd = _depositAmountUsd - token0DepositAmountUsd;
        }
    }

    function calculateWithdrawUnderlyingAmountsInUsd(
        uint256 _totalAssetUsdValue,
        uint256 _withdrawAmountUsd,
        uint128 _targetWeight0,
        uint128 _targetWeight1,
        uint128 _effectiveWeight0
    )
        internal
        pure
        returns (
            uint256 token0WithdrawAmountUsd,
            uint256 token1WithdrawAmountUsd
        )
    {
        uint256 updatedTotalAssetUsdValue = _totalAssetUsdValue -
            _withdrawAmountUsd;
        uint256 totalWeight = _targetWeight0 + _targetWeight1;

        uint256 targetToken0UsdValue = (updatedTotalAssetUsdValue *
            _targetWeight0) / totalWeight;
        uint256 currentToken0UsdValue = (_totalAssetUsdValue *
            _effectiveWeight0) / totalWeight;

        if (targetToken0UsdValue >= currentToken0UsdValue) {
            // asset0 underweight, sell only asset1
            token0WithdrawAmountUsd = 0;
            token1WithdrawAmountUsd = _withdrawAmountUsd;
        } else {
            // asset1 underweight or weights are balanced, sell only asset0
            token0WithdrawAmountUsd =
                currentToken0UsdValue -
                targetToken0UsdValue;
            token1WithdrawAmountUsd =
                _withdrawAmountUsd -
                token0WithdrawAmountUsd;
        }
    }

    function calculateEffectiveWeights(
        uint256 _token0UsdValue,
        uint256 _totalAssetsUsdValue,
        uint256 _totalWeight
    )
        internal
        pure
        returns (uint256 effectiveWeight0, uint256 effectiveWeight1)
    {
        effectiveWeight0 =
            (_token0UsdValue * _totalWeight) /
            _totalAssetsUsdValue;
        effectiveWeight1 = _totalWeight - effectiveWeight0;
    }
}
