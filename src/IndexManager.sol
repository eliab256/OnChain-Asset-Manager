// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Index} from "./Index.sol";
import {IIndexManager} from "./Interface/IIndexManager.sol";
import {IndexAsset} from "./types.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IIndex} from "./Interface/IIndex.sol";

contract IndexManager is AccessControl {
    using SafeERC20 for IERC20;

    event IndexCreated(
        address indexed indexAddress,
        address indexed asset0,
        address indexed asset1,
        address assetManager
    );

    event IndexInitialized(
        address indexed indexAddress,
        address indexed assetManager
    );
    event IndexRebalanced(
        address indexed indexAddress,
        address indexed rebalancer
    );
    event IndexWeightsChanged(
        address indexed indexAddress,
        address indexed assetManager,
        uint112 oldWeightAsset0,
        uint112 oldWeightAsset1,
        uint112 newWeightAsset0,
        uint112 newWeightAsset1,
        uint256 implementationTimestamp
    );
    event FeesCollected(
        address indexed indexAddress,
        address indexed feeCollector,
        uint256 feeAmount
    );

    error IndexManager__InvalidIndexAssetsAddress();
    error IndexManager__InvalidIndexAssetsAmount();
    error IndexManager__InvalidIndexAssetsPercentages();
    error IndexManager__UnderlyingAssetNotERC20();
    error IndexManager__PriceFeedNotAvailable(address priceFeed);
    error IndexManager__IndexAlreadyExists(address index);
    error IndexManager__IsNotIndex();
    error IndexManager__IndexAlreadyInitialized();
    error IndexManager__InvalidPriceFeedAddress();
    error IndexManager__NotIndexInitialized();
    error IndexManager__InvalidPercentage();

    bytes32 public constant ASSET_MANAGER_ROLE =
        keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant FEE_COLLECTOR_ROLE =
        keccak256("FEE_COLLECTOR_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    uint112 public constant MAX_PERCENTAGE = 1000000; // 100% with 4 decimals

    address[] private indexes;
    mapping(address => mapping(address => address)) private getIndex;
    mapping(address => bool) private isIndex;
    mapping(address => bool) private isInitialized;

    IERC20 internal immutable i_usdc;
    address internal immutable i_router;

    modifier isIndexInitialized(address indexAddress) {
        if (!isInitialized[indexAddress]) {
            revert IndexManager__NotIndexInitialized();
        }
        _;
    }

    constructor(address _usdcAddress, address _router) {
        i_usdc = IERC20(_usdcAddress);
        i_router = _router;

        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(ASSET_MANAGER_ROLE, msg.sender);
        grantRole(FEE_COLLECTOR_ROLE, msg.sender);
        grantRole(REBALANCER_ROLE, msg.sender);
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
    ) public onlyRole(ASSET_MANAGER_ROLE) {
        if (_assetA.asset == _assetB.asset) {
            revert IndexManager__InvalidIndexAssetsAddress();
        }

        (address tokenAsset0, address tokenAsset1) = sortAssets(
            _assetA.asset,
            _assetB.asset
        );

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
        if (getIndex[asset0.asset][asset1.asset] != address(0)) {
            revert IndexManager__IndexAlreadyExists(
                getIndex[asset0.asset][asset1.asset]
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

        address index = _deployIndex(
            asset0,
            asset1,
            _feePercentage,
            address(i_usdc)
        );

        getIndex[asset0.asset][asset1.asset] = index;
        isIndex[index] = true;
        indexes.push(index);

        emit IndexCreated(index, asset0.asset, asset1.asset, msg.sender);
    }

    function _deployIndex(
        IndexAsset memory _asset0,
        IndexAsset memory _asset1,
        uint256 _feePercentage,
        address _usdcAddress
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
                i_router,
                _usdcAddress,
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

    function initializeIndex(
        address _indexAddress,
        uint256 _underlyingAmount0
    ) public onlyRole(ASSET_MANAGER_ROLE) {
        if (_underlyingAmount0 == 0) {
            revert IndexManager__InvalidIndexAssetsAmount();
        }
        if (!isIndex[_indexAddress]) {
            revert IndexManager__IsNotIndex();
        }

        if (isInitialized[_indexAddress]) {
            revert IndexManager__IndexAlreadyInitialized();
        }
        isInitialized[_indexAddress] = true;

        Index(_indexAddress).initialize(_underlyingAmount0);

        emit IndexInitialized(_indexAddress, msg.sender);
    }

    function rebalanceIndex(
        address _indexAddress
    ) public isIndexInitialized(_indexAddress) onlyRole(REBALANCER_ROLE) {
        IIndex(_indexAddress).rebalanceIndex();

        emit IndexRebalanced(_indexAddress, msg.sender);
    }

    function changeWeights(
        address _indexAddress,
        uint112 _newWeightAsset0 // With 4 decimals, e.g. 50000 = 5%
    ) public isIndexInitialized(_indexAddress) onlyRole(ASSET_MANAGER_ROLE) {
        if (_newWeightAsset0 > MAX_PERCENTAGE) {
            revert IndexManager__InvalidPercentage();
        }
        // weight of asset1 is implicitly calculated as 100% - weight of asset0
        IIndex index = IIndex(_indexAddress);
        (uint112 oldWeightAsset0, uint112 oldWeightAsset1) = index
            .getAssetsWeights();
        uint112 newWeightAsset1 = MAX_PERCENTAGE - _newWeightAsset0;

        uint256 implementationTimestamp = index.updateWeights(_newWeightAsset0);

        emit IndexWeightsChanged(
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
     * @dev Collects fees from the specified index and transfers them to the caller.
     * @param _indexAddress The address of the index from which to collect fees
     */
    function collectFees(
        address _indexAddress
    ) public isIndexInitialized(_indexAddress) onlyRole(FEE_COLLECTOR_ROLE) {
        IIndex index = IIndex(_indexAddress);

        //This Function set allowance and approve this contract, returns fees amount to be collected
        uint256 feeAmount = index.collectFees(msg.sender);
        i_usdc.safeTransferFrom(_indexAddress, msg.sender, feeAmount);

        emit FeesCollected(_indexAddress, msg.sender, feeAmount);
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
        index = getIndex[asset0][asset1];
    }

    /**
     * @dev Returns all index addresses managed by the index manager
     * @return address[] An array of all index addresses
     */
    function getAllIndexes() public view returns (address[] memory) {
        return indexes;
    }

    /**
     * @dev Checks if an address is a valid index contract
     * @param indexAddress Address to check
     * @return bool True if the address is a valid index, false otherwise
     */
    function isIndexAddress(address indexAddress) public view returns (bool) {
        return isIndex[indexAddress];
    }

    /**
     * @dev Checks if an index is initialized
     * @param indexAddress Address of the index to check
     * @return bool True if the index is initialized, false otherwise
     */
    function checkIsIndexInitialized(
        address indexAddress
    ) public view returns (bool) {
        return isInitialized[indexAddress];
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
     * @dev Returns the address of the USDC token used by the index manager
     * @return address The address of the USDC token
     */
    function getUsdcAddress() public view returns (address) {
        return address(i_usdc);
    }

    function getRouterAddress() public view returns (address) {
        return i_router;
    }
}
