// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {IIndex} from "../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute} from "../../src/types.sol";
import {IRouter} from "../../src/Interface/IRouter.sol";
import {Router} from "../../src/Router.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

import "../../src/errors/RouterErrors.sol";
import "../../src/events/IndexEvents.sol";


contract RouterTest is BaseTest {

    /// Valid tolerance: 5% expressed with 4-decimal precision (5 * 100 = 500 / 10_000).
    uint256 constant VALID_TOLERANCE = 500;

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
    //  Getter functions
    // =========================================================================

    function testGetIndexManagerReturnsCorrectAddress() public view {
        assertEq(router.getIndexManager(), address(indexManager));
    }

    function testGetUsdcReturnsCorrectAddress() public view {
        assertEq(router.getUsdc(), address(mockUsdc));
    }

    // =========================================================================
    //  buyExactUsdcAmountOfShares — input validation
    // =========================================================================

    function testBuySharesRevertsIfIndexNotInitialized() public {
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(user1, usdcAmount);

        vm.prank(user1);
        mockUsdc.approve(address(nonInitializedIndex), usdcAmount);

        vm.prank(user1);
        vm.expectRevert(Router__InvalidIndexAddress.selector);
        router.buyExactUsdcAmountOfShares(
            address(nonInitializedIndex),
            usdcAmount,
            VALID_TOLERANCE
        );
    }

    function testBuySharesRevertsIfAmountIsZero() public {
        vm.prank(user1);
        vm.expectRevert(Router__InvalidAmounts.selector);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            0,
            VALID_TOLERANCE
        );
    }

    function testBuySharesRevertsIfToleranceIsZero() public {
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(user1, usdcAmount);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcAmount);

        vm.prank(user1);
        vm.expectRevert(Router__InvalidTolerance.selector);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
            0
        );
    }

    function testBuySharesRevertsIfToleranceEqualsMaxTolerance() public {
        // tolerance >= 10_000 is invalid
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(user1, usdcAmount);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcAmount);

        vm.prank(user1);
        vm.expectRevert(Router__InvalidTolerance.selector);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
            10_000
        );
    }

    function testBuySharesRevertsIfToleranceAboveMax() public {
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(user1, usdcAmount);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcAmount);

        vm.prank(user1);
        vm.expectRevert(Router__InvalidTolerance.selector);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
            10_001
        );
    }

    function testBuySharesAcceptsMaxValidTolerance() public {
        // 9_999 is the highest valid tolerance
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(user1, usdcAmount);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcAmount);

        vm.prank(user1);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
            9_999
        );
        // No revert expected
    }

    function testBuySharesAcceptsMinValidTolerance() public {
        // 1 is the minimum valid tolerance
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(user1, usdcAmount);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcAmount);

        vm.prank(user1);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
            1
        );
    }

    // =========================================================================
    //  buyExactUsdcAmountOfShares
    // =========================================================================

    function testBuySharesMintsSharesForCaller() public {
        uint256 usdcAmount = 2_000e6;
        uint256 sharesBefore = initializedIndex.balanceOf(user1);

        _buySharesForUser(user1, usdcAmount);

        assertGt(
            initializedIndex.balanceOf(user1),
            sharesBefore,
            "user1 must receive shares"
        );
    }

    function testBuySharesPullsUsdcFromCaller() public {
        uint256 usdcAmount = 2_000e6;
        mockUsdc.mint(user1, usdcAmount);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcAmount);

        uint256 usdcBefore = mockUsdc.balanceOf(user1);

        vm.prank(user1);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE
        );

        assertEq(
            mockUsdc.balanceOf(user1),
            usdcBefore - usdcAmount,
            "USDC must be pulled from user1"
        );
    }

    function testBuySharesIncreasesTotalSupply() public {
        uint256 supplyBefore = initializedIndex.totalSupply();

        _buySharesForUser(user1, 2_000e6);

        assertGt(
            initializedIndex.totalSupply(),
            supplyBefore,
            "total supply must increase after mint"
        );
    }

    function testBuySharesEmitsDepositEvent() public {
        uint256 usdcAmount = 2_000e6;
        mockUsdc.mint(user1, usdcAmount);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcAmount);

        // Deposit(address indexed user, uint256 usdcAmountIn, uint256 sharesMinted,
        //         uint256 token0Added, uint256 token1Added)
        bytes32 expectedSig = keccak256(
            "Deposit(address,uint256,uint256,uint256,uint256)"
        );

        vm.recordLogs();
        vm.prank(user1);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
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
                assertEq(userFromEvent, user1, "event must log user1 as depositor");

                (uint256 logUsdcIn, uint256 logShares, , ) = abi.decode(
                    logs[i].data,
                    (uint256, uint256, uint256, uint256)
                );
                assertEq(logUsdcIn, usdcAmount, "logged USDC amount mismatch");
                assertGt(logShares, 0, "logged shares must be > 0");
                break;
            }
        }
        assertTrue(found, "Deposit event not emitted by Index");
    }

    function testBuySharesAccruesProtocolFees() public {
        (, uint128 feesBefore) = initializedIndex.getFeesInfo();

        _buySharesForUser(user1, 2_000e6);

        (, uint128 feesAfter) = initializedIndex.getFeesInfo();
        assertGt(feesAfter, feesBefore, "protocol fees must accrue from mint");
    }

    function testTwoUsersCanBuySharesIndependently() public {
        _buySharesForUser(user1, 2_000e6);
        _buySharesForUser(user2, 4_000e6);

        assertGt(initializedIndex.balanceOf(user1), 0, "user1 must have shares");
        assertGt(initializedIndex.balanceOf(user2), 0, "user2 must have shares");
        // user2 deposited 2× more USDC  should receive more shares.
        assertGt(
            initializedIndex.balanceOf(user2),
            initializedIndex.balanceOf(user1),
            "user2 should have more shares than user1"
        );
    }

    // =========================================================================
    //  sellExactAmountOfSharesForUsdc — input validation
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

    // =========================================================================
    //  sellExactAmountOfSharesForUsdc — happy path
    // =========================================================================

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

        // Withdrawal(address indexed user, uint256 sharesBurned,
        //            uint256 token0Removed, uint256 token1Removed, uint256 usdcAmountOut)
        bytes32 expectedSig = keccak256(
            "Withdrawal(address,uint256,uint256,uint256,uint256)"
        );

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
                assertEq(userFromEvent, user1, "event must log user1 as redeemer");

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
        assertGe(feesAfterRedeem, feesBeforeRedeem, "fees must not decrease after redeem");
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
    //  getMinMintPreview
    // =========================================================================

    function testGetMinMintPreviewReturnsNonZeroForValidInputs() public view {
        uint256 usdcAmount = 1_000e6;
        uint256 minShares = router.getMinMintPreview(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE
        );
        assertGt(minShares, 0, "minShares must be > 0 for non-zero USDC amount");
    }

    function testGetMinMintPreviewDecreasesWithHigherTolerance() public view {
        uint256 usdcAmount = 1_000e6;
        uint256 minSharesLow  = router.getMinMintPreview(address(initializedIndex), usdcAmount, 100);
        uint256 minSharesHigh = router.getMinMintPreview(address(initializedIndex), usdcAmount, 1_000);

        assertGt(
            minSharesLow,
            minSharesHigh,
            "higher tolerance equal lower guaranteed min shares"
        );
    }

    function testGetMinMintPreviewIncreasesWithHigherUsdcAmount() public view {
        uint256 minSharesSmall = router.getMinMintPreview(
            address(initializedIndex),
            1_000e6,
            VALID_TOLERANCE
        );
        uint256 minSharesLarge = router.getMinMintPreview(
            address(initializedIndex),
            10_000e6,
            VALID_TOLERANCE
        );

        assertGt(
            minSharesLarge,
            minSharesSmall,
            "larger deposit equal more guaranteed min shares"
        );
    }

    function testGetMinMintPreviewRevertsIfToleranceIsZero() public {
        vm.expectRevert();
        router.getMinMintPreview(address(initializedIndex), 1_000e6, 0);
    }

    function testGetMinMintPreviewRevertsIfToleranceIsAtOrAboveMax() public {
        vm.expectRevert();
        router.getMinMintPreview(address(initializedIndex), 1_000e6, 10_000);
    }

    // =========================================================================
    //  getMinRedeemPreview
    // =========================================================================

    function testGetMinRedeemPreviewReturnsNonZeroForValidInputs() public view {
        // Use a portion of the initializer's shares.
        uint256 sharesAmount = initializedIndex.totalSupply() / 10;
        uint256 minUsdc = router.getMinRedeemPreview(
            address(initializedIndex),
            sharesAmount,
            VALID_TOLERANCE
        );
        assertGt(minUsdc, 0, "minUsdc must be > 0");
    }

    function testGetMinRedeemPreviewDecreasesWithHigherTolerance() public view {
        uint256 sharesAmount = initializedIndex.totalSupply() / 10;
        uint256 minUsdcLow  = router.getMinRedeemPreview(address(initializedIndex), sharesAmount, 100);
        uint256 minUsdcHigh = router.getMinRedeemPreview(address(initializedIndex), sharesAmount, 1_000);

        assertGt(
            minUsdcLow,
            minUsdcHigh,
            "higher tolerance equal lower guaranteed min USDC"
        );
    }

    function testGetMinRedeemPreviewIncreasesWithMoreShares() public view {
        uint256 totalShares = initializedIndex.totalSupply();
        uint256 minUsdcSmall = router.getMinRedeemPreview(
            address(initializedIndex),
            totalShares / 10,
            VALID_TOLERANCE
        );
        uint256 minUsdcLarge = router.getMinRedeemPreview(
            address(initializedIndex),
            totalShares / 2,
            VALID_TOLERANCE
        );

        assertGt(
            minUsdcLarge,
            minUsdcSmall,
            "more shares redeemed equal more USDC expected"
        );
    }

    function testGetMinRedeemPreviewRevertsIfToleranceIsZero() public {
        uint256 sharesAmount = initializedIndex.totalSupply() / 10;
        vm.expectRevert();
        router.getMinRedeemPreview(address(initializedIndex), sharesAmount, 0);
    }

    function testGetMinRedeemPreviewRevertsIfToleranceIsAtOrAboveMax() public {
        uint256 sharesAmount = initializedIndex.totalSupply() / 10;
        vm.expectRevert();
        router.getMinRedeemPreview(
            address(initializedIndex),
            sharesAmount,
            10_000
        );
    }

    // // =========================================================================
    // //  Integration: buy then sell — invariants
    // // =========================================================================

    // function testBuyAndSellMaintainsShareSupplyInvariant() public {
    //     uint256 supplyBefore = initializedIndex.totalSupply();

    //     uint256 sharesBought = _buySharesForUser(user1, 4_000e6);
    //     assertGt(initializedIndex.totalSupply(), supplyBefore);

    //     vm.prank(user1);
    //     router.sellExactAmountOfSharesForUsdc(
    //         address(initializedIndex),
    //         sharesBought,
    //         VALID_TOLERANCE
    //     );

    //     // After full redemption, total supply must equal the pre-buy value.
    //     assertEq(
    //         initializedIndex.totalSupply(),
    //         supplyBefore,
    //         "totalSupply must return to pre-buy value after full redeem"
    //     );
    // }

    // function testMultipleUsersBuyAndSellIndependently() public {
    //     uint256 shares1 = _buySharesForUser(user1, 2_000e6);
    //     uint256 shares2 = _buySharesForUser(user2, 6_000e6);

    //     assertGt(shares1, 0);
    //     assertGt(shares2, 0);

    //     // User1 sells all shares
    //     vm.prank(user1);
    //     router.sellExactAmountOfSharesForUsdc(
    //         address(initializedIndex),
    //         shares1,
    //         VALID_TOLERANCE
    //     );
    //     assertEq(initializedIndex.balanceOf(user1), 0, "user1 shares must be 0");
    //     assertGt(initializedIndex.balanceOf(user2), 0, "user2 shares must remain");

    //     // User2 sells all shares
    //     vm.prank(user2);
    //     router.sellExactAmountOfSharesForUsdc(
    //         address(initializedIndex),
    //         shares2,
    //         VALID_TOLERANCE
    //     );
    //     assertEq(initializedIndex.balanceOf(user2), 0, "user2 shares must be 0");
    // }

    // function testMinMintPreviewBoundIsHonouredByActualMint() public {
    //     uint256 usdcAmount = 2_000e6;
    //     mockUsdc.mint(user1, usdcAmount);
    //     vm.prank(user1);
    //     mockUsdc.approve(address(initializedIndex), usdcAmount);

    //     // Preview the minimum shares before the mint.
    //     uint256 minShares = router.getMinMintPreview(
    //         address(initializedIndex),
    //         usdcAmount,
    //         VALID_TOLERANCE
    //     );

    //     vm.prank(user1);
    //     router.buyExactUsdcAmountOfShares(
    //         address(initializedIndex),
    //         usdcAmount,
    //         VALID_TOLERANCE
    //     );

    //     uint256 actualShares = initializedIndex.balanceOf(user1);
    //     assertGe(
    //         actualShares,
    //         minShares,
    //         "actual shares must be >= preview minimum"
    //     );
    // }

    // function testMinRedeemPreviewBoundIsHonouredByActualRedeem() public {
    //     uint256 sharesBought = _buySharesForUser(user1, 4_000e6);

    //     uint256 minUsdc = router.getMinRedeemPreview(
    //         address(initializedIndex),
    //         sharesBought,
    //         VALID_TOLERANCE
    //     );

    //     uint256 usdcBefore = mockUsdc.balanceOf(user1);

    //     vm.prank(user1);
    //     router.sellExactAmountOfSharesForUsdc(
    //         address(initializedIndex),
    //         sharesBought,
    //         VALID_TOLERANCE
    //     );

    //     uint256 usdcReceived = mockUsdc.balanceOf(user1) - usdcBefore;
    //     assertGe(
    //         usdcReceived,
    //         minUsdc,
    //         "USDC received must be >= preview minimum"
    //     );
    // }
}
