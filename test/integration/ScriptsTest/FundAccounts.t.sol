// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FundAccounts} from "../../../script/FundAccounts.s.sol";
import {HelperConfigFromDeployment} from "../../../script/HelperConfigFromDeployment.s.sol";
import {NetworkConfig} from "../../../script/HelperConfig.s.sol";
import {DeploymentFile} from "../../../script/DeploymentFile.sol";
import {CodeConstants} from "../../../script/CodeConstants.sol";

/**
 * @dev Runs FundAccounts on the default chain 31337, which reads the committed `deployments/31337.json`.
 *      The file is only read: the mock tokens it lists are placed at its addresses with deployCodeTo,
 *      and the keepers come from HelperConfigFromDeployment, the same source the script uses.
 */
contract FundAccountsTest is Test, CodeConstants {
    FundAccounts public fundAccounts;
    address public weth;
    address public wbtc;
    address public usdc;
    address public rebalancer;
    address public feeCollector;
    address public funder;

    /// @dev KEEPER_ETH_TARGET of FundAccounts: private in the script, so mirrored here.
    uint256 internal constant KEEPER_ETH_TARGET = 10 ether;
    uint256 internal constant FUNDER_INITIAL_BALANCE = 1_000 ether;
    uint256 internal constant KEEPER_PARTIAL_BALANCE = 3 ether;
    uint256 internal constant KEEPER_ABOVE_TARGET_BALANCE = 25 ether;
    /// @dev Runtime code `PUSH0 PUSH0 REVERT`: reverts on every call, plain value transfers included.
    bytes internal constant ETH_REJECTING_CODE = hex"5f5ffd";

    function setUp() public {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(DeploymentFile.getPath());
        weth = vm.parseJsonAddress(json, ".mocks.WETH.token");
        wbtc = vm.parseJsonAddress(json, ".mocks.WBTC.token");
        usdc = vm.parseJsonAddress(json, ".config.usdc");
        deployCodeTo("AssetTokenMock.sol:AssetTokenMock", abi.encode("Wrapped Ether", "WETH", uint8(18)), weth);
        deployCodeTo("AssetTokenMock.sol:AssetTokenMock", abi.encode("Wrapped Bitcoin", "WBTC", uint8(8)), wbtc);
        deployCodeTo("USDCMock.sol:MockUSDC", usdc);

        NetworkConfig memory config = new HelperConfigFromDeployment().getActiveNetworkConfig();
        rebalancer = config.rebalancer;
        feeCollector = config.feeCollector;

        // The broadcaster the script uses with a bare vm.startBroadcast().
        vm.startBroadcast();
        (, funder,) = vm.readCallers();
        vm.stopBroadcast();
        vm.deal(funder, FUNDER_INITIAL_BALANCE);

        fundAccounts = new FundAccounts();
    }

    ////////////////////////////////////////////////////////////////////
    ///////////////////////////// keeper ETH ///////////////////////////
    ////////////////////////////////////////////////////////////////////

    function testRunFundsKeepersToTargetOnAnvil() public {
        assertEq(block.chainid, ANVIL_CHAIN_ID, "tests must run on the anvil chain id");
        assertNotEq(rebalancer, feeCollector, "anvil config must use distinct keepers");
        assertNotEq(rebalancer, funder, "the rebalancer must not be the funder");
        assertNotEq(feeCollector, funder, "the fee collector must not be the funder");
        assertEq(rebalancer.balance, 0, "rebalancer starts empty");
        assertEq(feeCollector.balance, 0, "fee collector starts empty");

        fundAccounts.run();

        assertEq(rebalancer.balance, KEEPER_ETH_TARGET, "rebalancer must hold the target");
        assertEq(feeCollector.balance, KEEPER_ETH_TARGET, "fee collector must hold the target");
        assertEq(funder.balance, FUNDER_INITIAL_BALANCE - 2 * KEEPER_ETH_TARGET, "funder must pay both shortfalls");
    }

    function testRunIsIdempotentForKeepersOnAnvil() public {
        fundAccounts.run();
        uint256 funderBalanceAfterFirstRun = funder.balance;
        assertEq(rebalancer.balance, KEEPER_ETH_TARGET, "rebalancer after the first run");
        assertEq(feeCollector.balance, KEEPER_ETH_TARGET, "fee collector after the first run");

        fundAccounts.run();

        assertEq(rebalancer.balance, KEEPER_ETH_TARGET, "rebalancer must not receive more ETH");
        assertEq(feeCollector.balance, KEEPER_ETH_TARGET, "fee collector must not receive more ETH");
        assertEq(funder.balance, funderBalanceAfterFirstRun, "second run must send no ETH");
    }

    function testRunTopsUpPartiallyFundedKeeperOnAnvil() public {
        vm.deal(rebalancer, KEEPER_PARTIAL_BALANCE);
        assertEq(rebalancer.balance, KEEPER_PARTIAL_BALANCE, "rebalancer pre-funded below target");

        fundAccounts.run();

        assertEq(rebalancer.balance, KEEPER_ETH_TARGET, "rebalancer must end exactly at the target");
        assertEq(feeCollector.balance, KEEPER_ETH_TARGET, "fee collector must hold the target");
        assertEq(
            funder.balance,
            FUNDER_INITIAL_BALANCE - (KEEPER_ETH_TARGET - KEEPER_PARTIAL_BALANCE) - KEEPER_ETH_TARGET,
            "funder must pay only the shortfalls"
        );
    }

    function testRunLeavesKeeperAboveTargetUnchangedOnAnvil() public {
        vm.deal(feeCollector, KEEPER_ABOVE_TARGET_BALANCE);
        assertGt(feeCollector.balance, KEEPER_ETH_TARGET, "fee collector pre-funded above target");

        fundAccounts.run();

        assertEq(feeCollector.balance, KEEPER_ABOVE_TARGET_BALANCE, "balance above target must not change");
        assertEq(rebalancer.balance, KEEPER_ETH_TARGET, "rebalancer must hold the target");
        assertEq(funder.balance, FUNDER_INITIAL_BALANCE - KEEPER_ETH_TARGET, "funder must pay only the rebalancer");
    }

    ////////////////////////////////////////////////////////////////////
    ///////////////////////////// reverts //////////////////////////////
    ////////////////////////////////////////////////////////////////////

    function testRunRevertsOnUnsupportedChain() public {
        vm.chainId(MAINNET_CHAIN_ID);

        vm.expectRevert(abi.encodeWithSelector(FundAccounts.FundAccounts__UnsupportedChain.selector, MAINNET_CHAIN_ID));
        fundAccounts.run();
    }

    function testRunRevertsWhenKeeperRejectsEthOnAnvil() public {
        vm.etch(rebalancer, ETH_REJECTING_CODE);

        vm.expectRevert(abi.encodeWithSelector(FundAccounts.FundAccounts__EthTransferFailed.selector, rebalancer));
        fundAccounts.run();
    }
}
