//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IIndexManager} from "../../../src/Interface/IIndexManager.sol";
import {ISwapManager} from "../../../src/Interface/ISwapManager.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute, AssetAvailable} from "../../../src/contracts/types.sol";
import {Index} from "../../../src/contracts/core/Index.sol";
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
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";

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

    function _mintSharesHelper(address _minter) internal {
        vm.startPrank(_minter);
        mockUsdc.approve(address(initializedIndex), VALID_USDC_AMOUNT);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        vm.stopPrank();
    }

    // =========================================================================
    //  Redeem
    // =========================================================================

    function testRedeemRevertIfNotInitialized() public {
        vm.expectRevert(Index__NotInitialized.selector);
        vm.prank(user1);
        nonInitializedIndex.redeem(user1, VALID_USDC_AMOUNT, VALID_TOLERANCE);
    }

    function testRedeemRevertsIfCallerIsNotRouter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                keccak256("ROUTER_ROLE")
            )
        );
        vm.prank(user1);
        initializedIndex.redeem(user1, VALID_USDC_AMOUNT, VALID_TOLERANCE);
    }

    function testRedeemRevertsIfPriceIsStale() public {
        _mintSharesHelper(user1);

        uint256 sharesToRedeem = initializedIndex.balanceOf(user1);
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(Index__PriceIsStale.selector);
        vm.prank(address(router));
        initializedIndex.redeem(user1, sharesToRedeem, VALID_TOLERANCE);
    }

    function testRedeemRevertsIfToleranceExceeded() public {
        _mintSharesHelper(user1);

        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockUsdc),
            mockUniRouter.computeRate(1e18, 1) // 1 wei USDC per WETH
        );
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockUsdc),
            mockUniRouter.computeRate(1e8, 1) // 1 wei USDC per WBTC
        );

        uint256 sharesToRedeem = initializedIndex.balanceOf(user1);

        vm.expectRevert(Index__ToleranceExceeded.selector);
        vm.prank(address(router));
        initializedIndex.redeem(user1, sharesToRedeem, VALID_TOLERANCE);
    }

    function testRedeemBurnsSharesAndTransfersUsdcToUser() public {
        _mintSharesHelper(user1);

        uint256 sharesToRedeem = initializedIndex.balanceOf(user1);
        uint256 usdcBalanceBefore = mockUsdc.balanceOf(user1);

        vm.prank(address(router));
        initializedIndex.redeem(user1, sharesToRedeem, VALID_TOLERANCE);

        assertEq(
            initializedIndex.balanceOf(user1),
            0,
            "all shares must be burned after full redeem"
        );
        assertGt(
            mockUsdc.balanceOf(user1),
            usdcBalanceBefore,
            "user1 must receive USDC after redeeming shares"
        );
    }

    function testRedeemDecreasesTotalSupplyByBurnedShares() public {
        _mintSharesHelper(user1);

        uint256 sharesToRedeem = initializedIndex.balanceOf(user1);
        uint256 totalSupplyBefore = initializedIndex.totalSupply();

        vm.prank(address(router));
        initializedIndex.redeem(user1, sharesToRedeem, VALID_TOLERANCE);

        assertEq(
            initializedIndex.totalSupply(),
            totalSupplyBefore - sharesToRedeem,
            "totalSupply must decrease by the exact number of burned shares"
        );
        assertEq(
            initializedIndex.balanceOf(user1),
            0,
            "all shares must be burned after full redeem"
        );
    }

    function testRedeemDecreasesAssetReserves() public {
        _mintSharesHelper(user1);

        (uint128 reserve0Before, uint128 reserve1Before) = initializedIndex
            .getAssetsReserves();

        uint256 sharesToRedeem = initializedIndex.balanceOf(user1);

        vm.prank(address(router));
        initializedIndex.redeem(user1, sharesToRedeem, VALID_TOLERANCE);

        (uint128 reserve0After, uint128 reserve1After) = initializedIndex
            .getAssetsReserves();

        assertLt(
            reserve0After,
            reserve0Before,
            "reserve0 must decrease after redeem"
        );
        assertLt(
            reserve1After,
            reserve1Before,
            "reserve1 must decrease after redeem"
        );
    }

    function testRedeemAccruesProtocolFees() public {
        _mintSharesHelper(user1);

        (, uint128 feesBefore) = initializedIndex.getFeesInfo();
        uint256 sharesToRedeem = initializedIndex.balanceOf(user1);

        vm.prank(address(router));
        initializedIndex.redeem(user1, sharesToRedeem, VALID_TOLERANCE);

        (, uint128 feesAfter) = initializedIndex.getFeesInfo();
        assertGt(
            feesAfter,
            feesBefore,
            "protocol fees must accrue during redeem"
        );
    }

    function testRedeemPartialBurnLeavesRemainingShares() public {
        _mintSharesHelper(user1);

        uint256 totalShares = initializedIndex.balanceOf(user1);
        uint256 sharesToRedeem = totalShares / 2;

        vm.prank(address(router));
        initializedIndex.redeem(user1, sharesToRedeem, VALID_TOLERANCE);

        assertApproxEqAbs(
            initializedIndex.balanceOf(user1),
            totalShares - sharesToRedeem,
            1,
            "remaining balance must equal original minus redeemed shares"
        );
    }

    function testRedeemUsdcReceivedIsLessThanDepositedDueToFees() public {
        uint256 usdcBalanceBeforeMint = mockUsdc.balanceOf(user1);

        _mintSharesHelper(user1);

        uint256 usdcBalanceAfterMint = mockUsdc.balanceOf(user1);
        uint256 sharesToRedeem = initializedIndex.balanceOf(user1);

        vm.prank(address(router));
        initializedIndex.redeem(user1, sharesToRedeem, VALID_TOLERANCE);

        uint256 usdcReceived = mockUsdc.balanceOf(user1) - usdcBalanceAfterMint;

        assertLt(
            usdcReceived,
            VALID_USDC_AMOUNT,
            "USDC received after fees must be less than the original deposit"
        );
        assertLt(
            mockUsdc.balanceOf(user1),
            usdcBalanceBeforeMint,
            "net USDC balance after round-trip must be lower due to fees"
        );
    }

    function testRedeemEmitsSharesBurnedEvent() public {
        _mintSharesHelper(user1);

        uint256 sharesToRedeem = initializedIndex.balanceOf(user1);
        bytes32 expectedSig = SharesBurned.selector;

        vm.recordLogs();
        vm.prank(address(router));
        initializedIndex.redeem(user1, sharesToRedeem, VALID_TOLERANCE);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;

        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(initializedIndex) &&
                logs[i].topics[0] == expectedSig
            ) {
                eventFound = true;

                // _from is indexed → topics[1]
                address fromInEvent = address(
                    uint160(uint256(logs[i].topics[1]))
                );
                assertEq(
                    fromInEvent,
                    user1,
                    "event must log user1 as redeemer"
                );

                (
                    uint256 logShares,
                    uint256 logToken0,
                    uint256 logToken1,
                    uint256 logUsdcOut
                ) = abi.decode(
                        logs[i].data,
                        (uint256, uint256, uint256, uint256)
                    );

                assertEq(
                    logShares,
                    sharesToRedeem,
                    "event must log the correct shares amount burned"
                );
                assertGt(
                    logToken0,
                    0,
                    "event must log non-zero token0 removed"
                );
                assertGt(
                    logToken1,
                    0,
                    "event must log non-zero token1 removed"
                );
                assertGt(
                    logUsdcOut,
                    0,
                    "event must log non-zero USDC sent to user"
                );
                break;
            }
        }
        assertTrue(eventFound, "SharesBurned event must be emitted");
    }

    function testRedeemTwoUsersIndependently() public {
        // Mint USDC for user2 since Base.setUp only funds user1
        mockUsdc.mint(user2, VALID_USDC_AMOUNT);

        _mintSharesHelper(user1);

        vm.startPrank(user2);
        mockUsdc.approve(address(initializedIndex), VALID_USDC_AMOUNT);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        vm.stopPrank();

        uint256 shares1 = initializedIndex.balanceOf(user1);
        uint256 shares2 = initializedIndex.balanceOf(user2);

        // user1 redeems
        vm.prank(address(router));
        initializedIndex.redeem(user1, shares1, VALID_TOLERANCE);

        assertEq(
            initializedIndex.balanceOf(user1),
            0,
            "user1 shares must be 0 after redeem"
        );
        assertEq(
            initializedIndex.balanceOf(user2),
            shares2,
            "user2 shares must be unaffected by user1 redeem"
        );

        // user2 redeems
        vm.prank(address(router));
        initializedIndex.redeem(user2, shares2, VALID_TOLERANCE);

        assertEq(
            initializedIndex.balanceOf(user2),
            0,
            "user2 shares must be 0 after redeem"
        );
    }

    // =========================================================================
    //  minRedeemPreview
    // =========================================================================

    function testMinRedeemPreviewRevertsIfNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Index__NotInitialized.selector));
        nonInitializedIndex.minRedeemPreview(
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );
    }

    function testMinRedeemPreviewRevertsIfPriceIsStale() public {
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(abi.encodeWithSelector(Index__PriceIsStale.selector));
        initializedIndex.minRedeemPreview(VALID_USDC_AMOUNT, VALID_TOLERANCE);
    }

    function testMinRedeemPreviewReturnsNonZeroForValidInput() public view {
        uint256 sharesAmount = initializedIndex.totalSupply() / 10;
        uint256 result = initializedIndex.minRedeemPreview(
            sharesAmount,
            VALID_TOLERANCE
        );
        assertGt(
            result,
            0,
            "minimum USDC must be > 0 for a positive shares input"
        );
    }

    function testMinRedeemPreviewHigherToleranceLowersMinimumUsdc()
        public
        view
    {
        uint256 sharesAmount = initializedIndex.totalSupply() / 10;

        uint256 resultLow = initializedIndex.minRedeemPreview(
            sharesAmount,
            VALID_TOLERANCE
        );
        uint256 resultHigh = initializedIndex.minRedeemPreview(
            sharesAmount,
            VALID_TOLERANCE * 2
        );

        assertGt(
            resultLow,
            resultHigh,
            "higher tolerance must yield fewer guaranteed USDC"
        );
    }

    function testMinRedeemPreviewZeroToleranceReturnsMaximumMinimum()
        public
        view
    {
        uint256 sharesAmount = initializedIndex.totalSupply() / 10;

        uint256 resultZero = initializedIndex.minRedeemPreview(sharesAmount, 0);
        uint256 resultValid = initializedIndex.minRedeemPreview(
            sharesAmount,
            VALID_TOLERANCE
        );

        assertGt(
            resultZero,
            resultValid,
            "zero tolerance must yield more minimum USDC than any positive tolerance"
        );
    }

    function testMinRedeemPreviewMatchesManualCalculation() public view {
        uint256 sharesAmount = initializedIndex.totalSupply() / 10;

        // 1. Share USD value (18-dec standard)
        (, , uint256 totalAssetUsdValue) = initializedIndex.getAssetsUsdValue();
        uint256 totalSupply = initializedIndex.totalSupply();
        uint256 shareValueStd = (sharesAmount * totalAssetUsdValue) /
            totalSupply;

        // 2. Protocol fee deduction
        (uint32 feePercentage, ) = initializedIndex.getFeesInfo();
        uint256 feeAmount = (shareValueStd * uint256(feePercentage)) /
            uint256(MAX_PERCENTAGE);
        uint256 netUsdcStd = shareValueStd - feeAmount;

        // 3. Tolerance deduction
        uint256 minUsdcStd = (netUsdcStd *
            (uint256(MAX_PERCENTAGE) - VALID_TOLERANCE)) /
            uint256(MAX_PERCENTAGE);

        // 4. Convert std decimals → token decimals (18 → 6)
        (, , uint8 usdcDecimals) = initializedIndex.getAssetsAndUsdcDecimals();
        uint256 expectedMinUsdc = minUsdcStd /
            (10 ** (DECIMALS_STANDARD - usdcDecimals));

        uint256 result = initializedIndex.minRedeemPreview(
            sharesAmount,
            VALID_TOLERANCE
        );

        assertEq(
            result,
            expectedMinUsdc,
            "minRedeemPreview must match the step-by-step manual reconstruction"
        );
    }

    function testMinRedeemPreviewZeroSharesReturnsZero() public view {
        uint256 result = initializedIndex.minRedeemPreview(0, VALID_TOLERANCE);
        assertEq(result, 0, "zero shares input must produce zero minimum USDC");
    }

    function testMinRedeemPreviewBoundIsHonouredByActualRedeem() public {
        _mintSharesHelper(user1);

        uint256 sharesToRedeem = initializedIndex.balanceOf(user1);

        // Preview before the redeem
        uint256 minUsdcPreview = initializedIndex.minRedeemPreview(
            sharesToRedeem,
            VALID_TOLERANCE
        );

        uint256 usdcBefore = mockUsdc.balanceOf(user1);

        vm.prank(address(router));
        initializedIndex.redeem(user1, sharesToRedeem, VALID_TOLERANCE);

        uint256 usdcReceived = mockUsdc.balanceOf(user1) - usdcBefore;

        assertGe(
            usdcReceived,
            minUsdcPreview,
            "actual USDC received must be >= the minimum previewed"
        );
    }

    // =========================================================================
    //  _swapAssetsForUsdc — single-swap branches
    // =========================================================================

    function testRedeemSingleSwapSellOnlyAsset1WhenAsset0Underweight()
        public
    {
        // Mint some shares for user1 at balanced prices.
        _mintSharesViaRouter(user1, 100e6);
        uint256 shares = initializedIndex.balanceOf(user1);
        assertGt(shares, 0, "User must have shares to redeem");

        // Make asset1 severely overweight (= asset0 underweight).
        // In calculateWithdrawUnderlyingAmountsInUsd the IF branch fires:
        // targetToken0 >= currentToken0 → sell only asset1.
        _makeAsset1Overweight();

        uint256 usdcBefore = mockUsdc.balanceOf(user1);
        _redeemSharesViaRouter(user1, shares);

        assertGt(
            mockUsdc.balanceOf(user1),
            usdcBefore,
            "User should receive USDC back"
        );
        assertEq(
            initializedIndex.balanceOf(user1),
            0,
            "All shares should be burned"
        );
    }

    function testRedeemSingleSwapSellOnlyAsset0WhenAsset1Underweight()
        public
    {
        _mintSharesViaRouter(user1, 100e6);
        uint256 shares = initializedIndex.balanceOf(user1);
        assertGt(shares, 0, "User must have shares to redeem");

        _makeAsset0Overweight();

        uint256 usdcBefore = mockUsdc.balanceOf(user1);
        _redeemSharesViaRouter(user1, shares);

        assertGt(
            mockUsdc.balanceOf(user1),
            usdcBefore,
            "User should receive USDC back"
        );
        assertEq(
            initializedIndex.balanceOf(user1),
            0,
            "All shares should be burned"
        );
    }
}
