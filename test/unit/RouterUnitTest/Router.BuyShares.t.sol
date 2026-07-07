// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {IIndex} from "../../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute} from "../../../src/contracts/types.sol";
import {IRouter} from "../../../src/Interface/IRouter.sol";
import {Router} from "../../../src/contracts/periphery/Router.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

import "../../../src/errors/RouterErrors.sol";
import "../../../src/events/IndexEvents.sol";

contract RouterBuySharesTest is BaseTest {

    /// @dev Known private key used to derive a test address with vm.addr().
    ///      Using a fixed key lets us sign EIP-2612 permits with vm.sign().
    uint256 internal constant PERMIT_USER_PK =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// @dev Address derived from PERMIT_USER_PK.
    address internal permitUser;

    function setUp() public override {
        super.setUp();
        _setupMockRouterForWethWbtcIndex();
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev Builds and signs an EIP-2612 permit digest.
    ///      Returns the (v, r, s) components ready to pass to the Router.
    function _signPermit(
        address _owner,
        uint256 _ownerPk,
        address _spender,
        uint256 _value,
        uint256 _deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        uint256 nonce = mockUsdc.nonces(_owner);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                _owner,
                _spender,
                _value,
                nonce,
                _deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", mockUsdc.DOMAIN_SEPARATOR(), structHash)
        );

        (v, r, s) = vm.sign(_ownerPk, digest);
    }

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

    function testbuySharesRevertIfUSerHasNotEnoughUSDC() public {
        uint256 usdcAmount = 1_000e6;

        uint256 userBalance = mockUsdc.balanceOf(user3);
        assertEq(userBalance, 0, "user3 should start with zero USDC");

        vm.prank(user3); // user3 has no USDC
        mockUsdc.approve(address(initializedIndex), usdcAmount);

        vm.prank(user3);
        vm.expectRevert(
            abi.encodeWithSelector(
                Router__InsufficientUsdcBalance.selector,
                userBalance,
                usdcAmount
            )
        );
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE
        );
    }

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
        // tolerance >= MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION (100_000) is invalid
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(user1, usdcAmount);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcAmount);

        vm.prank(user1);
        vm.expectRevert(Router__InvalidTolerance.selector);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
            MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION
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
            MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION + 1
        );
    }

    function testBuySharesAcceptsMaxValidTolerance() public {
        // MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION - 1 is the highest valid tolerance
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(user1, usdcAmount);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcAmount);

        vm.prank(user1);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
            MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION - 1
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
                assertEq(
                    userFromEvent,
                    user1,
                    "event must log user1 as depositor"
                );

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

        assertGt(
            initializedIndex.balanceOf(user1),
            0,
            "user1 must have shares"
        );
        assertGt(
            initializedIndex.balanceOf(user2),
            0,
            "user2 must have shares"
        );
        // user2 deposited 2× more USDC  should receive more shares.
        assertGt(
            initializedIndex.balanceOf(user2),
            initializedIndex.balanceOf(user1),
            "user2 should have more shares than user1"
        );
    }

     // =========================================================================
    //  buyExactUsdcAmountOfSharesWithPermit — failure tests
    // =========================================================================

    function testBuySharesWithPermitRevertsIfIndexNotInitialized() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(nonInitializedIndex),
            usdcAmount,
            deadline
        );

        vm.prank(permitUser);
        vm.expectRevert(Router__InvalidIndexAddress.selector);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(nonInitializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );
    }

    function testBuySharesWithPermitRevertsIfAmountIsZero() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            0,
            deadline
        );

        vm.prank(permitUser);
        vm.expectRevert(Router__InvalidAmounts.selector);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            0,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );
    }

    function testBuySharesWithPermitRevertsIfToleranceIsZero() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        vm.prank(permitUser);
        vm.expectRevert(Router__InvalidTolerance.selector);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            0,
            deadline,
            v,
            r,
            s
        );
    }

    function testBuySharesWithPermitRevertsIfToleranceAboveMax() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        vm.prank(permitUser);
        vm.expectRevert(Router__InvalidTolerance.selector);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION,
            deadline,
            v,
            r,
            s
        );
    }

    function testBuySharesWithPermitRevertsIfDeadlineExpired() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        // Sign with a deadline in the past
        uint256 deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        vm.prank(permitUser);
        vm.expectRevert();
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );
    }

    function testBuySharesWithPermitRevertsIfWrongSigner() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 deadline = block.timestamp + 1 hours;

        // Sign the permit with a different private key (not permitUser's key)
        uint256 wrongPk = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser, // owner claimed in the struct
            wrongPk,    // but signed by someone else
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        // msg.sender is permitUser but the signature was made with wrongPk → invalid signer
        vm.prank(permitUser);
        vm.expectRevert();
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );
    }

    function testBuySharesWithPermitRevertsIfWrongSpender() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 deadline = block.timestamp + 1 hours;

        // Permit authorises the Router instead of the Index → spender mismatch
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(router), // wrong spender
            usdcAmount,
            deadline
        );

        vm.prank(permitUser);
        vm.expectRevert();
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );
    }

    function testBuySharesWithPermitRevertsIfPermitAmountLowerThanRequested()
        public
    {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 deadline = block.timestamp + 1 hours;

        // Permit only covers half the requested amount
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount / 2, // insufficient allowance
            deadline
        );

        vm.prank(permitUser);
        vm.expectRevert();
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );
    }

    function testBuySharesWithPermitRevertsOnReplay() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 1_000e6;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        // First use: succeeds
        mockUsdc.mint(permitUser, usdcAmount);
        vm.prank(permitUser);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );

        // Second use of the same signature (replay): must revert because nonce advanced
        mockUsdc.mint(permitUser, usdcAmount);
        vm.prank(permitUser);
        vm.expectRevert();
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );
    }

    // =========================================================================
    //  buyExactUsdcAmountOfSharesWithPermit — happy path tests
    // =========================================================================

    function testBuySharesWithPermitWorks() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 2_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        uint256 sharesBefore = initializedIndex.balanceOf(permitUser);

        // No explicit approve() needed — permit handles it
        vm.prank(permitUser);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );

        assertGt(
            initializedIndex.balanceOf(permitUser),
            sharesBefore,
            "permitUser must receive shares without a prior approve"
        );
    }

    function testBuySharesWithPermitPullsUsdcFromCaller() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 2_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 usdcBefore = mockUsdc.balanceOf(permitUser);
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        vm.prank(permitUser);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );

        assertEq(
            mockUsdc.balanceOf(permitUser),
            usdcBefore - usdcAmount,
            "full USDC amount must be pulled from permitUser"
        );
    }

    function testBuySharesWithPermitMintsEqualSharesAsRegularBuy() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 2_000e6;

        // — regular buy for user1 —
        mockUsdc.mint(user1, usdcAmount);
        vm.prank(user1);
        mockUsdc.approve(address(initializedIndex), usdcAmount);
        vm.prank(user1);
        router.buyExactUsdcAmountOfShares(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE
        );
        uint256 sharesFromRegularBuy = initializedIndex.balanceOf(user1);

        // — permit buy for permitUser at same index state (same block) —
        mockUsdc.mint(permitUser, usdcAmount);
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );
        vm.prank(permitUser);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );
        uint256 sharesFromPermitBuy = initializedIndex.balanceOf(permitUser);

        // Both operations deposit the same amount → should receive the same shares
        // (minor rounding allowed due to sequential state changes)
        assertApproxEqRel(
            sharesFromPermitBuy,
            sharesFromRegularBuy,
            1e15, // 0.1% relative tolerance
            "permit buy must mint approximately the same shares as regular buy"
        );
    }

    function testBuySharesWithPermitIncreasesTotalSupply() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 2_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 supplyBefore = initializedIndex.totalSupply();
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        vm.prank(permitUser);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );

        assertGt(
            initializedIndex.totalSupply(),
            supplyBefore,
            "total supply must increase after permit mint"
        );
    }

    function testBuySharesWithPermitAccruesProtocolFees() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 2_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        (, uint128 feesBefore) = initializedIndex.getFeesInfo();
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        vm.prank(permitUser);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );

        (, uint128 feesAfter) = initializedIndex.getFeesInfo();
        assertGt(
            feesAfter,
            feesBefore,
            "protocol fees must accrue from permit mint"
        );
    }

    function testBuySharesWithPermitNonceIncrementsAfterUse() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 nonceBefore = mockUsdc.nonces(permitUser);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        vm.prank(permitUser);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
        );

        assertEq(
            mockUsdc.nonces(permitUser),
            nonceBefore + 1,
            "nonce must increment by 1 after permit is consumed"
        );
    }

    function testBuySharesWithPermitEmitsDepositEvent() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 2_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        bytes32 expectedSig = SharesMinted.selector;

        vm.recordLogs();
        vm.prank(permitUser);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            VALID_TOLERANCE,
            deadline,
            v,
            r,
            s
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
                    permitUser,
                    "event must log permitUser as depositor"
                );

                (uint256 logUsdcIn, uint256 logShares, , ) = abi.decode(
                    logs[i].data,
                    (uint256, uint256, uint256, uint256)
                );
                assertEq(logUsdcIn, usdcAmount, "logged USDC amount mismatch");
                assertGt(logShares, 0, "logged shares must be > 0");
                break;
            }
        }
        assertTrue(found, "SharesMinted event not emitted by Index");
    }

    function testBuySharesWithPermitAcceptsMaxValidTolerance() public {
        permitUser = vm.addr(PERMIT_USER_PK);
        uint256 usdcAmount = 1_000e6;
        mockUsdc.mint(permitUser, usdcAmount);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxValidTolerance = MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION - 1;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            permitUser,
            PERMIT_USER_PK,
            address(initializedIndex),
            usdcAmount,
            deadline
        );

        vm.prank(permitUser);
        router.buyExactUsdcAmountOfSharesWithPermit(
            address(initializedIndex),
            usdcAmount,
            maxValidTolerance,
            deadline,
            v,
            r,
            s
        );
        // No revert expected
    }
}
