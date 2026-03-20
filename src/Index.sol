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
import {IndexAsset, InitStateCache, SwapType} from "./types.sol";
import {CodeConstants} from "./CodeConstants.sol";
import {console} from "forge-std/console.sol";
import {ISwapManager} from "./Interface/ISwapManager.sol";
import {
    IUniversalRouter
} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";

contract Index is IIndex, ERC20, AccessControl, CodeConstants {
    using UnderlyingMath for uint256;
    using SharesMath for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant INDEX_MANAGER_ROLE =
        keccak256("INDEX_MANAGER_ROLE");
    bytes32 public constant ROUTER_ROLE = keccak256("ROUTER_ROLE");

    IERC20 internal immutable i_asset0;
    IERC20 internal immutable i_asset1;
    IERC20 internal immutable i_usdc;

    uint8 internal immutable i_decimals0;
    uint8 internal immutable i_decimals1;
    uint8 internal immutable i_decimalsUsdc;

    AggregatorV3Interface internal immutable i_asset0PriceFeed;
    AggregatorV3Interface internal immutable i_asset1PriceFeed;
    AggregatorV3Interface internal immutable i_usdcPriceFeed;

    ISwapManager internal immutable i_swapManager;
    IUniversalRouter internal immutable i_universalRouter;

    uint128 internal s_weight0;
    uint128 internal s_weight1;
    uint128 internal s_pendingWeight0;
    uint128 internal s_pendingWeight1;
    uint256 internal s_weightUpdateExecutableAt; // timestamp after which the pending weights can be implemented

    // Reserves are standardized to 18 decimals for easier calculations and converted back to token decimals before transfers.
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
        address _swapManager,
        address _uniswapUniversalRouter,
        IndexAsset memory _asset0,
        IndexAsset memory _asset1,
        uint32 _feePercentage
    ) ERC20(_name, _symbol) {
        i_asset0 = IERC20(_asset0.asset);
        i_asset1 = IERC20(_asset1.asset);
        i_usdc = IERC20(_usdcAddress);

        i_swapManager = ISwapManager(_swapManager);
        i_universalRouter = IUniversalRouter(_uniswapUniversalRouter);

        s_weight0 = _asset0.weightPercentage;
        s_weight1 = _asset1.weightPercentage;

        s_feePercentage = _feePercentage;

        i_asset0PriceFeed = AggregatorV3Interface(_asset0.priceFeed);
        i_asset1PriceFeed = AggregatorV3Interface(_asset1.priceFeed);
        i_usdcPriceFeed = AggregatorV3Interface(_usdcPricefeed);

        i_decimals0 = IERC20Metadata(_asset0.asset).decimals();
        i_decimals1 = IERC20Metadata(_asset1.asset).decimals();
        i_decimalsUsdc = IERC20Metadata(_usdcAddress).decimals();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(INDEX_MANAGER_ROLE, msg.sender);
        _grantRole(ROUTER_ROLE, _router);
    }

    /**
     * @dev Initializes the index with the specified underlying amount of asset0.
     * @param _underlyingAmount0 The amount (in wei) of asset0 to initialize the index with.
     */
    function initialize(
        address _depositor,
        uint256 _underlyingAmount0
    ) external onlyRole(INDEX_MANAGER_ROLE) {
        if (s_initialized) {
            revert Index__AlreadyInitialized();
        }

        if (_underlyingAmount0 == 0) {
            revert Index__InvalidUnderlyingAmount();
        }
        i_asset0.safeTransferFrom(
            _depositor,
            address(this),
            _underlyingAmount0
        );

        (uint128 weight0, uint128 weight1) = getAssetsWeights();

        // All values are converted to the 18-decimal standard for easier calculations.

        // Convert the input asset0 amount to the 18-decimal standard.
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

        // Convert underlyingAmount1 from the 18-decimal standard to token decimals if needed.
        uint256 underlyingAmount1TokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                underlyingAmount1,
                i_decimals1
            );

        i_asset1.safeTransferFrom(
            _depositor,
            address(this),
            underlyingAmount1TokenDecimals
        );

        // Update reserves
        s_asset0Reserve = underlyingAmount0;
        s_asset1Reserve = underlyingAmount1;
        s_initialized = true;

        // Mint the initial shares to the initializer
        // All Values are in 18 decimals standard, so we can directly sum the USD values of the underlying assets to calculate the initial shares to mint
        uint256 initialShares = underlying0UsdValue + underlying1UsdValue;
        _mint(_depositor, initialShares);

        emit IndexInitialized(
            underlyingAmount0,
            underlyingAmount1,
            underlying0UsdValue,
            underlying1UsdValue,
            initialShares
        );
    }

    /**
     * @notice Mints index shares by depositing USDC.
     * @dev The router calls this function after collecting funds from the user.
     * @param _to The recipient of the minted shares.
     * @param _usdcAmountIn The USDC amount deposited, in token decimals.
     * @param _maxTolerance The maximum tolerated value deviation during the operation.
     */
    function mintShares(
        address _to,
        uint256 _usdcAmountIn,
        uint256 _maxTolerance
    ) public isInitialized onlyRole(ROUTER_ROLE) {
        // Transfer USDC from the user to the index.
        i_usdc.safeTransferFrom(_to, address(this), _usdcAmountIn);

        // 1. Cache the initial state values.
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

        // 2. Process fees.
        uint256 netUsdcAmount;
        {
            // 2.1 Normalize the USDC amount to the 18-decimal standard for easier calculations.
            uint256 usdcAmountInNormalized = _convertToDecimalStandard(
                _usdcAmountIn,
                i_decimalsUsdc
            );

            // 2.2 Calculate protocol fees on the USDC amount and update accrued fees.
            uint128 feeAmount;
            (feeAmount, netUsdcAmount) = _calculateFees(usdcAmountInNormalized);
            s_totalFees += feeAmount;
        }

        // 3. Execute swaps and measure the received asset value.
        uint128 asset0Received;
        uint128 asset1Received;
        uint256 asset0ReceivedUsdValue;
        uint256 asset1ReceivedUsdValue;
        {
            // 3.1 Get target weights and effective weights before the swaps.
            (uint128 weight0, uint128 weight1) = getAssetsWeights();
            (uint128 effectiveWeight0, ) = _getAssetsEffectiveWights(
                initState.asset0UsdValue,
                initState.totalAssetUsdValue
            );

            // 3.2 Calculate the USDC allocation to swap into asset0 and asset1.
            (
                uint256 usdcAmount0ToSwap,
                uint256 usdcAmount1ToSwap
            ) = UnderlyingMath.calculateDepositAllocationInUsd(
                    initState.totalAssetUsdValue,
                    netUsdcAmount,
                    weight0,
                    weight1,
                    effectiveWeight0
                );

            // 3.3 Swap USDC for asset0 and asset1.
            (
                uint128 asset0ReceivedFromSwap,
                uint128 asset1ReceivedFromSwap
            ) = _swapUsdcForAssets(usdcAmount0ToSwap, usdcAmount1ToSwap);

            // 3.4 Calculate the USD value of the received asset0 and asset1.
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

        // 4. Validate tolerance and compute minted shares.
        uint256 sharesToMint;
        {
            // 4.1 Compare the actual mint result against the pre-swap expectation under the configured tolerance.
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

            // 4.2 Revert if the observed result is outside the accepted tolerance.
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

    /**
     * @dev Computes the shares to mint and checks whether the swap result stayed within tolerance.
     * @param _usdcAmountIn The net USDC input amount in 18-decimal standard units.
     * @param _maxTolerance The maximum tolerated deviation.
     * @param _totalAssetUsdValueBefore The total index value before the mint operation.
     * @param asset0ReceivedUsdValue The USD value received in asset0.
     * @param asset1ReceivedUsdValue The USD value received in asset1.
     * @return sharesToMint The number of shares to mint.
     * @return toleranceExceeded True if the actual result is below the tolerated minimum.
     */
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
        // 1. Standardize the USDC amount to 18 decimals.
        uint256 _usdcAmountInNormalized = _convertToDecimalStandard(
            _usdcAmountIn,
            i_decimalsUsdc
        );
        // 2. Calculate net USDC amount after protocol fees
        (, uint256 netUsdcAmount) = _calculateFees(_usdcAmountInNormalized);

        // 3. Calculate the minimum value that may remain after swap slippage.
        uint256 minimumUsdAmount = netUsdcAmount
            .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);

        // 4. Calculate the minimum number of shares expected after fees and tolerance.
        (, , , , , , , uint256 totalAssetUsdValue) = _initFunctionValues();
        minimumSharesToMint = _mintPreview(
            minimumUsdAmount,
            totalAssetUsdValue
        );
    }

    /**
     * @dev Calculates the shares minted for a given normalized USDC amount.
     * @param _usdcAmountIn The normalized USDC amount in 18-decimal standard units.
     * @param _totalAssetUsdValueBefore The total index value before minting.
     * @return sharesToMint The number of shares to mint.
     */
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
     * @notice Redeems shares for USDC.
     * @dev The router calls this function on behalf of the user.
     * @param _from The address whose shares are redeemed.
     * @param _sharesAmount The amount of shares to redeem (in wei).
     * @param _maxTolerance The maximum acceptable tolerance (in basis points).
     */
    function redeem(
        address _from,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) public isInitialized onlyRole(ROUTER_ROLE) {
        // 1. Cache the initial state values.
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

        // 2. Calculate the USD value represented by the shares being redeemed.
        uint256 sharesBurnUsdValue = _sharesAmount.calculateShareValueInUsd(
            initState.totalAssetUsdValue,
            totalSupply()
        );

        // 3. Swap underlying assets back to USDC.
        uint128 asset0AmountToRedeem;
        uint128 asset1AmountToRedeem;
        uint256 usdcReceived;
        {
            // 3.1 Get target weights and effective weights before the swap.
            (uint128 weight0, uint128 weight1) = getAssetsWeights();
            (uint128 effectiveWeight0, ) = _getAssetsEffectiveWights(
                initState.asset0UsdValue,
                initState.totalAssetUsdValue
            );

            // 3.2 Calculate the USD value of asset0 and asset1 to swap for USDC.
            (uint256 asset0UsdToSwap, uint256 asset1UsdToSwap) = UnderlyingMath // @audit-info: consider whether effective weights should be calculated inside the library
                .calculateWithdrawUnderlyingAmountsInUsd(
                    initState.totalAssetUsdValue,
                    sharesBurnUsdValue,
                    weight0,
                    weight1,
                    effectiveWeight0
                );
            // 3.3 Swap asset0 and asset1 for USDC according to the index weights.
            usdcReceived = _swapAssetsForUsdc(asset0UsdToSwap, asset1UsdToSwap);
        }
        // 4. Calculate the net USDC amount after fees.

        (uint128 feeAmount, uint256 netUsdcAmount) = _calculateFees(
            usdcReceived
        );

        // 5. Validate tolerance.
        {
            // 5.1 Subtract protocol fees from the expected USDC amount.
            (, uint256 netExpectedUsdcAmount) = _calculateFees(
                sharesBurnUsdValue
            );

            // 5.2 Calculate the minimum acceptable amount after applying tolerance.
            uint256 minNetAmountAcceptable = netExpectedUsdcAmount
                .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);

            // 5.3 Compare the received USDC amount with the tolerated minimum.
            bool toleranceExceeded;

            if (netUsdcAmount < minNetAmountAcceptable) {
                toleranceExceeded = true;
            } else {
                toleranceExceeded = false;
            }

            // 5.4 Revert if the result is outside the accepted tolerance.
            if (toleranceExceeded) {
                revert Index__ToleranceExceeded();
            }
        }

        // 6. Update reserves and accrued fees.
        s_asset0Reserve -= asset0AmountToRedeem;
        s_asset1Reserve -= asset1AmountToRedeem;
        s_totalFees += feeAmount;

        // 7. Convert USDC back to token decimals before the transfer.
        uint256 netUsdcAmountTokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                netUsdcAmount,
                i_decimalsUsdc
            );

        // 8. Burn the shares and transfer USDC to the user.
        i_usdc.safeTransfer(_from, netUsdcAmountTokenDecimals);
        _burn(_from, _sharesAmount);

        // 9. Emit the burn event.
        emit Withdrawal(
            _from,
            _sharesAmount,
            asset0AmountToRedeem,
            asset1AmountToRedeem,
            netUsdcAmountTokenDecimals
        );
    }

    /**
     * @notice Returns the minimum USDC expected for a redemption.
     * @param _sharesAmountIn The amount of shares to redeem.
     * @param _maxTolerance The maximum tolerated deviation.
     * @return minUsdcToReceive The minimum USDC amount expected, in token decimals.
     */
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

        // USDC amount to receive with 18-decimal precision.
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
     * @notice Assumes the USDC amount has already been converted to the 18-decimal standard.
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
     * @notice Returns the latest normalized Chainlink price for a supported asset.
     * @param _asset The asset address whose price is requested.
     * @return price The asset price in USD with 18 decimals.
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

    /**
     * @notice Proposes a new target weight for asset0.
     * @param _newWeightAsset0 The proposed weight for asset0.
     * @return implementationTimestamp The timestamp after which the update can be executed.
     */
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

    /**
     * @notice Executes a pending weight update and triggers a rebalance.
     */
    function executeWeightUpdate() external onlyRole(INDEX_MANAGER_ROLE) {
        if (
            s_weightUpdateExecutableAt == 0 ||
            block.timestamp < s_weightUpdateExecutableAt
        ) {
            revert Index__PendingWeightUpdate();
        }

        s_weight0 = s_pendingWeight0;
        s_weight1 = s_pendingWeight1;

        // Reset pending weights and execution timestamp.
        s_pendingWeight0 = 0;
        s_pendingWeight1 = 0;
        s_weightUpdateExecutableAt = 0;

        // Rebalance the index using the new target weights.
        rebalanceIndex();

        emit IndexWeightsUpdated(s_weight0, s_weight1, block.timestamp);
    }

    /**
     * @notice Transfers accrued protocol fees to the collector.
     * @param _collector The recipient of the collected fees.
     * @return feesCollected The amount of fees transferred.
     */
    function collectFees(
        address _collector
    ) external onlyRole(INDEX_MANAGER_ROLE) returns (uint256 feesCollected) {
        feesCollected = s_totalFees;
        s_totalFees = 0;
        i_usdc.safeTransfer(_collector, feesCollected);

        emit FeesCollected(_collector, feesCollected);
    }

    /**
     * @notice Rebalances the index to match its target weights.
     */
    function rebalanceIndex() public onlyRole(INDEX_MANAGER_ROLE) {
        // 1. Cache the initial state values.
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

        // 2. Revert if no rebalance is needed.
        {
            bool rebalanceNeeded = _checkIfRebalanceNeeded(
                initState.asset0UsdValue,
                initState.totalAssetUsdValue
            );
            if (!rebalanceNeeded) {
                revert Index__RebalanceNotNeeded();
            }
        }

        // 3. Calculate which asset amount must be swapped to restore the target weights.
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

        // 4. Execute the required swap.
        uint128 updatedReserv0;
        uint128 updatedReserv1;
        if (amount0ToSwap > 0) {
            // Swap token0 for token1.
            uint128 token1Received = _swapAssetForAsset(
                address(i_asset0),
                amount0ToSwap
            );

            updatedReserv0 =
                initState.initialAsset0Reserve -
                amount0ToSwap.toUint128();
            updatedReserv1 = initState.initialAsset1Reserve + token1Received;
        } else {
            // Swap token1 for token0.
            uint128 token0Received = _swapAssetForAsset(
                address(i_asset1),
                amount1ToSwap
            );
            updatedReserv1 =
                initState.initialAsset1Reserve -
                amount1ToSwap.toUint128();
            updatedReserv0 = initState.initialAsset0Reserve + token0Received;
        }

        (, , uint256 totalAssetUsdValueAfter) = getAssetsUsdValue();

        // 5. Revert if total value dropped more than the accepted slippage tolerance.
        if (
            totalAssetUsdValueAfter <
            initState.totalAssetUsdValue.calculateNetAmountFromTolerance(
                MAX_SLIPPAGE_TOLERANCE,
                MAX_PERCENTAGE
            )
        ) {
            revert Index__RebalanceSlippageTooHigh();
        }

        s_asset0Reserve = updatedReserv0;
        s_asset1Reserve = updatedReserv1;

        // 6. Emit the rebalance event.
        emit IndexRebalanced(
            initState.initialAsset0Reserve,
            initState.initialAsset1Reserve,
            s_asset0Reserve,
            s_asset1Reserve,
            block.timestamp
        );
    }

    /**
     * @dev Checks whether the current effective weight is outside the rebalance threshold.
     * @param _token0UsdValue The USD value of token0.
     * @param _totalAssetUsdValue The total USD value of the index.
     * @return True if rebalancing is required.
     */
    function _checkIfRebalanceNeeded(
        uint256 _token0UsdValue,
        uint256 _totalAssetUsdValue
    ) internal view returns (bool) {
        (uint128 weight0, ) = _getAssetsEffectiveWights(
            _token0UsdValue,
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
        // Query the price feeds to get the asset and USDC prices with 18-decimal precision.
        priceAsset0 = getLatestPrice(address(i_asset0));
        priceAsset1 = getLatestPrice(address(i_asset1));
        priceUsdc = getLatestPrice(address(i_usdc));

        // Read the current reserves from storage.
        (initialAsset0Reserve, initialAsset1Reserve) = getAssetsAmount();

        // Calculate the USD value of the asset reserves.
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
        // Calculate the total USD value of the index assets.
        totalAssetUsdValue = asset0UsdValue + asset1UsdValue;
    }

    /**
     * @dev Swaps USDC into the underlying assets.
     * @param _usdcAmountIn0 The USDC amount allocated to asset0, in 18-decimal standard units.
     * @param _usdcAmountIn1 The USDC amount allocated to asset1, in 18-decimal standard units.
     * @return asset0StdDecimalsReceived The received asset0 amount in 18-decimal standard units.
     * @return asset1StdDecimalsReceived The received asset1 amount in 18-decimal standard units.
     */
    function _swapUsdcForAssets(
        uint256 _usdcAmountIn0,
        uint256 _usdcAmountIn1
    )
        internal
        returns (
            uint128 asset0StdDecimalsReceived,
            uint128 asset1StdDecimalsReceived
        )
    {
        // 1. Convert USDC amount from 18 decimals standard to USDC decimals
        uint128 usdcAmount0TokenDecimals;
        uint128 usdcAmount1TokenDecimals;
        if (_usdcAmountIn0 > 0) {
            usdcAmount0TokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                _usdcAmountIn0,
                i_decimalsUsdc
            ).toUint128();
        }

        if (_usdcAmountIn1 > 0) {
            usdcAmount1TokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                _usdcAmountIn1,
                i_decimalsUsdc
            ).toUint128();
        }

        // 2. Prepare swap parameters and capture balances before the swap.
        bytes memory commands;
        bytes[] memory inputs;
        uint256 asset0balanceBefore;
        uint256 asset1balanceBefore;
        if (_usdcAmountIn0 == 0 && _usdcAmountIn1 > 0) {
            // Prepare a single swap from USDC to asset1.
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET1_USDC,
                address(i_usdc),
                usdcAmount1TokenDecimals
            );

            // Get the asset1 balance before the swap.
            asset1balanceBefore = i_asset1.balanceOf(address(this));
        } else if (_usdcAmountIn0 > 0 && _usdcAmountIn1 == 0) {
            // Prepare a single swap from USDC to asset0.
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                address(i_usdc),
                usdcAmount0TokenDecimals
            );
            // Get the asset0 balance before the swap.
            asset0balanceBefore = i_asset0.balanceOf(address(this));
        } else {
            // Prepare a double swap from USDC into asset0 and asset1.
            (commands, inputs) = i_swapManager.buildDoubleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                SwapType.ASSET1_USDC,
                address(i_usdc),
                address(i_usdc),
                usdcAmount0TokenDecimals,
                usdcAmount1TokenDecimals
            );

            // Get both balances before the swap.
            asset0balanceBefore = i_asset0.balanceOf(address(this));
            asset1balanceBefore = i_asset1.balanceOf(address(this));
        }
        // @audit-info: implement swap slippage protection
        // 3. Approve the router to spend USDC and execute swap
        i_usdc.forceApprove(
            address(i_universalRouter),
            usdcAmount0TokenDecimals + usdcAmount1TokenDecimals
        );

        i_universalRouter.execute(
            commands,
            inputs,
            block.timestamp + SWAP_DEADLINE
        );

        // 4. Measure balances after the swap and compute the received token amounts.

        if (_usdcAmountIn0 > 0) {
            uint256 asset0balanceAfter = i_asset0.balanceOf(address(this));
            uint256 assetReceivedTokenDecimals = asset0balanceAfter -
                asset0balanceBefore;
            asset0StdDecimalsReceived = _convertToDecimalStandard(
                assetReceivedTokenDecimals,
                i_decimals0
            ).toUint128();
        }

        if (_usdcAmountIn1 > 0) {
            uint256 asset1balanceAfter = i_asset1.balanceOf(address(this));
            uint256 assetReceivedTokenDecimals = asset1balanceAfter -
                asset1balanceBefore;
            asset1StdDecimalsReceived = _convertToDecimalStandard(
                assetReceivedTokenDecimals,
                i_decimals1
            ).toUint128();
        }
    }

    /**
     * @dev Swaps the underlying assets back to USDC.
     * @param _asset0UsdToSwap The USD value of asset0 to swap, in 18-decimal standard units.
     * @param _asset1UsdToSwap The USD value of asset1 to swap, in 18-decimal standard units.
     * @return usdcReceived The received USDC amount in 18-decimal standard units.
     */
    function _swapAssetsForUsdc(
        uint256 _asset0UsdToSwap,
        uint256 _asset1UsdToSwap
    ) internal returns (uint256 usdcReceived) {
        // 1. Prepare token amounts to swap in token decimals.

        uint128 asset0AmountTokenDecimals;
        uint128 asset1AmountTokenDecimals;
        {
            // 1.1 Convert asset0 amount from USD value to token decimals
            if (_asset0UsdToSwap > 0) {
                uint256 asset0AmountToSwap = UnderlyingMath
                    .calculateTokenAmountFromUsdValue(
                        _asset0UsdToSwap,
                        getLatestPrice(address(i_asset0)),
                        DECIMALS_STANDARD
                    );
                asset0AmountTokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                    asset0AmountToSwap,
                    i_decimals0
                ).toUint128();
            }
            // 1.2 Convert asset1 amount from USD value to token decimals
            if (_asset1UsdToSwap > 0) {
                uint256 asset1AmountToSwap = UnderlyingMath
                    .calculateTokenAmountFromUsdValue(
                        _asset1UsdToSwap,
                        getLatestPrice(address(i_asset1)),
                        DECIMALS_STANDARD
                    );
                asset1AmountTokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                    asset1AmountToSwap,
                    i_decimals1
                ).toUint128();
            }
        }

        // 2. Prepare swap parameters.
        bytes memory commands;
        bytes[] memory inputs;
        if (_asset0UsdToSwap > 0 && _asset1UsdToSwap == 0) {
            // Prepare a single swap from asset0 to USDC.
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                address(i_asset0),
                asset0AmountTokenDecimals
            );

            i_asset0.forceApprove(
                address(i_universalRouter),
                asset0AmountTokenDecimals
            );
        } else if (_asset0UsdToSwap == 0 && _asset1UsdToSwap > 0) {
            // Prepare a single swap from asset1 to USDC.
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET1_USDC,
                address(i_asset1),
                asset1AmountTokenDecimals
            );

            i_asset1.forceApprove(
                address(i_universalRouter),
                asset1AmountTokenDecimals
            );
        } else {
            // Prepare a double swap from asset0 and asset1 to USDC.
            (commands, inputs) = i_swapManager.buildDoubleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                SwapType.ASSET1_USDC,
                address(i_asset0),
                address(i_asset1),
                asset0AmountTokenDecimals,
                asset1AmountTokenDecimals
            );

            i_asset0.forceApprove(
                address(i_universalRouter),
                asset0AmountTokenDecimals
            );
            i_asset1.forceApprove(
                address(i_universalRouter),
                asset1AmountTokenDecimals
            );
        }

        // 3. Execute the swap.
        // @audit-issue : implement swap slippage protection
        uint256 usdcBalanceBefore = i_usdc.balanceOf(address(this));
        i_universalRouter.execute(
            commands,
            inputs,
            block.timestamp + SWAP_DEADLINE
        );
        uint256 usdcBalanceAfter = i_usdc.balanceOf(address(this));
        uint256 usdcReceivedTokenDecimals = usdcBalanceAfter -
            usdcBalanceBefore;

        // 4. Convert the received USDC amount to 18 decimals standard
        usdcReceived = _convertToDecimalStandard(
            usdcReceivedTokenDecimals,
            i_decimalsUsdc
        ).toUint128();
    }

    /**
     * @dev Swaps one underlying asset for the other during rebalancing.
     * @dev Accepts the amount to swap in 18-decimal standard units and returns the received amount in the same format.
     * @param _swapFrom The address of the asset to swap from.
     * @param _amountToSwap The amount of the asset to swap in 18 decimals standard.
     * @return amountReceived The amount of the asset received from the swap in 18 decimals standard.
     */
    function _swapAssetForAsset(
        address _swapFrom,
        uint256 _amountToSwap
    ) internal returns (uint128 amountReceived) {
        // 1. Convert the amount to swap from 18 decimals standard to token decimals
        uint128 amountToSwapTokenDecimals;
        if (_swapFrom == address(i_asset0)) {
            amountToSwapTokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                _amountToSwap,
                i_decimals0
            ).toUint128();
        } else {
            amountToSwapTokenDecimals = _convertFromStdDecimalsToTokenDecimals(
                _amountToSwap,
                i_decimals1
            ).toUint128();
        }

        // 2. Prepare swap parameters
        (
            bytes memory commands,
            bytes[] memory inputs,
            address tokenToSwap,
            address tokenToReceive
        ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET0_ASSET1,
                _swapFrom,
                amountToSwapTokenDecimals
            );

        // 3. Execute the swap and measure the amount received in token decimals.
        uint256 amountReceivedTokenDecimals;
        {
            uint256 balanceBefore = IERC20(tokenToReceive).balanceOf(
                address(this)
            );
            // 3.1 Approve the router to spend the token to swap
            IERC20(tokenToSwap).forceApprove(
                address(i_universalRouter),
                _amountToSwap
            );

            // 3.2 Execute swap
            i_universalRouter.execute(
                commands,
                inputs,
                block.timestamp + SWAP_DEADLINE
            );

            // 3.3 Get real amount received
            uint256 balanceAfter = IERC20(tokenToReceive).balanceOf(
                address(this)
            );
            amountReceivedTokenDecimals = balanceAfter - balanceBefore;
        }

        // 4. Convert the received asset amount to 18 decimals standard and return the amount received in standard decimals
        uint8 assetDecimals = _swapFrom == address(i_asset0)
            ? i_decimals1
            : i_decimals0;
        amountReceived = _convertToDecimalStandard(
            amountReceivedTokenDecimals,
            assetDecimals
        ).toUint128();

        // The caller performs the final validation on the amount received.
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
        if (_currentDecimals <= DECIMALS_STANDARD) {
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
     * @dev This performs two price-feed reads, which is unnecessary for some internal flows.
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
        (
            ,
            ,
            ,
            ,
            ,
            asset0TotalUsdValue,
            asset1TotalUsdValue,
            totalUsdValue
        ) = _initFunctionValues();
    }

    /**
     * @dev Gets the effective weights of the underlying assets in the index.
     * @dev The effective weight is calculated as the ratio of the asset's USD value to the total USD value of the index.
     * @return effectiveWeight0 The effective weight of asset0 in the index.
     * @return effectiveWeight1 The effective weight of asset1 in the index.
     */
    function getAssetsEffectiveWeights()
        public
        view
        returns (uint256 effectiveWeight0, uint256 effectiveWeight1)
    {
        (
            uint256 asset0TotalUsdValue,
            ,
            uint256 totalUsdValue
        ) = getAssetsUsdValue();

        (effectiveWeight0, effectiveWeight1) = _getAssetsEffectiveWights(
            asset0TotalUsdValue,
            totalUsdValue
        );
    }

    /**
     * @dev Calculates the effective weights of the two assets.
     * @param asset0UsdValue The USD value of asset0.
     * @param totalAssetUsdValue The total USD value of the index.
     * @return effectiveWeight0 The effective weight of asset0.
     * @return effectiveWeight1 The effective weight of asset1.
     */
    function _getAssetsEffectiveWights(
        uint256 asset0UsdValue,
        uint256 totalAssetUsdValue
    )
        internal
        pure
        returns (uint128 effectiveWeight0, uint128 effectiveWeight1)
    {
        (uint256 weight0, uint256 weight1) = UnderlyingMath
            .calculateEffectiveWeights(
                asset0UsdValue,
                totalAssetUsdValue,
                MAX_PERCENTAGE
            );

        effectiveWeight0 = weight0.toUint128();
        effectiveWeight1 = weight1.toUint128();
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

    function getUsdc() public view returns (address) {
        return address(i_usdc);
    }

    function getAsset0PriceFeed() public view returns (address) {
        return (address(i_asset0PriceFeed));
    }

    function getAsset1PriceFeed() public view returns (address) {
        return (address(i_asset1PriceFeed));
    }

    function getUsdcPriceFeed() public view returns (address) {
        return (address(i_usdcPriceFeed));
    }

    function getFeesInfo()
        public
        view
        returns (uint32 feePercentage, uint128 totalFees)
    {
        return (s_feePercentage, s_totalFees);
    }
}
