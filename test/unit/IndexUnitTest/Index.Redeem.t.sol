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
    uint256 internal constant VALID_USDC_AMOUNT = 1000e6; // 100 USDC with 6 decimals
    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _mintSharesHelper(
        address _minter
    ) internal {
        vm.startPrank(_minter);
        mockUsdc.approve(address(initializedIndex), VALID_USDC_AMOUNT);
        router.buyExactUsdcAmountOfShares(address(initializedIndex), VALID_USDC_AMOUNT, VALID_TOLERANCE);
        vm.stopPrank();
    }

    // =========================================================================
    //  Redeem
    // =========================================================================

    function testRedeemRevertIfNotInitialized() public {

        vm.expectRevert(abi.encodeWithSelector(Index__NotInitialized.selector));
        vm.prank(user1);
        nonInitializedIndex.redeem(
            user1,
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );
    }
}
