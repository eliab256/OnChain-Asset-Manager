//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
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
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";

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
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                keccak256("ROUTER_ROLE")
            )
        );
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

    function testMintSharesRevertsIfUserHasNoUsdcBalance() public {
        address userNoBalance = makeAddr("userNoBalance");

        // Grant unlimited allowance to the Index — allowance check will pass.
        vm.prank(userNoBalance);
        mockUsdc.approve(address(initializedIndex), type(uint256).max);

        // Balance is 0, so the transfer must revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                userNoBalance,
                0,
                VALID_USDC_AMOUNT
            )
        );
        vm.prank(address(router));
        initializedIndex.mintShares(
            userNoBalance,
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );
    }

    function testMintSharesUpdateStorageAndSendShares() public {
        uint256 user1InitialShares = initializedIndex.balanceOf(user1);
        (uint128 initialReserve0, uint128 initialReserve1) = initializedIndex
            .getAssetsReserves();
        (, , uint256 initialTotalUsdValueOnIndex) = initializedIndex
            .getAssetsUsdValue();

        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), VALID_USDC_AMOUNT);
        vm.prank(address(router));
        initializedIndex.mintShares(user1, VALID_USDC_AMOUNT, VALID_TOLERANCE);

        uint256 user1FinalShares = initializedIndex.balanceOf(user1);
        (uint128 finalReserve0, uint128 finalReserve1) = initializedIndex
            .getAssetsReserves();
        (, , uint256 finalTotalUsdValueOnIndex) = initializedIndex
            .getAssetsUsdValue();
        (uint32 feePercentage, uint128 totalFeesCollected) = initializedIndex
            .getFeesInfo();
        uint256 expectedFees = (VALID_USDC_AMOUNT * feePercentage) /
            MAX_PERCENTAGE;

        assertGt(
            user1FinalShares,
            user1InitialShares,
            "User should receive more shares after minting"
        );
        assertGt(
            finalReserve0,
            initialReserve0,
            "Reserve0 should increase after minting"
        );
        assertGt(
            finalReserve1,
            initialReserve1,
            "Reserve1 should increase after minting"
        );
        assertGt(
            finalTotalUsdValueOnIndex,
            initialTotalUsdValueOnIndex,
            "Total USD value on index should increase after minting"
        );
        assertEq(
            totalFeesCollected,
            expectedFees,
            "Fees collected should match expected fees"
        );
    }

    function testMintSharesEmitsEvent() public {
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), VALID_USDC_AMOUNT);

        bytes32 expectedSig = SharesMinted.selector;

        vm.recordLogs();
        vm.prank(address(router));
        initializedIndex.mintShares(user1, VALID_USDC_AMOUNT, VALID_TOLERANCE);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(initializedIndex) &&
                logs[i].topics[0] == expectedSig
            ) {
                eventFound = true;
                address _to = address(uint160(uint256(logs[i].topics[1])));
                assertEq(_to, user1, "event must log user1 as minter");

                (
                    uint256 usdcAmountIn,
                    uint256 sharesMinted,
                    uint256 token0,
                    uint256 token1
                ) = abi.decode(
                        logs[i].data,
                        (uint256, uint256, uint256, uint256)
                    );
                assertEq(
                    usdcAmountIn,
                    VALID_USDC_AMOUNT,
                    "event must log the correct USDC amount deposited"
                );
                assertGt(
                    sharesMinted,
                    0,
                    "event must log a non-zero amount of shares minted"
                );
                assertGt(
                    token0,
                    0,
                    "event must log a non-zero amount of token0 added to the index"
                );
                assertGt(
                    token1,
                    0,
                    "event must log a non-zero amount of token1 added to the index"
                );
            }
        }
    }

    // =========================================================================
    //  minMintPreview
    // =========================================================================

    function testMinMintPreviewRevertsIfNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Index__NotInitialized.selector));
        nonInitializedIndex.minMintPreview(VALID_USDC_AMOUNT, VALID_TOLERANCE);
    }

    function testMinMintPreviewRevertsIfPriceIsStale() public {
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(abi.encodeWithSelector(Index__PriceIsStale.selector));
        initializedIndex.minMintPreview(VALID_USDC_AMOUNT, VALID_TOLERANCE);
    }

    function testMinMintPreview_ReturnsNonZeroForValidInput() public view {
        uint256 result = initializedIndex.minMintPreview(
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        assertGt(
            result,
            0,
            "minimum shares must be > 0 for a positive USDC deposit"
        );
    }

    function testMinMintPreviewHigherToleranceLowersMinimumShares()
        public
        view
    {
        uint256 resultLowTolerance = initializedIndex.minMintPreview(
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        uint256 resultHighTolerance = initializedIndex.minMintPreview(
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE * 2
        );

        assertGt(
            resultLowTolerance,
            resultHighTolerance,
            "a higher tolerance must yield fewer minimum shares"
        );
    }

    function testMinMintPreviewZeroToleranceReturnsMaximumMinimumShares()
        public
        view
    {
        uint256 resultZeroTolerance = initializedIndex.minMintPreview(
            VALID_USDC_AMOUNT,
            0
        );
        uint256 resultValidTolerance = initializedIndex.minMintPreview(
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );

        assertGt(
            resultZeroTolerance,
            resultValidTolerance,
            "zero tolerance must yield more minimum shares than any positive tolerance"
        );
    }

    function testMinMintPreview_DeductsFeeBeforeApplyingTolerance()
        public
        view
    {
        // Normalize USDC to the 18-decimal standard used by Index internally.
        uint256 usdcStd = uint256(VALID_USDC_AMOUNT) *
            10 ** (DECIMALS_STANDARD - mockUsdc.decimals());

        // Gross minimum a caller would expect if no fee existed.
        uint256 grossMinimumIfNoFee = (usdcStd *
            (uint256(MAX_PERCENTAGE) - VALID_TOLERANCE)) /
            uint256(MAX_PERCENTAGE);

        uint256 result = initializedIndex.minMintPreview(
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );

        assertLt(
            result,
            grossMinimumIfNoFee,
            "fee must be deducted before tolerance is applied, reducing the minimum below the gross value"
        );
    }

    function testMinMintPreviewLargerDepositProportionallyMoreMinimumShares()
        public
        view
    {
        uint256 resultSmall = initializedIndex.minMintPreview(
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );
        uint256 resultLarge = initializedIndex.minMintPreview(
            VALID_USDC_AMOUNT * 2,
            VALID_TOLERANCE
        );

        assertEq(
            resultLarge,
            resultSmall * 2,
            "doubling the USDC input must exactly double the minimum shares"
        );
    }

    function testMinMintPreviewMatchesManualCalculation() public view {
        // 1. Normalise: 100e6 USDC (6 dec) → 100e18 (18 dec standard).
        uint256 usdcStd = uint256(VALID_USDC_AMOUNT) *
            10 ** (DECIMALS_STANDARD - mockUsdc.decimals());

        // 2. Protocol fee (1 %): fee = usdcStd * feePercentage / MAX_PERCENTAGE.
        uint256 feeAmount = (usdcStd * uint256(validFeePercentage)) /
            uint256(MAX_PERCENTAGE);
        uint256 netUsdcStd = usdcStd - feeAmount;

        // 3. Tolerance buffer: minimumUsd = netUsdcStd * (MAX - tolerance) / MAX.
        uint256 minimumUsdAmount = (netUsdcStd *
            (uint256(MAX_PERCENTAGE) - VALID_TOLERANCE)) /
            uint256(MAX_PERCENTAGE);

        // 4. Convert minimum USD to minimum shares using the current index ratio.
        (, , uint256 totalAssetUsdValue) = initializedIndex.getAssetsUsdValue();
        uint256 totalSupply = initializedIndex.totalSupply();
        uint256 expectedMinShares = (minimumUsdAmount * totalSupply) /
            totalAssetUsdValue;

        uint256 result = initializedIndex.minMintPreview(
            VALID_USDC_AMOUNT,
            VALID_TOLERANCE
        );

        assertEq(
            result,
            expectedMinShares,
            "minMintPreview must match the step-by-step manual reconstruction"
        );
    }

    function testMinMintPreviewZeroUsdcDepositReturnsZeroShares() public view {
        uint256 result = initializedIndex.minMintPreview(0, VALID_TOLERANCE);
        assertEq(
            result,
            0,
            "a zero USDC deposit must produce zero minimum shares"
        );
    }

    // =========================================================================
    //  _swapUsdcForAssets — single-swap branches
    // =========================================================================

    function testMintSingleSwapOnlyAsset1WhenAsset0Overweight() public {
        // Make asset0 severely overweight; a deposit should buy ONLY asset1.
        _makeAsset0Overweight();

        uint256 user1SharesBefore = initializedIndex.balanceOf(user1);

        _mintSharesViaRouter(user1, VALID_USDC_AMOUNT);

        uint256 user1SharesAfter = initializedIndex.balanceOf(user1);
        assertGt(
            user1SharesAfter,
            user1SharesBefore,
            "User should receive shares even when only asset1 is bought"
        );
    }

    function testMintSingleSwapOnlyAsset0WhenAsset1Overweight() public {
        // Make asset1 severely overweight; a deposit should buy ONLY asset0.
        _makeAsset1Overweight();

        uint256 user1SharesBefore = initializedIndex.balanceOf(user1);

        _mintSharesViaRouter(user1, VALID_USDC_AMOUNT);

        uint256 user1SharesAfter = initializedIndex.balanceOf(user1);
        assertGt(
            user1SharesAfter,
            user1SharesBefore,
            "User should receive shares even when only asset0 is bought"
        );
    }
}
