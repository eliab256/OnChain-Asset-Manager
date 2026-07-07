// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {UnderlyingMath} from "../../libraries/UnderlyingMath.sol";
import {SwapType} from "../types.sol";
import {ContractCodeConstants} from "../ContractCodeConstants.sol";
import "../../errors/IndexErrors.sol";
import {IndexConfigStorage} from "./IndexConfigStorage.sol";

/**
 * @title IndexSwapper
 * @notice Handles swap execution against the Universal Router and decimal conversions
 *         between token-native decimals and the internal 18-decimal standard.
 * @dev Declares `_getLatestPrice` as an unimplemented virtual hook: `_swapAssetsForUsdc`
 *      needs a fresh price at execution time, but the price-feed logic itself lives in
 *      IndexPricing (which inherits this contract and overrides the hook). This is the
 *      ONLY inheritance relationship this contract has — storage access is via the
 *      IndexConfigStorage library, no inheritance needed for that.
 */
abstract contract IndexSwapper is ContractCodeConstants {
    using UnderlyingMath for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    /// @dev Implemented by IndexPricing. See contract-level dev note.
    function _getLatestPrice(address _asset) internal view virtual returns (uint256);

    // =========================================================================
    //  Decimal conversion helpers
    // =========================================================================

    function _convertToDecimalStandard(
        uint256 _amount,
        uint8 _currentDecimals
    ) internal pure returns (uint256) {
        if (_currentDecimals <= DECIMALS_STANDARD) {
            (uint256 converted, ) = UnderlyingMath.convertToSpecificDecimal(
                _amount,
                _currentDecimals,
                DECIMALS_STANDARD
            );
            return converted;
        }
        revert Index__DecimalsStandardLowerThanCurrent();
    }

    function _convertFromStdDecimalsToTokenDecimals(
        uint256 _amount,
        uint8 _tokenDecimals
    ) internal pure returns (uint256 convertedAmount) {
        if (_tokenDecimals == DECIMALS_STANDARD) return _amount;
        if (_tokenDecimals < DECIMALS_STANDARD) {
            (convertedAmount, ) = UnderlyingMath.convertToSpecificDecimal(
                _amount,
                DECIMALS_STANDARD,
                _tokenDecimals
            );
        }
    }

    function _usdcToUsd(
        uint256 _usdcAmountStd,
        uint256 _priceUsdc
    ) internal pure returns (uint256 usdValue) {
        usdValue = (_usdcAmountStd * _priceUsdc) / (10 ** DECIMALS_STANDARD);
    }

    function _usdToUsdc(
        uint256 _usdValue,
        uint256 _priceUsdc
    ) internal pure returns (uint256 usdcAmountStd) {
        usdcAmountStd = (_usdValue * (10 ** DECIMALS_STANDARD)) / _priceUsdc;
    }

    // =========================================================================
    //  Swap wrappers
    // =========================================================================

    function _swapUsdcForAssets(
        uint256 _usdcAmountIn0,
        uint256 _usdcAmountIn1
    ) internal returns (uint256 asset0ReceivedStd, uint256 asset1ReceivedStd) {
        IndexConfigStorage.Layout storage $ = IndexConfigStorage.layout();

        uint256 usdcAmount0TokenDec;
        uint256 usdcAmount1TokenDec;
        if (_usdcAmountIn0 > 0)
            usdcAmount0TokenDec = _convertFromStdDecimalsToTokenDecimals(
                _usdcAmountIn0,
                $.decimalsUsdc
            );
        if (_usdcAmountIn1 > 0)
            usdcAmount1TokenDec = _convertFromStdDecimalsToTokenDecimals(
                _usdcAmountIn1,
                $.decimalsUsdc
            );

        bytes memory commands;
        bytes[] memory inputs;
        uint256 asset0BalanceBefore;
        uint256 asset1BalanceBefore;

        if (_usdcAmountIn0 == 0 && _usdcAmountIn1 > 0) {
            (commands, inputs, , ) = $.swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET1_USDC,
                address($.usdc),
                usdcAmount1TokenDec.toUint128()
            );
            asset1BalanceBefore = $.asset1.balanceOf(address(this));
        } else if (_usdcAmountIn0 > 0 && _usdcAmountIn1 == 0) {
            (commands, inputs, , ) = $.swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                address($.usdc),
                usdcAmount0TokenDec.toUint128()
            );
            asset0BalanceBefore = $.asset0.balanceOf(address(this));
        } else {
            (commands, inputs) = $.swapManager.buildDoubleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                SwapType.ASSET1_USDC,
                address($.usdc),
                address($.usdc),
                usdcAmount0TokenDec.toUint128(),
                usdcAmount1TokenDec.toUint128()
            );
            asset0BalanceBefore = $.asset0.balanceOf(address(this));
            asset1BalanceBefore = $.asset1.balanceOf(address(this));
        }

        $.usdc.safeTransfer(
            address($.universalRouter),
            usdcAmount0TokenDec + usdcAmount1TokenDec
        );
        $.universalRouter.execute(
            commands,
            inputs,
            block.timestamp + SWAP_DEADLINE
        );

        if (_usdcAmountIn0 > 0) {
            uint256 receivedTokenDec = $.asset0.balanceOf(address(this)) -
                asset0BalanceBefore;
            asset0ReceivedStd = _convertToDecimalStandard(
                receivedTokenDec,
                $.decimals0
            );
        }
        if (_usdcAmountIn1 > 0) {
            uint256 receivedTokenDec = $.asset1.balanceOf(address(this)) -
                asset1BalanceBefore;
            asset1ReceivedStd = _convertToDecimalStandard(
                receivedTokenDec,
                $.decimals1
            );
        }
    }

    function _swapAssetsForUsdc(
        uint256 _asset0UsdToSwap,
        uint256 _asset1UsdToSwap
    ) internal returns (uint256 usdcReceived) {
        IndexConfigStorage.Layout storage $ = IndexConfigStorage.layout();

        uint256 asset0AmountTokenDec;
        uint256 asset1AmountTokenDec;
        {
            if (_asset0UsdToSwap > 0) {
                uint256 amountStd = UnderlyingMath
                    .calculateTokenAmountFromUsdValue(
                        _asset0UsdToSwap,
                        _getLatestPrice(address($.asset0)),
                        DECIMALS_STANDARD
                    );
                asset0AmountTokenDec = _convertFromStdDecimalsToTokenDecimals(
                    amountStd,
                    $.decimals0
                );
            }
            if (_asset1UsdToSwap > 0) {
                uint256 amountStd = UnderlyingMath
                    .calculateTokenAmountFromUsdValue(
                        _asset1UsdToSwap,
                        _getLatestPrice(address($.asset1)),
                        DECIMALS_STANDARD
                    );
                asset1AmountTokenDec = _convertFromStdDecimalsToTokenDecimals(
                    amountStd,
                    $.decimals1
                );
            }
        }

        bytes memory commands;
        bytes[] memory inputs;

        if (_asset0UsdToSwap > 0 && _asset1UsdToSwap == 0) {
            (commands, inputs, , ) = $.swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                address($.asset0),
                asset0AmountTokenDec.toUint128()
            );
            $.asset0.safeTransfer(
                address($.universalRouter),
                asset0AmountTokenDec
            );
        } else if (_asset0UsdToSwap == 0 && _asset1UsdToSwap > 0) {
            (commands, inputs, , ) = $.swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET1_USDC,
                address($.asset1),
                asset1AmountTokenDec.toUint128()
            );
            $.asset1.safeTransfer(
                address($.universalRouter),
                asset1AmountTokenDec
            );
        } else {
            (commands, inputs) = $.swapManager.buildDoubleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                SwapType.ASSET1_USDC,
                address($.asset0),
                address($.asset1),
                asset0AmountTokenDec.toUint128(),
                asset1AmountTokenDec.toUint128()
            );
            $.asset0.safeTransfer(
                address($.universalRouter),
                asset0AmountTokenDec
            );
            $.asset1.safeTransfer(
                address($.universalRouter),
                asset1AmountTokenDec
            );
        }

        uint256 usdcBalanceBefore = $.usdc.balanceOf(address(this));

        $.universalRouter.execute(
            commands,
            inputs,
            block.timestamp + SWAP_DEADLINE
        );

        uint256 usdcReceivedTokenDec = $.usdc.balanceOf(address(this)) -
            usdcBalanceBefore;

        usdcReceived = _convertToDecimalStandard(
            usdcReceivedTokenDec,
            $.decimalsUsdc
        );
    }

    function _swapAssetForAsset(
        address _swapFrom,
        uint256 _amountToSwap
    ) internal returns (uint128 amountReceived) {
        IndexConfigStorage.Layout storage $ = IndexConfigStorage.layout();

        uint256 amountToSwapTokenDec;
        if (_swapFrom == address($.asset0)) {
            amountToSwapTokenDec = _convertFromStdDecimalsToTokenDecimals(
                _amountToSwap,
                $.decimals0
            );
        } else {
            amountToSwapTokenDec = _convertFromStdDecimalsToTokenDecimals(
                _amountToSwap,
                $.decimals1
            );
        }

        (
            bytes memory commands,
            bytes[] memory inputs,
            address tokenToSwap,
            address tokenToReceive
        ) = $.swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET0_ASSET1,
                _swapFrom,
                amountToSwapTokenDec.toUint128()
            );

        uint256 amountReceivedTokenDec;
        {
            uint256 balanceBefore = IERC20(tokenToReceive).balanceOf(
                address(this)
            );

            IERC20(tokenToSwap).safeTransfer(
                address($.universalRouter),
                amountToSwapTokenDec
            );
            $.universalRouter.execute(
                commands,
                inputs,
                block.timestamp + SWAP_DEADLINE
            );

            amountReceivedTokenDec =
                IERC20(tokenToReceive).balanceOf(address(this)) -
                balanceBefore;
        }

        uint8 receivedAssetDecimals = (_swapFrom == address($.asset0))
            ? $.decimals1
            : $.decimals0;
        amountReceived = _convertToDecimalStandard(
            amountReceivedTokenDec,
            receivedAssetDecimals
        ).toUint128();
    }
}