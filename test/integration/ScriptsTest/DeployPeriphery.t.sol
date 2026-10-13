// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MAINNET_FORK_BLOCK} from "../ForkConstants.sol";
import {DeployPeriphery} from "../../../script/DeployPeriphery.s.sol";
import {HelperConfig, AssetConfig} from "../../../script/HelperConfig.s.sol";
import {MultiSigWallet} from "../../../src/MultiSigWallet.sol";
import {Router} from "../../../src/Router.sol";
import {IndexManager} from "../../../src/IndexManager.sol";
import {Index} from "../../../src/Index.sol";
import {SwapManager} from "../../../src/SwapManager.sol";
import {PriceFeedManager} from "../../../src/PriceFeedManager.sol";
import {FeedConfig} from "../../../src/types.sol";
import {CodeConstants} from "../../../script/CodeConstants.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    TimelockController
} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IUpgraderAuth} from "../../../src/Interface/IUpgraderAuth.sol";

contract DeployPeripheryTest is Test, CodeConstants {
    MultiSigWallet public multiSigWallet;
    IndexManager public mainnetIndexManager;
    Router public mainnetRouter;
    SwapManager public mainnetSwapManager;
    HelperConfig public isolatedHelperConfig;
    TimelockController public timelock;
    address public mainnetDeployer;

    modifier selectFork(string memory rpcAlias) {
        if (keccak256(bytes(rpcAlias)) == keccak256(bytes("mainnet"))) {
            vm.createSelectFork(vm.rpcUrl(rpcAlias), MAINNET_FORK_BLOCK);
        } else {
            vm.createSelectFork(vm.rpcUrl(rpcAlias));
        }
        _;
    }
    
    function setUp() public {
        
    }

    function testDeployPeripheryOnMainnet() public selectFork("mainnet") {
        DeployPeriphery mainnetDeployerPeriphery = new DeployPeriphery();
        (
            mainnetIndexManager,
            mainnetRouter,
            isolatedHelperConfig,
            mainnetSwapManager,
            multiSigWallet,
            timelock,
            mainnetDeployer
        ) = mainnetDeployerPeriphery.run();

        // getUsdc/getUsdcPriceFeed were removed from the IndexManager: read them from the Router and the PriceFeedManager.
        assertEq(mainnetRouter.getUsdc(), isolatedHelperConfig.getActiveNetworkConfig().usdcAddress);
        assertEq(
            PriceFeedManager(mainnetIndexManager.getPriceFeedManagerAddress())
                .getPriceFeedConfig(isolatedHelperConfig.getActiveNetworkConfig().usdcAddress)
                .feed,
            isolatedHelperConfig.getActiveNetworkConfig().usdcPriceFeedAddress
        );
        assertEq(mainnetIndexManager.getUniswapUniversalRouter(), isolatedHelperConfig.getActiveNetworkConfig().uniswapUniversalRouter);
        assertEq(mainnetIndexManager.getRouterAddress(), address(mainnetRouter));
        assertEq(mainnetIndexManager.getSwapManagerAddress(), address(mainnetSwapManager));

        // SwapManager is the ERC1967 proxy owned by the IndexManager
        assertEq(
            mainnetSwapManager.owner(),
            address(mainnetIndexManager),
            "IndexManager must own the SwapManager proxy"
        );
        address implementation = address(
            uint160(
                uint256(
                    vm.load(
                        address(mainnetSwapManager),
                        ERC1967Utils.IMPLEMENTATION_SLOT
                    )
                )
            )
        );
        assertTrue(implementation != address(0), "implementation slot must be set");
        assertTrue(
            implementation != address(mainnetSwapManager),
            "implementation must differ from the proxy"
        );
        assertTrue(implementation.code.length > 0, "implementation must have code");
        assertEq(
            mainnetSwapManager.getImplementation(),
            implementation,
            "getImplementation must match the ERC-1967 slot"
        );
    }

    function testDeployPeripheryDeploysPriceFeedManagerOnMainnet()
        public
        selectFork("mainnet")
    {
        DeployPeriphery mainnetDeployerPeriphery = new DeployPeriphery();
        (
            mainnetIndexManager,
            mainnetRouter,
            isolatedHelperConfig,
            mainnetSwapManager,
            multiSigWallet,
            timelock,
            mainnetDeployer
        ) = mainnetDeployerPeriphery.run();
        PriceFeedManager priceFeedManager = mainnetDeployerPeriphery
            .priceFeedManager();

        assertEq(
            address(priceFeedManager),
            mainnetIndexManager.getPriceFeedManagerAddress(),
            "script must expose the IndexManager PriceFeedManager proxy"
        );
        assertEq(
            priceFeedManager.owner(),
            address(mainnetIndexManager),
            "IndexManager must own the PriceFeedManager proxy"
        );

        address implementation = address(
            uint160(
                uint256(
                    vm.load(
                        address(priceFeedManager),
                        ERC1967Utils.IMPLEMENTATION_SLOT
                    )
                )
            )
        );
        assertTrue(implementation != address(0), "implementation slot must be set");
        assertTrue(
            implementation != address(priceFeedManager),
            "implementation must differ from the proxy"
        );
        assertTrue(implementation.code.length > 0, "implementation must have code");
        assertEq(
            priceFeedManager.getImplementation(),
            implementation,
            "getImplementation must match the ERC-1967 slot"
        );

        // USDC/USD feed registered by the script with USDC_USD_PRICEFEED_MAX_DELAY.
        FeedConfig memory usdcConfig = priceFeedManager.getPriceFeedConfig(
            USDC_MAINNET
        );
        assertEq(usdcConfig.feed, USDC_USD_PRICEFEED_MAINNET);
        assertEq(usdcConfig.maxDelay, USDC_USD_PRICEFEED_MAX_DELAY);
        assertTrue(priceFeedManager.hasPriceFeed(USDC_MAINNET));
        assertGt(priceFeedManager.getPrice(USDC_MAINNET), 0);

        // Asset feeds are registered later, by DeployAndInitNewIndex.
        assertFalse(priceFeedManager.hasPriceFeed(WETH_MAINNET));

        // The deployer no longer holds ASSET_MANAGER_ROLE: it cannot register feeds.
        assertFalse(
            mainnetIndexManager.hasRole(
                mainnetIndexManager.ASSET_MANAGER_ROLE(),
                mainnetDeployer
            )
        );
        assertTrue(
            mainnetIndexManager.hasRole(
                mainnetIndexManager.ASSET_MANAGER_ROLE(),
                address(multiSigWallet)
            )
        );
    }

    ////////////////////////////////////////////////////////////////////
    ////////////////////////// TimelockController //////////////////////
    ////////////////////////////////////////////////////////////////////

    function testDeployPeripheryDeploysTimelockOnMainnet()
        public
        selectFork("mainnet")
    {
        DeployPeriphery deployPeriphery = new DeployPeriphery();
        (
            mainnetIndexManager,
            mainnetRouter,
            isolatedHelperConfig,
            mainnetSwapManager,
            multiSigWallet,
            timelock,
            mainnetDeployer
        ) = deployPeriphery.run();

        _assertTimelockSetup(deployPeriphery);
    }

    function testDeployPeripheryDeploysTimelockOnAnvil() public {
        DeployPeriphery deployPeriphery = new DeployPeriphery();
        (
            mainnetIndexManager,
            mainnetRouter,
            isolatedHelperConfig,
            mainnetSwapManager,
            multiSigWallet,
            timelock,
            mainnetDeployer
        ) = deployPeriphery.run();

        _assertTimelockSetup(deployPeriphery);
    }

    /// @dev Shared assertions on the TimelockController wiring produced by DeployPeriphery.run().
    function _assertTimelockSetup(DeployPeriphery _deployPeriphery) internal view {
        assertTrue(address(timelock) != address(0), "timelock must be deployed");
        assertTrue(address(timelock).code.length > 0, "timelock must have code");
        assertEq(
            address(_deployPeriphery.timelock()),
            address(timelock),
            "script must expose the returned timelock"
        );
        assertEq(timelock.getMinDelay(), TIMELOCK_MIN_DELAY, "min delay");
        assertEq(timelock.getMinDelay(), 2 days, "min delay must be 2 days");

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        address multiSig = address(multiSigWallet);

        assertTrue(timelock.hasRole(proposerRole, multiSig), "multisig must be proposer");
        assertTrue(timelock.hasRole(executorRole, multiSig), "multisig must be executor");
        assertTrue(timelock.hasRole(cancellerRole, multiSig), "multisig must be canceller");
        assertFalse(timelock.hasRole(adminRole, multiSig), "multisig must not be timelock admin");

        assertFalse(timelock.hasRole(proposerRole, mainnetDeployer), "deployer must not be proposer");
        assertFalse(timelock.hasRole(executorRole, mainnetDeployer), "deployer must not be executor");
        assertFalse(timelock.hasRole(cancellerRole, mainnetDeployer), "deployer must not be canceller");
        assertFalse(timelock.hasRole(adminRole, mainnetDeployer), "deployer must not be timelock admin");

        // Open executor role (address(0)) must not be granted: only the multisig can execute.
        assertFalse(timelock.hasRole(executorRole, address(0)), "executor role must not be open");
        // OZ v5 grants DEFAULT_ADMIN_ROLE to the timelock itself; with admin = address(0) nobody else holds it.
        assertTrue(timelock.hasRole(adminRole, address(timelock)), "timelock must self-administer");
        assertFalse(timelock.hasRole(adminRole, address(0)), "address(0) must not be admin");
        assertFalse(
            timelock.hasRole(adminRole, address(mainnetIndexManager)),
            "IndexManager must not be timelock admin"
        );
        assertFalse(
            timelock.hasRole(adminRole, address(_deployPeriphery)),
            "script contract must not be timelock admin"
        );

        // The timelock is the only upgrader of the three proxies.
        assertEq(
            IUpgraderAuth(address(mainnetSwapManager)).getUpgrader(),
            address(timelock),
            "SwapManager upgrader"
        );
        assertEq(
            IUpgraderAuth(mainnetIndexManager.getPriceFeedManagerAddress()).getUpgrader(),
            address(timelock),
            "PriceFeedManager upgrader"
        );
        assertEq(
            IUpgraderAuth(address(mainnetRouter)).getUpgrader(),
            address(timelock),
            "Router upgrader"
        );
    }
}
