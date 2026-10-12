// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ContractCodeConstants} from "./ContractCodeConstants.sol";
import {Index} from "./Index.sol";
import {IIndexManager} from "./Interface/IIndexManager.sol";
import {ISwapManager} from "./Interface/ISwapManager.sol";
import {SwapManager} from "./SwapManager.sol";
import {IPriceFeedManager} from "./Interface/IPriceFeedManager.sol";
import {IRouter} from "./Interface/IRouter.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./errors/IndexManagerErrors.sol";
import "./events/IndexManagerEvents.sol";
import {IndexAsset, SwapRoute, IndexAction} from "./types.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IIndex} from "./Interface/IIndex.sol";

contract IndexManager is IIndexManager, AccessControl, ContractCodeConstants {
    using SafeERC20 for IERC20;

    struct IndexAssets {
        address asset0;
        address asset1;
    }

    bytes32 public constant ASSET_MANAGER_ROLE =
        keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant FEE_COLLECTOR_ROLE =
        keccak256("FEE_COLLECTOR_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    uint32 public constant MAX_FEES_PERCENTAGE = 10 * PERCENTAGE_FEE_PRECISION; // 10%
    uint32 public constant MIN_FEES_PERCENTAGE =
        (1 * PERCENTAGE_FEE_PRECISION) / 10; // 0.1%

    address internal immutable i_usdc;
    address internal immutable i_uniswapUniversalRouter;
    // SwapManager ERC1967 proxy, deployed in the constructor. Same address for every index.
    address internal immutable i_swapManager;
    // PriceFeedManager ERC1967 proxy, deployed in the constructor. Same address for every index.
    address internal immutable i_priceFeedManager;
    // Router ERC1967 proxy, deployed in the constructor. Every index grants ROUTER_ROLE to this address.
    address internal immutable i_router;

    address[] private s_deployedIndexes;
    address[] private s_initializedIndexes;
    // Mapping from assets to index
    mapping(address => mapping(address => address)) private s_getIndex;
    // Mapping from index to address
    mapping(address => IndexAssets) private s_indexAssets;
    mapping(address => bool) private s_isIndex;
    mapping(address => bool) private s_isInitialized;

    uint256 private s_totalFeesCollected;

    modifier isIndexInitialized(address indexAddress) {
        _isIndexInitialized(indexAddress);
        _;
    }

    modifier areIndexesInitialized(address[] calldata indexAddresses) {
        _areIndexesInitialized(indexAddresses);
        _;
    }

    /**
     * @param _usdcAddress The USDC token address.
     * @param _uniswapUniversalRouter The Uniswap Universal Router address.
     * @param _swapManagerImplementation The SwapManager implementation; the constructor deploys its proxy, owned by this contract.
     * @param _priceFeedManagerImplementation The PriceFeedManager implementation; the constructor deploys its proxy, owned by this contract.
     * @param _routerImplementation The Router implementation; the constructor deploys its proxy, bound to this contract.
     * @param _upgrader The only account allowed to upgrade the three proxies (the TimelockController). Must be non-zero.
     */
    constructor(
        address _usdcAddress,
        address _uniswapUniversalRouter,
        address _swapManagerImplementation,
        address _priceFeedManagerImplementation,
        address _routerImplementation,
        address _upgrader
    ) {
        if (_upgrader == address(0)) revert IndexManager__ZeroAddress();
        if (_swapManagerImplementation.code.length == 0) {
            revert IndexManager__InvalidImplementation(
                _swapManagerImplementation
            );
        }
        if (_priceFeedManagerImplementation.code.length == 0) {
            revert IndexManager__InvalidImplementation(
                _priceFeedManagerImplementation
            );
        }
        if (_routerImplementation.code.length == 0) {
            revert IndexManager__InvalidImplementation(_routerImplementation);
        }
        i_usdc = _usdcAddress;
        i_uniswapUniversalRouter = _uniswapUniversalRouter;
        i_swapManager = address(
            new ERC1967Proxy(
                _swapManagerImplementation,
                abi.encodeCall(
                    SwapManager.initialize,
                    (address(this), _upgrader)
                )
            )
        );
        i_priceFeedManager = address(
            new ERC1967Proxy(
                _priceFeedManagerImplementation,
                abi.encodeCall(
                    IPriceFeedManager.initialize,
                    (address(this), _upgrader)
                )
            )
        );
        i_router = address(
            new ERC1967Proxy(
                _routerImplementation,
                abi.encodeCall(
                    IRouter.initialize,
                    (address(this), _usdcAddress, _upgrader)
                )
            )
        );

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ASSET_MANAGER_ROLE, msg.sender);
        _grantRole(FEE_COLLECTOR_ROLE, msg.sender);
        _grantRole(REBALANCER_ROLE, msg.sender);
    }

    /**
     * @dev Creates a new index with the specified fee percentage and underlying assets.
     * @notice The caller must have the ASSET_MANAGER_ROLE to call this function.
     * @notice All percentages are expressed with 4 decimals, so 100% = 1000000, 1% = 10000, etc.
     * @param _feePercentage The fee percentage for the index.
     * @notice asset0, asset1 and USDC must already have a price feed registered in the PriceFeedManager.
     * @param _assetA The first underlying asset of the index. The struct includes the asset address and its weight percentage in the index.
     * @param _assetB The second underlying asset of the index. The struct includes the asset address and its weight percentage in the index.
     */
    function createIndex(
        uint32 _feePercentage,
        IndexAsset memory _assetA,
        IndexAsset memory _assetB
    )
        public
        onlyRole(ASSET_MANAGER_ROLE)
        returns (address index, address token0, address token1)
    {
        if (_assetA.asset == _assetB.asset) {
            revert IndexManager__InvalidIndexAssetsAddress();
        }
        if (_assetA.asset == i_usdc || _assetB.asset == i_usdc) {
            revert IndexManager__UsdcCannotBeIndexAsset();
        }
        if (
            _feePercentage > MAX_FEES_PERCENTAGE ||
            _feePercentage < MIN_FEES_PERCENTAGE
        ) {
            revert IndexManager__InvalidFeePercentage();
        }

        // 1. Sort TokenA and TokenB
        IndexAsset memory asset0;
        IndexAsset memory asset1;
        {
            (address tokenAsset0, ) = sortAssets(_assetA.asset, _assetB.asset);
            if (tokenAsset0 == _assetA.asset) {
                asset0 = _assetA;
                asset1 = _assetB;
            } else {
                asset0 = _assetB;
                asset1 = _assetA;
            }
        }

        // 2. Check that the index does not already exist.
        if (s_getIndex[asset0.asset][asset1.asset] != address(0)) {
            revert IndexManager__IndexAlreadyExists(
                s_getIndex[asset0.asset][asset1.asset]
            );
        }

        // 3. Check that each weight is strictly between MIN_WEIGHT and MAX_WEIGHT
        //    (same bounds as Index.proposeUpdateWeights) and that they sum to 100%.
        if (
            asset0.weightPercentage <= MIN_WEIGHT ||
            asset0.weightPercentage >= MAX_WEIGHT ||
            asset1.weightPercentage <= MIN_WEIGHT ||
            asset1.weightPercentage >= MAX_WEIGHT ||
            asset0.weightPercentage + asset1.weightPercentage != MAX_WEIGHT
        ) {
            revert IndexManager__InvalidIndexAssetsPercentages();
        }

        // 4. Check that the underlying assets implement ERC20 metadata.
        _validateAssetIsERC20(asset0.asset);
        _validateAssetIsERC20(asset1.asset);

        // 5. Check that the underlying assets and USDC have a price feed registered in the PriceFeedManager.
        _checkPriceFeedRegistered(asset0.asset);
        _checkPriceFeedRegistered(asset1.asset);
        _checkPriceFeedRegistered(i_usdc);

        // 6. Deploy the index contract
        index = _deployIndex(asset0, asset1, _feePercentage);

        // 7. Store its address in the mappings and arrays.
        s_getIndex[asset0.asset][asset1.asset] = index;
        s_indexAssets[index] = IndexAssets({
            asset0: asset0.asset,
            asset1: asset1.asset
        });
        s_isIndex[index] = true;
        s_deployedIndexes.push(index);

        // 8. Emit event with the index address, its assets, weights and fee.
        emit IndexCreated(
            index,
            asset0.asset,
            asset1.asset,
            asset0.weightPercentage,
            asset1.weightPercentage,
            _feePercentage,
            msg.sender
        );

        // 9. Return the index address and its assets addresses.
        return (index, asset0.asset, asset1.asset);
    }

    /**
     * @notice Initializes the specified index with the given underlying amount.
     * @param _indexAddress The address of the index to initialize.
     * @param _underlyingAmount0 The amount of the first underlying asset to initialize the index with.
     * @param _routeAsset0Usdc The route used for Asset0 ↔ USDC swaps.
     * @param _routeAsset1Usdc The route used for Asset1 ↔ USDC swaps.
     * @param _routeAsset0Asset1 The route used for Asset0 ↔ Asset1 swaps.
     */
    function initializeIndex(
        address _depositor,
        address _indexAddress,
        uint256 _underlyingAmount0,
        SwapRoute memory _routeAsset0Usdc,
        SwapRoute memory _routeAsset1Usdc,
        SwapRoute memory _routeAsset0Asset1
    ) public onlyRole(ASSET_MANAGER_ROLE) {
        if (_underlyingAmount0 == 0) {
            revert IndexManager__InvalidIndexAssetsAmount();
        }
        if (!s_isIndex[_indexAddress]) {
            revert IndexManager__IsNotIndex();
        }

        if (s_isInitialized[_indexAddress]) {
            revert IndexManager__IndexAlreadyInitialized();
        }
        s_isInitialized[_indexAddress] = true;
        s_initializedIndexes.push(_indexAddress);

        ISwapManager(i_swapManager).registerIndex(
            _indexAddress,
            _routeAsset0Usdc,
            _routeAsset1Usdc,
            _routeAsset0Asset1
        );

        IIndex(_indexAddress).initialize(_depositor, _underlyingAmount0);
        emit IndexActionTriggered(_indexAddress, msg.sender, IndexAction.INITIALIZE);
    }

    /**
     * @notice Calculates the required deposit amount of one asset given a known amount of the other, using the index's current target weights and Chainlink prices.
     * @dev Uses the ratio: amountOut_USD = amountIn_USD * weightOut / weightIn, then converts the resulting USD value back to token units via the price feed.
     * @param _amount The known token amount, expressed in the asset's native token decimals.
     * @param _indexAddress  The address of the index whose weights and price feeds are used.
     * @param _zeroToOne Direction flag:
     *                   - true  → `_amount` is denominated in asset0; returns the proportional asset1 amount required.
     *                   - false → `_amount` is denominated in asset1; returns the proportional asset0 amount required.
     * @return amountToDeposit The required amount of the complementary asset, expressed in that asset's native token decimals.
     */
    function retrieveAmountFromAmount(
        uint256 _amount,
        address _indexAddress,
        bool _zeroToOne
    ) public view returns (uint256 amountToDeposit) {
        (uint128 weight0, uint128 weight1) = IIndex(_indexAddress)
            .getAssetsWeights();
        IndexAssets memory indexAssets = s_indexAssets[_indexAddress];
        uint256 asset0Price = IIndex(_indexAddress).getLatestPrice(
            indexAssets.asset0
        );
        uint256 asset1Price = IIndex(_indexAddress).getLatestPrice(
            indexAssets.asset1
        );
        if (_zeroToOne) {
            uint256 amount0InUsd = (_amount * asset0Price) /
                (10 ** IERC20Metadata(indexAssets.asset0).decimals());
            uint256 amount1InUsd = (amount0InUsd * weight1) / weight0;
            amountToDeposit =
                (amount1InUsd *
                    (10 ** IERC20Metadata(indexAssets.asset1).decimals())) /
                asset1Price;
        } else {
            uint256 amount1InUsd = (_amount * asset1Price) /
                (10 ** IERC20Metadata(indexAssets.asset1).decimals());
            uint256 amount0InUsd = (amount1InUsd * weight0) / weight1;
            amountToDeposit =
                (amount0InUsd *
                    (10 ** IERC20Metadata(indexAssets.asset0).decimals())) /
                asset0Price;
        }
    }

    /**
     * @notice Rebalances a single index.
     * @dev This function doesn't revert if rebalance fails but emit an event with the failure reason.
     * @param _indexAddress The address of the index to rebalance.
     */
    function rebalanceSingleIndex(
        address _indexAddress
    )
        public
        isIndexInitialized(_indexAddress)
        onlyRole(REBALANCER_ROLE)
    {
        (bool success, bytes memory reasonBytes) = _rebalanceSingleIndex(
            _indexAddress
        );
        if (!success) emit IndexRebalanceFailed(_indexAddress, reasonBytes);
    }

    /**
     * @notice Allows to rebalance multiple indexes in a single transaction, instead of having to call rebalanceIndex multiple times.
     * @notice Less Gas efficient than rebalanceAllIndexes, because check if is initialized for each index.
     * @dev If one of the call fails, the entire transaction will revert
     * @param _indexAddresses An array of index addresses to rebalance.
     */
    function rebalanceMultipleIndexes(
        address[] calldata _indexAddresses
    )
        public
        onlyRole(REBALANCER_ROLE)
        areIndexesInitialized(_indexAddresses)
    {
        uint256 length = _indexAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            (bool success, bytes memory reasonBytes) = _rebalanceSingleIndex(
                _indexAddresses[i]
            );
            if (!success)
                emit IndexRebalanceFailed(_indexAddresses[i], reasonBytes);
        }
    }

    /**
     * @notice Rebalances all initialized indexes.
     * @dev Less Gas efficient than rebalanceMultipleIndexes, because check if is initialized for each index.
     */
    function rebalanceAllIndexes()
        public
        onlyRole(REBALANCER_ROLE)
    {
        uint256 length = s_initializedIndexes.length;
        for (uint256 i = 0; i < length; i++) {
            address indexAddress = s_initializedIndexes[i];
            (bool success, bytes memory reasonBytes) = _rebalanceSingleIndex(
                indexAddress
            );
            if (!success) emit IndexRebalanceFailed(indexAddress, reasonBytes);
        }
    }

    /**
     * @notice Proposes new weights for the specified index.
     * @param _indexAddress The address of the index to propose new weights for.
     * @param _newWeightAsset0 The new weight for the first asset, with 4 decimals (e.g., 50000 = 5%).
     */
    function proposeNewWeights(
        address _indexAddress,
        uint128 _newWeightAsset0 // With 4 decimals, e.g. 50000 = 5%
    ) public isIndexInitialized(_indexAddress) onlyRole(ASSET_MANAGER_ROLE) {
        // The weight of asset1 is implicitly calculated by the index as 100% - weight of asset0.
        IIndex(_indexAddress).proposeUpdateWeights(_newWeightAsset0);
        emit IndexActionTriggered(_indexAddress, msg.sender, IndexAction.PROPOSE_WEIGHTS);
    }

    /**
     * @notice Executes the weight update for the specified index.
     * @param _indexAddress The address of the index to execute the weight update for.
     */
    function executeSingleWeightUpdate(
        address _indexAddress
    )
        public
        isIndexInitialized(_indexAddress)
        onlyRole(ASSET_MANAGER_ROLE)
    {
        (bool success, bytes memory reasonBytes) = _executeSingleWeightUpdate(
            _indexAddress
        );
        if (!success) emit WeightsUpdateFailed(_indexAddress, reasonBytes);
    }

    /**
     * @notice Cancels the pending weight update for the specified index.
     * @param _indexAddress The address of the index to cancel the weight update for.
     */
    function cancelWeightUpdate(
        address _indexAddress
    ) public isIndexInitialized(_indexAddress) onlyRole(ASSET_MANAGER_ROLE) {
        IIndex(_indexAddress).cancelWeightUpdate();
        emit IndexActionTriggered(_indexAddress, msg.sender, IndexAction.CANCEL_WEIGHTS);
    }

    /**
     * @notice Executes the weight update for multiple indexes.
     * @dev If one of the call fails, the entire transaction will not revert
     * @param _indexAddresses An array of index addresses to execute the weight update for.
     */
    function executeWeightUpdateForMultipleIndexes(
        address[] calldata _indexAddresses
    )
        public
        onlyRole(ASSET_MANAGER_ROLE)
        areIndexesInitialized(_indexAddresses)
    {
        uint256 length = _indexAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            (
                bool success,
                bytes memory reasonBytes
            ) = _executeSingleWeightUpdate(_indexAddresses[i]);
            if (!success)
                emit WeightsUpdateFailed(_indexAddresses[i], reasonBytes);
        }
    }

    /**
     * @notice Executes the weight update for all initialized indexes.
     * @dev If one of the call fails, the entire transaction will not revert
     */
    function executeWeightUpdateForAllIndexes()
        public
        onlyRole(ASSET_MANAGER_ROLE)
    {
        uint256 length = s_initializedIndexes.length;
        for (uint256 i = 0; i < length; i++) {
            (
                bool success,
                bytes memory reasonBytes
            ) = _executeSingleWeightUpdate(s_initializedIndexes[i]);
            if (!success)
                emit WeightsUpdateFailed(s_initializedIndexes[i], reasonBytes);
        }
    }

    /**
     * @dev Collects fees from the specified index and transfers them to the caller.
     * @param _indexAddress The address of the index from which to collect fees
     */
    function collectFeesFromSingleIndex(
        address _indexAddress
    ) public isIndexInitialized(_indexAddress) onlyRole(FEE_COLLECTOR_ROLE) {
        (
            uint256 feeAmount,
            bool success,
            bytes memory reasonBytes
        ) = _collectFeesFromSingleIndex(_indexAddress, msg.sender);
        if (success) {
            s_totalFeesCollected += feeAmount;
        } else {
            emit FeesCollectionFailed(_indexAddress, msg.sender, reasonBytes);
        }
    }

    /**
     * @notice Allows to collect fees from specific indexes in a single transaction, instead of having to call collectFees multiple times.
     * @notice Less Gas efficient than collectFeesFromAllIndexes, because check if is initialized for each index.
     * @dev If one of the call fails, the entire transaction will revert
     */
    function collectFeesFromMultipleIndexes(
        address[] calldata _indexAddresses
    )
        public
        onlyRole(FEE_COLLECTOR_ROLE)
        areIndexesInitialized(_indexAddresses)
    {
        uint256 length = _indexAddresses.length;
        uint256 totalFeesCollected = 0;
        for (uint256 i = 0; i < length; i++) {
            address indexAddress = _indexAddresses[i];
            (
                uint256 feeAmount,
                bool success,
                bytes memory reasonBytes
            ) = _collectFeesFromSingleIndex(indexAddress, msg.sender);
            if (success) {
                totalFeesCollected += feeAmount;
            } else {
                emit FeesCollectionFailed(
                    indexAddress,
                    msg.sender,
                    reasonBytes
                );
            }
        }
        s_totalFeesCollected += totalFeesCollected;
    }

    /**
     * @notice Collects fees from all initialized indexes and transfers them to the caller.
     * @dev If one of the call fails, the entire transaction will not revert
     */
    function collectFeesFromAllIndexes() public onlyRole(FEE_COLLECTOR_ROLE) {
        uint256 length = s_initializedIndexes.length;
        uint256 totalFeesCollected = 0;
        for (uint256 i = 0; i < length; i++) {
            address indexAddress = s_initializedIndexes[i];
            (
                uint256 feeAmount,
                bool success,
                bytes memory reasonBytes
            ) = _collectFeesFromSingleIndex(indexAddress, msg.sender);
            if (success) {
                totalFeesCollected += feeAmount;
            } else {
                emit FeesCollectionFailed(
                    indexAddress,
                    msg.sender,
                    reasonBytes
                );
            }
        }
        s_totalFeesCollected += totalFeesCollected;
    }

    /**
     * @dev Sorts two asset addresses to ensure consistent ordering.
     * @dev Used to maintain a consistent order of assets in the indexes
     * @param _assetAddressB The address of the second asset
     * @return token0 The address of the first asset in sorted order
     * @return token1 The address of the second asset in sorted order
     */
    function sortAssets(
        address _assetAddressA,
        address _assetAddressB
    ) public pure returns (address token0, address token1) {
        if (_assetAddressA < _assetAddressB) {
            return (_assetAddressA, _assetAddressB);
        } else {
            return (_assetAddressB, _assetAddressA);
        }
    }

    /**
     * @dev Checks if an index is initialized and reverts if it is not
     * @param _indexAddress Address of the index to check
     */
    function _isIndexInitialized(address _indexAddress) internal view {
        if (!s_isInitialized[_indexAddress]) {
            revert IndexManager__NotIndexInitialized(_indexAddress);
        }
    }

    /**
     * @dev Checks if multiple indexes are initialized and reverts if any of them are not
     * @param _indexAddresses Addresses of the indexes to check
     */
    function _areIndexesInitialized(
        address[] calldata _indexAddresses
    ) internal view {
        uint256 length = _indexAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            if (!s_isInitialized[_indexAddresses[i]]) {
                revert IndexManager__NotIndexInitialized(_indexAddresses[i]);
            }
        }
    }

    /**
     * @notice Checks that an asset has a price feed registered in the PriceFeedManager.
     * @dev Reverts with IndexManager__PriceFeedNotRegistered otherwise.
     * @param _asset The asset to check.
     */
    function _checkPriceFeedRegistered(address _asset) internal view {
        if (!IPriceFeedManager(i_priceFeedManager).hasPriceFeed(_asset)) {
            revert IndexManager__PriceFeedNotRegistered(_asset);
        }
    }

    /**
     * @dev Deploys a new index contract with the specified assets, fee percentage, and USDC address.
     * @param _asset0 The first asset of the index.
     * @param _asset1 The second asset of the index.
     * @param _feePercentage The fee percentage for the index.
     * @return index The address of the newly deployed index contract.
     */
    function _deployIndex(
        IndexAsset memory _asset0,
        IndexAsset memory _asset1,
        uint32 _feePercentage
    ) internal returns (address index) {
        // Prepare constructor data for the Index deployment.
        string memory name;
        string memory symbol;
        {
            string memory symbol0 = IERC20Metadata(_asset0.asset).symbol();
            string memory symbol1 = IERC20Metadata(_asset1.asset).symbol();
            name = string(abi.encodePacked("Index ", symbol0, "/", symbol1));
            symbol = string(abi.encodePacked("IDX", symbol0, symbol1));
        }

        bytes memory bytecode = abi.encodePacked(
            type(Index).creationCode,
            abi.encode(
                name,
                symbol,
                i_router,
                i_usdc,
                i_priceFeedManager,
                i_swapManager,
                i_uniswapUniversalRouter,
                _asset0,
                _asset1,
                _feePercentage
            )
        );
        bytes32 salt = keccak256(
            abi.encodePacked(_asset0.asset, _asset1.asset)
        );
        assembly {
            index := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        if (index == address(0)) {
            revert IndexManager__IndexDeployFailed();
        }
    }

    /**
     * @dev Validates if an address is a valid ERC20 token usable by an index.
     *      Reverts with `IndexManager__InvalidIndexAssetsAddress` if the asset is address(0) or
     *      `symbol()` is missing/reverts, and with `IndexManager__InvalidAssetDecimals` if
     *      `decimals()` is missing/reverts or returns a value above DECIMALS_STANDARD.
     * @param _asset Address to validate
     */
    function _validateAssetIsERC20(address _asset) internal view {
        if (_asset == address(0)) {
            revert IndexManager__InvalidIndexAssetsAddress();
        }

        // Check if contract has symbol() function (ERC20 standard)
        (bool success, bytes memory result) = _asset.staticcall(
            abi.encodeWithSignature("symbol()")
        );
        if (!(success && result.length > 0)) {
            revert IndexManager__InvalidIndexAssetsAddress();
        }

        // Check that decimals() exists and does not exceed DECIMALS_STANDARD,
        // otherwise decimal conversions in the Index would revert or truncate to 0.
        (success, result) = _asset.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        if (
            !success ||
            result.length < 32 ||
            abi.decode(result, (uint256)) > DECIMALS_STANDARD
        ) {
            revert IndexManager__InvalidAssetDecimals(_asset);
        }
    }

    /**
     * @notice This function is used internally by rebalanceMultipleIndexes and rebalanceAllIndexes to handle rebalance for each index, allowing for error handling
     * on a per-index basis without reverting the entire transaction if one index fails to transfer fees.
     * @dev Rebalances a single index and returns whether it was successful and the reason if it failed.
     * @dev Emits IndexActionTriggered (REBALANCE) on success.
     * @param _indexAddress The address of the index to rebalance.
     * @return success A boolean indicating whether the rebalance was successful.
     * @return reasonBytes Raw revert data of the rebalance call, unchanged (may be empty); empty on success.
     */
    function _rebalanceSingleIndex(
        address _indexAddress
    ) internal returns (bool success, bytes memory reasonBytes) {
        try IIndex(_indexAddress).rebalanceIndex() {
            emit IndexActionTriggered(_indexAddress, msg.sender, IndexAction.REBALANCE);
            return (true, "");
        } catch (bytes memory reason) {
            return (false, reason);
        }
    }

    /**
     * @notice Collects fees from a single index and transfers them to the specified fee collector address.
     * @notice This function is used internally by collectFeesFromMultipleIndexes and collectFeesFromAllIndexes to handle fee collection for each index, allowing for error handling on a per-index basis without reverting the entire transaction if one index fails to transfer fees.
     * @param _indexAddress The address of the index from which to collect fees.
     * @dev Emits IndexActionTriggered (COLLECT_FEES) on success, with `_feeCollector` (always msg.sender) as caller.
     * @param _feeCollector The address to which the collected fees should be transferred.
     * @return feeAmount The amount of fees collected from the index.
     * @return success A boolean indicating whether the fee collection and transfer were successful.
     * @return reasonBytes Raw revert data of the collectFees call, unchanged (may be empty); empty on success.
     */
    // @audit-info : document the try/catch and revert pattern later
    function _collectFeesFromSingleIndex(
        address _indexAddress,
        address _feeCollector
    )
        internal
        returns (uint256 feeAmount, bool success, bytes memory reasonBytes)
    {
        IIndex index = IIndex(_indexAddress);
        try index.collectFees(_feeCollector) returns (uint256 collectedFees) {
            feeAmount = collectedFees;
            success = true;
            emit IndexActionTriggered(_indexAddress, _feeCollector, IndexAction.COLLECT_FEES);
            reasonBytes = "";
        } catch (bytes memory reason) {
            feeAmount = 0;
            success = false;
            reasonBytes = reason;
        }
    }

    /**
     * @dev Executes the weight update for a single index and returns whether it was successful and the reason if it failed.
     * @dev Emits IndexActionTriggered (EXECUTE_WEIGHTS) on success.
     * @param _indexAddress The address of the index to execute the weight update for.
     * @return success A boolean indicating whether the weight update was successful.
     * @return reasonBytes Raw revert data of the executeWeightUpdate call, unchanged (may be empty); empty on success.
     * @notice This function uses try-catch to handle potential errors during the execution of the weight update. If an error occurs, it returns the raw revert data along with a success flag set to false. If the call succeeds, it returns true with an empty reason.
     * @notice This approach allows the contract to attempt weight updates on multiple indexes without reverting the entire transaction if one of them fails, while still providing feedback on which updates were successful and which were not.
     */
    function _executeSingleWeightUpdate(
        address _indexAddress
    ) internal returns (bool success, bytes memory reasonBytes) {
        IIndex index = IIndex(_indexAddress);
        try index.executeWeightUpdate() {
            success = true;
            emit IndexActionTriggered(_indexAddress, msg.sender, IndexAction.EXECUTE_WEIGHTS);
            reasonBytes = "";
        } catch (bytes memory reason) {
            reasonBytes = reason;
            success = false;
        }
    }

    // =========================================================================
    //  Getters
    // =========================================================================

    /**
     * @dev Checks if an address is a valid index contract
     * @param indexAddress Address to check
     * @return bool True if the address is a valid index, false otherwise
     */
    function isIndexAddress(address indexAddress) public view returns (bool) {
        return s_isIndex[indexAddress];
    }

    /**
     * @dev Checks if an index is initialized
     * @param indexAddress Address of the index to check
     * @return bool True if the index is initialized, false otherwise
     */
    function checkIsIndexInitialized(
        address indexAddress
    ) public view returns (bool) {
        return s_isInitialized[indexAddress];
    }

    /**
     * @dev Returns both underlying assets for an index.
     * @param _indexAddress Address of the index.
     * @return asset0 Address of index asset0.
     * @return asset1 Address of index asset1.
     */
    function getIndexAssets(
        address _indexAddress
    ) public view returns (address asset0, address asset1) {
        IndexAssets memory indexAssets = s_indexAssets[_indexAddress];
        return (indexAssets.asset0, indexAssets.asset1);
    }

    /**
     * @dev Returns the index address for a given pair of underlying assets, or address(0) if no index exists for that pair
     * The function sorts the asset addresses to ensure consistent ordering, so the caller can provide them in any order.
     * It then looks up the index address in the getIndex mapping using the sorted asset addresses as keys.
     * If an index exists for that pair of assets, its address is returned; otherwise, address(0) is returned to indicate
     * that no index exists for that asset pair.
     * @param _assetAddressA The address of the first underlying asset
     * @param _assetAddressB The address of the second underlying asset
     * @return index The address of the index contract for the given pair of underlying assets, or address(0) if no index exists for that pair
     */
    function getIndexByAssetsAddresses(
        address _assetAddressA,
        address _assetAddressB
    ) public view returns (address index) {
        (address asset0, address asset1) = sortAssets(
            _assetAddressA,
            _assetAddressB
        );
        index = s_getIndex[asset0][asset1];
    }

    /// @dev Inherit from IIndexManager. See interface for details.
    function getRouterAddress() public view returns (address) {
        return i_router;
    }

    /**
     * @notice Returns the address of the swap manager used by the index manager.
     * @return The swap manager address.
     */
    function getSwapManagerAddress() public view returns (address) {
        return i_swapManager;
    }

    /// @dev Inherit from IIndexManager. See interface for details.
    function getPriceFeedManagerAddress() public view returns (address) {
        return i_priceFeedManager;
    }

    /**
     * @dev Returns all index addresses managed by the index manager
     * @return address[] An array of all index addresses
     */
    function getDeployedIndexes() public view returns (address[] memory) {
        return s_deployedIndexes;
    }

    /**
     * @dev Returns all initialized index addresses.
     * @return address[] An array of initialized index addresses.
     */
    function getInitializedIndexes() public view returns (address[] memory) {
        return s_initializedIndexes;
    }

    /**
     * @dev Returns the total fees collected by the index manager
     * @return uint256 The total fees collected
     */
    function getTotalFeesCollected() public view returns (uint256) {
        return s_totalFeesCollected;
    }

    /**
     * @dev Returns the address of the USDC token used by the index manager
     * @return address The address of the USDC token
     */
    function getUsdc() public view returns (address) {
        return i_usdc;
    }

    /**
     * @dev Returns the address of the USDC Chainlink price feed registered in the PriceFeedManager
     * @return address The address of the USDC Chainlink price feed (address(0) if not registered)
     */
    function getUsdcPriceFeed() public view returns (address) {
        return IPriceFeedManager(i_priceFeedManager).getPriceFeedConfig(i_usdc).feed;
    }

    /**
     * @dev Returns the address of the Uniswap Universal Router used by the index manager
     * @return address The address of the Uniswap Universal Router
     */
    function getUniswapUniversalRouter() public view returns (address) {
        return i_uniswapUniversalRouter;
    }
}