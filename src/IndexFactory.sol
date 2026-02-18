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
    error IndexFactory__InvalidPriceFeedAddress();

    address[] public indices;
    mapping(address => mapping(address => address)) public getIndex;
    mapping(address => bool) public isIndex;

    constructor(address _adminController) Ownable(_adminController) {}

    function createIndex(
        string memory _name,
        string memory _symbol,
        uint256 _feePercentage,
        IndexAsset memory _assetA,
        IndexAsset memory _assetB
    ) public onlyOwner {
        //CHECK ASSETS ARE NOT THE SAME
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

        //CHECK AMOUNT OF UNDERLYING ASSETS IS NOT ZERO
        if (asset0.underlyingInitAmount == 0 ){
            revert IndexFactory__InvalidIndexAssetsAmount();
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

        // CHECK BALANCE OF UNDERLYING ASSET IN THE CONTRACT
        // TRANSFERFROM USER TO THE CONTRACT THE UNDERLYING ASSET
        //create2 per prevedere address e inviare fondi
        bytes memory bytecode = abi.encodePacked(
            type(Index).creationCode,
            abi.encode(
                _name, 
                _symbol, 
                asset0.asset, 
                asset1.asset, 
                asset0.weightPercentage, 
                asset1.weightPercentage, 
                asset0.priceFeed, 
                asset1.priceFeed, 
                _feePercentage 
            )
        );
        bytes32 salt = keccak256(abi.encodePacked(asset0.asset, asset1.asset));

        address index;
        assembly {
            index := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        getIndex[asset0.asset][asset1.asset] = index;
        isIndex[index] = true;
        indices.push(index);

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
