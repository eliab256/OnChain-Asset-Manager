//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UniversalRouterMock} from "../../mocks/UniversalRouterMock.sol";

import "../../../src/errors/IndexErrors.sol";
import "../../../src/events/IndexEvents.sol";

/**
 * @dev Event-only tests for the Index after the event refactor:
 *      SharesMinted / SharesBurned / IndexInitialized payloads, executeWeightUpdate
 *      log ordering (WeightsUpdated -> IndexRebalanced / Skipped / Failed) and the
 *      WeightsUpdateCancelled emitted when proposeUpdateWeights overwrites a proposal.
 */
contract IndexEventsTest is BaseTest {
    // =========================================================================
    //  Types
    // =========================================================================

    /// @dev Decoded SharesMinted / SharesBurned payload (same layout for both events).
    struct SharesEvent {
        bool found;
        address user;
        uint256 shares;
        uint256 asset0Amount;
        uint256 asset1Amount;
        uint256 usdcAmount;
        uint256 feeAmount;
    }

    /// @dev Snapshot of the Index / user state touched by mint and redeem.
    struct IndexSnapshot {
        uint256 userShares;
        uint256 userUsdc;
        uint256 indexUsdc;
        uint128 reserve0;
        uint128 reserve1;
        uint128 totalFees;
    }

    // =========================================================================
    //  Constants
    // =========================================================================

    /// USDC deposited in the mint / redeem event tests (6 decimals)
    uint256 constant MINT_USDC_AMOUNT = 1_000e6;

    // =========================================================================
    //  Values derived from the contracts
    // =========================================================================

    uint32 internal s_feePercentage;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();
        (s_feePercentage, ) = initializedIndex.getFeesInfo();
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _snapshot(
        address _user
    ) internal view returns (IndexSnapshot memory snap) {
        snap.userShares = initializedIndex.balanceOf(_user);
        snap.userUsdc = mockUsdc.balanceOf(_user);
        snap.indexUsdc = mockUsdc.balanceOf(address(initializedIndex));
        (snap.reserve0, snap.reserve1) = initializedIndex.getAssetsReserves();
        (, snap.totalFees) = initializedIndex.getFeesInfo();
    }

    function _decodeSharesEvent(
        Vm.Log[] memory _logs,
        bytes32 _sig
    ) internal view returns (SharesEvent memory ev) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (
                _logs[i].emitter != address(initializedIndex) ||
                _logs[i].topics[0] != _sig
            ) continue;

            ev.found = true;
            ev.user = address(uint160(uint256(_logs[i].topics[1])));
            (
                ev.shares,
                ev.asset0Amount,
                ev.asset1Amount,
                ev.usdcAmount,
                ev.feeAmount
            ) = abi.decode(
                _logs[i].data,
                (uint256, uint256, uint256, uint256, uint256)
            );
            break;
        }
    }

    /// @dev Returns how many logs from `_emitter` match `_sig` and the position of the first one.
    function _findLogs(
        Vm.Log[] memory _logs,
        address _emitter,
        bytes32 _sig
    ) internal pure returns (uint256 count, uint256 firstIndex) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (_logs[i].emitter != _emitter || _logs[i].topics[0] != _sig)
                continue;
            if (count == 0) firstIndex = i;
            count++;
        }
    }

    /// @dev Proposes `_newWeight0` as the IndexManager and returns executableAt.
    function _proposeWeights(
        uint128 _newWeight0
    ) internal returns (uint256 executableAt) {
        vm.prank(address(indexManager));
        executableAt = initializedIndex.proposeUpdateWeights(_newWeight0);
    }

    /// @dev Proposes `_newWeight0`, warps past the delay and refreshes the feeds.
    function _proposeAndWarpToExecutable(uint128 _newWeight0) internal {
        uint256 executableAt = _proposeWeights(_newWeight0);
        vm.warp(executableAt + 1 hours);
        _refreshPriceFeeds();
    }

    function _executeWeightUpdateAndRecord()
        internal
        returns (Vm.Log[] memory logs)
    {
        vm.recordLogs();
        vm.prank(address(indexManager));
        initializedIndex.executeWeightUpdate();
        logs = vm.getRecordedLogs();
    }

    /// @dev Token pair the next rebalance swaps, based on effective vs target weight of asset0.
    function _rebalanceSwapDirection(
        uint128 _targetWeight0
    ) internal view returns (address tokenIn, address tokenOut) {
        (uint128 effectiveWeight0, ) = initializedIndex
            .getAssetsEffectiveWeights();
        if (effectiveWeight0 > _targetWeight0)
            return (initializedToken0, initializedToken1);
        return (initializedToken1, initializedToken0);
    }

    /// @dev Overwrites the pending `_oldPending0` proposal with `_newWeight0` and checks the logs.
    function _assertOverwriteEmitsCancelledFirst(
        uint128 _oldPending0,
        uint128 _newWeight0
    ) internal {
        (uint128 currentWeight0, uint128 currentWeight1) = initializedIndex
            .getAssetsWeights();

        vm.recordLogs();
        uint256 newExecutableAt = _proposeWeights(_newWeight0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 cancelledCount, uint256 cancelledIndex) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateCancelled.selector
        );
        (uint256 proposedCount, uint256 proposedIndex) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateProposed.selector
        );

        assertEq(cancelledCount, 1, "WeightsUpdateCancelled must be emitted once");
        assertEq(proposedCount, 1, "WeightsUpdateProposed must be emitted once");
        assertLt(
            cancelledIndex,
            proposedIndex,
            "WeightsUpdateCancelled must be emitted before WeightsUpdateProposed"
        );

        (uint128 cancelled0, uint128 cancelled1) = abi.decode(
            logs[cancelledIndex].data,
            (uint128, uint128)
        );
        assertEq(cancelled0, _oldPending0, "cancelled weight0 mismatch");
        assertEq(
            cancelled1,
            MAX_WEIGHT - _oldPending0,
            "cancelled weight1 mismatch"
        );

        assertEq(
            logs[proposedIndex].data,
            abi.encode(
                currentWeight0,
                currentWeight1,
                _newWeight0,
                MAX_WEIGHT - _newWeight0,
                newExecutableAt
            ),
            "WeightsUpdateProposed payload mismatch"
        );
    }

    // =========================================================================
    //  initialize — IndexInitialized
    // =========================================================================

    function testInitializeEventCarriesDepositorAndAmounts() public {
        (uint8 decimals0, , ) = nonInitializedIndex.getAssetsAndUsdcDecimals();
        uint256 initAmount = 1 * 10 ** decimals0;

        vm.startPrank(user1);
        IERC20(nonInitializedToken0).approve(
            address(nonInitializedIndex),
            type(uint256).max
        );
        IERC20(nonInitializedToken1).approve(
            address(nonInitializedIndex),
            type(uint256).max
        );
        vm.stopPrank();

        uint256 balance0Before = IERC20(nonInitializedToken0).balanceOf(user1);
        uint256 balance1Before = IERC20(nonInitializedToken1).balanceOf(user1);

        vm.recordLogs();
        vm.prank(address(indexManager));
        nonInitializedIndex.initialize(user1, initAmount);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(nonInitializedIndex) ||
                logs[i].topics[0] != IndexInitialized.selector
            ) continue;

            eventFound = true;
            address depositor = address(uint160(uint256(logs[i].topics[1])));
            assertEq(depositor, user1, "event must log the depositor");
            assertTrue(
                depositor != address(indexManager),
                "event must not log the IndexManager as depositor"
            );

            (
                uint256 asset0Amount,
                uint256 asset1Amount,
                uint256 asset0UsdValue,
                uint256 asset1UsdValue,
                uint256 sharesMinted
            ) = abi.decode(
                    logs[i].data,
                    (uint256, uint256, uint256, uint256, uint256)
                );

            (uint128 reserve0, uint128 reserve1) = nonInitializedIndex
                .getAssetsReserves();
            assertEq(asset0Amount, initAmount, "asset0 amount mismatch");
            assertEq(
                asset0Amount,
                balance0Before - IERC20(nonInitializedToken0).balanceOf(user1),
                "asset0 amount must equal what the depositor paid"
            );
            assertEq(
                asset1Amount,
                balance1Before - IERC20(nonInitializedToken1).balanceOf(user1),
                "asset1 amount must equal what the depositor paid"
            );
            assertEq(asset0Amount, reserve0, "asset0 amount must equal reserve0");
            assertEq(asset1Amount, reserve1, "asset1 amount must equal reserve1");
            assertEq(
                sharesMinted,
                nonInitializedIndex.balanceOf(user1),
                "shares must be minted to the depositor"
            );
            assertEq(
                sharesMinted,
                nonInitializedIndex.totalSupply(),
                "initial shares must equal total supply"
            );
            assertEq(
                asset0UsdValue + asset1UsdValue,
                sharesMinted,
                "initial shares must equal the deposited USD value"
            );
            break;
        }
        assertTrue(eventFound, "IndexInitialized event was not emitted");
    }

    // =========================================================================
    //  mintShares — SharesMinted
    // =========================================================================

    function testMintSharesEventFeeAmountEqualsTotalFeesDelta() public {
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), MINT_USDC_AMOUNT);

        IndexSnapshot memory before = _snapshot(user1);

        vm.recordLogs();
        vm.prank(address(router));
        initializedIndex.mintShares(user1, MINT_USDC_AMOUNT, VALID_TOLERANCE);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        IndexSnapshot memory afterMint = _snapshot(user1);
        SharesEvent memory ev = _decodeSharesEvent(
            logs,
            SharesMinted.selector
        );

        assertTrue(ev.found, "SharesMinted event was not emitted");
        assertEq(ev.user, user1, "event must log user1");
        assertEq(
            ev.feeAmount,
            afterMint.totalFees - before.totalFees,
            "feeAmount must equal the s_totalFees delta"
        );
        assertEq(
            ev.feeAmount,
            (MINT_USDC_AMOUNT * s_feePercentage) / MAX_PERCENTAGE,
            "feeAmount must be the fee on the gross USDC, in USDC decimals"
        );
        assertEq(
            ev.usdcAmount,
            MINT_USDC_AMOUNT,
            "usdcAmountIn must be the gross USDC paid"
        );
        assertEq(
            ev.usdcAmount,
            before.userUsdc - afterMint.userUsdc,
            "usdcAmountIn must equal the user USDC spent"
        );
        assertEq(
            ev.shares,
            afterMint.userShares - before.userShares,
            "sharesMinted must equal the user share delta"
        );
        assertEq(
            ev.asset0Amount,
            afterMint.reserve0 - before.reserve0,
            "asset0Amount must equal the reserve0 delta"
        );
        assertEq(
            ev.asset1Amount,
            afterMint.reserve1 - before.reserve1,
            "asset1Amount must equal the reserve1 delta"
        );
    }

    // =========================================================================
    //  redeem — SharesBurned
    // =========================================================================

    function testRedeemEventFeeAmountEqualsTotalFeesDeltaAndUsdcOutIsNet()
        public
    {
        _mintSharesViaRouter(user1, MINT_USDC_AMOUNT);
        uint256 sharesToRedeem = initializedIndex.balanceOf(user1);

        IndexSnapshot memory before = _snapshot(user1);

        vm.recordLogs();
        vm.prank(address(router));
        initializedIndex.redeem(user1, sharesToRedeem, VALID_TOLERANCE);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        IndexSnapshot memory afterRedeem = _snapshot(user1);
        SharesEvent memory ev = _decodeSharesEvent(
            logs,
            SharesBurned.selector
        );

        assertTrue(ev.found, "SharesBurned event was not emitted");
        assertEq(ev.user, user1, "event must log user1");
        assertGt(ev.feeAmount, 0, "redeem must charge a fee");
        assertEq(
            ev.feeAmount,
            afterRedeem.totalFees - before.totalFees,
            "feeAmount must equal the s_totalFees delta"
        );
        assertEq(
            ev.feeAmount,
            afterRedeem.indexUsdc - before.indexUsdc,
            "feeAmount must equal the USDC retained by the index"
        );
        assertEq(
            ev.usdcAmount,
            afterRedeem.userUsdc - before.userUsdc,
            "usdcAmountOut must be the net USDC received by the user"
        );
        assertEq(
            ev.feeAmount,
            ((ev.usdcAmount + ev.feeAmount) * s_feePercentage) /
                MAX_PERCENTAGE,
            "feeAmount must be the fee on the gross USDC (net + fee)"
        );
        assertEq(ev.shares, sharesToRedeem, "sharesBurned mismatch");
        assertEq(
            ev.shares,
            before.userShares - afterRedeem.userShares,
            "sharesBurned must equal the user share delta"
        );
        assertEq(
            ev.asset0Amount,
            before.reserve0 - afterRedeem.reserve0,
            "asset0Amount must equal the reserve0 delta"
        );
        assertEq(
            ev.asset1Amount,
            before.reserve1 - afterRedeem.reserve1,
            "asset1Amount must equal the reserve1 delta"
        );
    }

    // =========================================================================
    //  executeWeightUpdate — log order and rebalance outcome
    // =========================================================================

    function testExecuteWeightUpdateEmitsWeightsUpdatedBeforeIndexRebalanced()
        public
    {
        _proposeAndWarpToExecutable(weight70);
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        _refreshExchangeRates();

        Vm.Log[] memory logs = _executeWeightUpdateAndRecord();

        (uint256 updatedCount, uint256 updatedIndex) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdated.selector
        );
        (uint256 rebalancedCount, uint256 rebalancedIndex) = _findLogs(
            logs,
            address(initializedIndex),
            IndexRebalanced.selector
        );
        (uint256 skippedCount, ) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateRebalanceSkipped.selector
        );
        (uint256 failedCount, ) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateRebalanceFailed.selector
        );

        assertEq(updatedCount, 1, "WeightsUpdated must be emitted once");
        assertEq(rebalancedCount, 1, "IndexRebalanced must be emitted once");
        assertEq(skippedCount, 0, "rebalance must not be skipped");
        assertEq(failedCount, 0, "rebalance must not fail");
        assertLt(
            updatedIndex,
            rebalancedIndex,
            "WeightsUpdated must be emitted before IndexRebalanced"
        );

        (uint128 weight0FromEvent, uint128 weight1FromEvent) = abi.decode(
            logs[updatedIndex].data,
            (uint128, uint128)
        );
        assertEq(weight0FromEvent, weight70, "logged weight0 mismatch");
        assertEq(
            weight1FromEvent,
            MAX_WEIGHT - weight70,
            "logged weight1 mismatch"
        );
    }

    function testExecuteWeightUpdateEmitsRebalanceSkippedWhenNotNeeded()
        public
    {
        // Move the effective weights, then propose them as the new target so
        // that the post-update rebalance is not needed.
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        (uint128 effectiveWeight0, ) = initializedIndex
            .getAssetsEffectiveWeights();
        _proposeAndWarpToExecutable(effectiveWeight0);
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);

        Vm.Log[] memory logs = _executeWeightUpdateAndRecord();

        (uint256 updatedCount, uint256 updatedIndex) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdated.selector
        );
        (uint256 skippedCount, uint256 skippedIndex) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateRebalanceSkipped.selector
        );
        (uint256 failedCount, ) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateRebalanceFailed.selector
        );
        (uint256 rebalancedCount, ) = _findLogs(
            logs,
            address(initializedIndex),
            IndexRebalanced.selector
        );

        assertEq(updatedCount, 1, "WeightsUpdated must be emitted once");
        assertEq(
            skippedCount,
            1,
            "WeightsUpdateRebalanceSkipped must be emitted once"
        );
        assertEq(
            failedCount,
            0,
            "WeightsUpdateRebalanceFailed must not be emitted for RebalanceNotNeeded"
        );
        assertEq(rebalancedCount, 0, "IndexRebalanced must not be emitted");
        assertLt(
            updatedIndex,
            skippedIndex,
            "WeightsUpdated must be emitted before WeightsUpdateRebalanceSkipped"
        );
        assertEq(
            logs[skippedIndex].topics.length,
            1,
            "WeightsUpdateRebalanceSkipped has no indexed params"
        );
        assertEq(
            logs[skippedIndex].data.length,
            0,
            "WeightsUpdateRebalanceSkipped has no data"
        );
    }

    function testExecuteWeightUpdateEmitsRebalanceFailedWithRawCustomError()
        public
    {
        _proposeAndWarpToExecutable(weight70);
        _updatePriceFeedsWithNewPrices(0, 0, WBTC_INITIAL_PRICE * 2, 0);
        _refreshExchangeRates();

        // Remove the rate of the pair the rebalance needs: the router reverts with
        // a custom error carrying arguments.
        (address tokenIn, address tokenOut) = _rebalanceSwapDirection(
            weight70
        );
        mockUniRouter.setExchangeRate(tokenIn, tokenOut, 0);
        bytes memory expectedReason = abi.encodeWithSelector(
            UniversalRouterMock.UniversalRouterMock__RateNotSet.selector,
            tokenIn,
            tokenOut
        );

        (uint128 reserve0Before, uint128 reserve1Before) = initializedIndex
            .getAssetsReserves();

        Vm.Log[] memory logs = _executeWeightUpdateAndRecord();

        (uint256 updatedCount, uint256 updatedIndex) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdated.selector
        );
        (uint256 failedCount, uint256 failedIndex) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateRebalanceFailed.selector
        );
        (uint256 skippedCount, ) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateRebalanceSkipped.selector
        );

        assertEq(updatedCount, 1, "WeightsUpdated must be emitted once");
        assertEq(
            failedCount,
            1,
            "WeightsUpdateRebalanceFailed must be emitted once"
        );
        assertEq(skippedCount, 0, "rebalance must not be reported as skipped");
        assertLt(
            updatedIndex,
            failedIndex,
            "WeightsUpdated must be emitted before WeightsUpdateRebalanceFailed"
        );
        assertEq(
            abi.decode(logs[failedIndex].data, (bytes)),
            expectedReason,
            "reasonData must be the raw custom error (selector + args)"
        );

        (uint128 weight0, ) = initializedIndex.getAssetsWeights();
        assertEq(weight0, weight70, "weights must still be updated");
        (uint128 reserve0After, uint128 reserve1After) = initializedIndex
            .getAssetsReserves();
        assertEq(reserve0After, reserve0Before, "reserve0 must not change");
        assertEq(reserve1After, reserve1Before, "reserve1 must not change");
    }

    // =========================================================================
    //  proposeUpdateWeights — WeightsUpdateCancelled on overwrite
    // =========================================================================

    function testProposeUpdateWeightsFirstProposalDoesNotEmitCancelled()
        public
    {
        vm.recordLogs();
        _proposeWeights(weight70);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 cancelledCount, ) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateCancelled.selector
        );
        (uint256 proposedCount, ) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateProposed.selector
        );
        assertEq(cancelledCount, 0, "first proposal must not emit Cancelled");
        assertEq(proposedCount, 1, "WeightsUpdateProposed must be emitted");
    }

    function testProposeUpdateWeightsOverwritingExecutableProposalEmitsCancelledFirst()
        public
    {
        uint256 executableAt = _proposeWeights(weight70);
        vm.warp(executableAt);

        _assertOverwriteEmitsCancelledFirst(weight70, weight30);
    }

    function testProposeUpdateWeightsOverwritingExpiredProposalEmitsCancelledFirst()
        public
    {
        uint256 executableAt = _proposeWeights(weight70);
        vm.warp(executableAt + WEIGHT_UPDATE_EXECUTION_WINDOW + 1);

        _assertOverwriteEmitsCancelledFirst(weight70, weight30);
    }

    function testProposeUpdateWeightsAfterExplicitCancelDoesNotEmitCancelled()
        public
    {
        _proposeWeights(weight70);
        vm.prank(address(indexManager));
        initializedIndex.cancelWeightUpdate();

        vm.recordLogs();
        _proposeWeights(weight30);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 cancelledCount, ) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateCancelled.selector
        );
        assertEq(
            cancelledCount,
            0,
            "a cleared proposal must not be cancelled again"
        );
    }

    function testProposeUpdateWeightsAfterExecutionDoesNotEmitCancelled()
        public
    {
        _proposeAndWarpToExecutable(weight70);
        vm.prank(address(indexManager));
        initializedIndex.executeWeightUpdate();

        vm.recordLogs();
        _proposeWeights(weight30);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 cancelledCount, ) = _findLogs(
            logs,
            address(initializedIndex),
            WeightsUpdateCancelled.selector
        );
        assertEq(
            cancelledCount,
            0,
            "an executed proposal must not be reported as cancelled"
        );
    }
}
