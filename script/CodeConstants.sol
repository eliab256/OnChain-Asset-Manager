//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract CodeConstants {
    // Chain IDs
    uint256 public constant MAINNET_CHAIN_ID = 1;
    uint256 public constant ANVIL_CHAIN_ID = 31337;

    uint8 public constant PRICE_FEED_DECIMALS = 8;

    ////////////////////////////
    ////////// MAINNET /////////
    ////////////////////////////
    // Token Contracts
    address public constant WETH_MAINNET =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC_MAINNET =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WBTC_MAINNET =
        0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant LINK_MAINNET =
        0x514910771AF9Ca656af840dff83E8264EcF986CA;

    // Pricefeeds Asset/USD Contracts
    address public constant WETH_USD_PRICEFEED_MAINNET =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant USDC_USD_PRICEFEED_MAINNET =
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public constant WBTC_USD_PRICEFEED_MAINNET =
        0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address public constant LINK_USD_PRICEFEED_MAINNET =
        0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;

    // Uniswap V4 addresses
    address public constant UNISWAP_V4_UNIVERSAL_ROUTER_MAINNET =
        0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

    address public constant ANVIL_DEPLOYER =
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 constant ANVIL_DEPLOYER_PK =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
}
