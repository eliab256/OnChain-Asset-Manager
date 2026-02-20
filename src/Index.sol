// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {UnderlyingMath} from "./libraries/UnderlyinMath.sol";

contract Index is ERC20, Ownable {
    using UnderlyingMath for uint256;
    using SafeERC20 for IERC20;

    error Index__AssetNotSupported();
    error Index__PriceFeedNotAvailable();
    error Index__PriceFeedRoundStale();
    error Index__PriceIsStale();
    error Index__AlreadyInitialized();
    error Index__InvalidUnderlyingAmount();
    error Index__NotInitialized();
    error Index__DecimalsStandardLowerThanCurrent();
    error Index__DecimalsNotCorrect();
    error Index__TransferFailed(address token, uint256 amount);
    error Index__SlippageExceeded();

    IERC20 public immutable i_asset0;
    IERC20 public immutable i_asset1;
    IERC20 public immutable i_usdc;

    uint8 internal immutable i_decimals0;
    uint8 internal immutable i_decimals1;
    uint8 internal immutable i_decimalsUsdc;

    AggregatorV3Interface public immutable i_asset0PriceFeed;
    AggregatorV3Interface public immutable i_asset1PriceFeed;

    uint256 public constant MAX_DELAY = 1 hours;
    uint8 public constant DECIMALS_STANDARD = 18;
    uint16 public constant PERCENTAGE_PRECISION = 10000; // 4 decimals precision for percentage values
    uint16 public constant MAX_PERCENTAGE = 100 * PERCENTAGE_PRECISION; // 100 with 4 decimals precision

    uint8 internal s_weight0;
    uint8 internal s_weight1;

    uint112 internal s_totalFees;

    uint112 internal s_totalToken0Amount;
    uint112 internal s_totalToken1Amount;

    // Fee percentage with 4 decimals precision (e.g. 25000 = 2.5%)
    uint16 internal s_feePercentage;
    bool internal s_initialized;

    modifier isInitialized() {
        if (!s_initialized) {
            revert Index__NotInitialized();
        }
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _adminController,
        address _usdcAddress,
        address _asset0,
        address _asset1,
        uint8 _weight0,
        uint8 _weight1,
        address _asset0PriceFeed,
        address _asset1PriceFeed,
        uint8 _feePercentage
    ) ERC20(_name, _symbol) Ownable(_adminController) {
        i_asset0 = IERC20(_asset0);
        i_asset1 = IERC20(_asset1);
        i_usdc = IERC20(_usdcAddress);

        s_weight0 = _weight0;
        s_weight1 = _weight1;
        i_decimalsUsdc = IERC20Metadata(_usdcAddress).decimals();

        s_feePercentage = _feePercentage;

        i_asset0PriceFeed = AggregatorV3Interface(_asset0PriceFeed);
        i_asset1PriceFeed = AggregatorV3Interface(_asset1PriceFeed);

        i_decimals0 = IERC20Metadata(_asset0).decimals();
        i_decimals1 = IERC20Metadata(_asset1).decimals();
    }

    /**
     * @dev Initializes the index with the specified underlying amount of asset0.
     * @param _underlyingAmount0 The amount (in wei) of asset0 to initialize the index with.
     */
    function initialize(uint256 _underlyingAmount0) external onlyOwner {
        if (s_initialized) {
            revert Index__AlreadyInitialized();
        }

        if (_underlyingAmount0 == 0) {
            revert Index__InvalidUnderlyingAmount();
        }
        i_asset0.safeTransferFrom(
            msg.sender,
            address(this),
            _underlyingAmount0
        );

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

        i_asset1.safeTransferFrom(msg.sender, address(this), underlyingAmount1);

        // Mint the initial shares to the initializer
        // All Values are in 18 decimals standard, so we can directly sum the USD values of the underlying assets to calculate the initial shares to mint
        uint256 initialShares = underlying0UsdValue + underlying1UsdValue;
        _mint(msg.sender, initialShares);

        s_initialized = true;
    }

    function mintShares(
        address _to,
        uint256 _usdcAmount,
        uint256 _maxSlippage
    ) public isInitialized {
        // 1. Calculate and subtract fees from the USDC amount
        (uint256 feeAmount, uint256 netUsdcAmount) = _calculateFees(
            _usdcAmount
        );
        s_totalFees += feeAmount;

        // 2. Calculate the amount of shares to mint.
        uint256 expectedShares = _mintPreview(netUsdcAmount);
        uint256 minimumSharesToMint = (expectedShares *
            (MAX_PERCENTAGE - _maxSlippage)) / MAX_PERCENTAGE;

        // 3. Transfer USDC from the user to the index
        i_usdc.safeTransferFrom(_to, address(this), _usdcAmount);

        // 4. Swap USDC for token0 and token1
        (uint256 token0Received, uint256 token1received) = _swapWithWeights(
            netUsdcAmount,
            s_weight0,
            s_weight1
        );

        s_totalToken0Amount += token0Received;
        s_totalToken1Amount += token1received;

        // 5. Calculate new Shares expected and compare with the expected shares calculated before the swap to check if the slippage is acceptable
        uint256 sharesToMint = _mintPreview(netUsdcAmount);

        // 5. Call the mint function to mint shares to the user
        if (sharesToMint < minimumSharesToMint) {
            revert Index__SlippageExceeded();
        } else {
            _mint(_to, sharesToMint);
        }

        // 6. Swap USDC for the underlying assets according to the index weights and update the index balances
    }

    function mintPreview(
        uint256 _usdcAmount
    ) public view isInitialized returns (uint256 sharesToMint) {
        (, uint256 netUsdcAmount) = _calculateFees(_usdcAmount);
        uint256 netUsdcAmountStdDecimals = _convertToDecimalStandard(
            netUsdcAmount,
            i_decimalsUsdc
        );
        sharesToMint = _mintPreview(netUsdcAmountStdDecimals);
    }

    function _mintPreview(
        uint256 _usdcAmount
    ) internal view returns (uint256 sharesToMint) {
        uint256 totalAssetUsdValue = getTotalAssetUsdValue();
        uint256 usdcAmountStdDecimals = _convertToDecimalStandard(
            _usdcAmount,
            i_decimalsUsdc
        );

        if (totalAssetUsdValue == 0) {
            sharesToMint = usdcAmountStdDecimals;
        } else {
            uint256 totalShares = totalSupply();
            sharesToMint =
                (usdcAmountStdDecimals * totalShares) /
                totalAssetUsdValue;
        }
    }

    function _calculateFees(
        uint256 _usdcAmount
    ) internal view returns (uint256 feeAmount, uint256 netUsdcAmount) {
        feeAmount = (_usdcAmount * s_feePercentage) / MAX_PERCENTAGE;
        netUsdcAmount = _usdcAmount - feeAmount;
    }

    /**
     * @dev Redeems the specified amount of shares for the underlying assets.
     * @param _from The address of the user redeeming the shares, it's necessary to let router use this function.
     * @param _sharesAmount The amount of shares to redeem (in wei).
     * @param _maxSlippage The maximum acceptable slippage (in basis points).
     */
    function redeem(
        address _from,
        uint256 _sharesAmount,
        uint256 _maxSlippage
    ) public isInitialized {
        uint256 expectedUsdcAmount = redeemPreview(_sharesAmount);
        uint256 minimumUsdcAmount = (expectedUsdcAmount *
            (MAX_PERCENTAGE - _maxSlippage)) / MAX_PERCENTAGE;
        // 1. Calculate the amount of Token0 and Token1 need to be swapped to USDC to redeem the shares and update the index balances

        // if (expectedUsdcAmount < minimumUsdcAmount) {
        //     revert Index__SlippageExceeded();
        // }
        _burn(_from, _sharesAmount);
        i_usdc.safeTransfer(_from, expectedUsdcAmount);
    }

    function redeemPreview(
        uint256 _sharesAmount
    ) public view isInitialized returns (uint256 usdcToReceive) {
        uint256 totalShares = totalSupply();
        uint256 totalAssetUsdValue = getTotalAssetUsdValue();

        uint256 usdcAmountStdDecimals = (_sharesAmount * totalAssetUsdValue) /
            totalShares;

        usdcToReceive = _convertFromStdDecimalsToTokenDecimals(
            usdcAmountStdDecimals,
            i_decimalsUsdc
        );
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
     * @param _currentDecimals The current decimals of the token.    grep -n "remappings" -A200 foundry.toml | sed -n '/remappings/{n;:a;/]/q;p; n; ba}' | tr -d '", ' > remappings.txt
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

    function getAsset0TotalUsdValue()
        public
        view
        returns (uint256 asset0TotalUsdValue)
    {
        (uint112 asset0Amount, ) = getAssetsAmount();
        uint256 asset0Price = getLatestPrice(address(i_asset0));
        asset0TotalUsdValue = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                _convertToDecimalStandard(asset0Amount, i_decimals0),
                asset0Price,
                DECIMALS_STANDARD
            );
    }

    function getAsset1TotalUsdValue()
        public
        view
        returns (uint256 asset1TotalUsdValue)
    {
        (, uint112 asset1Amount) = getAssetsAmount();
        uint256 asset1Price = getLatestPrice(address(i_asset1));
        asset1TotalUsdValue = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                _convertToDecimalStandard(asset1Amount, i_decimals1),
                asset1Price,
                DECIMALS_STANDARD
            );
    }

    function getTotalAssetUsdValue()
        public
        view
        returns (uint256 totalUsdValue)
    {
        uint256 asset0UsdValue = getAsset0TotalUsdValue();
        uint256 asset1UsdValue = getAsset1TotalUsdValue();
        totalUsdValue = asset0UsdValue + asset1UsdValue;
    }

    function getAssetsAndUsdcDecimals()
        public
        view
        returns (uint8 asset0Decimals, uint8 asset1Decimals, uint8 usdcDecimals)
    {
        return (i_decimals0, i_decimals1, i_decimalsUsdc);
    }

    function getAssetsWeights() public view returns (uint8, uint8) {
        return (s_weight0, s_weight1);
    }

    function getAssetsAmount() public view returns (uint256, uint256) {
        return (s_totalToken0Amount, s_totalToken1Amount);
    }

    function getFeesInfo()
        public
        view
        returns (uint16 feePercentage, uint112 totalFees)
    {
        return (s_feePercentage, s_totalFees);
    }

    function getPercentagePrecision() public pure returns (uint16) {
        return PERCENTAGE_PRECISION;
    }
}
