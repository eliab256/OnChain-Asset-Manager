//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Index} from "../src/Index.sol";
import {IndexManager} from "../src/IndexManager.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
import {PriceFeedManager} from "../src/PriceFeedManager.sol";
import {HelperConfig, AssetConfig} from "./HelperConfig.s.sol";
import {HelperConfigFromDeployment} from "./HelperConfigFromDeployment.s.sol";
import {DeploymentFile} from "./DeploymentFile.sol";
import {CodeConstants} from "./CodeConstants.sol";
import {AssetTokenMock} from "../test/mocks/AssetTokenMock.sol";
import {
    MockV3Aggregator
} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IndexAsset, AssetAvailable, SwapRoute} from "../src/types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IIndex} from "../src/Interface/IIndex.sol";
import {UnderlyingMath} from "../src/libraries/UnderlyingMath.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

struct RunParams {
    AssetAvailable assetA;
    AssetAvailable assetB;
    uint128 weightA;
    uint128 weightB;
    uint32 feePercentage;
    uint256 initialAssetADeposit;
    uint256 initialAssetBDeposit;
}

contract DeployAndInitNewIndex is Script, CodeConstants {
    error DeployAndInitNewIndex__DeploymentFileNotFound(string path);

    IndexManager public indexManager;
    HelperConfig public helperConfig;
    MultiSigWallet public multiSig;
    address[] public owners;
    uint256 public requiredConfirmations;

    // Set only by the CLI run() on anvil: mint the missing mock tokens to the deployer before funding the multisig.
    bool private s_mintMissingMocks;

    using SafeERC20 for IERC20;

    // Defaults of the CLI run(): WETH/WBTC 50/50, 1% fee, 1 unit of asset A deposited and asset B computed.
    string private constant DEFAULT_ASSET_A = "WETH";
    string private constant DEFAULT_ASSET_B = "WBTC";
    uint256 private constant DEFAULT_WEIGHT = 500_000;
    uint256 private constant DEFAULT_FEE_PERCENTAGE = 10_000;

    /**
     * @notice CLI entry point: creates and initializes an index on the deployment found in
     *         `deployments/<chainId>.json`.
     * @dev Reads the IndexManager and the MultiSigWallet from the deployment file and the index params
     *      from env, with defaults: INDEX_ASSET_A / INDEX_ASSET_B (WETH, WBTC, LINK or COMP; default
     *      WETH / WBTC), INDEX_WEIGHT_A / INDEX_WEIGHT_B (1_000_000 = 100%; default 50/50), INDEX_FEE
     *      (1_000_000 = 100%; default 1%), INDEX_DEPOSIT_A / INDEX_DEPOSIT_B (native decimals, 0 = computed;
     *      default 1 unit of asset A, asset B computed). On anvil it reuses the deployed mocks, refreshes
     *      their price feeds and mints to the deployer the mock tokens it lacks.
     * @return The new initialized index.
     */
    function run() external returns (Index) {
        string memory path = DeploymentFile.getPath();
        if (!vm.exists(path)) {
            revert DeployAndInitNewIndex__DeploymentFileNotFound(path);
        }
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(path);

        HelperConfig deploymentHelperConfig = new HelperConfigFromDeployment();
        RunParams memory params = _getRunParamsFromEnv(deploymentHelperConfig);

        if (block.chainid == ANVIL_CHAIN_ID) {
            s_mintMissingMocks = true;
            _refreshMockPriceFeeds(deploymentHelperConfig, params);
        }

        return
            _deployAndInitIndex(
                deploymentHelperConfig,
                vm.parseJsonAddress(json, ".indexManager"),
                vm.parseJsonAddress(json, ".multiSigWallet.address"),
                params
            );
    }

    /**
     * @notice Creates and initializes an index through the MultiSigWallet.
     * @dev Under `forge script --broadcast` it also adds the index to `deployments/<chainId>.json`.
     * @param _helperConfig The network configuration of the deployment.
     * @param _indexManager The IndexManager address.
     * @param _multiSig The MultiSigWallet address, holder of the IndexManager roles.
     * @param _params The index assets, weights, fee and initial deposits.
     * @return The new initialized index.
     */
    function run(
        HelperConfig _helperConfig,
        address _indexManager,
        address _multiSig,
        RunParams memory _params
    ) external returns (Index) {
        return
            _deployAndInitIndex(
                _helperConfig,
                _indexManager,
                _multiSig,
                _params
            );
    }

    // =========================================================================
    //  Internal helpers
    // =========================================================================

    /**
     * @notice Shared body of both run variants.
     * @param _helperConfig The network configuration of the deployment.
     * @param _indexManager The IndexManager address.
     * @param _multiSig The MultiSigWallet address.
     * @param _params The index assets, weights, fee and initial deposits.
     * @return The new initialized index.
     */
    function _deployAndInitIndex(
        HelperConfig _helperConfig,
        address _indexManager,
        address _multiSig,
        RunParams memory _params
    ) internal returns (Index) {
        helperConfig = _helperConfig;
        indexManager = IndexManager(_indexManager);
        multiSig = MultiSigWallet(payable(_multiSig));
        owners = multiSig.getOwners();
        requiredConfirmations = multiSig.getRequiredConfirmations();

        console.log("================== Deploying New Index =================");

        //  1. Create the index via MultiSig
        address newIndex = _createIndexViaMultiSig(_params);
        console.log("New Index Address:", newIndex);

        //  2. Approve tokens & initialize the index via MultiSig
        _approveAndInitializeIndex(_params, newIndex);

        console.log(
            "=============== New Index Deployed and Initialized =============="
        );

        if (DeploymentFile.shouldWrite()) {
            _recordIndex(newIndex, _params.feePercentage);
        }
        return (Index(newIndex));
    }

    function _createIndexViaMultiSig(
        RunParams memory _params
    ) internal returns (address newIndex) {
        AssetConfig memory assetAConfig = helperConfig.getActiveAssetConfig(
            _params.assetA
        );
        AssetConfig memory assetBConfig = helperConfig.getActiveAssetConfig(
            _params.assetB
        );

        // Feeds must be registered in the PriceFeedManager before createIndex.
        _registerPriceFeedIfMissing(assetAConfig);
        _registerPriceFeedIfMissing(assetBConfig);

        IndexAsset memory indexAssetA = IndexAsset({
            asset: assetAConfig.token,
            weightPercentage: _params.weightA
        });
        IndexAsset memory indexAssetB = IndexAsset({
            asset: assetBConfig.token,
            weightPercentage: _params.weightB
        });

        bytes memory createIndexData = abi.encodeCall(
            IndexManager.createIndex,
            (_params.feePercentage, indexAssetA, indexAssetB)
        );

        _submitConfirmAndExecute(address(indexManager), 0, createIndexData);

        address[] memory deployedIndexes = indexManager.getDeployedIndexes();
        newIndex = deployedIndexes[deployedIndexes.length - 1];
    }

    /**
     * @dev Registers the asset price feed in the PriceFeedManager through the MultiSig
     *      (holder of ASSET_MANAGER_ROLE) if the asset has no feed yet.
     */
    function _registerPriceFeedIfMissing(
        AssetConfig memory _assetConfig
    ) internal {
        PriceFeedManager priceFeedManager = PriceFeedManager(
            indexManager.getPriceFeedManagerAddress()
        );
        if (priceFeedManager.hasPriceFeed(_assetConfig.token)) return;

        bytes memory registerPriceFeedData = abi.encodeCall(
            PriceFeedManager.registerPriceFeed,
            (
                _assetConfig.token,
                _assetConfig.priceFeed,
                _assetConfig.priceFeedMaxDelay
            )
        );
        _submitConfirmAndExecute(
            address(priceFeedManager),
            0,
            registerPriceFeedData
        );
    }

    /**
     * @dev Computes deposits, funds the multisig with the underlying tokens,
     *      then has the multisig approve and initialize the index.
     */
    function _approveAndInitializeIndex(
        RunParams memory _params,
        address _newIndex
    ) internal {
        address token0 = Index(_newIndex).getAsset0();
        address token1 = Index(_newIndex).getAsset1();

        (
            uint256 initialAsset0Deposit,
            uint256 initialAsset1Deposit
        ) = _computeInitialDeposits(_params, token0, _newIndex);

        _fundMultiSig(token0, initialAsset0Deposit);
        _fundMultiSig(token1, initialAsset1Deposit);

        bytes memory approveAsset0Data = abi.encodeCall(
            IERC20.approve,
            (_newIndex, initialAsset0Deposit)
        );
        _submitConfirmAndExecute(token0, 0, approveAsset0Data);

        bytes memory approveAsset1Data = abi.encodeCall(
            IERC20.approve,
            (_newIndex, initialAsset1Deposit)
        );
        _submitConfirmAndExecute(token1, 0, approveAsset1Data);

        _initializeIndexViaMultiSig(_newIndex, token0, token1, initialAsset0Deposit);
    }

    /**
     * @notice Transfers an initial deposit from the deployer to the MultiSigWallet.
     * @dev When s_mintMissingMocks is set (CLI run on anvil), first mints to the deployer the
     *      shortfall of the mock token.
     * @param _token The index asset to transfer.
     * @param _amount The amount to transfer, in the native decimals of the token.
     */
    function _fundMultiSig(address _token, uint256 _amount) internal {
        address deployer = helperConfig.getActiveNetworkConfig().deployerAccount;
        vm.startBroadcast(deployer);
        if (s_mintMissingMocks) {
            uint256 balance = IERC20(_token).balanceOf(deployer);
            if (balance < _amount) {
                AssetTokenMock(_token).mint(deployer, _amount - balance);
            }
        }
        IERC20(_token).safeTransfer(address(multiSig), _amount);
        vm.stopBroadcast();
    }

    /**
     * @notice Has the MultiSigWallet initialize the index with the default swap routes.
     * @param _newIndex The index to initialize.
     * @param _token0 The index asset0.
     * @param _token1 The index asset1.
     * @param _initialAsset0Deposit The asset0 deposit, in its native decimals.
     */
    function _initializeIndexViaMultiSig(
        address _newIndex,
        address _token0,
        address _token1,
        uint256 _initialAsset0Deposit
    ) internal {
        (
            SwapRoute memory routeAsset0Usdc,
            SwapRoute memory routeAsset1Usdc,
            SwapRoute memory routeAsset0Asset1
        ) = helperConfig.getDefaultSwapRoutes(_token0, _token1);

        bytes memory initIndexData = abi.encodeCall(
            IndexManager.initializeIndex,
            (
                address(multiSig),
                _newIndex,
                _initialAsset0Deposit,
                routeAsset0Usdc,
                routeAsset1Usdc,
                routeAsset0Asset1
            )
        );

        _submitConfirmAndExecute(address(indexManager), 0, initIndexData);
    }

    /**
     * @dev Submits a tx to the MultiSig, collects the required confirmations
     *      from distinct owners, and executes it.  Each step is its own
     *      broadcast so that on a real network each owner signs independently.
     */
    function _submitConfirmAndExecute(
        address _target,
        uint256 _value,
        bytes memory _data
    ) internal {
        vm.startBroadcast(owners[0]);
        uint256 txId = multiSig.submitTransaction(_target, _value, _data);
        multiSig.confirmTransaction(txId);
        vm.stopBroadcast();

        for (uint256 i = 1; i < requiredConfirmations; i++) {
            vm.startBroadcast(owners[i]);
            multiSig.confirmTransaction(txId);
            vm.stopBroadcast();
        }

        vm.startBroadcast(owners[0]);
        multiSig.executeTransaction(txId);
        vm.stopBroadcast();
    }

    /**
     * @dev Resolves which raw deposit amount to use as token0 seed,
     *      then computes the proportional token1 amount.
     */
    function _computeInitialDeposits(
        RunParams memory _params,
        address _token0,
        address _newIndex
    ) internal view returns (uint256 asset0Deposit, uint256 asset1Deposit) {
        AssetConfig memory assetAConfig = helperConfig.getActiveAssetConfig(
            _params.assetA
        );
        if (_token0 == assetAConfig.token) {
            asset0Deposit = _params.initialAssetADeposit > 0
                ? _params.initialAssetADeposit
                : _complementaryAmount(
                    _params.initialAssetBDeposit,
                    _newIndex,
                    false
                );
        } else {
            asset0Deposit = _params.initialAssetBDeposit > 0
                ? _params.initialAssetBDeposit
                : _complementaryAmount(
                    _params.initialAssetADeposit,
                    _newIndex,
                    false
                );
        }
        asset1Deposit = _complementaryAmount(asset0Deposit, _newIndex, true);
    }

    /**
     * @dev Computes the amount of one index asset matching a known amount of the other,
     *      at the index target weights and Chainlink prices.
     * @param _amount The known amount, in the native decimals of the input asset.
     * @param _index The index whose assets, weights and prices are used.
     * @param _zeroToOne True if `_amount` is in asset0 (returns asset1), false if it is in asset1 (returns asset0).
     * @return The required amount of the other asset, in its native decimals.
     */
    function _complementaryAmount(
        uint256 _amount,
        address _index,
        bool _zeroToOne
    ) internal view returns (uint256) {
        address assetIn;
        address assetOut;
        uint128 weightIn;
        uint128 weightOut;
        {
            address asset0 = IIndex(_index).getAsset0();
            address asset1 = IIndex(_index).getAsset1();
            (uint128 weight0, uint128 weight1) = IIndex(_index)
                .getAssetsWeights();
            (assetIn, assetOut, weightIn, weightOut) = _zeroToOne
                ? (asset0, asset1, weight0, weight1)
                : (asset1, asset0, weight1, weight0);
        }
        PriceFeedManager priceFeedManager = PriceFeedManager(
            indexManager.getPriceFeedManagerAddress()
        );
        uint256 priceIn = priceFeedManager.getPrice(assetIn);
        uint256 priceOut = priceFeedManager.getPrice(assetOut);
        return
            UnderlyingMath.calculateComplementaryAssetAmount(
                _amount,
                priceIn,
                priceOut,
                IERC20Metadata(assetIn).decimals(),
                IERC20Metadata(assetOut).decimals(),
                weightIn,
                weightOut
            );
    }

    // =========================================================================
    //  CLI helpers
    // =========================================================================

    /**
     * @notice Builds the index params of the CLI run() from env vars and defaults.
     * @dev Unless INDEX_DEPOSIT_B is set, INDEX_DEPOSIT_A defaults to 1 unit of asset A
     *      (10 ** decimals). If both deposits are set, the one of asset0 is used and the other computed.
     * @param _helperConfig The network configuration, used to resolve the asset A token decimals.
     * @return The index params.
     */
    function _getRunParamsFromEnv(
        HelperConfig _helperConfig
    ) internal view returns (RunParams memory) {
        AssetAvailable assetA = _helperConfig.getAssetBySymbol(
            vm.envOr("INDEX_ASSET_A", string(DEFAULT_ASSET_A))
        );
        AssetAvailable assetB = _helperConfig.getAssetBySymbol(
            vm.envOr("INDEX_ASSET_B", string(DEFAULT_ASSET_B))
        );

        uint256 depositB = vm.envOr("INDEX_DEPOSIT_B", uint256(0));
        uint256 defaultDepositA = depositB == 0
            ? 10 **
                uint256(
                    IERC20Metadata(
                        _helperConfig.getActiveAssetConfig(assetA).token
                    ).decimals()
                )
            : 0;

        return
            RunParams({
                assetA: assetA,
                assetB: assetB,
                weightA: SafeCast.toUint128(
                    vm.envOr("INDEX_WEIGHT_A", DEFAULT_WEIGHT)
                ),
                weightB: SafeCast.toUint128(
                    vm.envOr("INDEX_WEIGHT_B", DEFAULT_WEIGHT)
                ),
                feePercentage: SafeCast.toUint32(
                    vm.envOr("INDEX_FEE", DEFAULT_FEE_PERCENTAGE)
                ),
                initialAssetADeposit: vm.envOr(
                    "INDEX_DEPOSIT_A",
                    defaultDepositA
                ),
                initialAssetBDeposit: depositB
            });
    }

    /**
     * @notice Re-publishes the current answer of the USDC and index asset mock feeds on anvil.
     * @dev Mock answers are only updated at deploy time, so on a long-running anvil node they would
     *      go stale (asset max delay 1h15m) and the PriceFeedManager would reject them.
     * @param _helperConfig The anvil network configuration.
     * @param _params The index params, whose assets select the feeds to refresh.
     */
    function _refreshMockPriceFeeds(
        HelperConfig _helperConfig,
        RunParams memory _params
    ) internal {
        MockV3Aggregator usdcFeed = MockV3Aggregator(
            _helperConfig.getActiveNetworkConfig().usdcPriceFeedAddress
        );
        MockV3Aggregator feedA = MockV3Aggregator(
            _helperConfig.getActiveAssetConfig(_params.assetA).priceFeed
        );
        MockV3Aggregator feedB = MockV3Aggregator(
            _helperConfig.getActiveAssetConfig(_params.assetB).priceFeed
        );

        vm.startBroadcast(
            _helperConfig.getActiveNetworkConfig().deployerAccount
        );
        usdcFeed.updateAnswer(usdcFeed.latestAnswer());
        feedA.updateAnswer(feedA.latestAnswer());
        feedB.updateAnswer(feedB.latestAnswer());
        vm.stopBroadcast();
    }

    /**
     * @notice Adds the new index to `deployments/<chainId>.json` under `indexes`, keyed by its address.
     * @dev Only the `.indexes.<address>` key is written, so other indexes and fields are preserved.
     *      If the file does not exist yet, a minimal one with `chainId` and empty `indexes` is created.
     *      `block` is the block number seen by the script, a lower bound of the creation block.
     * @param _index The new index.
     * @param _feePercentage The index fee percentage (1_000_000 = 100%).
     */
    function _recordIndex(address _index, uint32 _feePercentage) internal {
        string memory path = DeploymentFile.getPath();
        if (!vm.exists(path)) {
            string memory baseKey = "deploymentBase";
            vm.serializeJson(baseKey, "{}");
            vm.serializeUint(baseKey, "chainId", block.chainid);
            vm.createDir(DeploymentFile.DIRECTORY, true);
            vm.writeJson(vm.serializeString(baseKey, "indexes", "{}"), path);
        }

        (uint128 weight0, uint128 weight1) = IIndex(_index).getAssetsWeights();
        string memory key = "index";
        vm.serializeJson(key, "{}");
        vm.serializeAddress(key, "asset0", IIndex(_index).getAsset0());
        vm.serializeAddress(key, "asset1", IIndex(_index).getAsset1());
        vm.serializeUint(key, "weight0", weight0);
        vm.serializeUint(key, "weight1", weight1);
        vm.serializeUint(key, "feePercentage", _feePercentage);
        string memory entry = vm.serializeUint(key, "block", block.number);

        vm.writeJson(
            entry,
            path,
            string.concat(".indexes.", vm.toString(_index))
        );
        console.log("Index added to deployment file:", path);
    }
}
