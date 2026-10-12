//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
import {IndexManager} from "../src/IndexManager.sol";
import {Router} from "../src/Router.sol";
import {SwapManager} from "../src/SwapManager.sol";
import {PriceFeedManager} from "../src/PriceFeedManager.sol";
import {
    TimelockController
} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {HelperConfig, NetworkConfig} from "./HelperConfig.s.sol";
import {CodeConstants} from "../script/CodeConstants.sol";

contract DeployPeriphery is Script, CodeConstants {
    MultiSigWallet public multiSigWallet;
    IndexManager public indexManager;
    Router public router;
    HelperConfig public helperConfig;
    SwapManager public swapManager;
    PriceFeedManager public priceFeedManager;
    TimelockController public timelock;

    function run()
        external
        returns (
            IndexManager,
            Router,
            HelperConfig,
            SwapManager,
            MultiSigWallet,
            TimelockController,
            address deployer
        )
    {
        helperConfig = new HelperConfig();
        NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        deployer = config.deployerAccount;

        bool isAnvil = block.chainid == ANVIL_CHAIN_ID;

        vm.startBroadcast(deployer);

        console.log("============== Contracts Deployment ==============");
        // 1. Deploy MultiSigWallet and fund it with some ETH to cover transaction costs for confirmations and execution
        multiSigWallet = new MultiSigWallet(
            config.multiSigOwners,
            MULTISIG_REQUIRED_CONFIRMATIONS
        );
        address(multiSigWallet).call{value: 10 ether}("");

        // 2. Deploy the TimelockController, sole upgrader of the SwapManager, PriceFeedManager and Router proxies.
        //    The MultiSigWallet is the only proposer and executor; no admin, so the roles can change only
        //    through a timelocked operation on the timelock itself.
        address[] memory timelockMembers = new address[](1);
        timelockMembers[0] = address(multiSigWallet);
        timelock = new TimelockController(
            TIMELOCK_MIN_DELAY,
            timelockMembers,
            timelockMembers,
            address(0)
        );

        // 3. Deploy IndexManager; its constructor deploys and initializes the SwapManager, PriceFeedManager and Router proxies
        //    from fresh implementations (initializers disabled), with the IndexManager as owner and the timelock as upgrader
        indexManager = new IndexManager(
            config.usdcAddress,
            config.uniswapUniversalRouter,
            address(new SwapManager()),
            address(new PriceFeedManager()),
            address(new Router()),
            address(timelock)
        );
        swapManager = SwapManager(indexManager.getSwapManagerAddress());
        priceFeedManager = PriceFeedManager(
            indexManager.getPriceFeedManagerAddress()
        );
        router = Router(indexManager.getRouterAddress());

        // 3.1 Register the USDC/USD feed while the deployer still holds ASSET_MANAGER_ROLE
        priceFeedManager.registerPriceFeed(
            config.usdcAddress,
            config.usdcPriceFeedAddress,
            config.usdcPriceFeedMaxDelay
        );

        // 4. Transfer ownership to MultiSigWallet
        // Grant roles to the multi-sig first
        indexManager.grantRole(
            indexManager.DEFAULT_ADMIN_ROLE(),
            address(multiSigWallet)
        );
        indexManager.grantRole(
            indexManager.ASSET_MANAGER_ROLE(),
            address(multiSigWallet)
        );
        // Revoke ASSET_MANAGER_ROLE before DEFAULT_ADMIN_ROLE (revoking requires admin)
        indexManager.revokeRole(indexManager.ASSET_MANAGER_ROLE(), deployer);
        indexManager.revokeRole(indexManager.DEFAULT_ADMIN_ROLE(), deployer);

        console.log("============== Deployment Summary ==============");

        if (!isAnvil) {
            console.log("Deployer Address:", deployer);
            console.log("MultiSigWallet Address:", address(multiSigWallet));
            console.log("TimelockController (upgrader) Address:", address(timelock));
            console.log("IndexManager Address:", address(indexManager));
            console.log("SwapManager Proxy Address:", address(swapManager));
            console.log(
                "SwapManager Implementation Address:",
                swapManager.getImplementation()
            );
            console.log(
                "PriceFeedManager Proxy Address:",
                address(priceFeedManager)
            );
            console.log(
                "PriceFeedManager Implementation Address:",
                priceFeedManager.getImplementation()
            );
            console.log("Router Proxy Address:", address(router));
            console.log(
                "Router Implementation Address:",
                router.getImplementation()
            );
            console.log("Router's IndexManager:", router.getIndexManager());
            console.log(
                "IndexManager's SwapManager proxy:",
                indexManager.getSwapManagerAddress()
            );
        }

        vm.stopBroadcast();
        return (
            indexManager,
            router,
            helperConfig,
            swapManager,
            multiSigWallet,
            timelock,
            deployer
        );
    }
}
