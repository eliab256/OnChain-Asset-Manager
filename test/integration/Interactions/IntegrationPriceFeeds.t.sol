// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IntegrationBase} from "./IntegrationBase.t.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {Index} from "../../../src/Index.sol";
import {Router} from "../../../src/Router.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract IntegrationPriceFeeds is IntegrationBase {
    function setUp() public override {
        super.setUp();
    }


}
