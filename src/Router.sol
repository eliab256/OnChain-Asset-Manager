// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IIndex} from "./Interface/IIndex.sol";
import {IIndexManager} from "./Interface/IIndexManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRouter} from "./Interface/IRouter.sol";
import "./errors/RouterErrors.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Router is ReentrancyGuard {
    IIndexManager private immutable i_IndexManager;
    IERC20 private immutable i_usdc;

    using SafeERC20 for IERC20;

    modifier validIndex(address _indexAddress) {
        _validIndex(_indexAddress);
        _;
    }

    modifier validAmount(uint256 _amount) {
        _validAmount(_amount);
        _;
    }

    modifier validTolerance(uint256 _tolerance) {
        _validTolerance(_tolerance);
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
        _validInputs(_indexAddress, _amount, _tolerance);
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
     * @param _maxTolerance The maximum tolerance allowed (in basis points, e.g. 10000 = 1%).
     */
    function buyExactUsdcAmountOfShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    )
        public
        validInputs(_indexAddress, _usdcAmount, _maxTolerance)
        nonReentrant
    {
        _buyShares(_indexAddress, _usdcAmount, _maxTolerance);
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
    )
        public
        validInputs(_indexAddress, _sharesAmount, _maxTolerance)
        nonReentrant
    {
        _sellShares(_indexAddress, _sharesAmount, _maxTolerance);
    }

    function _buyShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    ) internal {
        IIndex index = IIndex(_indexAddress);
        i_usdc.approve(_indexAddress, _usdcAmount);
        //@audit-info insex call transferFrom routerContract
        index.mintShares(msg.sender, _usdcAmount, _maxTolerance);
    }

    function _sellShares(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) internal {
        IIndex index = IIndex(_indexAddress);
        // @audit-issue change transfer logic to optimize gas
        IERC20(_indexAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _sharesAmount
        );
        IERC20(_indexAddress).approve(_indexAddress, _sharesAmount);
        index.redeem(address(this), _sharesAmount, _maxTolerance);

        // Transfer all received USDC to user
        uint256 usdcBalance = i_usdc.balanceOf(address(this));
        i_usdc.safeTransfer(msg.sender, usdcBalance);
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
    function getMinRedeemPreview(
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
     * @notice Calculate the minimum amount of shares to receive for a given amount of USDC, based on the current index state and fees.
     * @return minSharesAmount The minimum amount of shares to receive after fees and tolerance (in token decimals, 18 for shares).
     * @notice Tolerace is used on net USDC amount, protocol fees are applied on input USDC
     *                                100USDC  -     1%fee    = 99USDC net amount
     * minSharesAmount calculation: usdcAmount - protocolfees = usdcAfterFees
     *     99USDC    * (100% - 5%)        = 94.05USDC after tolerance
     * usdcAfterFees * (1 - maxTolerance) = usdcAfterFeesAndTolerance
     * sharesAmount = (usdcAfterFeesAndTolerance * totalShares) / totalAsset
     */
    function getMinMintPreview(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    ) external view returns (uint256 minSharesAmount) {
        IIndex index = IIndex(_indexAddress);
        minSharesAmount = index.minMintPreview(_usdcAmount, _maxTolerance);
    }

    function _validAmount(uint256 _amount) internal pure {
        if (_amount == 0) {
            revert Router__InvalidAmounts();
        }
    }

    function _validIndex(address _indexAddress) internal view {
        if (!i_IndexManager.checkIsIndexInitialized(_indexAddress)) {
            revert Router__InvalidIndexAddress();
        }
    }

    function _validTolerance(uint256 _tolerance) internal pure {
        if (_tolerance >= 10000 || _tolerance == 0) {
            revert Router__InvalidTolerance();
        }
    }

    function _validInputs(
        address _indexAddress,
        uint256 _amount,
        uint256 _tolerance
    ) internal view {
        _validIndex(_indexAddress);
        _validAmount(_amount);
        _validTolerance(_tolerance);
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

// /**
//  * @notice MaxTolerance is used to revert the transaction if the tolerance is too high, protecting users from front-running and price manipulation.
//  * @dev Buys given amount of shares for a  max USDC amount.
//  * @param _indexAddress The address of the index.
//  * @param _sharesAmount The amount of shares to buy.
//  * @param _maxTolerance The maximum tolerance allowed (in basis points, e.g. 10000 = 1%).
//  */
// function buyExactAmountOfSharesForUsdc(
//     address _indexAddress,
//     uint256 _sharesAmount,
//     uint256 _maxTolerance
// )
//     public
//     validInputs(_indexAddress, _sharesAmount, _maxTolerance)
//     nonReentrant
// {
//     _buyShares(_indexAddress, 0, _sharesAmount, _maxTolerance);
// }

//     /**
//  * @notice Is sellMin and not sellExact because we can't guarantee the exact amount of USDC received for a given shares amount, due to tolerance.
//  * @notice MaxTolerance is used to revert the transaction if the tolerance is too high, protecting users from front-running and price manipulation.
//  * @param _indexAddress The address of the index.
//  * @param _usdcAmount The amount of USDC to receive.
//  * @param _maxTolerance The maximum tolerance allowed.
//  */
// function sellSharesForExactUsdcAmount(
//     address _indexAddress,
//     uint256 _usdcAmount,
//     uint256 _maxTolerance
// )
//     public
//     validInputs(_indexAddress, _usdcAmount, _maxTolerance)
//     nonReentrant
// {
//     _sellShares(_indexAddress, _usdcAmount, 0, _maxTolerance);
// }
