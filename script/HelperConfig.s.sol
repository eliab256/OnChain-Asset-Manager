//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CodeConstant} from "./CodeConstant.sol";
import {Script} from "forge-std/Script.sol";
import {IndexAsset} from "../src/types.sol";

contract HelperConfig is CodeConstant, Script {
    // error HelperConfig__InvalidChainId();
    // struct NetworkConfig {
    //     address usdcAddress;
    //     address deployerAccount;
    // }
    // NetworkConfig public activeNetworkConfig;
    // /**
    //  * @notice Initializes HelperConfig and sets active network configuration based on current chain
    //  * @dev Automatically detects chain ID and loads appropriate configuration
    //  * @dev Reverts with HelperConfig__InvalidChainId if chain is not supported
    //  */
    // constructor() {
    //     if (block.chainid == SEPOLIA_CHAIN_ID) {
    //         activeNetworkConfig = getSepoliaConfig();
    //     } else if (block.chainid == ANVIL_CHAIN_ID) {
    //         activeNetworkConfig = getAnvilConfig();
    //     } else {
    //         revert HelperConfig__InvalidChainId();
    //     }
    // }
    // function getActiveNetworkConfig()
    //     public
    //     view
    //     returns (NetworkConfig memory)
    // {
    //     return activeNetworkConfig;
    // }
    // /**
    //  * @notice Returns network configuration for Sepolia testnet
    //  * @return NetworkConfig Configuration struct with Sepolia testnet parameters
    //  */
    // function getSepoliaConfig() public view returns (NetworkConfig memory) {
    //     return
    //         // NetworkConfig({
    //         //     deployerAccount: SEPOLIA_DEPLOYER_ADDRESS
    //         // });
    // }
    // /**
    //  * @notice Returns network configuration for Anvil local development network
    //  * @return NetworkConfig Configuration struct with Anvil local development network parameters
    //  */
    // function getAnvilConfig() public view returns (NetworkConfig memory) {
    //     return
    //         // NetworkConfig({
    //         //     deployerAccount: ANVIL_DEPLOYER_ADDRESS
    //         // });
    // }
    // /**
    //  * @notice Returns network configuration for a specific chain ID
    //  * @dev Allows retrieving configuration for chains other than the current one
    //  * @dev Useful for testing deployment on multiple chains
    //  * @param chainId The chain ID to get configuration for
    //  * @return NetworkConfig Configuration struct for the specified chain
    //  * @custom:throws HelperConfig__InvalidChainId if chainId is not supported
    //  */
    // function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
    //     if (chainId == SEPOLIA_CHAIN_ID) {
    //         return getSepoliaConfig();
    //     } else if (chainId == ANVIL_CHAIN_ID) {
    //         return getAnvilConfig();
    //     } else {
    //         revert HelperConfig__InvalidChainId();
    //     }
    // }
}
