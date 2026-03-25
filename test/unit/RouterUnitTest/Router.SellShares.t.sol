// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute} from "../../../src/types.sol";
import {IRouter} from "../../../src/Interface/IRouter.sol";
import {Router} from "../../../src/Router.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

import "../../../src/errors/RouterErrors.sol";
import "../../../src/events/IndexEvents.sol";

contract RouterTest is BaseTest {
    function setUp() public override {
        super.setUp();
        _setupMockRouterForWethWbtcIndex();
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /**
     * @dev Sets exchange rates and funds the UniversalRouterMock for WETH/WBTC swaps.
     */
    function _setupMockRouterForWethWbtcIndex() internal {
        mockUniRouter.setExchangeRate(
            address(mockUsdc),
            address(mockWeth),
            mockUniRouter.computeRate(2_000e6, 1e18)
        );
        mockUniRouter.setExchangeRate(
            address(mockUsdc),
            address(mockWbtc),
            mockUniRouter.computeRate(30_000e6, 1e8)
        );
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockUsdc),
            mockUniRouter.computeRate(1e18, 2_000e6)
        );
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockUsdc),
            mockUniRouter.computeRate(1e8, 30_000e6)
        );
        mockUniRouter.setExchangeRate(
            address(mockWeth),
            address(mockWbtc),
            mockUniRouter.computeRate(15e18, 1e8)
        );
        mockUniRouter.setExchangeRate(
            address(mockWbtc),
            address(mockWeth),
            mockUniRouter.computeRate(1e8, 15e18)
        );

        deal(address(mockWeth), address(mockUniRouter), 100_000e18);
        deal(address(mockWbtc), address(mockUniRouter), 10_000e8);
        deal(address(mockUsdc), address(mockUniRouter), 1_000_000_000e6);
    }

    /**
     * @dev Mints USDC to `_user`, approves the Index to spend it, then buys
     *      shares via the Router. Returns the share balance gained.
     */
    function _buySharesForUser(
        address _user,
        uint256 _usdcAmount
    ) internal returns (uint256 sharesBought) {
        mockUsdc.mint(_user, _usdcAmount);

        vm.prank(_user);
        mockUsdc.approve(address(initializedIndex), _usdcAmount);

        uint256 sharesBefore = initializedIndex.balanceOf(_user);

        vm.prank(_user);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            _usdcAmount,
            VALID_TOLERANCE
        );

        sharesBought = initializedIndex.balanceOf(_user) - sharesBefore;
    }

    // =========================================================================
    //  sellExactAmountOfSharesForUsdc
    // =========================================================================

    function testSellSharesRevertsIfIndexNotInitialized() public {
        vm.prank(user1);
        vm.expectRevert(Router__InvalidIndexAddress.selector);
        router.sellExactAmountOfSharesForUsdc(
            address(nonInitializedIndex),
            100e18,
            VALID_TOLERANCE
        );
    }

    function testSellSharesRevertsIfAmountIsZero() public {
        vm.prank(user1);
        vm.expectRevert(Router__InvalidAmounts.selector);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            0,
            VALID_TOLERANCE
        );
    }

    function testSellSharesRevertsIfToleranceIsZero() public {
        vm.prank(user1);
        vm.expectRevert(Router__InvalidTolerance.selector);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            100e18,
            0
        );
    }

    function testSellSharesRevertsIfToleranceEqualsMaxTolerance() public {
        vm.prank(user1);
        vm.expectRevert(Router__InvalidTolerance.selector);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            100e18,
            10_000
        );
    }

    function testSellSharesBurnsSharesAndTransfersUsdcToCaller() public {
        uint256 usdcAmount = 4_000e6;
        uint256 sharesBought = _buySharesForUser(user1, usdcAmount);
        assertGt(sharesBought, 0, "user1 must have shares to sell");

        uint256 usdcBefore = mockUsdc.balanceOf(user1);

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            sharesBought,
            VALID_TOLERANCE
        );

        assertEq(
            initializedIndex.balanceOf(user1),
            0,
            "all shares must be burned"
        );
        assertGt(
            mockUsdc.balanceOf(user1),
            usdcBefore,
            "user1 must receive USDC after redeem"
        );
    }

    function testSellSharesDecreasesTotalSupply() public {
        uint256 sharesBought = _buySharesForUser(user1, 4_000e6);

        uint256 supplyBefore = initializedIndex.totalSupply();

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            sharesBought,
            VALID_TOLERANCE
        );

        assertEq(
            initializedIndex.totalSupply(),
            supplyBefore - sharesBought,
            "totalSupply must decrease by burned shares"
        );
    }

    function testSellSharesPartialRedeemLeavesRemainingShares() public {
        uint256 sharesBought = _buySharesForUser(user1, 4_000e6);
        uint256 sharesToSell = sharesBought / 2;

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            sharesToSell,
            VALID_TOLERANCE
        );

        assertApproxEqAbs(
            initializedIndex.balanceOf(user1),
            sharesBought - sharesToSell,
            1,
            "remaining shares must equal bought - sold"
        );
    }

    function testSellSharesEmitsWithdrawalEvent() public {
        uint256 sharesBought = _buySharesForUser(user1, 4_000e6);
        bytes32 expectedSig = SharesBurned.selector;

        vm.recordLogs();
        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            sharesBought,
            VALID_TOLERANCE
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(initializedIndex) &&
                logs[i].topics[0] == expectedSig
            ) {
                found = true;
                address userFromEvent = address(
                    uint160(uint256(logs[i].topics[1]))
                );
                assertEq(
                    userFromEvent,
                    user1,
                    "event must log user1 as redeemer"
                );

                (uint256 logShares, , , uint256 logUsdcOut) = abi.decode(
                    logs[i].data,
                    (uint256, uint256, uint256, uint256)
                );
                assertEq(logShares, sharesBought, "logged shares mismatch");
                assertGt(logUsdcOut, 0, "logged USDC out must be > 0");
                break;
            }
        }
        assertTrue(found, "Withdrawal event not emitted by Index");
    }

    function testSellSharesAccruesProtocolFees() public {
        _buySharesForUser(user1, 4_000e6);

        (, uint128 feesBeforeRedeem) = initializedIndex.getFeesInfo();

        uint256 sharesToSell = initializedIndex.balanceOf(user1);
        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            sharesToSell,
            VALID_TOLERANCE
        );

        (, uint128 feesAfterRedeem) = initializedIndex.getFeesInfo();
        assertGe(
            feesAfterRedeem,
            feesBeforeRedeem,
            "fees must not decrease after redeem"
        );
    }

    function testSellSharesUsdcReceivedIsLessOrEqualToDeposited() public {
        uint256 usdcDeposited = 4_000e6;
        mockUsdc.mint(user1, usdcDeposited);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcDeposited);
        vm.prank(user1);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcDeposited,
            VALID_TOLERANCE
        );

        uint256 usdcAfterBuy = mockUsdc.balanceOf(user1);
        uint256 sharesToSell = initializedIndex.balanceOf(user1);

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            sharesToSell,
            VALID_TOLERANCE
        );

        uint256 usdcReceived = mockUsdc.balanceOf(user1) - usdcAfterBuy;
        // After fees on both mint and redeem, USDC received must be < deposited.
        assertLt(
            usdcReceived,
            usdcDeposited,
            "USDC received after fees must be less than deposited"
        );
    }

    // =========================================================================
    //  Integration: buy then sell — invariants
    // =========================================================================

    function testBuyAndSellMaintainsShareSupplyInvariant() public {
        uint256 supplyBefore = initializedIndex.totalSupply();

        uint256 sharesBought = _buySharesForUser(user1, 4_000e6);
        assertGt(initializedIndex.totalSupply(), supplyBefore);

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            sharesBought,
            VALID_TOLERANCE
        );

        // After full redemption, total supply must equal the pre-buy value.
        assertEq(
            initializedIndex.totalSupply(),
            supplyBefore,
            "totalSupply must return to pre-buy value after full redeem"
        );
    }

    function testMultipleUsersBuyAndSellIndependently() public {
        uint256 shares1 = _buySharesForUser(user1, 2_000e6);
        uint256 shares2 = _buySharesForUser(user2, 6_000e6);

        assertGt(shares1, 0);
        assertGt(shares2, 0);

        // User1 sells all shares
        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            shares1,
            VALID_TOLERANCE
        );
        assertEq(
            initializedIndex.balanceOf(user1),
            0,
            "user1 shares must be 0"
        );
        assertGt(
            initializedIndex.balanceOf(user2),
            0,
            "user2 shares must remain"
        );

        // User2 sells all shares
        vm.prank(user2);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            shares2,
            VALID_TOLERANCE
        );
        assertEq(
            initializedIndex.balanceOf(user2),
            0,
            "user2 shares must be 0"
        );
    }

    function testMinMintPreviewBoundIsHonouredByActualMint() public {
        uint256 usdcAmount = 2_000e6;
        mockUsdc.mint(user1, usdcAmount);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcAmount);

        // Preview the minimum shares before the mint.
        uint256 minShares = router.getMinMintPreview(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE
        );

        vm.prank(user1);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE
        );

        uint256 actualShares = initializedIndex.balanceOf(user1);
        assertGe(
            actualShares,
            minShares,
            "actual shares must be >= preview minimum"
        );
    }

    function testMinRedeemPreviewBoundIsHonouredByActualRedeem() public {
        uint256 sharesBought = _buySharesForUser(user1, 4_000e6);

        uint256 minUsdc = router.getMinRedeemPreview(
            address(initializedIndex),
            sharesBought,
            VALID_TOLERANCE
        );

        uint256 usdcBefore = mockUsdc.balanceOf(user1);

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(initializedIndex),
            sharesBought,
            VALID_TOLERANCE
        );

        uint256 usdcReceived = mockUsdc.balanceOf(user1) - usdcBefore;
        assertGe(
            usdcReceived,
            minUsdc,
            "USDC received must be >= preview minimum"
        );
    }
}
