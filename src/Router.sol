// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IIndex} from "./Interface/IIndex.sol";
import {IIndexManager} from "./Interface/IIndexManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRouter} from "./Interface/IRouter.sol";
import "./errors/RouterErrors.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Router is IRouter, ReentrancyGuard {
    IIndexManager private immutable i_IndexManager;
    IERC20 private immutable i_usdc;

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

    modifier validTolerance(uint256 _tolerance) {
        if (_tolerance >= 10000 || _tolerance == 0) {
            revert Router__InvalidTolerance();
        }
        _;
    }

    /**
     * @dev Combined all the modifiers above into a single modifier to avoid having to repeat them for each function.
     */
    modifier validInputs(
        address _indexAddress,
        uint256 _amount,
        uint256 _tolerance
    ) {
        if (!i_IndexManager.checkIsIndexInitialized(_indexAddress)) {
            revert Router__InvalidIndexAddress();
        }
        if (_amount == 0) {
            revert Router__InvalidAmounts();
        }
        if (_tolerance >= 10000 || _tolerance == 0) {
            revert Router__InvalidTolerance();
        }
        _;
    }

    constructor(address _indexManager) {
        i_IndexManager = IIndexManager(_indexManager);
        i_usdc = IERC20(IIndexManager(_indexManager).getUsdcAddress());
    }

    /**
     * @notice buy exact amount of Usdc and receive shares, tolerance is used to protect users from front-running and price manipulation.
     * @notice If the amount of shares received is less than the minimum amount calculated with tolerance, the transaction will revert.
     * @param _indexAddress The address of the index.
     * @param _usdcAmount The amount of USDC to spend.
     * @param _maxTolerance The maximum tolerance allowed (in basis points, e.g. 100 = 1%).
     */
    function buyExactUsdcAmountOfShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    ) public validInputs(_indexAddress, _usdcAmount, _maxTolerance) nonReentrant {
        _buyShares(_indexAddress, _usdcAmount, 0, _maxTolerance);
    }

    /**
     * @notice Is buyMin and not buyExact because we can't guarantee the exact amount of shares received for a given USDC amount, due to tolerance.
     * @notice MaxTolerance is used to revert the transaction if the tolerance is too high, protecting users from front-running and price manipulation.
     * @dev Buys the minimum amount of shares for a given USDC amount.
     * @param _indexAddress The address of the index.
     * @param _sharesAmount The amount of shares to buy.
     * @param _maxTolerance The maximum tolerance allowed.
     */
    function buyMinAmountOfSharesForUsdc(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) public validInputs(_indexAddress, _sharesAmount, _maxTolerance) nonReentrant {
        _buyShares(_indexAddress, 0, _sharesAmount, _maxTolerance);
    }

    /**
     * @notice Sells an exact amount of shares for USDC, tolerance is used to protect users from front-running and price manipulation.
     * @notice If the amount of USDC received is less than the minimum amount calculated with tolerance, the transaction will revert.
     * @param _indexAddress The address of the index.
     * @param _sharesAmount The amount of shares to sell.
     * @param _maxTolerance The maximum tolerance allowed (in basis points, e.g. 100 = 1%).
     */
    function sellExactAmountOfSharesForUsdc(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) public validInputs(_indexAddress, _sharesAmount, _maxTolerance) nonReentrant {
        _sellShares(_indexAddress, 0, _sharesAmount, _maxTolerance);
    }

    /**
     * @notice Is sellMin and not sellExact because we can't guarantee the exact amount of USDC received for a given shares amount, due to tolerance.
     * @notice MaxTolerance is used to revert the transaction if the tolerance is too high, protecting users from front-running and price manipulation.
     * @param _indexAddress The address of the index.
     * @param _usdcAmount The amount of USDC to receive.
     * @param _maxTolerance The maximum tolerance allowed.
     */
    function sellSharesForMinUsdcAmount(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    ) public validInputs(_indexAddress, _usdcAmount, _maxTolerance) nonReentrant {
        _sellShares(_indexAddress, _usdcAmount, 0, _maxTolerance);
    }

    function _buyShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) internal {
        IIndex index = IIndex(_indexAddress);
        // used for buyExactUsdcAmountOfShares
        if (_usdcAmount > 0) {
            i_usdc.approve(_indexAddress, _usdcAmount);
            //@audit-info insex call transferFrom routerContract
            index.mintShares(msg.sender, _usdcAmount, _maxTolerance);
        }

        // used for buyMinAmountOfSharesForUsdc
        if (_sharesAmount > 0) {
            //  @audit-info implement for buyMinAmountOfSharesForUsdc: calculate how much USDC is needed for the desired shares, then approve and call mintShares
            
            // 1. index contract need allowance to transfer USDC from user
            // 2.
        }
    }

    function _sellShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) internal {
        IIndex index = IIndex(_indexAddress);

        //used for sellSharesForMinUsdcAmount
        if (_usdcAmount > 0) {
            // 1. Calculate the amount of shares to burn to get desired USDC
            uint256 sharesToBurn = _calculateSharesForUsdc(
                _indexAddress,
                _usdcAmount
            );

            // 2. Apply tolerance: might need to burn more shares to get exact USDC
            // @audit-info _sellShares: call redeem, if received USDC is less than desired amount less maxtolerance, revert

            // 3. Transfer shares from user and approve index to burn them
            //RC20(_indexAddress).transferFrom(msg.sender, address(this), maxSharesToBurn);
            //RC20(_indexAddress).approve(_indexAddress, maxSharesToBurn);

            // 4. Call redeem to burn shares and receive USDC
            //ndex.redeem(address(this), maxSharesToBurn, _maxTolerance);

            // 5. Transfer USDC to user
            i_usdc.transfer(msg.sender, _usdcAmount);
        }

        // used for sellExactAmountOfSharesForUsdc
        if (_sharesAmount > 0) {
            // @audit-issue change transfer logic to optimize gas
            IERC20(_indexAddress).transferFrom(
                msg.sender,
                address(this),
                _sharesAmount
            );
            IERC20(_indexAddress).approve(_indexAddress, _sharesAmount);
            index.redeem(address(this), _sharesAmount, _maxTolerance);

            // Transfer all received USDC to user
            uint256 usdcBalance = i_usdc.balanceOf(address(this));
            i_usdc.transfer(msg.sender, usdcBalance);
        }
    }

    function getMinMintSharesAmountForExactUsdc(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    )
        external
        view
        validTolerance(_maxTolerance)
        returns (uint256 minSharesAmount)
    {
        IIndex index = IIndex(_indexAddress);
        minSharesAmount = index.minMintPreview(_usdcAmount, _maxTolerance);
    }

    function getMaxUsdcAmountToMintExactShares(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    )
        external
        view
        validTolerance(_maxTolerance)
        returns (uint256 maxUsdcAmount)
    {
        IIndex index = IIndex(_indexAddress);

    }


    /**
     * @notice Tolerace is used on net USDC amount, protocol fees are applied on input USDC
     * @notice Returned value accounts for the subtraction of protocol fees and maximum slippage tolerance
     * @dev Calculate the minimum amount of USDC to receive for a given amount of shares, based on the current index state and fees.
     * This is the inverse of redeemPreview: given shares, calculate USDC, then apply fees and tolerance to get minimum USDC to receive.
     * @param _indexAddress The address of the index.
     * @param _sharesAmount The amount of shares to redeem.
     * @param _maxTolerance The maximum tolerance allowed (in basis points, e.g. 100 = 1%). 
     * @return minUsdcAmount The minimum amount of USDC to receive after fees and tolerance (in token decimals, 6 for USDC).
     */
    function getMinUsdcAmountFromRedeemExactShares(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    )
        external
        view
        validTolerance(_maxTolerance)
        returns (uint256 minUsdcAmount)
    {
        IIndex index = IIndex(_indexAddress);
        minUsdcAmount = index.minRedeemPreview(_sharesAmount, _maxTolerance);
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
        (, , uint256 totalAssetUsdValue )= index.getAssetsUsdValue();
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
        (uint32 feePercentage, ) = index.getFeesInfo();
        uint112 percentagePrecision = index.getPercentagePrecision();
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
        (,,uint256 totalAssetUsdValue) = index.getAssetsUsdValue();
        uint256 totalShares = index.totalSupply();

        // Formula: sharesNeeded = (usdcAmount * totalShares) / totalAssetValue
        // This is the inverse of: usdc = (shares * totalAssetValue) / totalShares
        sharesNeeded = (_usdcAmount * totalShares) / totalAssetUsdValue;
    }

    /**
     * @notice Returns the address of the IndexManager contract used by the router.
     * @return The address of the IndexManager contract.
     */
    function getIndexManager() external view returns (address) {
        return address(i_IndexManager);
    }

   /**
    * @notice Returns the address of the USDC token used by the router.
    * @return The address of the USDC token.
    */
    function getUsdc() external view returns (address) {
        return address(i_usdc);
    }
}
