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
import {ContractCodeConstants} from "./ContractCodeConstants.sol";
import {console} from "forge-std/console.sol";
import {ISwapManager} from "./Interface/ISwapManager.sol";
import {
    IUniversalRouter
} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title Index
 *
 * @notice Reserve accounting
 * s_asset0Reserve and s_asset1Reserve are stored in **token decimals**
 * (i.e. the native decimals of each underlying asset).
 *
 */
contract Index is IIndex, ERC20, AccessControl, ContractCodeConstants {
    using UnderlyingMath for uint256;
    using SharesMath for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    // =========================================================================
    //  Roles
    // =========================================================================

    bytes32 public constant INDEX_MANAGER_ROLE =
        keccak256("INDEX_MANAGER_ROLE");
    bytes32 public constant ROUTER_ROLE = keccak256("ROUTER_ROLE");

    // =========================================================================
    //  Immutables
    // =========================================================================

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

    // =========================================================================
    //  Storage
    // =========================================================================

    uint128 internal s_weight0;
    uint128 internal s_weight1;
    uint128 internal s_pendingWeight0;
    uint128 internal s_pendingWeight1;
    uint256 internal s_weightUpdateExecutableAt;

    /**
     * @dev Reserves are stored in **token decimals** (native decimals of each asset).
     *      They are converted to the 18-decimal standard only when USD values are needed.
     */
    uint128 internal s_asset0Reserve; // token decimals of i_asset0
    uint128 internal s_asset1Reserve; // token decimals of i_asset1

    uint128 internal s_totalFees; // usdc-decimals

    uint32 internal s_feePercentage;
    bool internal s_initialized;

    // =========================================================================
    //  Modifier
    // =========================================================================

    modifier isInitialized() {
        _isInitialized();
        _;
    }

    // =========================================================================
    //  Constructor
    // =========================================================================

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
        _grantRole(INDEX_MANAGER_ROLE, address(this));
        _grantRole(ROUTER_ROLE, _router);
    }

    // =========================================================================
    //  Public / external
    // =========================================================================

    /**
     * @dev Initialises the index by depositing the seed amount of asset0.
     *      The proportional amount of asset1 is derived from the target weights.
     *
     * @param _depositor         Address that provides the seed tokens.
     * @param _underlyingAmount0 Amount of asset0 in **token decimals**.
     */
    function initialize(
        address _depositor,
        uint256 _underlyingAmount0
    ) external onlyRole(INDEX_MANAGER_ROLE) {
        if (s_initialized) revert Index__AlreadyInitialized();
        if (_underlyingAmount0 == 0) revert Index__InvalidUnderlyingAmount();

        i_asset0.safeTransferFrom(
            _depositor,
            address(this),
            _underlyingAmount0
        );

        (uint128 weight0, uint128 weight1) = getAssetsWeights();

        // ── Convert asset0 input to std decimals for USD maths ───────────────
        uint256 underlyingAmount0Std = _convertToDecimalStandard(
            _underlyingAmount0,
            i_decimals0
        );

        uint256 underlying0UsdValue = UnderlyingMath
            .calculateUSDValueOfTokenAmountStdDecimals(
                underlyingAmount0Std,
                getLatestPrice(address(i_asset0)),
                DECIMALS_STANDARD
            );

        uint256 underlying1UsdValue = UnderlyingMath
            .calculateAmount1UsdFromAmount0UsdAndIndexWeights(
                underlying0UsdValue,
                weight0,
                weight1
            );

        uint256 underlyingAmount1Std = UnderlyingMath
            .calculateTokenAmountFromUsdValue(
                underlying1UsdValue,
                getLatestPrice(address(i_asset1)),
                DECIMALS_STANDARD
            );

        // Convert asset1 std amount → token decimals for the actual transfer
        uint256 underlyingAmount1TokenDec = _convertFromStdDecimalsToTokenDecimals(
                underlyingAmount1Std,
                i_decimals1
            );

        i_asset1.safeTransferFrom(
            _depositor,
            address(this),
            underlyingAmount1TokenDec
        );

        // ── Store reserves in token decimals ─────────────────────────────────
        s_asset0Reserve = _underlyingAmount0.toUint128();
        s_asset1Reserve = underlyingAmount1TokenDec.toUint128();
        s_initialized = true;

        uint256 initialShares = underlying0UsdValue + underlying1UsdValue;
        _mint(_depositor, initialShares);

        emit IndexInitialized(
            _underlyingAmount0,
            underlyingAmount1TokenDec,
            underlying0UsdValue,
            underlying1UsdValue,
            initialShares
        );
    }

    /**
     * @notice Mints index shares by depositing USDC.
     * @notice Check on user usdc balance is done in the router before calling this function.
     * @param _to           Recipient of the minted shares.
     * @param _usdcAmountIn USDC amount in token decimals.
     * @param _maxTolerance Maximum tolerated value deviation.
     */
    function mintShares(
        address _to,
        uint256 _usdcAmountIn,
        uint256 _maxTolerance
    ) public isInitialized onlyRole(ROUTER_ROLE) {
        i_usdc.safeTransferFrom(_to, address(this), _usdcAmountIn);

        // 1. Cache initial state.
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

        // 2. Fees (work in std decimals throughout).
        uint256 netUsdcAmountStdDecimlas;
        {
            // 2.1 Calculate fees on token decimals avoid future rounding error
            uint128 feeAmount;
            uint256 netUsdcAmount;
            (feeAmount, netUsdcAmount) = _calculateFees(_usdcAmountIn);
            s_totalFees += feeAmount;

            // 2.2 Normalize netUsdcAmount to std decimlas for internal calculations.
            netUsdcAmountStdDecimlas = _convertToDecimalStandard(
                netUsdcAmount,
                i_decimalsUsdc
            );
        }

        // 3. Swaps.
        // asset*ReceivedStd are in the 18-decimal standard (returned by _swapUsdcForAssets).
        uint256 asset0ReceivedStd;
        uint256 asset1ReceivedStd;
        uint256 asset0ReceivedUsdValue;
        uint256 asset1ReceivedUsdValue;
        {
            // 3.1 get effective and target weights
            (uint128 targetWeight0, uint128 targetWeight1) = getAssetsWeights();
            (uint128 effectiveWeight0, ) = _getAssetsEffectiveWights(
                initState.asset0UsdValue,
                initState.totalAssetUsdValue
            );

            // 3.2 Calculate usd amount to swap for each underlyin token
            (
                uint256 usdcAmount0ToSwap,
                uint256 usdcAmount1ToSwap
            ) = UnderlyingMath.calculateDepositAllocationInUsd(
                    initState.totalAssetUsdValue,
                    netUsdcAmountStdDecimlas,
                    targetWeight0,
                    targetWeight1,
                    effectiveWeight0
                );

            // 3.3 Swap USDC and receive Token0 and Token1 amount in std decimals
            (asset0ReceivedStd, asset1ReceivedStd) = _swapUsdcForAssets(
                usdcAmount0ToSwap,
                usdcAmount1ToSwap
            );

            // 3.4 Calculate the USD value of the amounts received to perform the tolerance check later.
            asset0ReceivedUsdValue = UnderlyingMath
                .calculateUSDValueOfTokenAmountStdDecimals(
                    asset0ReceivedStd,
                    initState.priceAsset0,
                    DECIMALS_STANDARD
                );
            asset1ReceivedUsdValue = UnderlyingMath
                .calculateUSDValueOfTokenAmountStdDecimals(
                    asset1ReceivedStd,
                    initState.priceAsset1,
                    DECIMALS_STANDARD
                );
        }

        // 4. Tolerance check.
        uint256 sharesToMint = _calculateShareToMintAndValidateTolerance(
            netUsdcAmountStdDecimlas,
            _maxTolerance,
            initState.totalAssetUsdValue,
            asset0ReceivedUsdValue,
            asset1ReceivedUsdValue
        );
        if (sharesToMint == 0) revert Index__ToleranceExceeded();

        // 5. Mint.
        _mint(_to, sharesToMint);

        // 6. Update reserves in token decimals.
        //    Convert std-decimal amounts received back to token decimals before storing.
        uint128 asset0ReceivedTokenDec = _convertFromStdDecimalsToTokenDecimals(
            asset0ReceivedStd,
            i_decimals0
        ).toUint128();
        uint128 asset1ReceivedTokenDec = _convertFromStdDecimalsToTokenDecimals(
            asset1ReceivedStd,
            i_decimals1
        ).toUint128();

        s_asset0Reserve += asset0ReceivedTokenDec;
        s_asset1Reserve += asset1ReceivedTokenDec;

        // 7. Emit SharesMinted event
        emit SharesMinted(
            _to,
            _usdcAmountIn,
            sharesToMint,
            asset0ReceivedTokenDec,
            asset1ReceivedTokenDec
        );
    }

    /**
     * @notice Redeems shares for USDC.
     * @param _from         Address whose shares are redeemed.
     * @param _sharesAmount Shares to burn.
     * @param _maxTolerance Maximum tolerated deviation.
     */
    function redeem(
        address _from,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) public isInitialized onlyRole(ROUTER_ROLE) {
        // 1. Cache initial state.
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

        // 2. USD value of shares being redeemed.
        uint256 sharesBurnUsdValue = _sharesAmount.calculateShareValueInUsd(
            initState.totalAssetUsdValue,
            totalSupply()
        );

        // 3. Swap underlying assets → USDC.
        //    Track asset balance deltas to obtain the exact token amounts consumed.
        uint256 usdcReceived;
        uint128 asset0AmountRedeemedTokenDec;
        uint128 asset1AmountRedeemedTokenDec;
        {
            (uint128 weight0, uint128 weight1) = getAssetsWeights();
            (uint128 effectiveWeight0, ) = _getAssetsEffectiveWights(
                initState.asset0UsdValue,
                initState.totalAssetUsdValue
            );

            (uint256 asset0UsdToSwap, uint256 asset1UsdToSwap) = UnderlyingMath
                .calculateWithdrawUnderlyingAmountsInUsd(
                    initState.totalAssetUsdValue,
                    sharesBurnUsdValue,
                    weight0,
                    weight1,
                    effectiveWeight0
                );

            // Snapshot balances before the swap to measure exact amounts consumed.
            uint256 asset0Before = i_asset0.balanceOf(address(this));
            uint256 asset1Before = i_asset1.balanceOf(address(this));

            usdcReceived = _swapAssetsForUsdc(asset0UsdToSwap, asset1UsdToSwap);

            // Delta = tokens sent to the router, already in token decimals.
            asset0AmountRedeemedTokenDec = (asset0Before -
                i_asset0.balanceOf(address(this))).toUint128();
            asset1AmountRedeemedTokenDec = (asset1Before -
                i_asset1.balanceOf(address(this))).toUint128();
        }

        // 4. Fees.
        (uint128 feeAmount, uint256 netUsdcAmount) = _calculateFees(
            usdcReceived
        );

        // 5. Tolerance check.
        {
            (, uint256 netExpectedUsdcAmount) = _calculateFees(
                sharesBurnUsdValue
            );
            uint256 minNetAmountAcceptable = netExpectedUsdcAmount
                .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);

            if (netUsdcAmount < minNetAmountAcceptable)
                revert Index__ToleranceExceeded();
        }

        // 6. Update reserves (token decimals) and fees.
        s_asset0Reserve -= asset0AmountRedeemedTokenDec;
        s_asset1Reserve -= asset1AmountRedeemedTokenDec;
        s_totalFees += feeAmount;

        // 7. Transfer USDC to user (convert from std decimals to token decimals).
        uint256 netUsdcAmountTokenDec = _convertFromStdDecimalsToTokenDecimals(
            netUsdcAmount,
            i_decimalsUsdc
        );
        i_usdc.safeTransfer(_from, netUsdcAmountTokenDec);
        _burn(_from, _sharesAmount);

        emit SharesBurned(
            _from,
            _sharesAmount,
            asset0AmountRedeemedTokenDec,
            asset1AmountRedeemedTokenDec,
            netUsdcAmountTokenDec
        );
    }

    /**
     * @dev Preview: minimum shares to mint for a given USDC input and tolerance.
     */
    function minMintPreview(
        uint256 _usdcAmountIn,
        uint256 _maxTolerance
    ) public view isInitialized returns (uint256 minimumSharesToMint) {
        uint256 usdcAmountInNormalized = _convertToDecimalStandard(
            _usdcAmountIn,
            i_decimalsUsdc
        );
        (, uint256 netUsdcAmount) = _calculateFees(usdcAmountInNormalized);

        uint256 minimumUsdAmount = netUsdcAmount
            .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);

        (, , , , , , , uint256 totalAssetUsdValue) = _initFunctionValues();
        minimumSharesToMint = _mintPreview(
            minimumUsdAmount,
            totalAssetUsdValue
        );
    }

    /**
     * @dev Preview: minimum USDC to receive for a given shares amount and tolerance.
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

        uint256 minUsdcEighteenDec = netUsdcAmount
            .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);

        minUsdcToReceive = _convertFromStdDecimalsToTokenDecimals(
            minUsdcEighteenDec,
            i_decimalsUsdc
        );
    }

    /**
     * @notice Proposes a new target weight for asset0 and then derive the corresponding weight for asset1.
     * @param _newWeightAsset0 New target weight for asset0 in weight units (100% = 1000000).
     * @return implementationTimestamp Timestamp at which the proposed weights can be implemented.
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
        ) revert Index__PendingWeightUpdate();

        bool invalidWeight0 = _newWeightAsset0 >= MAX_WEIGHT ||
            _newWeightAsset0 <= MIN_WEIGHT ||
            _newWeightAsset0 == s_weight0;
        if (invalidWeight0) revert Index__InvalidWeight();

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
     * @notice Executes the pending weight update and triggers a rebalance.
     * @notice Rebalance is attempted even if the update fails to execute to avoid getting stuck with pending weights that cannot be implemented.
     */
    function executeWeightUpdate() external onlyRole(INDEX_MANAGER_ROLE) {
        if (
            s_weightUpdateExecutableAt == 0 ||
            block.timestamp < s_weightUpdateExecutableAt
        ) revert Index__NotPendingWeightUpdate();

        s_weight0 = s_pendingWeight0;
        s_weight1 = s_pendingWeight1;

        s_pendingWeight0 = 0;
        s_pendingWeight1 = 0;
        s_weightUpdateExecutableAt = 0;

        (bool rebalanceSuccess, bytes memory reasonData) = _tryRebalanceIndex();
        if (!rebalanceSuccess) emit WeightUpdateRebalanceFailed(reasonData);

        emit IndexWeightsUpdated(s_weight0, s_weight1, block.timestamp);
    }

    /**
     * @notice Transfers accrued protocol fees to the collector.
     */
    function collectFees(
        address _collector
    ) external onlyRole(INDEX_MANAGER_ROLE) returns (uint256 feesCollected) {
        uint128 cacheTotalFees = s_totalFees;
        if (cacheTotalFees == 0) revert Index__NoFeesToCollect();
        feesCollected = cacheTotalFees;
        s_totalFees = 0;
        i_usdc.safeTransfer(_collector, feesCollected);
        emit FeesCollected(_collector, feesCollected);
    }

    /**
     * @notice Rebalances the index to match its target weights.
     */
    function rebalanceIndex() public onlyRole(INDEX_MANAGER_ROLE) {
        // 1. Cache initial state.
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

        // 2. Check rebalance is needed.
        if (
            !_checkIfRebalanceNeeded(
                initState.asset0UsdValue,
                initState.totalAssetUsdValue
            )
        ) revert Index__RebalanceNotNeeded();

        // 3. Calculate amounts to swap (returned in std decimals).
        (uint128 weight0, uint128 weight1) = getAssetsWeights();
        (uint256 amount0ToSwapStd, uint256 amount1ToSwapStd) = UnderlyingMath
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

        // 4. Execute swap and compute updated reserves in token decimals.
        //    initialAsset0Reserve / initialAsset1Reserve from initState are in STD DECIMALS
        //    (converted in _initFunctionValues).  We must convert back to token decimals
        //    when writing to storage.
        uint128 updatedReserv0;
        uint128 updatedReserv1;

        if (amount0ToSwapStd > 0) {
            // Swap asset0 → asset1; result is in std decimals.
            uint128 token1ReceivedStd = _swapAssetForAsset(
                address(i_asset0),
                amount0ToSwapStd
            );

            // Convert amounts to token decimals for storage.
            uint256 amount0TokenDec = _convertFromStdDecimalsToTokenDecimals(
                amount0ToSwapStd,
                i_decimals0
            );
            uint256 token1TokenDec = _convertFromStdDecimalsToTokenDecimals(
                token1ReceivedStd,
                i_decimals1
            );

            updatedReserv0 = (s_asset0Reserve - amount0TokenDec.toUint128());
            updatedReserv1 = (s_asset1Reserve + token1TokenDec.toUint128());
        } else {
            // Swap asset1 → asset0; result is in std decimals.
            uint128 token0ReceivedStd = _swapAssetForAsset(
                address(i_asset1),
                amount1ToSwapStd
            );

            uint256 amount1TokenDec = _convertFromStdDecimalsToTokenDecimals(
                amount1ToSwapStd,
                i_decimals1
            );
            uint256 token0TokenDec = _convertFromStdDecimalsToTokenDecimals(
                token0ReceivedStd,
                i_decimals0
            );

            updatedReserv1 = (s_asset1Reserve - amount1TokenDec.toUint128());
            updatedReserv0 = (s_asset0Reserve + token0TokenDec.toUint128());
        }

        // 5. Persist reserves (token decimals).
        uint128 prevReserv0 = s_asset0Reserve;
        uint128 prevReserv1 = s_asset1Reserve;
        s_asset0Reserve = updatedReserv0;
        s_asset1Reserve = updatedReserv1;

        // 6. Slippage check (works on USD values, unaffected by decimal format).
        (, , uint256 totalAssetUsdValueAfter) = getAssetsUsdValue();
        if (
            totalAssetUsdValueAfter <
            initState.totalAssetUsdValue.calculateNetAmountFromTolerance(
                MAX_SLIPPAGE_TOLERANCE,
                MAX_PERCENTAGE
            )
        ) revert Index__RebalanceSlippageTooHigh();

        emit IndexRebalanced(
            prevReserv0,
            prevReserv1,
            s_asset0Reserve,
            s_asset1Reserve,
            block.timestamp
        );
    }

    // =========================================================================
    //  Internal — previews and fee helpers
    // =========================================================================

    function _mintPreview(
        uint256 _usdcAmountIn,
        uint256 _totalAssetUsdValueBefore
    ) internal view returns (uint256 sharesToMint) {
        sharesToMint = _usdcAmountIn.calculateSharesToMintFromUsdcAmount(
            _totalAssetUsdValueBefore,
            totalSupply()
        );
    }

    function _calculateShareToMintAndValidateTolerance(
        uint256 _usdcAmountIn,
        uint256 _maxTolerance,
        uint256 _totalAssetUsdValueBefore,
        uint256 asset0ReceivedUsdValue,
        uint256 asset1ReceivedUsdValue
    ) internal view returns (uint256 sharesToMint) {
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

        if (sharesToMint < minimumSharesToMint) sharesToMint = 0;
    }

    function _redeemPreview(
        uint256 _sharesAmountIn,
        uint256 _totalAssetUsdValueBefore
    ) internal view returns (uint256 usdcToReceiveBeforeFees) {
        usdcToReceiveBeforeFees = _sharesAmountIn.calculateShareValueInUsd(
            _totalAssetUsdValueBefore,
            totalSupply()
        );
    }

    /**
     * @notice Assumes the USDC amount is already in the 18-decimal standard.
     */
    function _calculateFees(
        uint256 _usdcAmountIn
    ) internal view returns (uint128 feeAmount, uint256 netUsdcAmount) {
        feeAmount = ((_usdcAmountIn * s_feePercentage) / MAX_PERCENTAGE)
            .toUint128();
        netUsdcAmount = _usdcAmountIn - feeAmount;
    }

    // =========================================================================
    //  Internal — state initialisation
    // =========================================================================

    /**
     * @dev Reads storage reserves (token decimals), converts them to the
     *      18-decimal standard, then derives all USD values needed by the
     *      calling function.  The returned reserve fields are in STD DECIMALS
     *      so that all callers can pass them directly into math functions
     *      without extra conversion.
     */
    function _initFunctionValues()
        internal
        view
        returns (
            uint256 priceAsset0,
            uint256 priceAsset1,
            uint256 priceUsdc,
            uint128 initialAsset0Reserve, // STD DECIMALS (18)
            uint128 initialAsset1Reserve, // STD DECIMALS (18)
            uint256 asset0UsdValue,
            uint256 asset1UsdValue,
            uint256 totalAssetUsdValue
        )
    {
        priceAsset0 = getLatestPrice(address(i_asset0));
        priceAsset1 = getLatestPrice(address(i_asset1));
        priceUsdc = getLatestPrice(address(i_usdc));

        // Read storage (token decimals) and convert to std decimals for calculations.
        initialAsset0Reserve = _convertToDecimalStandard(
            s_asset0Reserve,
            i_decimals0
        ).toUint128();
        initialAsset1Reserve = _convertToDecimalStandard(
            s_asset1Reserve,
            i_decimals1
        ).toUint128();

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
        totalAssetUsdValue = asset0UsdValue + asset1UsdValue;
    }

    // =========================================================================
    //  Internal — swap wrappers
    // =========================================================================

    /**
     * @dev Swaps USDC into the underlying assets.
     * @param _usdcAmountIn0 USDC for asset0, in 18-decimal standard.
     * @param _usdcAmountIn1 USDC for asset1, in 18-decimal standard.
     * @return asset0ReceivedStd Received asset0 in 18-decimal standard.
     * @return asset1ReceivedStd Received asset1 in 18-decimal standard.
     */
    function _swapUsdcForAssets(
        uint256 _usdcAmountIn0,
        uint256 _usdcAmountIn1
    ) internal returns (uint256 asset0ReceivedStd, uint256 asset1ReceivedStd) {
        // Convert USDC amounts from std decimals → token decimals.
        // Using uint256 to prevent intermediate overflow before SafeCast at storage.
        uint256 usdcAmount0TokenDec;
        uint256 usdcAmount1TokenDec;

        if (_usdcAmountIn0 > 0)
            usdcAmount0TokenDec = _convertFromStdDecimalsToTokenDecimals(
                _usdcAmountIn0,
                i_decimalsUsdc
            );
        if (_usdcAmountIn1 > 0)
            usdcAmount1TokenDec = _convertFromStdDecimalsToTokenDecimals(
                _usdcAmountIn1,
                i_decimalsUsdc
            );

        bytes memory commands;
        bytes[] memory inputs;
        uint256 asset0BalanceBefore;
        uint256 asset1BalanceBefore;

        if (_usdcAmountIn0 == 0 && _usdcAmountIn1 > 0) {
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET1_USDC,
                address(i_usdc),
                usdcAmount1TokenDec.toUint128()
            );
            asset1BalanceBefore = i_asset1.balanceOf(address(this));
        } else if (_usdcAmountIn0 > 0 && _usdcAmountIn1 == 0) {
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                address(i_usdc),
                usdcAmount0TokenDec.toUint128()
            );
            asset0BalanceBefore = i_asset0.balanceOf(address(this));
        } else {
            (commands, inputs) = i_swapManager.buildDoubleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                SwapType.ASSET1_USDC,
                address(i_usdc),
                address(i_usdc),
                usdcAmount0TokenDec.toUint128(),
                usdcAmount1TokenDec.toUint128()
            );
            asset0BalanceBefore = i_asset0.balanceOf(address(this));
            asset1BalanceBefore = i_asset1.balanceOf(address(this));
        }

        // @audit-info: implement swap slippage protection
        i_usdc.forceApprove(
            address(i_universalRouter),
            usdcAmount0TokenDec + usdcAmount1TokenDec
        );
        i_universalRouter.execute(
            commands,
            inputs,
            block.timestamp + SWAP_DEADLINE
        );

        // Measure received amounts (token decimals) and convert to std decimals.
        if (_usdcAmountIn0 > 0) {
            uint256 receivedTokenDec = i_asset0.balanceOf(address(this)) -
                asset0BalanceBefore;
            asset0ReceivedStd = _convertToDecimalStandard(
                receivedTokenDec,
                i_decimals0
            );
        }
        if (_usdcAmountIn1 > 0) {
            uint256 receivedTokenDec = i_asset1.balanceOf(address(this)) -
                asset1BalanceBefore;
            asset1ReceivedStd = _convertToDecimalStandard(
                receivedTokenDec,
                i_decimals1
            );
        }
    }

    /**
     * @dev Swaps the underlying assets back to USDC.
     * @param _asset0UsdToSwap USD value of asset0 to sell, in std decimals.
     * @param _asset1UsdToSwap USD value of asset1 to sell, in std decimals.
     * @return usdcReceived Received USDC in std decimals.
     */
    function _swapAssetsForUsdc(
        uint256 _asset0UsdToSwap,
        uint256 _asset1UsdToSwap
    ) internal returns (uint256 usdcReceived) {
        // Derive token amounts from USD values; use uint256 throughout.
        uint256 asset0AmountTokenDec;
        uint256 asset1AmountTokenDec;
        {
            if (_asset0UsdToSwap > 0) {
                uint256 amountStd = UnderlyingMath
                    .calculateTokenAmountFromUsdValue(
                        _asset0UsdToSwap,
                        getLatestPrice(address(i_asset0)),
                        DECIMALS_STANDARD
                    );
                asset0AmountTokenDec = _convertFromStdDecimalsToTokenDecimals(
                    amountStd,
                    i_decimals0
                );
            }
            if (_asset1UsdToSwap > 0) {
                uint256 amountStd = UnderlyingMath
                    .calculateTokenAmountFromUsdValue(
                        _asset1UsdToSwap,
                        getLatestPrice(address(i_asset1)),
                        DECIMALS_STANDARD
                    );
                asset1AmountTokenDec = _convertFromStdDecimalsToTokenDecimals(
                    amountStd,
                    i_decimals1
                );
            }
        }

        bytes memory commands;
        bytes[] memory inputs;

        if (_asset0UsdToSwap > 0 && _asset1UsdToSwap == 0) {
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                address(i_asset0),
                asset0AmountTokenDec.toUint128()
            );
            i_asset0.forceApprove(
                address(i_universalRouter),
                asset0AmountTokenDec
            );
        } else if (_asset0UsdToSwap == 0 && _asset1UsdToSwap > 0) {
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET1_USDC,
                address(i_asset1),
                asset1AmountTokenDec.toUint128()
            );
            i_asset1.forceApprove(
                address(i_universalRouter),
                asset1AmountTokenDec
            );
        } else {
            (commands, inputs) = i_swapManager.buildDoubleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                SwapType.ASSET1_USDC,
                address(i_asset0),
                address(i_asset1),
                asset0AmountTokenDec.toUint128(),
                asset1AmountTokenDec.toUint128()
            );
            i_asset0.forceApprove(
                address(i_universalRouter),
                asset0AmountTokenDec
            );
            i_asset1.forceApprove(
                address(i_universalRouter),
                asset1AmountTokenDec
            );
        }

        // @audit-issue: implement swap slippage protection
        uint256 usdcBalanceBefore = i_usdc.balanceOf(address(this));
        i_universalRouter.execute(
            commands,
            inputs,
            block.timestamp + SWAP_DEADLINE
        );
        uint256 usdcReceivedTokenDec = i_usdc.balanceOf(address(this)) -
            usdcBalanceBefore;

        usdcReceived = _convertToDecimalStandard(
            usdcReceivedTokenDec,
            i_decimalsUsdc
        );
    }

    /**
     * @dev Swaps one underlying asset for the other during rebalancing.
     * @param _swapFrom     Asset address to sell.
     * @param _amountToSwap Amount in std decimals (18).
     * @return amountReceived Amount received in std decimals (18).
     */
    function _swapAssetForAsset(
        address _swapFrom,
        uint256 _amountToSwap
    ) internal returns (uint128 amountReceived) {
        // Convert the std-decimal amount to token decimals for the actual ERC20 operations.
        uint256 amountToSwapTokenDec;
        if (_swapFrom == address(i_asset0)) {
            amountToSwapTokenDec = _convertFromStdDecimalsToTokenDecimals(
                _amountToSwap,
                i_decimals0
            );
        } else {
            amountToSwapTokenDec = _convertFromStdDecimalsToTokenDecimals(
                _amountToSwap,
                i_decimals1
            );
        }

        (
            bytes memory commands,
            bytes[] memory inputs,
            address tokenToSwap,
            address tokenToReceive
        ) = i_swapManager.buildSingleSwapParams(
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

            IERC20(tokenToSwap).forceApprove(
                address(i_universalRouter),
                amountToSwapTokenDec
            );
            i_universalRouter.execute(
                commands,
                inputs,
                block.timestamp + SWAP_DEADLINE
            );

            amountReceivedTokenDec =
                IERC20(tokenToReceive).balanceOf(address(this)) -
                balanceBefore;
        }

        uint8 receivedAssetDecimals = (_swapFrom == address(i_asset0))
            ? i_decimals1
            : i_decimals0;
        amountReceived = _convertToDecimalStandard(
            amountReceivedTokenDec,
            receivedAssetDecimals
        ).toUint128();
    }

    // =========================================================================
    //  Internal — rebalance helpers
    // =========================================================================

    function _tryRebalanceIndex()
        internal
        returns (bool success, bytes memory reasonData)
    {
        try this.rebalanceIndex() {
            return (true, "");
        } catch Error(string memory reason) {
            return (
                false,
                abi.encodeWithSelector(
                    bytes4(keccak256("Error(string)")),
                    reason
                )
            );
        } catch (bytes memory lowLevelData) {
            return (
                false,
                lowLevelData.length > 0 ? lowLevelData : bytes("Unknown error")
            );
        }
    }

    function _checkIfRebalanceNeeded(
        uint256 _token0UsdValue,
        uint256 _totalAssetUsdValue
    ) internal view returns (bool) {
        (uint128 weight0, ) = _getAssetsEffectiveWights(
            _token0UsdValue,
            _totalAssetUsdValue
        );
        return
            weight0 < s_weight0 - REBALANCE_THRESHOLD ||
            weight0 > s_weight0 + REBALANCE_THRESHOLD;
    }

    // =========================================================================
    //  Internal — decimal helpers
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

    function _isInitialized() internal view {
        if (!s_initialized) revert Index__NotInitialized();
    }

    function _getAssetsEffectiveWights(
        uint256 asset0UsdValue,
        uint256 totalAssetUsdValue
    )
        internal
        pure
        returns (uint128 effectiveWeight0, uint128 effectiveWeight1)
    {
        (uint256 w0, uint256 w1) = UnderlyingMath.calculateEffectiveWeights(
            asset0UsdValue,
            totalAssetUsdValue,
            MAX_PERCENTAGE
        );
        effectiveWeight0 = w0.toUint128();
        effectiveWeight1 = w1.toUint128();
    }

    // =========================================================================
    //  Getters
    // =========================================================================

    /**
     * @notice Returns the latest normalised Chainlink price for a supported asset.
     * @return price USD price with 18 decimals.
     */
    function getLatestPrice(address _asset) public view returns (uint256) {
        AggregatorV3Interface feed;
        if (_asset == address(i_asset0)) feed = i_asset0PriceFeed;
        else if (_asset == address(i_asset1)) feed = i_asset1PriceFeed;
        else if (_asset == address(i_usdc)) feed = i_usdcPriceFeed;
        else revert Index__AssetNotSupported();

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (answer <= 0) revert Index__PriceFeedNotAvailable();
        if (answeredInRound < roundId) revert Index__PriceFeedRoundStale();
        if (block.timestamp - updatedAt > MAX_DELAY)
            revert Index__PriceIsStale();

        return _convertToDecimalStandard(uint256(answer), feed.decimals());
    }

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

    function getAssetsEffectiveWeights()
        public
        view
        returns (uint128 effectiveWeight0, uint128 effectiveWeight1)
    {
        (uint256 a0usd, , uint256 total) = getAssetsUsdValue();
        (effectiveWeight0, effectiveWeight1) = _getAssetsEffectiveWights(
            a0usd,
            total
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

    function getAssetsPendingWeights()
        public
        view
        returns (uint128, uint128, uint256)
    {
        return (s_pendingWeight0, s_pendingWeight1, s_weightUpdateExecutableAt);
    }

    /**
     * @notice Returns the raw reserves in **token decimals** as stored in contract state.
     */
    function getAssetsReserves() public view returns (uint128, uint128) {
        return (s_asset0Reserve, s_asset1Reserve);
    }

    /**
     * @notice Returns the reserves normalised to the 18-decimal standard.
     *         Useful for off-chain consumers that work in std units.
     */
    function getAssetsReservesStdDecimals()
        public
        view
        returns (uint256, uint256)
    {
        return (
            _convertToDecimalStandard(s_asset0Reserve, i_decimals0),
            _convertToDecimalStandard(s_asset1Reserve, i_decimals1)
        );
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
        return address(i_asset0PriceFeed);
    }
    function getAsset1PriceFeed() public view returns (address) {
        return address(i_asset1PriceFeed);
    }
    function getUsdcPriceFeed() public view returns (address) {
        return address(i_usdcPriceFeed);
    }

    function getFeesInfo()
        public
        view
        returns (uint32 feePercentage, uint128 totalFees)
    {
        return (s_feePercentage, s_totalFees);
    }

    function getInitializationStatus() public view returns (bool) {
        return s_initialized;
    }
}
