// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IIndexFactory} from "./Interface/IIndexFactory.sol";
import {IndexAsset} from "./types.sol";

contract AdminController is Ownable {

    IIndexFactory public indexFactory;

    constructor(address _indexFactory) Ownable(msg.sender) {
        indexFactory = IIndexFactory(_indexFactory);
    }

    function initiateIndexCreation(
        IndexAsset memory assetA, IndexAsset memory assetB
    ) public onlyOwner {
        indexFactory.createIndex(assetA, assetB);
    }
}
