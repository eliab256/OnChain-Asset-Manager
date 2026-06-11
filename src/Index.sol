// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
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
import {ISwapManager} from "./Interface/ISwapManager.sol";
import {
    IUniversalRouter
} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";

/**
 * @title Index
 *
 * @notice Reserve accounting
 * s_asset0Reserve and s_asset1Reserve are stored in **token decimals**
 * (i.e. the native decimals of each underlying asset).
 *
 */
contract Index is IIndex, ERC20Permit, AccessControl, ContractCodeConstants {
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
    ) ERC20Permit(_name) ERC20(_name, _symbol) {
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
     * @param _depositor Address that provides the seed tokens.
     * @param _underlyingAmount0 Amount of asset0 in **token decimals**.
     */
    function initialize(
        address _depositor,
        uint256 _underlyingAmount0
    ) external onlyRole(INDEX_MANAGER_ROLE) {
        // 1. Check if index is already initialized, if not proceed with initialization
        if (s_initialized) revert Index__AlreadyInitialized();

        // 2. Check if underlyingAmount0 is greater than 0 to avoid division by zero and meaningless initialization
        if (_underlyingAmount0 == 0) revert Index__InvalidUnderlyingAmount();

        // 3. Transfer Asset0 amount from the depositor to the index contract
        i_asset0.safeTransferFrom(
            _depositor,
            address(this),
            _underlyingAmount0
        );

        // 4. Get target weights to calculate underlying amount of asset1
        (uint128 weight0, uint128 weight1) = getAssetsWeights();

        // 5. Derive the required amount of asset1 from the provided amount of asset0 and the target weights.
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

        // 6. Convert asset1 std amount to token decimals for the actual transfer
        uint256 underlyingAmount1TokenDec = _convertFromStdDecimalsToTokenDecimals(
                underlyingAmount1Std,
                i_decimals1
            );

        // 7. Transfer the derived amount of asset1 from the depositor to the index contract
        i_asset1.safeTransferFrom(
            _depositor,
            address(this),
            underlyingAmount1TokenDec
        );

        // 8. Update reserves in token decimals and set index as initialized
        s_asset0Reserve = _underlyingAmount0.toUint128();
        s_asset1Reserve = underlyingAmount1TokenDec.toUint128();
        s_initialized = true;

        // 9. Calculate initialShersAmount and send to the depositor.
        uint256 initialShares = underlying0UsdValue + underlying1UsdValue;
        _mint(_depositor, initialShares);

        // 10. Emit event with initialization details
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
        uint256 netUsdcAmountStdDecimals;
        {
            // 2.1 Calculate fees on token decimals avoid future rounding error
            uint128 feeAmount;
            uint256 netUsdcAmount;
            (feeAmount, netUsdcAmount) = _calculateFees(_usdcAmountIn);
            s_totalFees += feeAmount;

            // 2.2 Normalize netUsdcAmount to std decimals for internal calculations.
            netUsdcAmountStdDecimals = _convertToDecimalStandard(
                netUsdcAmount,
                i_decimalsUsdc
            );
        }

        // 2.3 Convert net USDC amount to its real USD value using the USDC price feed.
        uint256 netDepositUsdValue = _usdcToUsd(
            netUsdcAmountStdDecimals,
            initState.priceUsdc
        );

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

            // 3.2 Calculate USD amount to allocate to each underlying token
            (
                uint256 usdAmount0ToAllocate,
                uint256 usdAmount1ToAllocate
            ) = UnderlyingMath.calculateDepositAllocationInUsd(
                    initState.totalAssetUsdValue,
                    netDepositUsdValue,
                    targetWeight0,
                    targetWeight1,
                    effectiveWeight0
                );

            // 3.3 Convert USD allocation amounts back to USDC amounts for swaps
            uint256 usdcAmount0ToSwap = _usdToUsdc(
                usdAmount0ToAllocate,
                initState.priceUsdc
            );
            uint256 usdcAmount1ToSwap = _usdToUsdc(
                usdAmount1ToAllocate,
                initState.priceUsdc
            );

            // 3.4 Swap USDC and receive Token0 and Token1 amount in std decimals
            (asset0ReceivedStd, asset1ReceivedStd) = _swapUsdcForAssets(
                usdcAmount0ToSwap,
                usdcAmount1ToSwap
            );

            // 3.5 Calculate the USD value of the amounts received to perform the tolerance check later.
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
            netDepositUsdValue,
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
            //3.1. Get target weights
            (uint128 weight0, uint128 weight1) = getAssetsWeights();

            //3.2. Get Effective weights at the moment
            (uint128 effectiveWeight0, ) = _getAssetsEffectiveWights(
                initState.asset0UsdValue,
                initState.totalAssetUsdValue
            );

            //3.3. Calculate the amount of assets to swap in usdc
            (uint256 asset0UsdToSwap, uint256 asset1UsdToSwap) = UnderlyingMath
                .calculateWithdrawUnderlyingAmountsInUsd(
                    initState.totalAssetUsdValue,
                    sharesBurnUsdValue,
                    weight0,
                    weight1,
                    effectiveWeight0
                );

            //3.4. Snapshot balances before the swap to measure exact amounts consumed.
            uint256 asset0Before = i_asset0.balanceOf(address(this));
            uint256 asset1Before = i_asset1.balanceOf(address(this));

            //3.5. Swap Assets to Usdc
            usdcReceived = _swapAssetsForUsdc(asset0UsdToSwap, asset1UsdToSwap);

            //3.6 Delta = tokens sent to the router, already in token decimals.
            asset0AmountRedeemedTokenDec = (asset0Before -
                i_asset0.balanceOf(address(this))).toUint128();
            asset1AmountRedeemedTokenDec = (asset1Before -
                i_asset1.balanceOf(address(this))).toUint128();
        }

        // 4. Fees (applied on USDC amounts, not USD).
        (uint128 feeAmount, uint256 netUsdcAmount) = _calculateFees(
            usdcReceived
        );

        // 5. Tolerance check.
        {
            //5.1. Get expected usdc amount
            uint256 expectedUsdcBeforeFees = _usdToUsdc(
                sharesBurnUsdValue,
                initState.priceUsdc
            );
            (, uint256 netExpectedUsdc) = _calculateFees(
                expectedUsdcBeforeFees
            );

            //5.2. Get minimum acceptable to validate the splippage
            uint256 minNetAmountAcceptable = netExpectedUsdc
                .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);

            //5.3. Revert if slippage is higher than tolerance
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

        //8. Burn shares and emit the event
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
     * @param _usdcAmountIn USDC amount in token decimals.
     * @param _maxTolerance Maximum tolerated deviation.
     */
    function minMintPreview(
        uint256 _usdcAmountIn,
        uint256 _maxTolerance
    ) public view isInitialized returns (uint256 minimumSharesToMint) {
        // 1. Convert USDC amount from token decimals to std decimals for internal calculations
        uint256 usdcAmountInNormalized = _convertToDecimalStandard(
            _usdcAmountIn,
            i_decimalsUsdc
        );

        // 2. apply fees in std decimals to avoid rounding issues.
        (, uint256 netUsdcAmount) = _calculateFees(usdcAmountInNormalized);

        // 3. Cache initial state.
        (
            ,
            ,
            uint256 priceUsdc,
            ,
            ,
            ,
            ,
            uint256 totalAssetUsdValue
        ) = _initFunctionValues();

        // 4. Convert net USDC amount to real USD value using the price feed.
        uint256 netUsdValue = _usdcToUsd(netUsdcAmount, priceUsdc);

        // 5. Calculate the minimum shares to mint based on the net USD value after fees and the tolerance.
        uint256 minimumUsdAmount = netUsdValue.calculateNetAmountFromTolerance(
            _maxTolerance,
            MAX_PERCENTAGE
        );
        // 6. Returns the minimum shares to mint corresponding to the minimum USD amount to accept based on the current total asset USD value and total shares supply.
        minimumSharesToMint = _mintPreview(
            minimumUsdAmount,
            totalAssetUsdValue
        );
    }

    /**
     * @dev Preview: minimum USDC to receive for a given shares amount and tolerance.
     * @param _sharesAmountIn Shares amount to redeem.
     * @param _maxTolerance Maximum tolerated deviation.
     * @return minUsdcToReceive Minimum USDC amount in token decimals the user should receive to accept the redemption.
     */
    function minRedeemPreview(
        uint256 _sharesAmountIn,
        uint256 _maxTolerance
    ) public view isInitialized returns (uint256 minUsdcToReceive) {
        // 1. Cache initial state.
        (
            ,
            ,
            uint256 priceUsdc,
            ,
            ,
            ,
            ,
            uint256 totalAssetUsdValue
        ) = _initFunctionValues();

        // 2. _redeemPreview returns the USD value of the shares being redeemed.
        uint256 sharesUsdValue = _redeemPreview(
            _sharesAmountIn,
            totalAssetUsdValue
        );

        // 3. Convert USD value to USDC amount, then apply fees.
        uint256 usdcAmountBeforeFees = _usdToUsdc(sharesUsdValue, priceUsdc);
        (, uint256 netUsdcAmount) = _calculateFees(usdcAmountBeforeFees);

        // 4. Calculate the minimum USDC amount to receive based on the net USDC amount after fees and the tolerance.
        uint256 minUsdcEighteenDec = netUsdcAmount
            .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);

        //5. Convert minimum USDC amount from std decimals to token decimals for the actual value to return.
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
        // 1. Check if there is already a pending weight update
        if (
            s_weightUpdateExecutableAt != 0 &&
            block.timestamp < s_weightUpdateExecutableAt
        ) revert Index__PendingWeightUpdate();

        // 2. Check if the new proposed weight is valid (not equal to current, not above max or below min).
        bool invalidWeight0 = _newWeightAsset0 >= MAX_WEIGHT ||
            _newWeightAsset0 <= MIN_WEIGHT ||
            _newWeightAsset0 == s_weight0;
        if (invalidWeight0) revert Index__InvalidWeight();

        // 3. Update implementationTimestamp with new timestamp for when the weight update can be executed,
        implementationTimestamp = block.timestamp + WEIGHT_UPDATE_DELAY;

        // 4. Store the proposed weights in storage.
        s_pendingWeight0 = _newWeightAsset0;
        s_pendingWeight1 = MAX_PERCENTAGE - _newWeightAsset0;
        s_weightUpdateExecutableAt = implementationTimestamp;

        // 5. Emit event with the proposed weights and the timestamp execution
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
        // 1. Check if there is a pending weight update ready to be executed, if not revert.
        if (
            s_weightUpdateExecutableAt == 0 ||
            block.timestamp < s_weightUpdateExecutableAt
        ) revert Index__NotPendingWeightUpdate();

        // 2. Update target weights with the pending weights
        s_weight0 = s_pendingWeight0;
        s_weight1 = s_pendingWeight1;

        // 3. Reset pending weights and timestamp in storage.
        s_pendingWeight0 = 0;
        s_pendingWeight1 = 0;
        s_weightUpdateExecutableAt = 0;

        // 4. Trigger rebalance and emit event with failure or success rebalance.
        (bool rebalanceSuccess, bytes memory reasonData) = _tryRebalanceIndex();
        if (!rebalanceSuccess) emit WeightUpdateRebalanceFailed(reasonData);

        // 5. Emit event with the new weights and the timestamp of the execution
        emit IndexWeightsUpdated(s_weight0, s_weight1, block.timestamp);
    }

    /**
     * @notice Transfers accrued protocol fees to the collector.
     * @dev Only callable by an index manager. Reverts if there are no fees to collect.
     * @param _collector Address that will receive the collected fees.
     * @return feesCollected Amount of fees collected in token decimals.
     */
    function collectFees(
        address _collector
    ) external onlyRole(INDEX_MANAGER_ROLE) returns (uint256 feesCollected) {
        // 1. Cache totalFees in a local variable to avoid multiple storage reads
        uint128 cacheTotalFees = s_totalFees;

        // 2. Check if there are fees to collect, if not revert.
        if (cacheTotalFees == 0) revert Index__NoFeesToCollect();

        // 3. Reset totalFees in storage before the transfer to prevent reentrancy issues.
        feesCollected = cacheTotalFees;
        s_totalFees = 0;

        // 4. Transfer the collected fees in USDC to the collector.
        i_usdc.safeTransfer(_collector, feesCollected);

        // 5. Emit event with the amount of fees collected and the collector address.
        emit FeesCollected(_collector, feesCollected);
    }

    /**
     * @notice Rebalances the index to match its target weights.
     * @dev Only callable by an index manager.
     * @dev Reverts if there are no fees to collect.
     * @dev Reverts if swap slippage is higher than the defined threshold.
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

        // 4. Scope: execute swap and compute updated reserves in token decimals.
        uint128 updatedReserv0;
        uint128 updatedReserv1;
        {
            // 4.1 If token0 swap to token1
            if (amount0ToSwapStd > 0) {
                // 4.1.1 Swap asset0 to asset1; result is in std decimals.
                uint128 token1ReceivedStd = _swapAssetForAsset(
                    address(i_asset0),
                    amount0ToSwapStd
                );

                // 4.1.2 Convert amounts to token decimals for storage.
                uint256 amount0TokenDec = _convertFromStdDecimalsToTokenDecimals(
                        amount0ToSwapStd,
                        i_decimals0
                    );
                uint256 token1TokenDec = _convertFromStdDecimalsToTokenDecimals(
                    token1ReceivedStd,
                    i_decimals1
                );
                // 4.1.3 Update reserves in token decimals.
                updatedReserv0 = (s_asset0Reserve -
                    amount0TokenDec.toUint128());
                updatedReserv1 = (s_asset1Reserve + token1TokenDec.toUint128());
            }

            // 4.2 Else, token1 swap to token0
            else {
                // 4.2.1 Swap asset1 to asset0; result is in std decimals.
                uint128 token0ReceivedStd = _swapAssetForAsset(
                    address(i_asset1),
                    amount1ToSwapStd
                );

                // 4.2.2 Convert amounts to token decimals for storage.
                uint256 amount1TokenDec = _convertFromStdDecimalsToTokenDecimals(
                        amount1ToSwapStd,
                        i_decimals1
                    );
                uint256 token0TokenDec = _convertFromStdDecimalsToTokenDecimals(
                    token0ReceivedStd,
                    i_decimals0
                );

                // 4.2.3 Update reserves in token decimals.
                updatedReserv1 = (s_asset1Reserve -
                    amount1TokenDec.toUint128());
                updatedReserv0 = (s_asset0Reserve + token0TokenDec.toUint128());
            }
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

        // 7. Emit event with rebalance details.
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

    /**
     * @notice used in the mint shares function to calculate the shares to mint based on the actual USD value of the assets received after the swap and validate the tolerance condition.
     * @notice used in the minMintPreview function to calculate the minimum shares to mint based on the USDC amount input and the tolerance without performing any swap.
     * @dev Returns the amount of shares to mint for a given USDC amount and total asset USD value before the mint.
     * @param _usdcAmountIn USDC amount in token decimals.
     * @param _totalAssetUsdValueBefore Total asset USD value before the mint.
     */
    function _mintPreview(
        uint256 _usdcAmountIn,
        uint256 _totalAssetUsdValueBefore
    ) internal view returns (uint256 sharesToMint) {
        sharesToMint = _usdcAmountIn.calculateSharesToMintFromUsdcAmount(
            _totalAssetUsdValueBefore,
            totalSupply()
        );
    }

    /**
     * @notice Validates if the shares to mint based on the actual USD value of the assets received after the swap is within the tolerated range compared to the shares to mint based on the USDC amount input.
     * @param _usdcAmountIn USDC amount in token decimals.
     * @param _maxTolerance Maximum tolerated deviation in percentage.
     * @param _totalAssetUsdValueBefore Total asset USD value before the mint.
     * @param asset0ReceivedUsdValue USD value of asset0 received after the swap.
     * @param asset1ReceivedUsdValue USD value of asset1 received after the swap.
     * @return sharesToMint Amount of shares to mint after validating the tolerance. Returns 0 if the tolerance condition is not met.
     */
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

    /**
     * @notice Calculates the USDC amount to receive for a given shares amount before fees.
     * @notice used in the redeem function to calculate the USDC amount to transfer to the user based on the USD value of the shares being redeemed before fees and validate the tolerance condition.
     * @notice used in the minRedeemPreview function to calculate the minimum USDC amount to receive based on the shares amount input and the tolerance without performing any swap.
     * @param _sharesAmountIn Amount of shares to redeem.
     * @param _totalAssetUsdValueBefore Total asset USD value before the redeem.
     * @return usdcToReceiveBeforeFees USDC amount to receive before fees.
     */
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
     * @param _usdcAmountIn USDC amount in 18-decimal standard.
     * @return feeAmount Calculated fee amount in 18-decimal standard.
     * @return netUsdcAmount USDC amount after deducting the fee, in 18-decimal standard.
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
     * @notice Returns values are stored in the InitStateCache struct to avoid stack too deep errors.
     * @dev Reads storage and price feeds to cache all the necessary values for the mint and redeem functions in a struct to avoid multiple storage reads and external calls throughout the functions, which would increase gas and create more points of failure (e.g. price feed calls).
     * @return priceAsset0 Price of asset0 from the price feed, in 18-decimal standard.
     * @return priceAsset1 Price of asset1 from the price feed, in 18-decimal standard.
     * @return priceUsdc Price of USDC from the price feed, in 18-decimal standard.
     * @return initialAsset0Reserve Initial reserve of asset0 in token decimals.
     * @return initialAsset1Reserve Initial reserve of asset1 in token decimals.
     * @return asset0UsdValue USD value of the initial reserve of asset0, calculated using the price feed and converted to 18-decimal standard.
     * @return asset1UsdValue USD value of the initial reserve of asset1, calculated using the price feed and converted to 18-decimal standard.
     * @return totalAssetUsdValue Total USD value of the initial reserves of both assets, calculated using the price feed and converted to 18-decimal standard.
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
        // 1. Convert USDC amounts from std decimals to token decimals for the swap input.
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

        // 2. Build swap commands and snapshot balances before the swap.
        // 2.1. Only asset1 needed single swap USDC to asset1
        if (_usdcAmountIn0 == 0 && _usdcAmountIn1 > 0) {
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET1_USDC,
                address(i_usdc),
                usdcAmount1TokenDec.toUint128()
            );
            asset1BalanceBefore = i_asset1.balanceOf(address(this));
        }
        // 2.2. Only asset0 needed single swap USDC to asset0
        else if (_usdcAmountIn0 > 0 && _usdcAmountIn1 == 0) {
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                address(i_usdc),
                usdcAmount0TokenDec.toUint128()
            );
            asset0BalanceBefore = i_asset0.balanceOf(address(this));
        }
        // 2.3. Both needed  double swap USDC to asset0 + USDC to asset1
        else {
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

        // 3. Transfer USDC to the Universal Router and execute the swap.
        //    payerIsUser=false → the router pays from its own balance (no Permit2 needed).
        i_usdc.safeTransfer(
            address(i_universalRouter),
            usdcAmount0TokenDec + usdcAmount1TokenDec
        );
        i_universalRouter.execute(
            commands,
            inputs,
            block.timestamp + SWAP_DEADLINE
        );

        // 4. Measure received amounts (token decimals) and convert to std decimals.
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
     * @return usdcReceived Received USDC amount in std decimals (NOT USD value).
     */
    function _swapAssetsForUsdc(
        uint256 _asset0UsdToSwap,
        uint256 _asset1UsdToSwap
    ) internal returns (uint256 usdcReceived) {
        // 1. Derive token amounts from USD values using Chainlink prices.
        uint256 asset0AmountTokenDec;
        uint256 asset1AmountTokenDec;
        {
            // 1.1 Calculate asset0 token amount from its USD value.
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
            // 1.2 Calculate asset1 token amount from its USD value.
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

        // 2. Build swap commands and transfer input tokens to the Universal Router.
        if (_asset0UsdToSwap > 0 && _asset1UsdToSwap == 0) {
            // 2.1 Only asset0 to sell; single swap asset0 to USDC.
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                address(i_asset0),
                asset0AmountTokenDec.toUint128()
            );
            i_asset0.safeTransfer(
                address(i_universalRouter),
                asset0AmountTokenDec
            );
        } else if (_asset0UsdToSwap == 0 && _asset1UsdToSwap > 0) {
            // 2.2 Only asset1 to sell; single swap asset1 to USDC.
            (commands, inputs, , ) = i_swapManager.buildSingleSwapParams(
                address(this),
                SwapType.ASSET1_USDC,
                address(i_asset1),
                asset1AmountTokenDec.toUint128()
            );
            i_asset1.safeTransfer(
                address(i_universalRouter),
                asset1AmountTokenDec
            );
        } else {
            // 2.3 Both to sell; double swap asset0 to USDC + asset1 to USDC.
            (commands, inputs) = i_swapManager.buildDoubleSwapParams(
                address(this),
                SwapType.ASSET0_USDC,
                SwapType.ASSET1_USDC,
                address(i_asset0),
                address(i_asset1),
                asset0AmountTokenDec.toUint128(),
                asset1AmountTokenDec.toUint128()
            );
            i_asset0.safeTransfer(
                address(i_universalRouter),
                asset0AmountTokenDec
            );
            i_asset1.safeTransfer(
                address(i_universalRouter),
   
                asset1AmountTokenDec
            );
        }

        // 3. Snapshot USDC balance before swap.
        uint256 usdcBalanceBefore = i_usdc.balanceOf(address(this));

        // 4.  Execute the swap via the Universal Router.
        i_universalRouter.execute(
            commands,
            inputs,
            block.timestamp + SWAP_DEADLINE
        );

        // 5. Calculate USDC received as the delta between balances.
        uint256 usdcReceivedTokenDec = i_usdc.balanceOf(address(this)) -
            usdcBalanceBefore;

        // 6. Convert received USDC from token decimals to std decimals.
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
        // 1. Convert the std-decimal amount to token decimals for the actual ERC20 operations.
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

        // 2. Build swap command for the asset0 ↔ asset1 route.
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

        // 3. Snapshot balance, transfer tokens to the Universal Router, and execute the swap.
        uint256 amountReceivedTokenDec;
        {
            uint256 balanceBefore = IERC20(tokenToReceive).balanceOf(
                address(this)
            );

            IERC20(tokenToSwap).safeTransfer(
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

        // 4. Convert received amount from token decimals to std decimals.
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

    /**
     * @notice Used on the executeWeightUpdate function to attempt the rebalance and catch any error that may occur during the process to emit it in an event instead of reverting the transaction.
     * @dev Attempts to rebalance the index.
     * @return success True if the rebalance was successful, false otherwise.
     * @return reasonData Encoded reason for failure if the rebalance was not successful.
     */
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
    /**
     * @dev Checks if a rebalance is needed based on the current weights of the assets.
     * @dev If effective weights exceed the target weights by more than the defined threshold, a rebalance is needed.
     * @param _token0UsdValue USD value of token0 in 18-decimal standard.
     * @param _totalAssetUsdValue Total USD value of all assets in 18-decimal standard.
     * @return bool True if a rebalance is needed, false otherwise.
     */
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

    /**
     * @dev Converts an amount from the token decimals to the 18-decimal standard.
     * @param _amount Amount in token decimals.
     * @param _currentDecimals Decimals of the token.
     * @return convertedAmount Amount converted to the 18-decimal standard.
     */
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

    /**
     * @dev Converts an amount from the 18-decimal standard to the token decimals.
     * @param _amount Amount in 18-decimal standard.
     * @param _tokenDecimals Decimals of the token to convert to.
     * @return convertedAmount Amount converted to the token decimals.
     * @notice If the token decimals are the same as the standard, returns the original amount. If the token decimals are lower than the standard, converts down. If the token decimals are higher
     */
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

    /**
     * @dev Converts a USDC amount (18-decimal std) to its real USD value
     *      using the USDC/USD Chainlink price feed.
     *      usdValue = (usdcAmountStd * priceUsdc) / 1e18
     * @param _usdcAmountStd USDC amount in 18-decimal standard.
     * @param _priceUsdc     USDC/USD price in 18-decimal standard.
     * @return usdValue      The real USD value in 18-decimal standard.
     */
    function _usdcToUsd(
        uint256 _usdcAmountStd,
        uint256 _priceUsdc
    ) internal pure returns (uint256 usdValue) {
        usdValue = (_usdcAmountStd * _priceUsdc) / (10 ** DECIMALS_STANDARD);
    }

    /**
     * @dev Converts a USD value (18-decimal std) to the equivalent USDC amount
     *      using the USDC/USD Chainlink price feed.
     *      usdcAmount = (usdValue * 1e18) / priceUsdc
     * @param _usdValue  USD value in 18-decimal standard.
     * @param _priceUsdc USDC/USD price in 18-decimal standard.
     * @return usdcAmountStd The USDC amount in 18-decimal standard.
     */
    function _usdToUsdc(
        uint256 _usdValue,
        uint256 _priceUsdc
    ) internal pure returns (uint256 usdcAmountStd) {
        usdcAmountStd = (_usdValue * (10 ** DECIMALS_STANDARD)) / _priceUsdc;
    }

    /**
     * @dev Checks if the contract is initialized.
     * @notice Reverts if the contract is not initialized.
     */
    function _isInitialized() internal view {
        if (!s_initialized) revert Index__NotInitialized();
    }

    /**
     * @notice Calculates the effective weights of asset0 and asset1 based on their USD values and the total USD value of the index.
     * @param asset0UsdValue USD value of asset0 in 18-decimal standard.
     * @param totalAssetUsdValue Total USD value of the index in 18-decimal standard.
     * @return effectiveWeight0 Effective weight of asset0 in percentage with 4 decimals (e.g., 600000 for 60.00%).
     * @return effectiveWeight1 Effective weight of asset1 in percentage with 4 decimals (e.g., 400000 for 40.00%).
     */
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
     * @notice Normalised means that the price is converted to the 18-decimal standard regardless of the decimals of the price feed, to have a consistent decimal format across all prices used in the contract.
     * @param _asset The address of the asset to get the price for. Must be either asset0, asset1, or USDC.
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
        if (_asset == address(i_usdc)) {
            if (block.timestamp - updatedAt > MAX_USDC_DELAY)
                revert Index__PriceIsStale();
        } else {
            if (block.timestamp - updatedAt > MAX_DELAY)
                revert Index__PriceIsStale();
        }
        return _convertToDecimalStandard(uint256(answer), feed.decimals());
    }

    /**
     * @notice Returns the total USD value of asset0, asset1, and the combined total.
     * @dev Values come from the _initFunctionValues function which reads the latest prices and reserves to calculate the USD values, so they are all consistent and based on the same block data.
     * @return asset0TotalUsdValue The total USD value of asset0.
     * @return asset1TotalUsdValue The total USD value of asset1.
     * @return totalUsdValue The combined total USD value of asset0 and asset1.
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
     * @notice Returns the effective weights at that moment of asset0 and asset1.
     * @return effectiveWeight0 The effective weight of asset0.
     * @return effectiveWeight1 The effective weight of asset1.
     */
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

    /**
     * @notice Returns the decimals of asset0, asset1, and USDC tokens.
     * @return asset0Decimals The decimals of asset0 token.
     * @return asset1Decimals The decimals of asset1 token.
     * @return usdcDecimals The decimals of USDC token.
     */
    function getAssetsAndUsdcDecimals()
        public
        view
        returns (uint8 asset0Decimals, uint8 asset1Decimals, uint8 usdcDecimals)
    {
        return (i_decimals0, i_decimals1, i_decimalsUsdc);
    }

    /**
     * @notice Returns the current weights of asset0 and asset1.
     * @return The current weights of asset0 and asset1.
     */
    function getAssetsWeights() public view returns (uint128, uint128) {
        return (s_weight0, s_weight1);
    }

    /**
     * @notice Returns the pending weights and the timestamp when the weight update can be executed.
     * @return The pending weights of asset0 and asset1, and the timestamp when the weight update can be executed.
     */
    function getAssetsPendingWeights()
        public
        view
        returns (uint128, uint128, uint256)
    {
        return (s_pendingWeight0, s_pendingWeight1, s_weightUpdateExecutableAt);
    }

    /**
     * @notice Returns the raw reserves in **token decimals** as stored in contract state.
     * @return The reserves of asset0 and asset1 in token decimals. These are the actual amounts used for swaps and stored in state, not normalised to 18 decimals.
     */
    function getAssetsReserves() public view returns (uint128, uint128) {
        return (s_asset0Reserve, s_asset1Reserve);
    }

    /**
     * @notice Returns the reserves normalised to the 18-decimal standard.
     *         Useful for off-chain consumers that work in std units.
     * @return The reserves of asset0 and asset1 in 18-decimal standard.
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

    /**
     * @notice Returns the address of the asset0 token.
     * @return The address of the asset0 token.
     */
    function getAsset0() public view returns (address) {
        return address(i_asset0);
    }

    /**
     * @notice Returns the address of the asset1 token.
     * @return The address of the asset1 token.
     */
    function getAsset1() public view returns (address) {
        return address(i_asset1);
    }

    /**
     * @notice Returns the address of the USDC token used for minting, redeeming, and fee collection.
     * @return The address of the USDC token.
     */
    function getUsdc() public view returns (address) {
        return address(i_usdc);
    }

    /**
     * @notice Returns the address of the asset0 price feed.
     * @return The address of the asset0 price feed.
     */
    function getAsset0PriceFeed() public view returns (address) {
        return address(i_asset0PriceFeed);
    }

    /**
     * @notice Returns the address of the asset1 price feed.
     * @return The address of the asset1 price feed.
     */
    function getAsset1PriceFeed() public view returns (address) {
        return address(i_asset1PriceFeed);
    }

    /**
     * @notice Returns the address of the USDC price feed.
     * @return The address of the USDC price feed.
     */
    function getUsdcPriceFeed() public view returns (address) {
        return address(i_usdcPriceFeed);
    }

    /**
     * @notice Returns the fee information of the contract.
     * @return feePercentage The current fee percentage.
     * @return totalFees The total fees accumulated.
     */
    function getFeesInfo()
        public
        view
        returns (uint32 feePercentage, uint128 totalFees)
    {
        return (s_feePercentage, s_totalFees);
    }

    /**
     * @notice Returns the initialization status of the contract.
     * @return bool indicating whether the contract has been initialized.
     */
    function getInitializationStatus() public view returns (bool) {
        return s_initialized;
    }
}
