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


contract RouterBuySharesTest is BaseTest {

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
    //  buyExactUsdcAmountOfShares 
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

        bytes32 expectedSig = SharesMinted.selector;

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

}
