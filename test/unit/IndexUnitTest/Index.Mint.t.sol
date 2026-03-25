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
import {
    IERC20Errors
} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import "../../../src/errors/IndexErrors.sol";
import "../../../src/events/IndexEvents.sol";

contract IndexMintTest is BaseTest {
    uint256 internal constant VALID_USDC_AMOUNT = 100e6; // 100 USDC with 6 decimals
    function setUp() public override {
        super.setUp();
    }

    function testMintRevertIfNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Index__NotInitialized.selector));
        vm.prank(user1);
        nonInitializedIndex.mintShares(
            user1,
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );
    }

    function testMintRevertsIfNotRouter() public {
        vm.expectRevert();
        vm.prank(user1);
        initializedIndex.mintShares(user1, VALID_USDC_AMOUNT, VALID_TOLERANCE);
    }

    function testMintRevertsIfUserHasNotEnoughBalance() public {
        address poorUser = makeAddr("poorUser");
        vm.prank(poorUser);
        mockUsdc.approve(address(router), VALID_USDC_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(initializedIndex),
                0,
                VALID_USDC_AMOUNT
            )
        );
        vm.prank(address(router));
        initializedIndex.mintShares(
            poorUser,
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );
    }

    function testMintRevertsIfPriceStealed() public {
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), VALID_USDC_AMOUNT);

        vm.warp(block.timestamp + 1 days); // Move forward in time to make the price stale

        vm.expectRevert(abi.encodeWithSelector(Index__PriceIsStale.selector));
        vm.prank(address(router));
        initializedIndex.mintShares(user1, VALID_USDC_AMOUNT, VALID_TOLERANCE);
    }
}
