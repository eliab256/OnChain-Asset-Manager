// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {UnderlyingMath} from "./libraries/UnderlyinMath.sol";

contract Index is ERC20 {
    using UnderlyingMath for uint256;
    error Index__AssetNotSupported();
    error Index__PriceFeedNotAvailable();
    error Index__PriceFeedRoundStale();
    error Index__PriceIsStale();
    error Index__AlreadyInitialized();
    error Index__NotInitialized();
    error Index__DecimalsStandardLowerThanCurrent();
    error Index__DecimalsNotCorrect();
    error Index__TransferFailed(address token, uint256 amount);

    IERC20 public immutable i_asset0;
    IERC20 public immutable i_asset1;

    uint8 public immutable i_decimals0;
    uint8 public immutable i_decimals1;

    AggregatorV3Interface public immutable i_asset0PriceFeed;
    AggregatorV3Interface public immutable i_asset1PriceFeed;

    uint8 public s_weight0;
    uint8 public s_weight1;

    uint8 public s_feePercentage;
    bool public s_initialized;

    uint256 public constant MAX_DELAY = 1 hours;
    uint8 public constant DECIMALS_STANDARD = 18;

    modifier isInitialized() {
        if (!s_initialized) {
            revert Index__NotInitialized();
        }
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _asset0,
        address _asset1,
        uint8 _weight0,
        uint8 _weight1,
        address _asset0PriceFeed,
        address _asset1PriceFeed,
        uint8 _feePercentage
    ) ERC20(_name, _symbol) {
        i_asset0 = IERC20(_asset0);
        i_asset1 = IERC20(_asset1);

        s_weight0 = _weight0;
        s_weight1 = _weight1;
        s_feePercentage = _feePercentage;

        i_asset0PriceFeed = AggregatorV3Interface(_asset0PriceFeed);
        i_asset1PriceFeed = AggregatorV3Interface(_asset1PriceFeed);

        i_decimals0 = IERC20Metadata(_asset0).decimals();
        i_decimals1 = IERC20Metadata(_asset1).decimals();

        //i_asset0.transferFrom(msg.sender, address(this), _underlyingAmount0); //msg.sender è da sostituire
        // i_asset1.transferFrom(msg.sender, address(this), _underlyingAmount1); //msg.sender è da sostituire

        //mint shares a owner
    }

    /**
     * @dev Initializes the index with the specified underlying amount of asset0.
     * @param _underlyingAmount0 The amount (in wei) of asset0 to initialize the index with.
     */
    function initialize(uint256 _underlyingAmount0) external /*onlyOwner*/ {
        if (s_initialized) {
            revert Index__AlreadyInitialized();
        }
        bool asset0success = i_asset0.transferFrom(
            msg.sender,
            address(this),
            _underlyingAmount0
        );
        if (!asset0success) {
            revert Index__TransferFailed(address(i_asset0), _underlyingAmount0);
        }

        //prices already standardized to 18 decimals
        uint256 underlyingAsset1Price = getLatestPrice(address(i_asset1));
        uint256 underlyingAsset0Price = getLatestPrice(address(i_asset0));

        //underlying0amount input converted to 18 decimals standard
        uint256 underlyingAmount0 = _convertToDecimalStandard(
            _underlyingAmount0,
            i_decimals0
        );

        uint256 underlying0UsdValue = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                underlyingAmount0,
                underlyingAsset0Price,
                DECIMALS_STANDARD
            );

        uint256 underlying1UsdValue = UnderlyingMath
            .calculateAmount1USDFromAmount0USDAndIndexWeights(
                underlying0UsdValue,
                s_weight0,
                s_weight1
            );

        uint256 underlyingAmount1 = UnderlyingMath
            .calculateTokenAmountFromUSDValue(
                underlying1UsdValue,
                underlyingAsset1Price,
                DECIMALS_STANDARD
            );


        //convert underlyingAmount1 from 18 decimals standard to token decimals if necessary
        underlyingAmount1 = _convertFromStdDecimalsToTokenDecimals(
            underlyingAmount1,
            i_decimals1
        );

        bool asset1success = i_asset1.transferFrom(
            msg.sender,
            address(this),
            underlyingAmount1
        );
        if (!asset1success) {
            revert Index__TransferFailed(address(i_asset1), underlyingAmount1);
        }

        s_initialized = true;
    }

    /**
     * @dev Initializes the index with the specified underlying amount of asset1.
     * @param _asset The asset who want to recover price.
     * @return price of the asset in USD with 18 decimals.
     */
    function getLatestPrice(address _asset) public view returns (uint256) {
        AggregatorV3Interface feed;
        if (_asset == address(i_asset0)) {
            feed = i_asset0PriceFeed;
        } else if (_asset == address(i_asset1)) {
            feed = i_asset1PriceFeed;
        } else {
            revert Index__AssetNotSupported();
        }
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (answer <= 0) {
            revert Index__PriceFeedNotAvailable();
        }

        if (answeredInRound < roundId) {
            revert Index__PriceFeedRoundStale();
        }

        if (block.timestamp - updatedAt > MAX_DELAY) {
            revert Index__PriceIsStale();
        }

        return _convertToDecimalStandard(uint256(answer), feed.decimals());
    }

    /**
     * @dev Used to convert the price from the feed to a standard 18 decimals format.
     * @dev Converts a number to a standard 18 decimals format.
     * @param _amount The amount to convert.
     * @param _currentDecimals The current decimals of the token.
     * @return The converted number in 18 decimals format.
     */
    function _convertToDecimalStandard(
        uint256 _amount,
        uint8 _currentDecimals
    ) internal pure returns (uint256) {
        if (_currentDecimals >= DECIMALS_STANDARD) {
            (uint256 convertedAmount, ) = UnderlyingMath
                .convertToSpecificDecimal(
                    _amount,
                    _currentDecimals,
                    DECIMALS_STANDARD
                );
            return convertedAmount;
        } else {
            revert Index__DecimalsStandardLowerThanCurrent();
        }
    }

    /**
     * @dev Used to convert the amount of the token from the standard 18 decimals format to the token decimals.
     * @dev Used before transferring the token to transfer the correct amount of token to the user.
     * @param _amount The amount to convert in 18 decimals format.
     * @param _tokenDecimals The decimals of the token to convert to.
     * @return convertedAmount The converted amount in the token decimals format.
     */
    function _convertFromStdDecimalsToTokenDecimals(
        uint256 _amount,
        uint8 _tokenDecimals
    ) internal pure returns (uint256 convertedAmount) {
        if (_tokenDecimals == DECIMALS_STANDARD) {
            convertedAmount = _amount;
        }

        if (_tokenDecimals < DECIMALS_STANDARD) {
            (convertedAmount, ) = UnderlyingMath.convertToSpecificDecimal(
                _amount,
                DECIMALS_STANDARD,
                _tokenDecimals
            );
            return convertedAmount;
        }
    }

    function getToken0Amount() public view returns (uint256) {
        return i_asset0.balanceOf(address(this));
    }

    function getToken1Amount() public view returns (uint256) {
        return i_asset1.balanceOf(address(this));
    }
}
