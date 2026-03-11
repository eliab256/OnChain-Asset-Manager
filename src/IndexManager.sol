// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Index} from "./Index.sol";
import {IIndexManager} from "./Interface/IIndexManager.sol";
import {ISwapManager} from "./Interface/ISwapManager.sol";
import "./errors/IndexManagerErrors.sol";
import "./events/IndexManagerEvents.sol";
import {IndexAsset, PoolKey} from "./types.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IIndex} from "./Interface/IIndex.sol";

contract IndexManager is IIndexManager, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ASSET_MANAGER_ROLE =
        keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant FEE_COLLECTOR_ROLE =
        keccak256("FEE_COLLECTOR_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    uint128 public constant MAX_PERCENTAGE = 1000000; // 100% with 4 decimals

    IERC20 internal immutable i_usdc;
    address internal immutable i_usdcPriceFeed;
    address internal immutable i_uniswapUniversalRouter;

    address[] private s_indexes;
    address[] private s_initializedIndexes;
    mapping(address => mapping(address => address)) private s_getIndex;
    mapping(address => bool) private s_isIndex;
    mapping(address => bool) private s_isInitialized;

    address internal s_router;
    address internal s_swapManager;
    uint256 private s_totalFeesCollected;

    modifier isIndexInitialized(address indexAddress) {
        _isIndexInitialized(indexAddress);
        _;
    }

    modifier areIndexesInitialized(address[] calldata indexAddresses) {
        _areIndexesInitialized(indexAddresses);
        _;
    }

    constructor(
        address _usdcAddress,
        address _usdcPriceFeed,
        address _uniswapUniversalRouter
    ) {
        i_usdc = IERC20(_usdcAddress);
        i_usdcPriceFeed = _usdcPriceFeed;
        i_uniswapUniversalRouter = _uniswapUniversalRouter;

        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(ASSET_MANAGER_ROLE, msg.sender);
        grantRole(FEE_COLLECTOR_ROLE, msg.sender);
        grantRole(REBALANCER_ROLE, msg.sender);
    }

    /**
     * @notice Sets the address of the router contract.
     * @param _newRouter The address of the new router contract.
     */
    function setRouterAddress(
        address _newRouter
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        s_router = _newRouter;

        emit RouterAddressSet(_newRouter, msg.sender);
    }

    function setSwapManagerAddress(
        address _swapManager
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        s_swapManager = _swapManager;

        emit SwapManagerAddressSet(_swapManager, msg.sender);
    }

    /**
     * @dev Creates a new index with the specified fee percentage and underlying assets.
     * @notice The caller must have the ASSET_MANAGER_ROLE to call this function.
     * @notice All percentages are expressed with 4 decimals, so 100% = 1000000, 1% = 10000, etc.
     * @param _feePercentage The fee percentage for the index.
     * @param _assetA The first underlying asset of the index. The struct includes the asset address, its weight percentage in the index, and its Chainlink price feed address.
     * @param _assetB The second underlying asset of the index. The struct includes the asset address, its weight percentage in the index, and its Chainlink price feed address.
     */
    function createIndex(
        uint256 _feePercentage,
        IndexAsset memory _assetA,
        IndexAsset memory _assetB
    )
        public
        onlyRole(ASSET_MANAGER_ROLE)
        returns (address index, address token0, address token1)
    {
        if (s_router == address(0)) {
            revert IndexManager__RouterAddressNotSet();
        }
        if (_assetA.asset == _assetB.asset) {
            revert IndexManager__InvalidIndexAssetsAddress();
        }

        (address tokenAsset0, ) = sortAssets(_assetA.asset, _assetB.asset);

        IndexAsset memory asset0;
        IndexAsset memory asset1;

        if (tokenAsset0 == _assetA.asset) {
            asset0 = _assetA;
            asset1 = _assetB;
        } else {
            asset0 = _assetB;
            asset1 = _assetA;
        }

        // CHECK INDEX IS NOT ALREADY CREATED
        if (s_getIndex[asset0.asset][asset1.asset] != address(0)) {
            revert IndexManager__IndexAlreadyExists(
                s_getIndex[asset0.asset][asset1.asset]
            );
        }

        // CHECK WEIGHT PERCENTAGES SUM TO 100
        if (
            asset0.weightPercentage + asset1.weightPercentage != MAX_PERCENTAGE
        ) {
            revert IndexManager__InvalidIndexAssetsPercentages();
        }

        // CHECK UNDERLYIN ASSETS ARE ERC20
        _validateAssetIsERC20(asset0.asset);
        _validateAssetIsERC20(asset1.asset);

        // CHECK UNDERLYIN ASSETS HAVE PRICEFEED CHAINLINK
        _validatePriceFeed(asset0.priceFeed);
        _validatePriceFeed(asset1.priceFeed);

        index = _deployIndex(asset0, asset1, _feePercentage);

        s_getIndex[asset0.asset][asset1.asset] = index;
        s_isIndex[index] = true;
        s_indexes.push(index);

        emit IndexCreated(index, asset0.asset, asset1.asset, msg.sender);
        return (index, asset0.asset, asset1.asset);
    }

    /**
     * @notice Initializes the specified index with the given underlying amount.
     * @param _indexAddress The address of the index to initialize.
     * @param _underlyingAmount0 The amount of the first underlying asset to initialize the index with.
     */
    function initializeIndex(
        address _indexAddress,
        uint256 _underlyingAmount0,
        PoolKey memory _poolKeyAsset0Usdc,
        PoolKey memory _poolKeyAsset1Usdc,
        PoolKey memory _poolKeyAsset0Asset1
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

        ISwapManager(s_swapManager).registerIndex(
            _indexAddress,
            _poolKeyAsset0Usdc,
            _poolKeyAsset1Usdc,
            _poolKeyAsset0Asset1
        );

        IIndex(_indexAddress).initialize(_underlyingAmount0);

        emit IndexInitialized(_indexAddress, msg.sender);
    }

    function rebalanceIndex(
        address _indexAddress
    ) public isIndexInitialized(_indexAddress) onlyRole(REBALANCER_ROLE) {
        (bool success, string memory reason) = _rebalanceSingleIndex(
            _indexAddress
        );
        if (!success) {
            emit IndexRebalanceFailed(_indexAddress, reason);
        } else {
            emit IndexRebalanced(_indexAddress, msg.sender);
        }
    }

    /**
     * @notice Allows to rebalance multiple indexes in a single transaction, instead of having to call rebalanceIndex multiple times.
     * @notice Less Gas efficient than rebalanceAllIndexes, because check if is initialized for each index.
     * @dev If one of the call fails, the entire transaction will revert
     * @param _indexAddresses An array of index addresses to rebalance.
     */
    function rebalanceMultipleIndexes(
        address[] calldata _indexAddresses
    ) public onlyRole(REBALANCER_ROLE) areIndexesInitialized(_indexAddresses) {
        uint256 length = _indexAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            (bool success, string memory reason) = _rebalanceSingleIndex(
                _indexAddresses[i]
            );
            if (!success) {
                emit IndexRebalanceFailed(_indexAddresses[i], reason);
            } else {
                emit IndexRebalanced(_indexAddresses[i], msg.sender);
            }
        }
    }

    /**
     * @notice Rebalances all initialized indexes.
     * @dev Less Gas efficient than rebalanceMultipleIndexes, because check if is initialized for each index.
     */
    function rebalanceAllIndexes() public onlyRole(REBALANCER_ROLE) {
        uint256 length = s_initializedIndexes.length;
        for (uint256 i = 0; i < length; i++) {
            address indexAddress = s_initializedIndexes[i];
            (bool success, string memory reason) = _rebalanceSingleIndex(
                indexAddress
            );
            if (!success) {
                emit IndexRebalanceFailed(indexAddress, reason);
            } else {
                emit IndexRebalanced(indexAddress, msg.sender);
            }
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
        if (_newWeightAsset0 > MAX_PERCENTAGE) {
            revert IndexManager__InvalidPercentage();
        }
        // weight of asset1 is implicitly calculated as 100% - weight of asset0
        IIndex index = IIndex(_indexAddress);
        (uint128 oldWeightAsset0, uint128 oldWeightAsset1) = index
            .getAssetsWeights();
        uint128 newWeightAsset1 = MAX_PERCENTAGE - _newWeightAsset0;

        uint256 implementationTimestamp = index.proposeUpdateWeights(
            _newWeightAsset0
        );

        emit NewIndexWeightsProposed(
            _indexAddress,
            msg.sender,
            oldWeightAsset0,
            oldWeightAsset1,
            _newWeightAsset0,
            newWeightAsset1,
            implementationTimestamp
        );
    }

    /**
     * @notice Executes the weight update for the specified index.
     * @param _indexAddress The address of the index to execute the weight update for.
     */
    function executeWeightUpdate(
        address _indexAddress
    ) public isIndexInitialized(_indexAddress) onlyRole(ASSET_MANAGER_ROLE) {
        (bool success, string memory reason) = _executeSingleWeightUpdate(
            _indexAddress
        );
        if (!success) {
            emit WeightUpdateFailed(_indexAddress, reason);
        } else {
            emit WeightUpdateExecuted(_indexAddress);
        }
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
            _executeSingleWeightUpdate(_indexAddresses[i]);
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
            (bool success, string memory reason) = _executeSingleWeightUpdate(
                s_initializedIndexes[i]
            );
            if (!success) {
                emit WeightUpdateFailed(s_initializedIndexes[i], reason);
            } else {
                emit WeightUpdateExecuted(s_initializedIndexes[i]);
            }
        }
    }

    /**
     * @dev Collects fees from the specified index and transfers them to the caller.
     * @param _indexAddress The address of the index from which to collect fees
     */
    function collectFees(
        address _indexAddress
    ) public isIndexInitialized(_indexAddress) onlyRole(FEE_COLLECTOR_ROLE) {
        (
            uint256 feeAmount,
            bool success,
            string memory reason
        ) = _collectFeesFroSingleIndex(_indexAddress, msg.sender);
        if (success) {
            s_totalFeesCollected += feeAmount;
            emit FeesCollected(_indexAddress, msg.sender, feeAmount);
        } else {
            emit FeesCollectionFailed(_indexAddress, msg.sender, reason);
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
                string memory reason
            ) = _collectFeesFroSingleIndex(indexAddress, msg.sender);
            if (success) {
                totalFeesCollected += feeAmount;
                emit FeesCollected(indexAddress, msg.sender, feeAmount);
            } else {
                emit FeesCollectionFailed(indexAddress, msg.sender, reason);
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
                string memory reason
            ) = _collectFeesFroSingleIndex(indexAddress, msg.sender);
            if (success) {
                totalFeesCollected += feeAmount;
                emit FeesCollected(indexAddress, msg.sender, feeAmount);
            } else {
                emit FeesCollectionFailed(indexAddress, msg.sender, reason);
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
     * @dev Checks if an index is initialized and reverts if it is not
     * @param indexAddress Address of the index to check
     */
    function _isIndexInitialized(address indexAddress) internal view {
        if (!s_isInitialized[indexAddress]) {
            revert IndexManager__NotIndexInitialized();
        }
    }

    /**
     * @dev Checks if multiple indexes are initialized and reverts if any of them are not
     * @param indexAddresses Addresses of the indexes to check
     */
    function _areIndexesInitialized(
        address[] calldata indexAddresses
    ) internal view {
        uint256 length = indexAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            if (!s_isInitialized[indexAddresses[i]]) {
                revert IndexManager__NotIndexInitialized();
            }
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
        uint256 _feePercentage
    ) internal returns (address index) {
        // prepare data for Index constructor
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
                s_router,
                address(i_usdc),
                i_usdcPriceFeed,
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
    }

    /**
     * @dev Validates if an address is a valid ERC20 token
     * @param _asset Address to validate
     */
    function _validateAssetIsERC20(address _asset) internal view {
        if (_asset == address(0)) {
            revert IndexManager__InvalidIndexAssetsAddress();
        }

        // Check if contract has decimals() function (ERC20 standard)
        (bool success, bytes memory result) = _asset.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        if (!(success && result.length > 0)) {
            revert IndexManager__InvalidIndexAssetsAddress();
        }
    }

    /**
     * @dev Validates if an address is a valid Chainlink Price Feed
     * @param _priceFeed Address to validate
     */
    function _validatePriceFeed(address _priceFeed) internal view {
        if (_priceFeed == address(0)) {
            revert IndexManager__InvalidPriceFeedAddress();
        }

        // Check if contract has latestRoundData() function (Chainlink standard)
        (bool success, bytes memory result) = _priceFeed.staticcall(
            abi.encodeWithSignature("latestRoundData()")
        );
        if (!(success && result.length > 0)) {
            revert IndexManager__InvalidPriceFeedAddress();
        }
    }

    /**
     * @notice This function is used internally by rebalanceMultipleIndexes and rebalanceAllIndexes to handle rebalance for each index, allowing for error handling
     * on a per-index basis without reverting the entire transaction if one index fails to transfer fees.
     * @dev Rebalances a single index and returns whether it was successful and the reason if it failed.
     * @param _indexAddress The address of the index to rebalance.
     * @return success A boolean indicating whether the rebalance was successful.
     * @return reason A string containing the reason for failure if the rebalance was not successful, or "Unknown error" if the reason could not be determined.
     */
    function _rebalanceSingleIndex(
        address _indexAddress
    ) internal returns (bool success, string memory reason) {
        try IIndex(_indexAddress).rebalanceIndex() {
            return (true, "");
        } catch Error(string memory _reason) {
            return (false, _reason);
        } catch {
            return (false, "Unknown error");
        }
    }

    /**
     * @notice Collects fees from a single index and transfers them to the specified fee collector address.
     * @notice This function is used internally by collectFeesFromMultipleIndexes and collectFeesFromAllIndexes to handle fee collection for each index, allowing for error handling on a per-index basis without reverting the entire transaction if one index fails to transfer fees.
     * @param _indexAddress The address of the index from which to collect fees.
     * @param _feeCollector The address to which the collected fees should be transferred.
     * @return feeAmount The amount of fees collected from the index.
     * @return success A boolean indicating whether the fee collection and transfer were successful.
     * @return reason A string containing the reason for failure if the fee collection or transfer was not successful, or "Unknown error" if the reason could not be determined.
     */
    // @audit-info fare post linkedin su trycatch e revert
    function _collectFeesFroSingleIndex(
        address _indexAddress,
        address _feeCollector
    ) internal returns (uint256 feeAmount, bool success, string memory reason) {
        IIndex index = IIndex(_indexAddress);
        try index.collectFees(_feeCollector) returns (uint256 collectedFees) {
            feeAmount = collectedFees;
            success = true;
            reason = "";
        } catch Error(string memory _reason) {
            feeAmount = 0;
            success = false;
            reason = _reason;
        } catch {
            feeAmount = 0;
            success = false;
            reason = "Unknown error";
        }
    }

    /**
     * @dev Executes the weight update for a single index and returns whether it was successful and the reason if it failed.
     * @param _indexAddress The address of the index to execute the weight update for.
     * @return success A boolean indicating whether the weight update was successful.
     * @return reason A string containing the reason for failure if the weight update was not successful, or "Unknown error" if the reason could not be determined.
     * @notice This function uses try-catch to handle potential errors during the execution of the weight update. If an error occurs, it captures the error message and returns it along with a success flag set to false. If the call succeeds, it returns true with an empty reason.
     * @notice This approach allows the contract to attempt weight updates on multiple indexes without reverting the entire transaction if one of them fails, while still providing feedback on which updates were successful and which were not.
     */
    function _executeSingleWeightUpdate(
        address _indexAddress
    ) internal returns (bool success, string memory reason) {
        IIndex index = IIndex(_indexAddress);
        try index.executeWeightUpdate() {
            success = true;
        } catch Error(string memory _reason) {
            reason = _reason;
            success = false;
        } catch {
            reason = "Unknown error";
            success = false;
        }
    }

    /**
     * @dev Returns the address of the USDC token used by the index manager
     * @return address The address of the USDC token
     */
    function getUsdcAddress() public view returns (address) {
        return address(i_usdc);
    }

    /**
     * @dev Returns the address of the router used by the index manager
     * @return address The address of the router
     */
    function getRouterAddress() public view returns (address) {
        return s_router;
    }

    function getSwapManagerAddress() public view returns (address) {
        return s_swapManager;
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

    /**
     * @dev Returns all index addresses managed by the index manager
     * @return address[] An array of all index addresses
     */
    function getAllIndexes() public view returns (address[] memory) {
        return s_indexes;
    }

    /**
     * @dev Returns the total fees collected by the index manager
     * @return uint256 The total fees collected
     */
    function getTotalFeesCollected() public view returns (uint256) {
        return s_totalFeesCollected;
    }
}
