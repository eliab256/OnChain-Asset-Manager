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


contract RouterGettersTest is BaseTest {

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

}
