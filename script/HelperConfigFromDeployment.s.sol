//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {HelperConfig, AssetConfig, NetworkConfig} from "./HelperConfig.s.sol";
import {DeploymentFile} from "./DeploymentFile.sol";
import {AssetAvailable} from "../src/types.sol";

/**
 * @notice HelperConfig that reuses an existing deployment instead of deploying new mocks.
 * @dev On anvil it loads USDC, the asset tokens, the price feeds and the UniversalRouterMock from
 *      `deployments/<chainId>.json`, written by DeployPeriphery. On mainnet and on the mainnet fork
 *      it builds the same config as HelperConfig, which deploys nothing there.
 */
contract HelperConfigFromDeployment is HelperConfig {
    error HelperConfigFromDeployment__DeploymentFileNotFound(string path);

    /**
     * @notice Returns the anvil network configuration loaded from the deployment file.
     * @dev Overrides HelperConfig.getAnvilConfig, so no mock is deployed. Reverts with
     *      HelperConfigFromDeployment__DeploymentFileNotFound if DeployPeriphery was not broadcast first.
     * @return NetworkConfig Configuration struct pointing at the mocks already deployed on anvil.
     */
    function getAnvilConfig()
        public
        override
        returns (NetworkConfig memory)
    {
        string memory path = DeploymentFile.getPath();
        if (!vm.exists(path)) {
            revert HelperConfigFromDeployment__DeploymentFileNotFound(path);
        }
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(path);

        for (uint8 i = 0; i <= uint8(type(AssetAvailable).max); i++) {
            _registerMockAssetConfig(json, AssetAvailable(i));
        }

        return
            NetworkConfig({
                usdcAddress: vm.parseJsonAddress(json, ".config.usdc"),
                usdcPriceFeedAddress: vm.parseJsonAddress(
                    json,
                    ".config.usdcPriceFeed"
                ),
                usdcPriceFeedMaxDelay: USDC_USD_PRICEFEED_MAX_DELAY,
                uniswapUniversalRouter: vm.parseJsonAddress(
                    json,
                    ".config.universalRouter"
                ),
                deployerAccount: vm.parseJsonAddress(json, ".deployer"),
                feeCollector: vm.parseJsonAddress(json, ".config.feeCollector"),
                rebalancer: vm.parseJsonAddress(json, ".config.rebalancer"),
                multiSigOwners: vm.parseJsonAddressArray(
                    json,
                    ".multiSigWallet.owners"
                )
            });
    }

    /**
     * @notice Stores the anvil asset config of a mock read from the deployment file.
     * @param _json The content of the deployment file.
     * @param _asset The asset whose mock token and price feed are loaded from `.mocks.<SYMBOL>`.
     */
    function _registerMockAssetConfig(
        string memory _json,
        AssetAvailable _asset
    ) internal {
        string memory mockKey = string.concat(
            ".mocks.",
            getAssetSymbol(_asset)
        );
        assetConfigByChainId[_asset][ANVIL_CHAIN_ID] = AssetConfig({
            token: vm.parseJsonAddress(_json, string.concat(mockKey, ".token")),
            priceFeed: vm.parseJsonAddress(
                _json,
                string.concat(mockKey, ".priceFeed")
            ),
            priceFeedMaxDelay: ASSET_USD_PRICEFEED_MAX_DELAY
        });
    }
}
