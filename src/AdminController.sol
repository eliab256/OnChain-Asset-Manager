// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IIndexFactory} from "./Interface/IIndexFactory.sol";
import {IndexAsset} from "./types.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AdminController is AccessControl {
    error AdminController__InvalidIndexFactoryAddress();
    error AdminController__NotIndexInitialized();
    error AdminController__InvalidIndexAssetsAmount();

    IIndexFactory public indexFactory;

    bytes32 public constant ASSET_MANAGER_ROLE =
        keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant FEE_COLLECTOR_ROLE =
        keccak256("FEE_COLLECTOR_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    modifier isIndexInitialized(address indexAddress) {
        if (!indexFactory.isIndexInitialized(indexAddress)) {
            revert AdminController__NotIndexInitialized();
        }
        _;
    }

    constructor(address _indexFactory) {
        if (_indexFactory == address(0)) {
            revert AdminController__InvalidIndexFactoryAddress();
        }
        indexFactory = IIndexFactory(_indexFactory);
        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(ASSET_MANAGER_ROLE, msg.sender);
        grantRole(FEE_COLLECTOR_ROLE, msg.sender);
        grantRole(REBALANCER_ROLE, msg.sender);
    }

    function initiateIndexCreation(
        IndexAsset memory _assetA,
        IndexAsset memory _assetB,
        uint256 _feePercentage
    ) public onlyRole(ASSET_MANAGER_ROLE) {
       
        indexFactory.createIndex(
            _feePercentage,
            _assetA,
            _assetB
        );
    }

    function initializeIndex(
        address _indexAddress,
        uint256 _underlyingAmount0
    ) public onlyRole(ASSET_MANAGER_ROLE) {
         if (_underlyingAmount0 == 0) {
            revert AdminController__InvalidIndexAssetsAmount();
        }
        indexFactory.initializeIndex(_indexAddress, _underlyingAmount0);
    }

    function collectFees(
        address indexAddress
    ) public onlyRole(FEE_COLLECTOR_ROLE) {
        // TO BE IMPLEMENTED
    }

    function rebalanceIndex(
        address indexAddress
    ) public onlyRole(REBALANCER_ROLE) {
        // TO BE IMPLEMENTED
    }
}
