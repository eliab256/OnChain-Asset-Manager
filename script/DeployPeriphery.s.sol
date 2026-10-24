//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
import {IndexManager} from "../src/IndexManager.sol";
import {IndexFactory} from "../src/IndexFactory.sol";
import {Index} from "../src/Index.sol";
import {Router} from "../src/Router.sol";
import {SwapManager} from "../src/SwapManager.sol";
import {PriceFeedManager} from "../src/PriceFeedManager.sol";
import {
    TimelockController
} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {HelperConfig, AssetConfig, NetworkConfig} from "./HelperConfig.s.sol";
import {CodeConstants} from "../script/CodeConstants.sol";
import {DeploymentFile} from "./DeploymentFile.sol";
import {AssetAvailable} from "../src/types.sol";

contract DeployPeriphery is Script, CodeConstants {
    MultiSigWallet public multiSigWallet;
    IndexManager public indexManager;
    IndexFactory public indexFactory;
    Router public router;
    HelperConfig public helperConfig;
    SwapManager public swapManager;
    PriceFeedManager public priceFeedManager;
    TimelockController public timelock;

    uint256 private s_startBlock;

    /**
     * @notice Deploys the MultiSigWallet, the TimelockController, the IndexFactory, the IndexManager
     *         and its three proxies, then hands the IndexManager roles over to the MultiSigWallet.
     * @dev Under `forge script --broadcast` it also rewrites `deployments/<chainId>.json` from scratch.
     */
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
        s_startBlock = block.number;
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

        // 3. Deploy the split-code IndexFactory, which stores the Index creation code outside the IndexManager
        indexFactory = new IndexFactory(type(Index).creationCode);

        // 3.1 Deploy IndexManager; its constructor deploys and initializes the SwapManager, PriceFeedManager and Router proxies
        //    from fresh implementations (initializers disabled), with the IndexManager as owner and the timelock as upgrader
        indexManager = new IndexManager(
            config.usdcAddress,
            config.uniswapUniversalRouter,
            address(new SwapManager()),
            address(new PriceFeedManager()),
            address(new Router()),
            address(timelock),
            address(indexFactory)
        );
        swapManager = SwapManager(indexManager.getSwapManagerAddress());
        priceFeedManager = PriceFeedManager(
            indexManager.getPriceFeedManagerAddress()
        );
        router = Router(indexManager.getRouterAddress());

        // 3.2 Register the USDC/USD feed while the deployer still holds ASSET_MANAGER_ROLE
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
            console.log("IndexFactory Address:", address(indexFactory));
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

        if (DeploymentFile.shouldWrite()) _writeDeploymentFile(config);

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

    ////////////////////////////////////////////////////////////////////
    ////////////////////////// deployment file /////////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice Writes `deployments/<chainId>.json` for a fresh deployment, replacing any previous file.
     * @dev `startBlock` is the block number at script start, a safe lower bound for an indexer.
     *      `mocks` is written only on anvil. `indexes` starts empty and is filled by DeployAndInitNewIndex.
     * @param _config The active network configuration used for the deployment.
     */
    function _writeDeploymentFile(NetworkConfig memory _config) internal {
        string memory root = "deployment";
        vm.serializeJson(root, "{}");
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeUint(root, "startBlock", s_startBlock);
        vm.serializeAddress(root, "deployer", _config.deployerAccount);
        vm.serializeString(root, "multiSigWallet", _serializeMultiSig());
        vm.serializeAddress(root, "timelock", address(timelock));
        vm.serializeAddress(root, "indexManager", address(indexManager));
        vm.serializeAddress(root, "indexFactory", address(indexFactory));
        vm.serializeString(
            root,
            "swapManager",
            _serializeProxy(
                "swapManager",
                address(swapManager),
                swapManager.getImplementation()
            )
        );
        vm.serializeString(
            root,
            "priceFeedManager",
            _serializeProxy(
                "priceFeedManager",
                address(priceFeedManager),
                priceFeedManager.getImplementation()
            )
        );
        vm.serializeString(
            root,
            "router",
            _serializeProxy(
                "router",
                address(router),
                router.getImplementation()
            )
        );
        vm.serializeString(root, "config", _serializeNetworkConfig(_config));
        if (block.chainid == ANVIL_CHAIN_ID) {
            vm.serializeString(root, "mocks", _serializeMocks());
        }
        string memory json = vm.serializeString(root, "indexes", "{}");

        vm.createDir(DeploymentFile.DIRECTORY, true);
        vm.writeJson(json, DeploymentFile.getPath());
        console.log("Deployment file written:", DeploymentFile.getPath());
    }

    /**
     * @notice Serializes the MultiSigWallet address, owners and required confirmations.
     * @return The JSON object of the `multiSigWallet` field.
     */
    function _serializeMultiSig() internal returns (string memory) {
        string memory key = "multiSigWallet";
        vm.serializeJson(key, "{}");
        vm.serializeAddress(key, "address", address(multiSigWallet));
        vm.serializeAddress(key, "owners", multiSigWallet.getOwners());
        return
            vm.serializeUint(
                key,
                "requiredConfirmations",
                multiSigWallet.getRequiredConfirmations()
            );
    }

    /**
     * @notice Serializes a UUPS proxy and its current implementation.
     * @param _key The in-memory JSON object key, unique per proxy.
     * @param _proxy The proxy address.
     * @param _implementation The implementation address behind the proxy.
     * @return The JSON object `{proxy, implementation}`.
     */
    function _serializeProxy(
        string memory _key,
        address _proxy,
        address _implementation
    ) internal returns (string memory) {
        vm.serializeJson(_key, "{}");
        vm.serializeAddress(_key, "proxy", _proxy);
        return vm.serializeAddress(_key, "implementation", _implementation);
    }

    /**
     * @notice Serializes the external addresses and accounts of the network configuration.
     * @param _config The active network configuration.
     * @return The JSON object of the `config` field.
     */
    function _serializeNetworkConfig(
        NetworkConfig memory _config
    ) internal returns (string memory) {
        string memory key = "config";
        vm.serializeJson(key, "{}");
        vm.serializeAddress(key, "usdc", _config.usdcAddress);
        vm.serializeAddress(key, "usdcPriceFeed", _config.usdcPriceFeedAddress);
        vm.serializeAddress(
            key,
            "universalRouter",
            _config.uniswapUniversalRouter
        );
        vm.serializeAddress(key, "feeCollector", _config.feeCollector);
        return vm.serializeAddress(key, "rebalancer", _config.rebalancer);
    }

    /**
     * @notice Serializes the anvil mock token and price feed of every available asset, keyed by symbol.
     * @dev Read back by HelperConfigFromDeployment to reuse the mocks in later scripts.
     * @return The JSON object of the `mocks` field.
     */
    function _serializeMocks() internal returns (string memory) {
        string memory key = "mocks";
        string memory json = vm.serializeJson(key, "{}");
        for (uint8 i = 0; i <= uint8(type(AssetAvailable).max); i++) {
            AssetAvailable asset = AssetAvailable(i);
            AssetConfig memory assetConfig = helperConfig.getActiveAssetConfig(
                asset
            );
            string memory symbol = helperConfig.getAssetSymbol(asset);
            string memory assetKey = string.concat("mock", symbol);
            vm.serializeJson(assetKey, "{}");
            vm.serializeAddress(assetKey, "token", assetConfig.token);
            json = vm.serializeString(
                key,
                symbol,
                vm.serializeAddress(
                    assetKey,
                    "priceFeed",
                    assetConfig.priceFeed
                )
            );
        }
        return json;
    }
}
