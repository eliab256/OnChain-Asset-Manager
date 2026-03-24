// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployPeriphery} from "../../../script/DeployPeriphery.s.sol";
import {
    DeployAndInitNewIndex,
    RunParams
} from "../../../script/DeployAndInitNewIndex.s.sol";
import {HelperConfig, AssetConfig} from "../../../script/HelperConfig.s.sol";
import {Router} from "../../../src/Router.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {Index} from "../../../src/Index.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {CodeConstants} from "../../../script/CodeConstants.sol";
import {ContractCodeConstants} from "../../../src/ContractCodeConstants.sol";
import {AssetAvailable} from "../../../src/types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployAndInitIndexTest is Test, CodeConstants, ContractCodeConstants {
    IndexManager public indexManager;
    Router public router;
    SwapManager public swapManager;
    HelperConfig public helperConfig;
    address public deployer;

    modifier onMainnetFork() {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        _;
    }

    function setUp() public onMainnetFork {
        DeployPeriphery mainnetDeployerPeriphery = new DeployPeriphery();
        (
            indexManager,
            router,
            helperConfig,
            swapManager,
            deployer
        ) = mainnetDeployerPeriphery.run();
    }

    function testDeployIndexOnMainnet() public {
        // ── Build RunParams for a 60/40 WETH/WBTC index ──────────────────
        uint128 weight60 = 60 * WEIGHT_PRECISION;
        uint128 weight40 = 40 * WEIGHT_PRECISION;
        uint32 feePercentage = 1 * PERCENTAGE_FEE_PRECISION; // 1%

        uint256 initialWbtcDeposit = 1 * 10 ** 8; // 1 WBTC

        RunParams memory params = RunParams({
            assetA: AssetAvailable.WETH,
            assetB: AssetAvailable.WBTC,
            weightA: weight60,
            weightB: weight40,
            feePercentage: feePercentage,
            initialAssetADeposit: 0, // computed by the script via retrieveAmountFromAmount
            initialAssetBDeposit: initialWbtcDeposit
        });

        // ── Fund deployer with WETH and WBTC on the fork ─────────────────
        deal(WETH_MAINNET, deployer, 100e18);
        deal(WBTC_MAINNET, deployer, 100e8);

        // ── Deploy and initialise the index ──────────────────────────────
        DeployAndInitNewIndex deployAndInitNewIndex = new DeployAndInitNewIndex();

        Index newIndex = deployAndInitNewIndex.run(
            helperConfig,
            address(indexManager),
            params
        );

        // ── Assertions ───────────────────────────────────────────────────
        assertTrue(
            address(newIndex) != address(0),
            "Index address must not be zero"
        );
        assertTrue(
            newIndex.getInitializationStatus(),
            "Index must be initialized"
        );
        assertTrue(
            indexManager.checkIsIndexInitialized(address(newIndex)),
            "IndexManager must see index as initialized"
        );

        // Reserves must be non-zero after initialization
        (uint128 r0, uint128 r1) = newIndex.getAssetsReserves();
        assertGt(r0, 0, "reserve0 must be > 0");
        assertGt(r1, 0, "reserve1 must be > 0");

        // Deployer must hold initial shares
        assertGt(newIndex.balanceOf(deployer), 0, "deployer must have shares");
        assertEq(
            newIndex.balanceOf(deployer),
            newIndex.totalSupply(),
            "deployer must hold all shares"
        );

        // Verify weights are set correctly
        (uint128 w0, uint128 w1) = newIndex.getAssetsWeights();
        assertEq(w0 + w1, MAX_WEIGHT, "weights must sum to MAX_WEIGHT");
    }
}
