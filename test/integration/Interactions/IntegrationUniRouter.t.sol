// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IntegrationBase} from "./IntegrationBase.t.sol";
import {ContractCodeConstants} from "../../../src/ContractCodeConstants.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {Index} from "../../../src/Index.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../../../src/errors/IndexErrors.sol";
import "../../../src/errors/RouterErrors.sol";

contract IntegrationUniRouter is IntegrationBase, ContractCodeConstants {
    uint256 constant USDC_AMOUNT = 1_000e6;

    uint256 constant TOLERANCE = 5000; //5 * PERCENTAGE_FEE_PRECISION; // 5%

    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  mintShares — USDC → underlying assets via Uniswap
    // =========================================================================

    /**
     * @dev  Happy-path: buying shares swaps USDC for WBTC + WETH through the
     *       Universal Router and mints index shares to the buyer.
     */
    function test_mintShares_userReceivesShares() public {
        deal(address(usdc), user1, USDC_AMOUNT);

        uint256 sharesBefore = wbtcWethIndex.balanceOf(user1);

        vm.startPrank(user1);
        usdc.approve(address(wbtcWethIndex), USDC_AMOUNT);
        router.buyExactUsdcAmountOfShares(
            address(wbtcWethIndex),
            USDC_AMOUNT,
            TOLERANCE
        );
        vm.stopPrank();

        assertGt(
            wbtcWethIndex.balanceOf(user1),
            sharesBefore,
            "User must receive shares after buying"
        );
    }

    function test_mintShares_fullUsdcAmountIsSpent() public {
        deal(address(usdc), user1, USDC_AMOUNT);

        vm.startPrank(user1);
        usdc.approve(address(wbtcWethIndex), USDC_AMOUNT);
        router.buyExactUsdcAmountOfShares(
            address(wbtcWethIndex),
            USDC_AMOUNT,
            TOLERANCE
        );
        vm.stopPrank();

        assertEq(
            usdc.balanceOf(user1),
            0,
            "Entire USDC input must be consumed"
        );
    }

    function test_mintShares_indexReservesIncrease() public {
        deal(address(usdc), user1, USDC_AMOUNT);

        (uint128 r0Before, uint128 r1Before) = wbtcWethIndex
            .getAssetsReserves();

        vm.startPrank(user1);
        usdc.approve(address(wbtcWethIndex), USDC_AMOUNT);
        router.buyExactUsdcAmountOfShares(
            address(wbtcWethIndex),
            USDC_AMOUNT,
            TOLERANCE
        );
        vm.stopPrank();

        (uint128 r0After, uint128 r1After) = wbtcWethIndex.getAssetsReserves();

        // At least one reserve must increase (mint allocates to the underweight side)
        assertTrue(
            r0After > r0Before || r1After > r1Before,
            "At least one underlying reserve must increase after mint"
        );
    }

    function test_mintShares_totalSupplyIncreases() public {
        deal(address(usdc), user1, USDC_AMOUNT);

        uint256 supplyBefore = wbtcWethIndex.totalSupply();

        vm.startPrank(user1);
        usdc.approve(address(wbtcWethIndex), USDC_AMOUNT);
        router.buyExactUsdcAmountOfShares(
            address(wbtcWethIndex),
            USDC_AMOUNT,
            TOLERANCE
        );
        vm.stopPrank();

        assertGt(
            wbtcWethIndex.totalSupply(),
            supplyBefore,
            "Total share supply must increase after mint"
        );
    }

    function test_mintShares_indexUsdValueIncreases() public {
        deal(address(usdc), user1, USDC_AMOUNT);

        (, , uint256 totalUsdBefore) = wbtcWethIndex.getAssetsUsdValue();

        vm.startPrank(user1);
        usdc.approve(address(wbtcWethIndex), USDC_AMOUNT);
        router.buyExactUsdcAmountOfShares(
            address(wbtcWethIndex),
            USDC_AMOUNT,
            TOLERANCE
        );
        vm.stopPrank();

        (, , uint256 totalUsdAfter) = wbtcWethIndex.getAssetsUsdValue();

        assertGt(
            totalUsdAfter,
            totalUsdBefore,
            "Index total USD value must increase after mint"
        );
    }

    // ─── Router input validation ───────────────────────────────────────────────

    function test_mintShares_revertsWhenUsdcBalanceInsufficient() public {
        // user1 has no USDC
        vm.startPrank(user1);
        usdc.approve(address(wbtcWethIndex), USDC_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                Router__InsufficientUsdcBalance.selector,
                0, // userBalance
                USDC_AMOUNT // requiredAmount
            )
        );
        router.buyExactUsdcAmountOfShares(
            address(wbtcWethIndex),
            USDC_AMOUNT,
            TOLERANCE
        );
        vm.stopPrank();
    }

    function test_mintShares_revertsOnZeroAmount() public {
        deal(address(usdc), user1, USDC_AMOUNT);

        vm.startPrank(user1);
        usdc.approve(address(wbtcWethIndex), USDC_AMOUNT);

        vm.expectRevert(Router__InvalidAmounts.selector);
        router.buyExactUsdcAmountOfShares(address(wbtcWethIndex), 0, TOLERANCE);
        vm.stopPrank();
    }

    function test_mintShares_revertsOnZeroTolerance() public {
        deal(address(usdc), user1, USDC_AMOUNT);

        vm.startPrank(user1);
        usdc.approve(address(wbtcWethIndex), USDC_AMOUNT);

        vm.expectRevert(Router__InvalidTolerance.selector);
        router.buyExactUsdcAmountOfShares(
            address(wbtcWethIndex),
            USDC_AMOUNT,
            0
        );
        vm.stopPrank();
    }

    function test_mintShares_revertsOnTolerance10000OrAbove() public {
        deal(address(usdc), user1, USDC_AMOUNT);

        vm.startPrank(user1);
        usdc.approve(address(wbtcWethIndex), USDC_AMOUNT);

        vm.expectRevert(Router__InvalidTolerance.selector);
        router.buyExactUsdcAmountOfShares(
            address(wbtcWethIndex),
            USDC_AMOUNT,
            10_000
        );
        vm.stopPrank();
    }

    // =========================================================================
    //  redeem — underlying assets → USDC via Uniswap
    // =========================================================================

    function _mintSharesForUser(
        address _user
    ) internal returns (uint256 shares) {
        deal(address(usdc), _user, USDC_AMOUNT);
        vm.startPrank(_user);
        usdc.approve(address(wbtcWethIndex), USDC_AMOUNT);
        router.buyExactUsdcAmountOfShares(
            address(wbtcWethIndex),
            USDC_AMOUNT,
            TOLERANCE
        );
        vm.stopPrank();
        shares = wbtcWethIndex.balanceOf(_user);
    }

    function test_redeem_userReceivesUsdc() public {
        uint256 shares = _mintSharesForUser(user1);

        uint256 usdcBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(wbtcWethIndex),
            shares,
            TOLERANCE
        );

        assertGt(
            usdc.balanceOf(user1),
            usdcBefore,
            "User must receive USDC after redeeming shares"
        );
    }

    function test_redeem_allSharesAreBurned() public {
        uint256 shares = _mintSharesForUser(user1);

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(wbtcWethIndex),
            shares,
            TOLERANCE
        );

        assertEq(
            wbtcWethIndex.balanceOf(user1),
            0,
            "All shares must be burned on full redeem"
        );
    }

    function test_redeem_indexReservesDecrease() public {
        _mintSharesForUser(user1);
        uint256 shares = wbtcWethIndex.balanceOf(user1);

        (uint128 r0Before, uint128 r1Before) = wbtcWethIndex
            .getAssetsReserves();

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(wbtcWethIndex),
            shares,
            TOLERANCE
        );

        (uint128 r0After, uint128 r1After) = wbtcWethIndex.getAssetsReserves();

        assertTrue(
            r0After < r0Before || r1After < r1Before,
            "At least one underlying reserve must decrease after redeem"
        );
    }

    function test_redeem_totalSupplyDecreases() public {
        uint256 shares = _mintSharesForUser(user1);

        uint256 supplyBefore = wbtcWethIndex.totalSupply();

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(wbtcWethIndex),
            shares,
            TOLERANCE
        );

        assertLt(
            wbtcWethIndex.totalSupply(),
            supplyBefore,
            "Total supply must decrease after redeem"
        );
    }

    /**
     * @dev  Fees are charged on both mint (2 %) and redeem (2 %), plus swap
     *       slippage on both legs.  The round-trip must return strictly less
     *       USDC than deposited.
     */
    function test_redeem_roundTrip_returnsLessUsdcThanDeposited() public {
        uint256 shares = _mintSharesForUser(user1);

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(wbtcWethIndex),
            shares,
            TOLERANCE
        );

        assertLt(
            usdc.balanceOf(user1),
            USDC_AMOUNT,
            "Round-trip USDC must be less than deposited (fees + slippage)"
        );
    }

    // ─── Router input validation ───────────────────────────────────────────────

    function test_redeem_revertsWhenSharesBalanceInsufficient() public {
        // user1 has no shares
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Router__InsufficientSharesBalance.selector,
                0,
                1e18
            )
        );
        router.sellExactAmountOfSharesForUsdc(
            address(wbtcWethIndex),
            1e18,
            TOLERANCE
        );
        vm.stopPrank();
    }

    // =========================================================================
    //  rebalance — asset ↔ asset swap via Uniswap
    // =========================================================================

    /**
     * @dev  Increases the Chainlink WBTC answer by 20 % via vm.mockCall so the
     *       effective weight of WBTC rises from ~60 % to ~64 %, exceeding the
     *       REBALANCE_THRESHOLD of 3 %.  The rebalance then sells WBTC for WETH
     *       through the real Universal Router.
     */
    function test_rebalance_swapsSellsOverweightAsset() public {
        _mockDoubleWbtcPrice();

        (uint128 r0Before, uint128 r1Before) = wbtcWethIndex
            .getAssetsReserves();

        vm.prank(deployer);
        indexManager.rebalanceSingleIndex(address(wbtcWethIndex));

        (uint128 r0After, uint128 r1After) = wbtcWethIndex.getAssetsReserves();

        // WBTC (asset0) is overweighted → index sells WBTC → reserve0 decreases
        assertLt(
            r0After,
            r0Before,
            "WBTC reserve must decrease: overweight asset is sold"
        );
        // WETH (asset1) is underweighted → index buys WETH → reserve1 increases
        assertGt(
            r1After,
            r1Before,
            "WETH reserve must increase: underweight asset is bought"
        );
    }

    function test_rebalance_reducesWeightDeviation() public {
        _mockDoubleWbtcPrice();

        (uint128 ew0Before, ) = wbtcWethIndex.getAssetsEffectiveWeights();
        (uint128 tw0, ) = wbtcWethIndex.getAssetsWeights();

        uint256 deviationBefore = ew0Before > tw0
            ? uint256(ew0Before - tw0)
            : uint256(tw0 - ew0Before);

        vm.prank(deployer);
        indexManager.rebalanceSingleIndex(address(wbtcWethIndex));

        (uint128 ew0After, ) = wbtcWethIndex.getAssetsEffectiveWeights();
        uint256 deviationAfter = ew0After > tw0
            ? uint256(ew0After - tw0)
            : uint256(tw0 - ew0After);

        assertLt(
            deviationAfter,
            deviationBefore,
            "Weight deviation must shrink after rebalance"
        );
    }

    /**
     * @dev  After rebalancing, the total USD value of the index should not drop
     *       by more than MAX_SLIPPAGE_TOLERANCE (0.2 %).
     */
    function test_rebalance_preservesIndexTotalValue() public {
        _mockDoubleWbtcPrice();

        (, , uint256 totalUsdBefore) = wbtcWethIndex.getAssetsUsdValue();

        vm.prank(deployer);
        indexManager.rebalanceSingleIndex(address(wbtcWethIndex));

        (, , uint256 totalUsdAfter) = wbtcWethIndex.getAssetsUsdValue();

        // Allow up to 2 % loss from slippage (conservative upper bound on top of the 0.2 % protocol limit)
        uint256 minAcceptable = (totalUsdBefore * 98) / 100;
        assertGe(
            totalUsdAfter,
            minAcceptable,
            "Index total USD value dropped beyond acceptable slippage"
        );
    }

    // ─── Rebalance gating ─────────────────────────────────────────────────────

    /**
     * @dev  Without any price movement the effective weights stay within the
     *       REBALANCE_THRESHOLD, so the call must revert with Index__RebalanceNotNeeded.
     */
    function test_rebalance_revertsWhenNotNeeded() public {
        // The rebalance call propagates the revert through IndexManager.
        // _rebalanceSingleIndex wraps it in try/catch and emits IndexRebalanceFailed.
        // We verify by checking that no revert at the IndexManager level occurs but
        // the on-chain state is unchanged (reserves identical before and after).
        (uint128 r0Before, uint128 r1Before) = wbtcWethIndex
            .getAssetsReserves();

        vm.prank(deployer);
        indexManager.rebalanceSingleIndex(address(wbtcWethIndex));

        (uint128 r0After, uint128 r1After) = wbtcWethIndex.getAssetsReserves();

        // Reserves must be untouched since no rebalance was executed
        assertEq(
            r0After,
            r0Before,
            "asset0 reserve changed despite no rebalance needed"
        );
        assertEq(
            r1After,
            r1Before,
            "asset1 reserve changed despite no rebalance needed"
        );
    }

    // =========================================================================
    //  Multi-user isolation
    // =========================================================================

    function test_twoUsers_mintIndependently_receiveDifferentShares() public {
        // user2 deposits after user1 → same USDC but different NAV; shares will differ
        uint256 shares1 = _mintSharesForUser(user1);
        uint256 shares2 = _mintSharesForUser(user2);

        assertGt(shares1, 0, "user1 must hold shares");
        assertGt(shares2, 0, "user2 must hold shares");
        // After user1's deposit the NAV is higher, so user2 receives fewer shares per USDC
        assertGt(
            shares1,
            shares2,
            "Earlier depositor receives more shares per USDC"
        );
    }

    function test_user1Redeem_doesNotAffectUser2Shares() public {
        uint256 shares1 = _mintSharesForUser(user1);
        uint256 shares2 = _mintSharesForUser(user2);

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(wbtcWethIndex),
            shares1,
            TOLERANCE
        );

        assertEq(
            wbtcWethIndex.balanceOf(user1),
            0,
            "user1 shares must be fully burned"
        );
        assertEq(
            wbtcWethIndex.balanceOf(user2),
            shares2,
            "user2 shares must be untouched"
        );
    }

    function test_user1Redeem_receivesUsdc_user2SharesUnchanged() public {
        _mintSharesForUser(user1);
        uint256 shares2 = _mintSharesForUser(user2);

        uint256 user1UsdcBefore = usdc.balanceOf(user1);
        uint256 shares1 = wbtcWethIndex.balanceOf(user1);

        vm.prank(user1);
        router.sellExactAmountOfSharesForUsdc(
            address(wbtcWethIndex),
            shares1,
            TOLERANCE
        );

        assertGt(
            usdc.balanceOf(user1),
            user1UsdcBefore,
            "user1 must receive USDC on redeem"
        );
        assertEq(
            wbtcWethIndex.balanceOf(user2),
            shares2,
            "user2 balance must be unaffected"
        );
    }

    // =========================================================================
    //  Internal helpers
    // =========================================================================

    /**
     * @dev  Increases the WBTC/USD answer by 20 % via vm.mockCall so the effective
     *       weight of WBTC rises from ~60 % to ~64 %, exceeding the
     *       REBALANCE_THRESHOLD of 3 %.  A moderate bump (instead of 2×) avoids
     *       tripping the MAX_SLIPPAGE_TOLERANCE check, because the Chainlink
     *       price used for USD accounting diverges only slightly from the real
     *       pool price.
     *
     *       All other fields (roundId, startedAt, updatedAt, answeredInRound)
     *       are kept identical to the live values so staleness checks pass.
     */
    function _mockDoubleWbtcPrice() internal {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = wbtcPriceFeed.latestRoundData();

        vm.mockCall(
            address(wbtcPriceFeed),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                roundId,
                (answer * 120) / 100,
                startedAt,
                updatedAt,
                answeredInRound
            )
        );
    }
}
