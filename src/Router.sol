// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IIndex} from "./Interface/IIndex.sol";
import {IIndexManager} from "./Interface/IIndexManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Router {
    error Router__InvalidAmounts();
    error Router__InvalidIndexAddress();
    error Router__CannotSpecifyBothAmounts();
    error Router__InvalidSlippage();

    IIndexManager public immutable i_IndexManager;
    IERC20 public immutable i_usdc;

    modifier validIndex(address _indexAddress) {
        if (!i_IndexManager.checkIsIndexInitialized(_indexAddress)) {
            revert Router__InvalidIndexAddress();
        }
        _;
    }

    modifier validAmount(uint256 _amount) {
        if (_amount == 0) {
            revert Router__InvalidAmounts();
        }
        _;
    }

    modifier validSlippage(uint256 _slippage) {
        if (_slippage >= 10000 || _slippage == 0) {
            revert Router__InvalidSlippage();
        }
        _;
    }

    modifier validInputs(
        address _indexAddress,
        uint256 _amount,
        uint256 _slippage
    ) {
        if (!i_IndexManager.checkIsIndexInitialized(_indexAddress)) {
            revert Router__InvalidIndexAddress();
        }
        if (_amount == 0) {
            revert Router__InvalidAmounts();
        }
        if (_slippage >= 10000 || _slippage == 0) {
            revert Router__InvalidSlippage();
        }
        _;
    }

    constructor(address _indexManager) {
        i_IndexManager = IIndexManager(_indexManager);
        i_usdc = IERC20(IIndexManager(_indexManager).getUsdcAddress());
    }

    function buyExactUsdcAmountOfShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxSlippage
    ) public validInputs(_indexAddress, _usdcAmount, _maxSlippage) {
        _buyShares(_indexAddress, _usdcAmount, 0, _maxSlippage);
    }

    function buyExactAmountOfSharesForUsdc(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    ) public validInputs(_indexAddress, _sharesAmount, _maxSlippage) {
        _buyShares(_indexAddress, 0, _sharesAmount, _maxSlippage);
    }

    function sellExactAmountOfSharesForUsdc(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    ) public validInputs(_indexAddress, _sharesAmount, _maxSlippage) {
        _sellShares(_indexAddress, 0, _sharesAmount, _maxSlippage);
    }

    function sellSharesForExactUsdcAmount(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxSlippage
    ) public validInputs(_indexAddress, _usdcAmount, _maxSlippage) {
        _sellShares(_indexAddress, _usdcAmount, 0, _maxSlippage);
    }

    function _buyShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    ) internal {
        IIndex index = IIndex(_indexAddress);
        // used for buyExactAmountOfSharesForUsdc
        if (_usdcAmount > 0) {
            i_usdc.approve(_indexAddress, _usdcAmount);
            index.mintShares(msg.sender, _usdcAmount, _maxSlippage);
        }

        // used for buyExactAmountOfSharesForUsdc
        if (_sharesAmount > 0) {
            //         // Calculate how much USDC is needed to get the desired shares
            //         uint256 usdcNeeded = _calculateUsdcForShares(_indexAddress, _sharesAmount);
            //
            //         // Apply slippage tolerance: user might need to pay more due to slippage
            //         uint16 percentagePrecision = index.getPercentagePrecision();
            //         uint256 maxUsdcAmount = (usdcNeeded * (percentagePrecision + _maxSlippage)) / percentagePrecision;
            //
            //         i_usdc.transferFrom(msg.sender, address(this), maxUsdcAmount);
            //         i_usdc.approve(_indexAddress, maxUsdcAmount);
            //         index.mintShares(msg.sender, maxUsdcAmount, _maxSlippage);
        }
    }

    function _sellShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    ) internal {
        IIndex index = IIndex(_indexAddress);

        // used for sellSharesForExactUsdcAmount
        //     if (_usdcAmount > 0) {
        //         // 1. Calculate the amount of shares to burn to get desired USDC
        //         uint256 sharesToBurn = _calculateSharesForUsdc(_indexAddress, _usdcAmount);
        //
        //         // 2. Apply slippage tolerance: might need to burn more shares to get exact USDC
        //         uint16 percentagePrecision = index.getPercentagePrecision();
        //         uint256 maxSharesToBurn = (sharesToBurn * (percentagePrecision + _maxSlippage)) / percentagePrecision;
        //
        //         // 3. Transfer shares from user and approve index to burn them
        //         IERC20(_indexAddress).transferFrom(msg.sender, address(this), maxSharesToBurn);
        //         IERC20(_indexAddress).approve(_indexAddress, maxSharesToBurn);
        //
        //         // 4. Call redeem to burn shares and receive USDC
        //         index.redeem(address(this), maxSharesToBurn, _maxSlippage);
        //
        //         // 5. Transfer USDC to user
        //         i_usdc.transfer(msg.sender, _usdcAmount);
        //     }
        //     // used for sellExactAmountOfSharesForUsdc
        //     if (_sharesAmount > 0) {
        //         IERC20(_indexAddress).transferFrom(msg.sender, address(this), _sharesAmount);
        //         IERC20(_indexAddress).approve(_indexAddress, _sharesAmount);
        //         index.redeem(address(this), _sharesAmount, _maxSlippage);
        //
        //         // Transfer all received USDC to user
        //         uint256 usdcBalance = i_usdc.balanceOf(address(this));
        //         i_usdc.transfer(msg.sender, usdcBalance);
        //     }
    }

    function getMinSharesAmountForExactUsdc(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxSlippage
    )
        external
        view
        validSlippage(_maxSlippage)
        returns (uint256 minSharesAmount)
    {
        IIndex index = IIndex(_indexAddress);
        uint16 percentagePrecision = index.getPercentagePrecision();
        uint256 tempShareAmount = index.mintPreview(_usdcAmount);

        minSharesAmount =
            (tempShareAmount * (percentagePrecision - _maxSlippage)) /
            percentagePrecision;
    }

    function getMinUsdcAmountForExactShares(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    )
        external
        view
        validSlippage(_maxSlippage)
        returns (uint256 minUsdcAmount)
    {
        IIndex index = IIndex(_indexAddress);
        uint16 percentagePrecision = index.getPercentagePrecision();
        uint256 tempUsdcAmount = index.redeemPreview(_sharesAmount);

        minUsdcAmount =
            (tempUsdcAmount * (percentagePrecision - _maxSlippage)) /
            percentagePrecision;
    }

    /**
     * @dev Calculate how much USDC is needed to get a specific amount of shares
     * Inverse of mintPreview: given shares, calculate USDC needed
     */
    function _calculateUsdcForShares(
        address _indexAddress,
        uint256 _sharesAmount
    ) internal view returns (uint256 usdcNeeded) {
        IIndex index = IIndex(_indexAddress);
        uint256 totalAssetUsdValue = index.getTotalAssetUsdValue();
        uint256 totalShares = index.totalSupply();

        if (totalShares == 0) {
            // If no shares exist, USDC needed equals shares amount (1:1)
            usdcNeeded = _sharesAmount;
        } else {
            // Formula: usdcNeeded = (sharesAmount * totalAssetValue) / totalShares
            // This is the inverse of: shares = (usdc * totalShares) / totalAssetValue
            usdcNeeded = (_sharesAmount * totalAssetUsdValue) / totalShares;
        }

        // Add fees back (this is approximate, as fees are calculated on input)
        (uint16 feePercentage, ) = index.getFeesInfo();
        uint16 percentagePrecision = index.getPercentagePrecision();
        usdcNeeded =
            (usdcNeeded * percentagePrecision) /
            (percentagePrecision - feePercentage);
    }

    /**
     * @dev Calculate how many shares need to be burned to get a specific amount of USDC
     * Inverse of redeemPreview: given USDC, calculate shares needed
     */
    function _calculateSharesForUsdc(
        address _indexAddress,
        uint256 _usdcAmount
    ) internal view returns (uint256 sharesNeeded) {
        IIndex index = IIndex(_indexAddress);
        uint256 totalAssetUsdValue = index.getTotalAssetUsdValue();
        uint256 totalShares = index.totalSupply();

        // Formula: sharesNeeded = (usdcAmount * totalShares) / totalAssetValue
        // This is the inverse of: usdc = (shares * totalAssetValue) / totalShares
        sharesNeeded = (_usdcAmount * totalShares) / totalAssetUsdValue;
    }
}
