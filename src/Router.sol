// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IIndex} from "./Interface/IIndex.sol";
import {ContractCodeConstants} from "./ContractCodeConstants.sol";
import {IIndexManager} from "./Interface/IIndexManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IRouter} from "./Interface/IRouter.sol";
import {
    Router__InvalidAmounts,
    Router__InvalidIndexAddress,
    Router__InvalidTolerance,
    Router__InsufficientUsdcBalance,
    Router__InsufficientSharesBalance,
    Router__ZeroAddress
} from "./errors/RouterErrors.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UpgraderAuth} from "./UpgraderAuth.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/**
 * @title Router
 * @notice Entry point for users to buy and sell shares of every Index.
 * @dev UUPS upgradeable. Deployed behind an ERC1967Proxy created by the IndexManager.
 *      Only the upgrader (the TimelockController) can upgrade it, see UpgraderAuth.
 *      Every Index stores the proxy address as its router, so an upgrade applies to all indexes.
 *      Storage follows ERC-7201 namespaced layout. ReentrancyGuard (OZ 5.x) keeps its status in its own
 *      ERC-7201 slot; on the proxy the status starts at 0, which is treated as not entered.
 */
contract Router is
    IRouter,
    Initializable,
    UpgraderAuth,
    ReentrancyGuard,
    ContractCodeConstants
{
    using SafeERC20 for IERC20;

    ////////////////////////////////////////////////////////////////////
    ///////////////////////////// storage //////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /// @custom:storage-location erc7201:onchainassetmanager.storage.Router
    struct RouterStorage {
        IIndexManager indexManager;
        IERC20 usdc;
    }

    // keccak256(abi.encode(uint256(keccak256("onchainassetmanager.storage.Router")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ROUTER_STORAGE_LOCATION =
        0x1951d9b676cbf01f1a8948ead5c25acf648eb31d2c1dddaf6ed23e4243124c00;

    ////////////////////////////////////////////////////////////////////
    //////////////////////////// modifiers /////////////////////////////
    ////////////////////////////////////////////////////////////////////

    modifier validIndex(address _indexAddress) {
        _validIndex(_indexAddress);
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
        uint256 _tolerance,
        bool isBuying
    ) {
        _validInputs(_indexAddress, _amount, _tolerance, isBuying);
        _;
    }

    ////////////////////////////////////////////////////////////////////
    ///////////////////// constructor / initializer ////////////////////
    ////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Inherit from IRouter. See interface for details.
    function initialize(
        address _indexManager,
        address _usdc,
        address _upgrader
    ) external initializer {
        if (_indexManager == address(0) || _usdc == address(0))
            revert Router__ZeroAddress();
        __UpgraderAuth_init(_upgrader);

        RouterStorage storage $ = _getRouterStorage();
        $.indexManager = IIndexManager(_indexManager);
        $.usdc = IERC20(_usdc);
    }

    ////////////////////////////////////////////////////////////////////
    ////////////////////////// buy / sell shares ///////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice Set Allowance to the index contract to spend Usdc
     * @notice buy exact amount of Usdc and receive shares, tolerance is used to protect users from front-running and price manipulation.
     * @notice If the amount of shares received is less than the minimum amount calculated with tolerance, the transaction will revert.
     * @param _indexAddress The address of the index.
     * @param _usdcAmount The amount of USDC to spend.
     * @param _maxTolerance The maximum tolerance allowed (e.g. 10_000 = 1%, 50_000 = 5%). Must be < MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION.
     */
    function buyExactUsdcAmountOfShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    )
        public
        validInputs(_indexAddress, _usdcAmount, _maxTolerance, true)
        nonReentrant
    {
        _buyShares(_indexAddress, _usdcAmount, _maxTolerance);
    }

    /// @dev Inherit from IRouter. See interface for details.
    function buyExactUsdcAmountOfSharesWithPermit(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        external
        validInputs(_indexAddress, _usdcAmount, _maxTolerance, true)
        nonReentrant
    {
        IERC20Permit(address(_getRouterStorage().usdc)).permit(
            msg.sender,
            _indexAddress,
            _usdcAmount,
            _deadline,
            _v,
            _r,
            _s
        );
        _buyShares(_indexAddress, _usdcAmount, _maxTolerance);
    }

    /**
     * @notice Set Allowance to the index contract to spend Shares
     * @notice MaxTolerance is used to revert the transaction if the tolerance is too high, protecting users from front-running and price manipulation.
     * @notice Sells an exact amount of shares for USDC, tolerance is used to protect users from front-running and price manipulation.
     * @notice If the amount of USDC received is less than the minimum amount calculated with tolerance, the transaction will revert.
     * @param _indexAddress The address of the index.
     * @param _sharesAmount The amount of shares to sell.
     * @param _maxTolerance The maximum tolerance allowed (e.g. 10_000 = 1%, 50_000 = 5%). Must be < MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION.
     */
    function sellExactAmountOfSharesForUsdc(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    )
        public
        validInputs(_indexAddress, _sharesAmount, _maxTolerance, false)
        nonReentrant
    {
        _sellShares(_indexAddress, _sharesAmount, _maxTolerance);
    }

    /**
     * @notice User set Allowance to the index contract to spend Usdc
     * @notice Buy exact amount of Usdc and receive shares, tolerance is used to protect users from front-running and price manipulation.
     * @notice If the amount of shares received is less than the minimum amount calculated with tolerance, the transaction will revert.
     * @dev This function may appear superfluous in the current implementation, as it only wraps a direct preview calculation.
     *   It has been deliberately kept as a separate internal layer to simplify the management of potentially more complex minting
     *   logic in future iterations (e.g. dynamic fee tiers, multi-asset routing, conditional share pricing).
     * @param _indexAddress The address of the index.
     * @param _usdcAmount The amount of USDC to spend.
     * @param _maxTolerance The maximum tolerance allowed (e.g. 10_000 = 1%, 50_000 = 5%). Must be < MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION.
     */
    function _buyShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    ) internal {
        IIndex index = IIndex(_indexAddress);
        index.mintShares(msg.sender, _usdcAmount, _maxTolerance);
    }

    /**
     * @notice User set Allowance to the index contract to spend Shares
     * @notice MaxTolerance is used to revert the transaction if the tolerance is too high, protecting users from front-running and price manipulation.
     * @notice Sells an exact amount of shares for USDC, tolerance is used to protect users from front-running and price manipulation.
     * @notice If the amount of USDC received is less than the minimum amount calculated with tolerance, the transaction will revert.
     * @dev This function may appear superfluous in the current implementation, as it only wraps a direct preview calculation.
     *   It has been deliberately kept as a separate internal layer to simplify the management of potentially more complex minting
     *   logic in future iterations (e.g. dynamic fee tiers, multi-asset routing, conditional share pricing).
     * @param _indexAddress The address of the index.
     * @param _sharesAmount The amount of shares to sell.
     * @param _maxTolerance The maximum tolerance allowed (e.g. 10_000 = 1%, 50_000 = 5%). Must be < MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION.
     */
    function _sellShares(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) internal {
        IIndex index = IIndex(_indexAddress);
        index.redeem(msg.sender, _sharesAmount, _maxTolerance);
    }

    /**
     * @notice Tolerace is used on net USDC amount, protocol fees are applied on input USDC
     * @notice Returned value accounts for the subtraction of protocol fees and maximum slippage tolerance
     * @dev Calculate the minimum amount of USDC to receive for a given amount of shares, based on the current index state and fees.
     * This is the inverse of redeemPreview: given shares, calculate USDC, then apply fees and tolerance to get minimum USDC to receive.
     * @param _indexAddress The address of the index.
     * @param _sharesAmount The amount of shares to redeem.
     * @param _maxTolerance The maximum tolerance allowed (e.g. 10_000 = 1%, 50_000 = 5%). Must be < MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION.
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
        validIndex(_indexAddress)
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
     * @param _indexAddress The address of the index.
     * @param _usdcAmount The amount of USDC to spend.
     * @param _maxTolerance The maximum tolerance allowed (e.g. 10_000 = 1%, 50_000 = 5%). Must be < MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION.
     */
    function getMinMintPreview(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    )
        external
        view
        validTolerance(_maxTolerance)
        validIndex(_indexAddress)
        returns (uint256 minSharesAmount)
    {
        IIndex index = IIndex(_indexAddress);
        minSharesAmount = index.minMintPreview(_usdcAmount, _maxTolerance);
    }

    /**
     * @dev Validates that the given amount is non-zero.
     * @param _amount The amount to validate.
     */
    function _validAmount(uint256 _amount) internal pure {
        if (_amount == 0) {
            revert Router__InvalidAmounts();
        }
    }

    /**
     * @dev Validates that the caller has sufficient balance for the operation.
     * @param _indexAddress The address of the index.
     * @param _amount The amount to validate.
     * @param isBuying True if the operation is a buy, false if it's a sell.
     */
    function _validBalance(
        address _indexAddress,
        uint256 _amount,
        bool isBuying
    ) internal view {
        if (isBuying) {
            uint256 userUsdcBalance = _getRouterStorage().usdc.balanceOf(
                msg.sender
            );
            if (userUsdcBalance < _amount) {
                revert Router__InsufficientUsdcBalance(
                    userUsdcBalance,
                    _amount
                );
            }
        } else {
            IIndex index = IIndex(_indexAddress);
            uint256 userSharesBalance = index.balanceOf(msg.sender);
            if (userSharesBalance < _amount) {
                revert Router__InsufficientSharesBalance(
                    userSharesBalance,
                    _amount
                );
            }
        }
    }

    /**
     * @dev Validates that the given index address is initialized.
     * @param _indexAddress The address of the index to validate.
     */
    function _validIndex(address _indexAddress) internal view {
        if (
            !_getRouterStorage().indexManager.checkIsIndexInitialized(
                _indexAddress
            )
        ) {
            revert Router__InvalidIndexAddress();
        }
    }

    /**
     * @dev Validates that the given tolerance is within the allowed range.
     * @param _tolerance The tolerance to validate. Must be > 0 and < 10%.
     */
    function _validTolerance(uint256 _tolerance) internal pure {
        if (
            _tolerance >= MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION ||
            _tolerance == 0
        ) {
            revert Router__InvalidTolerance();
        }
    }

    /**
     * @notice It works as a single validation layer for all the inputs of the buy and sell functions.
     * @dev Validates that the given inputs are valid for a buy or sell operation.
     * @param _indexAddress The address of the index.
     * @param _amount The amount to validate.
     * @param _tolerance The tolerance to validate.
     * @param isBuying True if the operation is a buy, false if it's a sell.
     */
    function _validInputs(
        address _indexAddress,
        uint256 _amount,
        uint256 _tolerance,
        bool isBuying
    ) internal view {
        _validIndex(_indexAddress);
        _validAmount(_amount);
        _validTolerance(_tolerance);
        _validBalance(_indexAddress, _amount, isBuying);
    }

    /**
     * @notice Returns the address of the IndexManager contract used by the router.
     * @return The address of the IndexManager contract.
     */
    function getIndexManager() external view returns (address) {
        return address(_getRouterStorage().indexManager);
    }

    function getMaxTolerance() external pure returns (uint256) {
        return MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION;
    }
    
    /**
     * @notice Returns the address of the USDC token used by the router.
     * @return The address of the USDC token.
     */
    function getUsdc() external view returns (address) {
        return address(_getRouterStorage().usdc);
    }

    /// @dev Inherit from IRouter. See interface for details.
    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    ////////////////////////////////////////////////////////////////////
    ////////////////////////////// storage /////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice Returns the ERC-7201 namespaced storage struct of the Router.
     * @return $ Storage pointer at ROUTER_STORAGE_LOCATION.
     */
    function _getRouterStorage()
        internal
        pure
        returns (RouterStorage storage $)
    {
        assembly {
            $.slot := ROUTER_STORAGE_LOCATION
        }
    }
}
