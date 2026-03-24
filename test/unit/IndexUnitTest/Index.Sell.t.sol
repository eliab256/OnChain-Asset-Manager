//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IIndexManager} from "../../../src/Interface/IIndexManager.sol";
import {ISwapManager} from "../../../src/Interface/ISwapManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute, AssetAvailable} from "../../../src/types.sol";
import {Index} from "../../../src/Index.sol";
import {
    HelperConfig,
    AssetConfig,
    NetworkConfig
} from "../../../script/HelperConfig.s.sol";
import {
    DeployAndInitNewIndex,
    RunParams
} from "../../../script/DeployAndInitNewIndex.s.sol";
import {console2} from "forge-std/console2.sol";

import "../../../src/errors/IndexErrors.sol";
import "../../../src/events/IndexEvents.sol";

contract IndexMintTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  Redeem
    // =========================================================================
}
