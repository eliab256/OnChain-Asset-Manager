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

contract IndexTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  deployment and constructor
    // =========================================================================
    function testIndexDeployment() public {
        (address effectiveToken0, address effectiveToken1) = indexManager
            .sortAssets(address(mockLink), address(mockWbtc));

        assertEq(nonInitializedIndex.getAsset0(), effectiveToken0);
        assertEq(nonInitializedIndex.getAsset1(), effectiveToken1);
        assertEq(effectiveToken0, address(mockWbtc));
        assertEq(effectiveToken1, address(mockLink));
        assertEq(nonInitializedIndex.getUsdc(), address(mockUsdc));
        assertEq(
            nonInitializedIndex.getAsset0PriceFeed(),
            address(mockWbtcPriceFeed)
        );
        assertEq(
            nonInitializedIndex.getAsset1PriceFeed(),
            address(mockLinkPriceFeed)
        );
        assertEq(
            nonInitializedIndex.getUsdcPriceFeed(),
            address(mockUsdcPriceFeed)
        );
        (uint128 actualWeight0, uint128 actualWeight1) = nonInitializedIndex
            .getAssetsWeights();
        assertEq(actualWeight0, weight40);
        assertEq(actualWeight1, weight60);
        (
            uint32 actualFeePercentage,
            uint128 actualTotalfees
        ) = nonInitializedIndex.getFeesInfo();
        assertEq(actualFeePercentage, validFeePercentage);
        assertEq(actualTotalfees, 0);
        (uint8 dec0, uint8 dec1, uint8 decUsdc) = nonInitializedIndex
            .getAssetsAndUsdcDecimals();
        assertEq(
            dec0,
            mockWbtc.decimals(),
            "Asset0 decimals should match the mockWbtc decimals"
        );
        assertEq(
            dec1,
            mockLink.decimals(),
            "Asset1 decimals should match the mockLink decimals"
        );
        assertEq(
            decUsdc,
            mockUsdc.decimals(),
            "USDC decimals should match the mockUsdc decimals"
        );
        assertEq(
            indexManager.checkIsIndexInitialized(address(nonInitializedIndex)),
            false
        );
    }

    // =========================================================================
    //  initialization
    // =========================================================================

    function testIndexInitializationRevertIfAlreadyInitialized() public {
        assertEq(
            indexManager.checkIsIndexInitialized(address(initializedIndex)),
            true
        );
        uint256 initAmount = 10 * 10 ** mockWeth.decimals();

        vm.expectRevert(Index__AlreadyInitialized.selector);
        vm.prank(address(indexManager));
        initializedIndex.initialize(address(deployer), initAmount);
    }

    function testInitializarionRevertIfNotCalledByIndexManager() public {
        uint256 initAmount = 10 * 10 ** mockWeth.decimals();

        bytes32 indexManagerRole = nonInitializedIndex.INDEX_MANAGER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "AccessControlUnauthorizedAccount(address,bytes32)"
                    )
                ),
                user1,
                indexManagerRole
            )
        );
        vm.prank(user1);
        nonInitializedIndex.initialize(address(deployer), initAmount);
    }

    function testInitializationRevertIfAmountIsZero() public {
        uint256 initAmount = 0;

        vm.expectRevert(Index__InvalidUnderlyingAmount.selector);
        vm.prank(address(indexManager));
        nonInitializedIndex.initialize(address(deployer), initAmount);
    }

    function testInitializationRevertIfDeployerHasInsufficientBalanceOfAsset0()
        public
    {
        uint256 initAmount = 10 * 10 ** mockWeth.decimals();
        vm.startPrank(deployer);
        mockWeth.approve(address(nonInitializedIndex), initAmount);
        mockWeth.transfer(user1, mockWeth.balanceOf(deployer));
        vm.stopPrank();
        assertEq(
            mockWeth.balanceOf(deployer),
            0,
            "Deployer should have 0 WETH balance"
        );

        vm.expectRevert();
        vm.prank(address(indexManager));
        nonInitializedIndex.initialize(address(deployer), initAmount);
    }

    function testInitializationRevertIfDeployerHasInsufficientBalanceOfAsset1()
        public
    {
        uint256 initAmount = 10 * 10 ** mockWbtc.decimals();
        vm.startPrank(deployer);
        mockWbtc.approve(address(nonInitializedIndex), initAmount);
        mockLink.transfer(user1, mockLink.balanceOf(deployer));
        vm.stopPrank();
        assertEq(
            mockLink.balanceOf(deployer),
            0,
            "Deployer should have 0 LINK balance"
        );
        assertTrue(
            mockWbtc.balanceOf(deployer) > initAmount,
            "Deployer should have sufficient WBTC balance"
        );

        vm.expectRevert();
        vm.prank(address(indexManager));
        nonInitializedIndex.initialize(address(deployer), initAmount);
    }

    function testIndexInitializationWorksAndUpdateStateCorrectly() public {
        assertEq(nonInitializedToken0, address(mockWbtc));
        assertEq(nonInitializedToken1, address(mockLink));
        assertEq(nonInitializedIndex.getInitializationStatus(), false);

        vm.startPrank(deployer);
        uint256 initAmount = 10 * 10 ** mockWbtc.decimals();
        mockWbtc.approve(address(nonInitializedIndex), initAmount);
        mockLink.approve(address(nonInitializedIndex), type(uint256).max);
        vm.stopPrank();

        vm.prank(address(indexManager));
        nonInitializedIndex.initialize(address(deployer), initAmount);

        assertEq(nonInitializedIndex.getInitializationStatus(), true);

        (uint128 reserve0, uint128 reserve1) = nonInitializedIndex
            .getAssetsReserves();
        (uint8 decimals0, uint8 decimals1, ) = nonInitializedIndex
            .getAssetsAndUsdcDecimals();

        // Reserves are now stored in token decimals
        // reserve0 should equal initAmount (token decimals)
        assertEq(
            reserve0,
            initAmount,
            "Asset0 reserve should equal initAmount in token decimals"
        );

        // Compute expected amount1 in token decimals
        uint8 multiplier0 = DECIMALS_STANDARD - decimals0;
        uint256 amount0InUsd = (initAmount *
            uint256(mockWbtcPriceFeed.latestAnswer()) *
            10 ** multiplier0) / 10 ** mockWbtcPriceFeed.decimals();

        (uint128 weight0, uint128 weight1) = nonInitializedIndex
            .getAssetsWeights();

        uint256 amount1InUsd = (amount0InUsd * weight1) / weight0;

        // amount1 in std decimals (18-dec)
        uint256 amount1InStd = (amount1InUsd *
            10 ** mockLinkPriceFeed.decimals()) /
            uint256(mockLinkPriceFeed.latestAnswer());

        // Convert from std decimals to token1 decimals
        uint256 expectedReserve1;
        if (decimals1 < DECIMALS_STANDARD) {
            expectedReserve1 =
                amount1InStd /
                (10 ** (DECIMALS_STANDARD - decimals1));
        } else {
            expectedReserve1 = amount1InStd;
        }

        assertEq(
            reserve1,
            expectedReserve1,
            "Asset1 reserve in token decimals"
        );

        uint256 expectedInitialShares = amount0InUsd + amount1InUsd;
        assertEq(
            nonInitializedIndex.balanceOf(deployer),
            nonInitializedIndex.totalSupply()
        );
        assertEq(nonInitializedIndex.totalSupply(), expectedInitialShares);
    }

    function testInitializeEmitEvent() public {
        vm.startPrank(deployer);
        uint256 initAmount = 10 * 10 ** mockWbtc.decimals();
        mockWbtc.approve(address(nonInitializedIndex), initAmount);
        mockLink.approve(address(nonInitializedIndex), type(uint256).max);
        vm.stopPrank();
        (uint8 decimals0, uint8 decimals1, ) = nonInitializedIndex
            .getAssetsAndUsdcDecimals();
        uint8 multiplier0 = DECIMALS_STANDARD - decimals0;

        uint256 amount0InUsd = (initAmount *
            uint256(mockWbtcPriceFeed.latestAnswer()) *
            10 ** multiplier0) / 10 ** mockWbtcPriceFeed.decimals();

        (uint128 weight0, uint128 weight1) = nonInitializedIndex
            .getAssetsWeights();

        uint256 amount1InUsd = (amount0InUsd * weight1) / weight0;

        // amount1 in std decimals
        uint256 amount1InStd = (amount1InUsd *
            10 ** mockLinkPriceFeed.decimals()) /
            uint256(mockLinkPriceFeed.latestAnswer());

        // Convert from std decimals to token1 decimals
        uint256 amount1TokenDec;
        if (decimals1 < DECIMALS_STANDARD) {
            amount1TokenDec =
                amount1InStd /
                (10 ** (DECIMALS_STANDARD - decimals1));
        } else {
            amount1TokenDec = amount1InStd;
        }

        uint256 expectedInitialShares = amount0InUsd + amount1InUsd;

        vm.expectEmit(true, true, true, true);
        emit IndexInitialized(
            initAmount, // token decimals, not std
            amount1TokenDec, // token decimals, not std
            amount0InUsd,
            amount1InUsd,
            expectedInitialShares
        );

        vm.prank(address(indexManager));
        nonInitializedIndex.initialize(address(deployer), initAmount);
    }

    // =========================================================================
    //  minting functions
    // =========================================================================



}
