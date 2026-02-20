// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Index} from "./Index.sol";
import {IIndexFactory} from "./Interface/IIndexFactory.sol";
import {IndexAsset} from "./types.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract IndexFactory is Ownable {
    error IndexFactory__InvalidIndexAssetsAddress();
    error IndexFactory__InvalidIndexAssetsAmount();
    error IndexFactory__InvalidIndexAssetsPercentages();
    error IndexFactory__UnderlyingAssetNotERC20();
    error IndexFactory__PriceFeedNotAvailable(address priceFeed);
    error IndexFactory__IndexAlreadyExists(address index);
    error IndexFactory__IsNotIndex();
    error IndexFactory__IndexAlreadyInitialized();
    error IndexFactory__InvalidPriceFeedAddress();

    address[] private indexes;
    mapping(address => mapping(address => address)) private getIndex;
    mapping(address => bool) private isIndex;
    mapping(address => bool) private isInitialized;

    address public immutable i_usdcAddress;

    constructor(address _adminController, address _usdcAddress) Ownable(_adminController) {
        i_usdcAddress = _usdcAddress;
    }

    function createIndex(
        uint256 _feePercentage,
        IndexAsset memory _assetA,
        IndexAsset memory _assetB
    ) public onlyOwner {
        if (_assetA.asset == _assetB.asset) {
            revert IndexFactory__InvalidIndexAssetsAddress();
        }

        (IndexAsset memory asset0, IndexAsset memory asset1) = sortAssets(
            _assetA,
            _assetB
        );

        // CHECK INDEX IS NOT ALREADY CREATED
        if (getIndex[asset0.asset][asset1.asset] != address(0)) {
            revert IndexFactory__IndexAlreadyExists(
                getIndex[asset0.asset][asset1.asset]
            );
        }

        // CHECK WEIGHT PERCENTAGES SUM TO 100
        if (asset0.weightPercentage + asset1.weightPercentage != 100) {
            revert IndexFactory__InvalidIndexAssetsPercentages();
        }

        // CHECK UNDERLYIN ASSETS ARE ERC20
        _validateAssetIsERC20(asset0.asset);
        _validateAssetIsERC20(asset1.asset);

        // CHECK UNDERLYIN ASSETS HAVE PRICEFEED CHAINLINK
        _validatePriceFeed(asset0.priceFeed);
        _validatePriceFeed(asset1.priceFeed);

        address index = _deployIndex(asset0, asset1, _feePercentage, i_usdcAddress);

        getIndex[asset0.asset][asset1.asset] = index;
        isIndex[index] = true;
        indexes.push(index);
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
                msg.sender,
                _usdcAddress,
                _asset0.asset,
                _asset1.asset,
                _asset0.weightPercentage,
                _asset1.weightPercentage,
                _asset0.priceFeed,
                _asset1.priceFeed,
                _feePercentage
            )
        );
        bytes32 salt = keccak256(abi.encodePacked(_asset0.asset, _asset1.asset));
        assembly {
            index := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
    }

    function initializeIndex(
        address indexAddress,
        uint256 underlyingAmount0
    ) public onlyOwner {
        if (!isIndex[indexAddress]) {
            revert IndexFactory__IsNotIndex();
        }

        if (isInitialized[indexAddress]) {
            revert IndexFactory__IndexAlreadyInitialized();
        }

        Index(indexAddress).initialize(underlyingAmount0);
        isInitialized[indexAddress] = true;
    }

    function sortAssets(
        IndexAsset memory _assetA,
        IndexAsset memory _assetB
    ) public pure returns (IndexAsset memory, IndexAsset memory) {
        if (_assetA.asset < _assetB.asset) {
            return (_assetA, _assetB);
        } else {
            return (_assetB, _assetA);
        }
    }

    function getAllIndexes() public view returns (address[] memory) {
        return indexes;
    }

    // function getIndexByAssets(
    //     address assetA,
    //     address assetB
    // ) public view returns (address index, bool isAlreadyInitialized) {
    //     (IndexAsset memory asset0, IndexAsset memory asset1) = sortAssets(
    //         IndexAsset(assetA, 0, 0, address(0)),
    //         IndexAsset(assetB, 0, 0, address(0))
    //     );
    //     index = getIndex[asset0.asset][asset1.asset];
    //     isAlreadyInitialized = isInitialized[index];
    //     return (index, isAlreadyInitialized);
    // }

    function isIndexAddress(address indexAddress) public view returns (bool) {
        return isIndex[indexAddress];
    }

    function isIndexInitialized(
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
            revert IndexFactory__InvalidIndexAssetsAddress();
        }

        // Check if contract has decimals() function (ERC20 standard)
        (bool success, bytes memory result) = _asset.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        if (!(success && result.length > 0)) {
            revert IndexFactory__InvalidIndexAssetsAddress();
        }
    }

    /**
     * @dev Validates if an address is a valid Chainlink Price Feed
     * @param _priceFeed Address to validate
     */
    function _validatePriceFeed(address _priceFeed) internal view {
        if (_priceFeed == address(0)) {
            revert IndexFactory__InvalidPriceFeedAddress();
        }

        // Check if contract has latestRoundData() function (Chainlink standard)
        (bool success, bytes memory result) = _priceFeed.staticcall(
            abi.encodeWithSignature("latestRoundData()")
        );
        if (!(success && result.length > 0)) {
            revert IndexFactory__InvalidPriceFeedAddress();
        }
    }
}
