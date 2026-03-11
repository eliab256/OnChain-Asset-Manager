// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IIndex} from "./Interface/IIndex.sol";
import "./events/IndexEvents.sol";
import "./errors/IndexErrors.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {UnderlyingMath} from "./libraries/UnderlyingMath.sol";
import {SharesMath} from "./libraries/SharesMath.sol";
import {IndexAsset, InitStateCache} from "./types.sol";
import {console} from "forge-std/console.sol";
import {
    IUniversalRouter
} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {
    Commands
} from "@uniswap/universal-router/contracts/libraries/Commands.sol";

contract Index is IIndex, ERC20, AccessControl {
    using UnderlyingMath for uint256;
    using SharesMath for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    IERC20 internal immutable i_asset0;
    IERC20 internal immutable i_asset1;
    IERC20 internal immutable i_usdc;

    uint8 internal immutable i_decimals0;
    uint8 internal immutable i_decimals1;
    uint8 internal immutable i_decimalsUsdc;

    AggregatorV3Interface internal immutable i_asset0PriceFeed;
    AggregatorV3Interface internal immutable i_asset1PriceFeed;
    AggregatorV3Interface internal immutable i_usdcPriceFeed;

    IUniversalRouter internal immutable i_uniswapUniversalRouter;
    address internal constant PERMIT2 =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint256 public constant GRACE_PERIOD = 1 days;
    uint256 public constant MAX_DELAY = 1 hours;
    uint8 public constant DECIMALS_STANDARD = 18;
    uint128 public constant PERCENTAGE_FEE_PRECISION = 10000; // 4 decimals precision for percentage values
    uint128 public constant MAX_PERCENTAGE = 100 * PERCENTAGE_FEE_PRECISION; // 100 with 4 decimals precision

    bytes32 public constant INDEX_MANAGER_ROLE =
        keccak256("INDEX_MANAGER_ROLE");
    bytes32 public constant ROUTER_ROLE = keccak256("ROUTER_ROLE");

    uint256 internal constant WEIGHT_UPDATE_DELAY = 2 days; // timelock duration
    uint128 internal constant WEIGHT_PRECISION = 10000; // 4 decimals precision for weights to allow more granular weights
    uint128 internal constant MAX_WEIGHT = 100 * WEIGHT_PRECISION; // 100% with 4 decimals precision
    uint128 internal constant REBALANCE_THRESHOLD = 3 * WEIGHT_PRECISION; // 3% with 4 decimals precision, if the effective weight of an asset deviates from its target weight by more than this threshold, the index can be rebalanced
    uint128 internal s_weight0;
    uint128 internal s_weight1;
    uint128 internal s_pendingWeight0;
    uint128 internal s_pendingWeight1;
    uint256 internal s_weightUpdateExecutableAt; // timestamp after which the pending weights can be implemented

    //reserves standardized to 18 decimals for easier calculations, convert to token decimals when transferring to user
    uint128 internal s_asset0Reserve;
    uint128 internal s_asset1Reserve;

    uint128 internal s_totalFees;

    // Fee percentage with 4 decimals precision (e.g. 25000 = 2.5%)
    uint32 internal s_feePercentage;
    bool internal s_initialized;

    modifier isInitialized() {
        _isInitialized();
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _router,
        address _usdcAddress,
        address _usdcPricefeed,
        address _uniswapUniversalRouter,
        IndexAsset memory _asset0,
        IndexAsset memory _asset1,
        uint32 _feePercentage
    ) ERC20(_name, _symbol) {
        i_asset0 = IERC20(_asset0.asset);
        i_asset1 = IERC20(_asset1.asset);
        i_usdc = IERC20(_usdcAddress);

        s_weight0 = _asset0.weightPercentage;
        s_weight1 = _asset1.weightPercentage;

        s_feePercentage = _feePercentage;

        i_asset0PriceFeed = AggregatorV3Interface(_asset0.priceFeed);
        i_asset1PriceFeed = AggregatorV3Interface(_asset1.priceFeed);
        i_usdcPriceFeed = AggregatorV3Interface(_usdcPricefeed);

        i_uniswapUniversalRouter = IUniversalRouter(_uniswapUniversalRouter);

        i_decimals0 = IERC20Metadata(_asset0.asset).decimals();
        i_decimals1 = IERC20Metadata(_asset1.asset).decimals();
        i_decimalsUsdc = IERC20Metadata(_usdcAddress).decimals();

        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(INDEX_MANAGER_ROLE, msg.sender);
        grantRole(ROUTER_ROLE, _router);
    }

    /**
     * @dev Initializes the index with the specified underlying amount of asset0.
     * @param _underlyingAmount0 The amount (in wei) of asset0 to initialize the index with.
     */
    function initialize(
        uint256 _underlyingAmount0
    ) external onlyRole(INDEX_MANAGER_ROLE) {
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

        (uint128 weight0, uint128 weight1) = getAssetsWeights();

        // all values are converted to 18 decimals standard for easier calculations

        //underlying0amount input converted to 18 decimals standard
        uint128 underlyingAmount0 = _convertToDecimalStandard(
            _underlyingAmount0,
            i_decimals0
        ).toUint128();

        uint256 underlying0UsdValue = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                underlyingAmount0,
                getLatestPrice(address(i_asset0)),
                DECIMALS_STANDARD
            );

        uint256 underlying1UsdValue = UnderlyingMath
            .calculateAmount1UsdFromAmount0UsdAndIndexWeights(
                underlying0UsdValue,
                weight0,
                weight1
            );

        uint128 underlyingAmount1 = UnderlyingMath
            .calculateTokenAmountFromUsdValue(
                underlying1UsdValue,
                getLatestPrice(address(i_asset1)),
                DECIMALS_STANDARD
            )
            .toUint128();

        //convert underlyingAmount1 from 18 decimals standard to token decimals if necessary
        uint256 underlyingAmount1TokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                underlyingAmount1,
                i_decimals1
            );

        i_asset1.safeTransferFrom(
            msg.sender,
            address(this),
            underlyingAmount1TokenDecimals
        );

        // Mint the initial shares to the initializer
        // All Values are in 18 decimals standard, so we can directly sum the USD values of the underlying assets to calculate the initial shares to mint
        uint256 initialShares = underlying0UsdValue + underlying1UsdValue;
        _mint(msg.sender, initialShares);

        // Update reserves
        s_asset0Reserve = underlyingAmount0;
        s_asset1Reserve = underlyingAmount1;
        s_initialized = true;

        emit IndexInitialized(
            underlyingAmount0,
            underlyingAmount1,
            underlying0UsdValue,
            underlying1UsdValue,
            initialShares
        );
    }

    function mintShares(
        address _to,
        uint256 _usdcAmountIn,
        uint256 _maxTolerance
    ) public isInitialized onlyRole(ROUTER_ROLE) {
        //Transfer USDC from the user to the index
        i_usdc.safeTransferFrom(_to, address(this), _usdcAmountIn);

        // 1. Struct to cache inital state values
        InitStateCache memory initState;
        (
            initState.priceAsset0,
            initState.priceAsset1,
            initState.priceUsdc,
            initState.initialAsset0Reserve,
            initState.initialAsset1Reserve,
            initState.asset0UsdValue,
            initState.asset1UsdValue,
            initState.totalAssetUsdValue
        ) = _initFunctionValues();

        // Scope 2: Process fees
        uint256 netUsdcAmount;
        {
            // 2.1 Normalize USDC amount to 18 decimals standard for easier calculations
            uint256 usdcAmountInNormalized = _convertToDecimalStandard(
                _usdcAmountIn,
                i_decimalsUsdc
            );

            // 2.2 Calculate protocol fees on the USDC amount to mint shares and update total fees accrued
            uint128 feeAmount;
            (feeAmount, netUsdcAmount) = _calculateFees(usdcAmountInNormalized);
            s_totalFees += feeAmount;
        }

        // Scope 3:
        uint128 asset0Received;
        uint128 asset1Received;
        uint256 asset0ReceivedUsdValue;
        uint256 asset1ReceivedUsdValue;
        {
            // 3.1 get weights and effective weights before swaps
            (uint128 weight0, uint128 weight1) = getAssetsWeights();
            (uint128 effectiveWeight0, ) = _getAssetsEffectiveWights(
                initState.asset0UsdValue,
                initState.asset1UsdValue,
                initState.totalAssetUsdValue
            );

            // 3.2 calculate the amount of usdc swap for asset0 and the amount of usdc swap for asset1
            (
                uint256 usdcAmount0ToSwap,
                uint256 usdcAmount1ToSwap
            ) = UnderlyingMath.calculateDepositAllocationInUsd(
                    // @audit-info conviene calcolare effective weight dentro la library?
                    initState.totalAssetUsdValue,
                    netUsdcAmount,
                    weight0,
                    weight1,
                    effectiveWeight0
                );

            // 3.3 swap USDC for asset0 and asset1
            uint128 asset0ReceivedFromSwap = _swapFromUsdc(
                usdcAmount0ToSwap,
                address(i_asset0)
            );
            uint128 asset1ReceivedFromSwap = _swapFromUsdc(
                usdcAmount1ToSwap,
                address(i_asset1)
            );

            // 3.4 calculate the USD value of the received asset0 and asset1
            asset0ReceivedUsdValue = UnderlyingMath
                .calculateUSDValueOfTokenAmountStdDecimals(
                    asset0ReceivedFromSwap,
                    initState.priceAsset0,
                    DECIMALS_STANDARD
                );
            asset1ReceivedUsdValue = UnderlyingMath
                .calculateUSDValueOfTokenAmountStdDecimals(
                    asset1ReceivedFromSwap,
                    initState.priceAsset1,
                    DECIMALS_STANDARD
                );
        }

        //Scope 4:
        uint256 sharesToMint;
        {
            // 4.1 Calculate new Shares expected and compare with the expected shares calculated before the swap to check if the tolerance is acceptable
            (
                uint256 sharesToMintTemp,
                bool toleranceExceeded
            ) = _calculateShareToMintAndValidateTolerance(
                    netUsdcAmount,
                    _maxTolerance,
                    initState.totalAssetUsdValue,
                    asset0ReceivedUsdValue,
                    asset1ReceivedUsdValue
                );
            sharesToMint = sharesToMintTemp;

            // 4.2 If the tolerance is acceptable, mint the shares to the user, otherwise revert the transaction
            if (toleranceExceeded) {
                revert Index__ToleranceExceeded();
            }
        }

        // 5. Mint shares to the user
        _mint(_to, sharesToMint);

        // 6. Update reserves
        s_asset0Reserve += asset0Received;
        s_asset1Reserve += asset1Received;

        // 7. Emit mint event
        emit Deposit(
            _to,
            _usdcAmountIn,
            sharesToMint,
            asset0Received,
            asset1Received
        );
    }

    function _calculateShareToMintAndValidateTolerance(
        uint256 _usdcAmountIn,
        uint256 _maxTolerance,
        uint256 _totalAssetUsdValueBefore,
        uint256 asset0ReceivedUsdValue,
        uint256 asset1ReceivedUsdValue
    ) internal view returns (uint256 sharesToMint, bool toleranceExceeded) {
        uint256 expectedShares = _mintPreview(
            _usdcAmountIn,
            _totalAssetUsdValueBefore
        );
        uint256 minimumSharesToMint = expectedShares
            .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);

        sharesToMint = _mintPreview(
            asset0ReceivedUsdValue + asset1ReceivedUsdValue,
            _totalAssetUsdValueBefore
        );

        if (sharesToMint < minimumSharesToMint) {
            return (0, true);
        } else {
            return (sharesToMint, false);
        }
    }

    /**
     * @dev Previews the amount of shares to mint for a given USDC amount and tolerance.
     * @param _usdcAmountIn The amount of USDC to mint shares with (in token decimals).
     * @param _maxTolerance The maximum acceptable tolerance (in basis points).
     * @return minimumSharesToMint The minimum amount of shares to mint (in wei) after applying the fees and the tolerance.
     */
    function minMintPreview(
        uint256 _usdcAmountIn,
        uint256 _maxTolerance
    ) public view isInitialized returns (uint256 minimumSharesToMint) {
        // 1. Standadize USDC amount to 18 decimals
        uint256 _usdcAmountInNormalized = _convertToDecimalStandard(
            _usdcAmountIn,
            i_decimalsUsdc
        );
        // 2. Calculate net USDC amount after protocol fees
        (, uint256 netUsdcAmount) = _calculateFees(_usdcAmountInNormalized);

        //3. Calculate the minimum amomount of value can be lost during swaps from USDC to underlying assets
        uint256 minimumUsdAmount = netUsdcAmount
            .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);

        //4. Calculate the amount of shares to mint with the minimum USD amount after fees and tolerance, based on the current index state
        (, , , , , , , uint256 totalAssetUsdValue) = _initFunctionValues();
        minimumSharesToMint = _mintPreview(
            minimumUsdAmount,
            totalAssetUsdValue
        );
    }

    function _mintPreview(
        uint256 _usdcAmountIn,
        uint256 _totalAssetUsdValueBefore
    ) internal view returns (uint256 sharesToMint) {
        uint256 totalShares = totalSupply();
        sharesToMint = _usdcAmountIn.calculateSharesToMintFromUsdcAmount(
            _totalAssetUsdValueBefore,
            totalShares
        );
    }

    /**
     * @dev Redeems the specified amount of shares for the underlying assets.
     * @param _from The address of the user redeeming the shares, it's necessary to let router use this function.
     * @param _sharesAmount The amount of shares to redeem (in wei).
     * @param _maxTolerance The maximum acceptable tolerance (in basis points).
     */
    function redeem(
        address _from,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) public isInitialized onlyRole(ROUTER_ROLE) {
        // 1. Struct to cache inital state values
        InitStateCache memory initState;
        (
            initState.priceAsset0,
            initState.priceAsset1,
            initState.priceUsdc,
            initState.initialAsset0Reserve,
            initState.initialAsset1Reserve,
            initState.asset0UsdValue,
            initState.asset1UsdValue,
            initState.totalAssetUsdValue
        ) = _initFunctionValues();

        // 2. Calculate USD value of the shares to redeem based on totalUSDvalue and total shares supply
        uint256 sharesBurnUsdValue = _sharesAmount.calculateShareValueInUsd(
            initState.totalAssetUsdValue,
            totalSupply()
        );

        // 3. Scope: swap underlying assets for USDC
        uint128 asset0AmountToRedeem;
        uint128 asset1AmountToRedeem;
        uint256 usdcReceived;
        {
            // 3.1 Get asset weights and effective weights before swap
            (uint128 weight0, uint128 weight1) = getAssetsWeights();
            (uint128 effectiveWeight0, ) = _getAssetsEffectiveWights(
                initState.asset0UsdValue,
                initState.asset1UsdValue,
                initState.totalAssetUsdValue
            );

            // 3.2 Calculate the amount of asset0 and asset1 to swap for USDC
            (uint256 asset0UsdToSwap, uint256 asset1UsdToSwap) = UnderlyingMath // audit-info conviene calcolare effective weight dentro la library?
                .calculateWithdrawUnderlyingAmountsInUsd(
                    initState.totalAssetUsdValue,
                    sharesBurnUsdValue,
                    weight0,
                    weight1,
                    effectiveWeight0
                );
            // 4. Swap asset0 and asset1 for USDC according to the weights of the index, calculate the total amount of USDC received from the swap
            usdcReceived = _swapAssetsForUsdc(asset0UsdToSwap, asset1UsdToSwap);
        }
        // 5. Calculate net USDC amount after fees  on the USDC amount received from the swap

        (uint128 feeAmount, uint256 netUsdcAmount) = _calculateFees(
            usdcReceived
        );

        // 6. Scope: Validate tolerance
        {
            // 6.1. Subtract protocol fees from the usdc expected amount
            (, uint256 netExpectedUsdcAmount) = _calculateFees(
                sharesBurnUsdValue
            );

            // 6.2. Calculate the minimum amount of USDC to receive after applying the maximum tolerance
            uint256 minNetAmountAcceptable = netExpectedUsdcAmount
                .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);

            // 6.3. Compare USDC received with the expected USDC amount (netUsdcAmount) and tolerance
            bool toleranceExceeded;

            if (netUsdcAmount < minNetAmountAcceptable) {
                toleranceExceeded = true;
            } else {
                toleranceExceeded = false;
            }

            // 6.4. if the tolerance is acceptable, continue with the redeem, otherwise revert the transaction
            if (toleranceExceeded) {
                revert Index__ToleranceExceeded();
            }
        }

        // 7. Update reserves and total fees accrued
        s_asset0Reserve -= asset0AmountToRedeem;
        s_asset1Reserve -= asset1AmountToRedeem;
        s_totalFees += feeAmount;

        // 8 Convert USDC to its decimals before transfer
        uint256 netUsdcAmountTokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                netUsdcAmount,
                i_decimalsUsdc
            );

        // 9 Burn the shares from the user and transfer the USDC to the user
        i_usdc.safeTransfer(_from, netUsdcAmountTokenDecimals);
        _burn(_from, _sharesAmount);

        // 10 Emit burn event
        emit Withdrawal(
            _from,
            _sharesAmount,
            asset0AmountToRedeem,
            asset1AmountToRedeem,
            netUsdcAmountTokenDecimals
        );
    }

    function minRedeemPreview(
        uint256 _sharesAmountIn,
        uint256 _maxTolerance
    ) public view isInitialized returns (uint256 minUsdcToReceive) {
        (, , uint256 totalAssetUsdValue) = getAssetsUsdValue();
        uint256 usdcAmountBeforeFees = _redeemPreview(
            _sharesAmountIn,
            totalAssetUsdValue
        );

        (, uint256 netUsdcAmount) = _calculateFees(usdcAmountBeforeFees);

        //Usdc amount to receive with 18 decimals precision
        uint256 minUsdcToReceiveEighteenDecimals = netUsdcAmount
            .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);

        // Convert minUsdcToReceive from 18 decimals standard to USDC decimals
        minUsdcToReceive = _convertFromStdDecimalsToTokenDecimals(
            minUsdcToReceiveEighteenDecimals,
            i_decimalsUsdc
        );
    }

    /**
     * @dev Previews the amount of USDC to receive for a given amount of shares.
     * @param _sharesAmountIn The amount of shares to redeem (in wei).
     * @param _totalAssetUsdValueBefore The total asset USD value before redemption.
     * @return usdcToReceiveBeforeFees The amount of USDC to receive before fees (in 18 decimals).
     */
    function _redeemPreview(
        uint256 _sharesAmountIn,
        uint256 _totalAssetUsdValueBefore
    ) internal view returns (uint256 usdcToReceiveBeforeFees) {
        uint256 totalShares = totalSupply();
        usdcToReceiveBeforeFees = _sharesAmountIn.calculateShareValueInUsd(
            _totalAssetUsdValueBefore,
            totalShares
        );
    }

    /**
     * @notice Assume USDC amount is already converted to 18 decimals standard before calling this function
     * @dev Calculates the fees for a given USDC amount.
     * @param _usdcAmountIn The amount of USDC to calculate fees for (in 18 decimals).
     * @return feeAmount The calculated fee amount (in 18 decimals).
     * @return netUsdcAmount The net USDC amount after deducting fees (in 18 decimals).
     */
    function _calculateFees(
        uint256 _usdcAmountIn
    ) internal view returns (uint128 feeAmount, uint256 netUsdcAmount) {
        feeAmount = ((_usdcAmountIn * s_feePercentage) / MAX_PERCENTAGE)
            .toUint128();
        netUsdcAmount = _usdcAmountIn - feeAmount;
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
        } else if (_asset == address(i_usdc)) {
            feed = i_usdcPriceFeed;
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

        uint256 priceNormalized = _convertToDecimalStandard(
            uint256(answer),
            feed.decimals()
        );

        return priceNormalized;
    }

    function proposeUpdateWeights(
        uint128 _newWeightAsset0
    )
        external
        onlyRole(INDEX_MANAGER_ROLE)
        returns (uint256 implementationTimestamp)
    {
        if (
            s_weightUpdateExecutableAt != 0 &&
            block.timestamp < s_weightUpdateExecutableAt
        ) {
            revert Index__PendingWeightUpdate();
        }

        bool invalidWeight0 = _newWeightAsset0 >
            s_weight0 + REBALANCE_THRESHOLD ||
            _newWeightAsset0 + REBALANCE_THRESHOLD < s_weight0 ||
            _newWeightAsset0 >= MAX_WEIGHT ||
            _newWeightAsset0 == 0;
        if (invalidWeight0) {
            revert Index__InvalidWeight();
        }

        implementationTimestamp = block.timestamp + WEIGHT_UPDATE_DELAY;

        s_pendingWeight0 = _newWeightAsset0;
        s_pendingWeight1 = MAX_PERCENTAGE - _newWeightAsset0;
        s_weightUpdateExecutableAt = implementationTimestamp;

        emit WeightsUpdateProposed(
            s_pendingWeight0,
            s_pendingWeight1,
            s_weightUpdateExecutableAt
        );
    }

    function executeWeightUpdate() external onlyRole(INDEX_MANAGER_ROLE) {
        if (
            s_weightUpdateExecutableAt == 0 ||
            block.timestamp < s_weightUpdateExecutableAt
        ) {
            revert Index__PendingWeightUpdate();
        }

        s_weight0 = s_pendingWeight0;
        s_weight1 = s_pendingWeight1;

        // reset pending weights and executable timestamp
        s_pendingWeight0 = 0;
        s_pendingWeight1 = 0;
        s_weightUpdateExecutableAt = 0;

        // rebalance index with new weights
        rebalanceIndex();

        emit IndexWeightsUpdated(s_weight0, s_weight1, block.timestamp);
    }

    function collectFees(
        address _collector
    ) external onlyRole(INDEX_MANAGER_ROLE) returns (uint256 feesCollected) {
        feesCollected = s_totalFees;
        s_totalFees = 0;
        i_usdc.safeTransfer(_collector, feesCollected);

        emit FeesCollected(_collector, feesCollected);
    }

    function rebalanceIndex() public onlyRole(INDEX_MANAGER_ROLE) {
        // 1. Struct to cache inital state values
        InitStateCache memory initState;
        (
            initState.priceAsset0,
            initState.priceAsset1,
            ,
            initState.initialAsset0Reserve,
            initState.initialAsset1Reserve,
            initState.asset0UsdValue,
            initState.asset1UsdValue,
            initState.totalAssetUsdValue
        ) = _initFunctionValues();

        // 2. Scope: Check if rebalance is needed, if not revert
        {
            bool rebalanceNeeded = _checkIfRebalanceNeeded(
                initState.asset0UsdValue,
                initState.asset1UsdValue,
                initState.totalAssetUsdValue
            );
            if (!rebalanceNeeded) {
                revert Index__RebalanceNotNeeded();
            }
        }

        // 3. Calculate the amount of token0 or token1 to swap to rebalance the index according to the target weights of the index
        (uint128 weight0, uint128 weight1) = getAssetsWeights();
        (uint256 amount0ToSwap, uint256 amount1ToSwap) = UnderlyingMath
            .calculateRebalanceAmounts(
                initState.totalAssetUsdValue,
                initState.asset0UsdValue,
                initState.asset1UsdValue,
                weight0,
                weight1,
                initState.priceAsset0,
                initState.priceAsset1,
                DECIMALS_STANDARD
            );

        // 4. Conditional swap and reserve updates
        if (amount0ToSwap > 0) {
            // swap token0 for token1
            uint128 token1Received = _swapAssetForAsset(
                address(i_asset0),
                amount0ToSwap
            );
            s_asset0Reserve -= amount0ToSwap.toUint128();
            s_asset1Reserve += token1Received;
        } else {
            // swap token1 for token0
            uint128 token0Received = _swapAssetForAsset(
                address(i_asset1),
                amount1ToSwap
            );
            s_asset1Reserve -= amount1ToSwap.toUint128();
            s_asset0Reserve += token0Received;
        }

        // 5. Emit event
        emit IndexRebalanced(
            initState.initialAsset0Reserve,
            initState.initialAsset1Reserve,
            s_asset0Reserve,
            s_asset1Reserve,
            block.timestamp
        );
    }

    function _checkIfRebalanceNeeded(
        uint256 _token0UsdValue,
        uint256 _token1UsdValue,
        uint256 _totalAssetUsdValue
    ) internal view returns (bool) {
        (uint128 weight0, ) = _getAssetsEffectiveWights(
            _token0UsdValue,
            _token1UsdValue,
            _totalAssetUsdValue
        );

        if (
            weight0 < s_weight0 + REBALANCE_THRESHOLD ||
            weight0 > s_weight0 - REBALANCE_THRESHOLD
        ) {
            return false;
        } else {
            return true;
        }
    }
    /**
     * @dev Initializes the function values to avoid multiple external calls and storage reads.
     * @return priceAsset0 The price of asset0 in USD with 18 decimals.
     * @return priceAsset1 The price of asset1 in USD with 18 decimals.
     * @return priceUsdc The price of USDC in USD with 18 decimals.
     * @return initialAsset0Reserve The initial reserve of asset0.
     * @return initialAsset1Reserve The initial reserve of asset1.
     * @return asset0UsdValue The USD value of asset0.
     * @return asset1UsdValue The USD value of asset1.
     * @return totalAssetUsdValue The total USD value of the assets in the index.
     */
    function _initFunctionValues()
        internal
        view
        returns (
            uint256 priceAsset0,
            uint256 priceAsset1,
            uint256 priceUsdc,
            uint128 initialAsset0Reserve,
            uint128 initialAsset1Reserve,
            uint256 asset0UsdValue,
            uint256 asset1UsdValue,
            uint256 totalAssetUsdValue
        )
    {
        // call price feed to get the price of asset0 and asset1 in USD with 18 decimals
        priceAsset0 = getLatestPrice(address(i_asset0));
        priceAsset1 = getLatestPrice(address(i_asset1));
        priceUsdc = getLatestPrice(address(i_usdc));

        // get the initial reserves of asset0 and asset1 from storage
        (initialAsset0Reserve, initialAsset1Reserve) = getAssetsAmount();

        // calculate the USD value of asset0 and asset1 reserves
        asset0UsdValue = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                initialAsset0Reserve,
                priceAsset0,
                DECIMALS_STANDARD
            );
        asset1UsdValue = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                initialAsset1Reserve,
                priceAsset1,
                DECIMALS_STANDARD
            );
        // calculate the total USD value of the assets in the index
        totalAssetUsdValue = asset0UsdValue + asset1UsdValue;
    }

    function _swapFromUsdc(
        uint256 _usdcAmountIn,
        address _swapFor
    ) internal returns (uint128 assetReceived) {
        // TO BE IMPLEMENTED
        // 1. Convert USDC amount from 18 decimals standard to USDC decimals
        uint256 usdcAmountTokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                _usdcAmountIn,
                i_decimalsUsdc
            );

        // 2. Make Swap
        // @audit-info implement swap with slippage protection
        uint256 assetReceivedTokenDecimals;
        // 3. Convert the received asset amount to 18 decimals standard
        uint8 assetDecimals = _swapFor == address(i_asset0)
            ? i_decimals0
            : i_decimals1;
        assetReceived = _convertToDecimalStandard(
            assetReceivedTokenDecimals,
            assetDecimals
        ).toUint128();
    }

    function _swapAssetsForUsdc(
        uint256 _asset0UsdToSwap,
        uint256 _asset1UsdToSwap
    ) internal returns (uint256 usdcReceived) {
        // 1. Convert the asset amounts from USD value to token amount in 18 decimals standard
        uint256 asset0AmountToSwap = UnderlyingMath
            .calculateTokenAmountFromUsdValue(
                _asset0UsdToSwap,
                getLatestPrice(address(i_asset0)),
                DECIMALS_STANDARD
            );
        uint256 asset1AmountToSwap = UnderlyingMath
            .calculateTokenAmountFromUsdValue(
                _asset1UsdToSwap,
                getLatestPrice(address(i_asset1)),
                DECIMALS_STANDARD
            );

        // 2. Convert the asset amounts from 18 decimals standard to token decimals
        uint256 asset0AmountTokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                asset0AmountToSwap,
                i_decimals0
            );
        uint256 asset1AmountTokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                asset1AmountToSwap,
                i_decimals1
            );

        // 3. Make Swap
        // @audit-info implement swap with slippage protection
        uint256 usdcReceivedTokenDecimals;

        // 4. Convert the received USDC amount to 18 decimals standard
        usdcReceived = _convertToDecimalStandard(
            usdcReceivedTokenDecimals,
            i_decimalsUsdc
        );
    }

    function _swapAssetForAsset(
        address _swapFrom,
        uint256 _amountToSwap
    ) internal returns (uint128 amountReceived) {
        // TO BE IMPLEMENTED
        // 1. Convert the amount to swap from 18 decimals standard to token decimals
        uint256 amountToSwapTokenDecimals;
        if (_swapFrom == address(i_asset0)) {
            amountToSwapTokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                _amountToSwap,
                i_decimals0
            );
        } else {
            amountToSwapTokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                _amountToSwap,
                i_decimals1
            );
        }

        // 2. Make Swap
        // @audit-info implement swap with slippage protection
        uint256 amountReceivedTokenDecimals;

        // 3. Convert the received asset amount to 18 decimals standard
        uint8 assetDecimals = _swapFrom == address(i_asset0)
            ? i_decimals1
            : i_decimals0;
        amountReceived = _convertToDecimalStandard(
            amountReceivedTokenDecimals,
            assetDecimals
        ).toUint128();
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

    function _isInitialized() internal view {
        if (!s_initialized) {
            revert Index__NotInitialized();
        }
    }

    /**
     * @dev Gets the total USD value of the underlying assets in the index.
     * @dev Makes two calls to the price feed, unnecessary for internal functions
     * @return asset0TotalUsdValue The total USD value of asset0 in the index.
     * @return asset1TotalUsdValue The total USD value of asset1 in the index.
     * @return totalUsdValue The total USD value of the index.
     */
    function getAssetsUsdValue()
        public
        view
        returns (
            uint256 asset0TotalUsdValue,
            uint256 asset1TotalUsdValue,
            uint256 totalUsdValue
        )
    {
        (uint128 asset0Amount, uint128 asset1Amount) = getAssetsAmount();
        uint256 asset0Price = getLatestPrice(address(i_asset0));
        uint256 asset1Price = getLatestPrice(address(i_asset1));

        asset0TotalUsdValue = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                asset0Amount,
                asset0Price,
                DECIMALS_STANDARD
            );
        asset1TotalUsdValue = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                asset1Amount,
                asset1Price,
                DECIMALS_STANDARD
            );
        totalUsdValue = asset0TotalUsdValue + asset1TotalUsdValue;
    }

    function getAssetsEffectiveWeights()
        public
        view
        returns (uint256 effectiveWeight0, uint256 effectiveWeight1)
    {
        (
            uint256 asset0TotalUsdValue,
            uint256 asset1TotalUsdValue,
            uint256 totalUsdValue
        ) = getAssetsUsdValue();

        (effectiveWeight0, effectiveWeight1) = _getAssetsEffectiveWights(
            asset0TotalUsdValue,
            asset1TotalUsdValue,
            totalUsdValue
        );
    }

    function _getAssetsEffectiveWights(
        uint256 asset0UsdValue,
        uint256 asset1UsdValue,
        uint256 totalAssetUsdValue
    )
        internal
        pure
        returns (uint128 effectiveWeight0, uint128 effectiveWeight1)
    {
        // a = totalAsset0
        // b = totalAsset1
        // c = totalValue (a + b)
        // x = effectiveWeight0
        // y = effectiveWeight1
        // a : c = x : 100 => x = (a * 100) / c
        // b : c = y : 100 => y = (b * 100) / c
        effectiveWeight0 = SafeCast.toUint128(
            (asset0UsdValue * MAX_PERCENTAGE) / totalAssetUsdValue
        );
        effectiveWeight1 = SafeCast.toUint128(
            (asset1UsdValue * MAX_PERCENTAGE) / totalAssetUsdValue
        );
    }

    function getAssetsAndUsdcDecimals()
        public
        view
        returns (uint8 asset0Decimals, uint8 asset1Decimals, uint8 usdcDecimals)
    {
        return (i_decimals0, i_decimals1, i_decimalsUsdc);
    }

    function getAssetsWeights() public view returns (uint128, uint128) {
        return (s_weight0, s_weight1);
    }

    function getAssetsAmount() public view returns (uint128, uint128) {
        return (s_asset0Reserve, s_asset1Reserve);
    }

    function getAsset0() public view returns (address) {
        return address(i_asset0);
    }

    function getAsset1() public view returns (address) {
        return address(i_asset1);
    }

    function getFeesInfo()
        public
        view
        returns (uint32 feePercentage, uint128 totalFees)
    {
        return (s_feePercentage, s_totalFees);
    }

    function getPercentagePrecision() public pure returns (uint128) {
        return PERCENTAGE_FEE_PRECISION;
    }

    function getWeightPrecision() public pure returns (uint128) {
        return WEIGHT_PRECISION;
    }
}
