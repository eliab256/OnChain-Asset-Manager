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
    // Router ERC1967 proxy, deployed in the constructor. Every index stores this address as its router.
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
            (address tokenAsset0, ) = _sortAssets(_assetA.asset, _assetB.asset);
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

        // 4. Check that the underlying assets and USDC have a price feed registered in the PriceFeedManager.
        //    ERC20 metadata (symbol, decimals <= 18) is validated by the PriceFeedManager at feed registration.
        _checkPriceFeedRegistered(asset0.asset);
        _checkPriceFeedRegistered(asset1.asset);
        _checkPriceFeedRegistered(i_usdc);

        // 5. Deploy the index contract
        index = _deployIndex(asset0, asset1, _feePercentage);

        // 6. Store its address in the mappings and arrays.
        s_getIndex[asset0.asset][asset1.asset] = index;
        s_indexAssets[index] = IndexAssets({
            asset0: asset0.asset,
            asset1: asset1.asset
        });
        s_isIndex[index] = true;
        s_deployedIndexes.push(index);

        // 7. Emit event with the index address, its assets, weights and fee.
        emit IndexCreated(
            index,
            asset0.asset,
            asset1.asset,
            asset0.weightPercentage,
            asset1.weightPercentage,
            _feePercentage,
            msg.sender
        );

        // 8. Return the index address and its assets addresses.
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

    /// @dev Inherit from IIndexManager. See interface for details.
    function rebalanceSingleIndex(
        address _indexAddress
    )
        public
        isIndexInitialized(_indexAddress)
        onlyRole(REBALANCER_ROLE)
    {
        _tryIndexAction(_indexAddress, IndexAction.REBALANCE);
    }

    /// @dev Inherit from IIndexManager. See interface for details.
    function rebalanceMultipleIndexes(
        address[] calldata _indexAddresses
    )
        public
        onlyRole(REBALANCER_ROLE)
        areIndexesInitialized(_indexAddresses)
    {
        _tryIndexActions(_indexAddresses, IndexAction.REBALANCE);
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

    /// @dev Inherit from IIndexManager. See interface for details.
    function executeSingleWeightUpdate(
        address _indexAddress
    )
        public
        isIndexInitialized(_indexAddress)
        onlyRole(ASSET_MANAGER_ROLE)
    {
        _tryIndexAction(_indexAddress, IndexAction.EXECUTE_WEIGHTS);
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

    /// @dev Inherit from IIndexManager. See interface for details.
    function executeWeightUpdateForMultipleIndexes(
        address[] calldata _indexAddresses
    )
        public
        onlyRole(ASSET_MANAGER_ROLE)
        areIndexesInitialized(_indexAddresses)
    {
        _tryIndexActions(_indexAddresses, IndexAction.EXECUTE_WEIGHTS);
    }

    /// @dev Inherit from IIndexManager. See interface for details.
    function collectFeesFromSingleIndex(
        address _indexAddress
    ) public isIndexInitialized(_indexAddress) onlyRole(FEE_COLLECTOR_ROLE) {
        s_totalFeesCollected += _tryIndexAction(
            _indexAddress,
            IndexAction.COLLECT_FEES
        );
    }

    /// @dev Inherit from IIndexManager. See interface for details.
    function collectFeesFromMultipleIndexes(
        address[] calldata _indexAddresses
    )
        public
        onlyRole(FEE_COLLECTOR_ROLE)
        areIndexesInitialized(_indexAddresses)
    {
        s_totalFeesCollected += _tryIndexActions(
            _indexAddresses,
            IndexAction.COLLECT_FEES
        );
    }

    /**
     * @notice Sorts two asset addresses in ascending order.
     * @dev Used to keep a consistent asset0/asset1 order in the indexes and in the s_getIndex mapping.
     * @param _assetAddressA The address of the first asset.
     * @param _assetAddressB The address of the second asset.
     * @return The lower of the two addresses (asset0).
     * @return The higher of the two addresses (asset1).
     */
    function _sortAssets(
        address _assetAddressA,
        address _assetAddressB
    ) internal pure returns (address, address) {
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
     * @notice Triggers a rebalance, a weights update execution or a fee collection on an index without reverting on failure.
     * @dev Low-level call to the index with the calldata selected by `_action`: rebalanceIndex(), executeWeightUpdate()
     *      or collectFees(msg.sender) (fees are always sent to the caller of the IndexManager).
     *      The target is always a registered and initialized index, so it has code.
     *      On success emits IndexActionTriggered(_index, msg.sender, _action); on failure emits
     *      IndexActionFailed(_index, msg.sender, _action, reason) with the raw revert data and returns 0.
     *      Only REBALANCE, EXECUTE_WEIGHTS and COLLECT_FEES are passed by the callers.
     * @param _index The address of the index to act on.
     * @param _action The action to trigger (REBALANCE, EXECUTE_WEIGHTS or COLLECT_FEES).
     * @return feeAmount The fees collected, in USDC units (6 decimals); 0 for other actions or on failure.
     */
    function _tryIndexAction(
        address _index,
        IndexAction _action
    ) internal returns (uint256 feeAmount) {
        bytes memory callData;
        if (_action == IndexAction.REBALANCE) {
            callData = abi.encodeCall(IIndex.rebalanceIndex, ());
        } else if (_action == IndexAction.EXECUTE_WEIGHTS) {
            callData = abi.encodeCall(IIndex.executeWeightUpdate, ());
        } else {
            callData = abi.encodeCall(IIndex.collectFees, (msg.sender));
        }

        (bool success, bytes memory result) = _index.call(callData);
        if (!success) {
            emit IndexActionFailed(_index, msg.sender, _action, result);
            return 0;
        }
        if (_action == IndexAction.COLLECT_FEES) {
            feeAmount = abi.decode(result, (uint256));
        }
        emit IndexActionTriggered(_index, msg.sender, _action);
    }

    /**
     * @notice Triggers the same action on several indexes, continuing past the ones that fail.
     * @dev Calls _tryIndexAction for each index; the caller has already checked that all of them are initialized.
     * @param _indexes The addresses of the indexes to act on.
     * @param _action The action to trigger (REBALANCE, EXECUTE_WEIGHTS or COLLECT_FEES).
     * @return totalFees The sum of the fees collected, in USDC units (6 decimals); 0 for other actions.
     */
    function _tryIndexActions(
        address[] calldata _indexes,
        IndexAction _action
    ) internal returns (uint256 totalFees) {
        uint256 length = _indexes.length;
        for (uint256 i = 0; i < length; i++) {
            totalFees += _tryIndexAction(_indexes[i], _action);
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
        (address asset0, address asset1) = _sortAssets(
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
     * @dev Returns the address of the Uniswap Universal Router used by the index manager
     * @return address The address of the Uniswap Universal Router
     */
    function getUniswapUniversalRouter() public view returns (address) {
        return i_uniswapUniversalRouter;
    }
}