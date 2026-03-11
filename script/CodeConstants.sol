//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract CodeConstants {
    // Chain IDs
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant MAINNET_CHAIN_ID = 1;
    uint256 public constant ANVIL_CHAIN_ID = 31337;

    ////////////////////////////
    ////////// SEPOLIA /////////
    ////////////////////////////
    // Token Contracts
    address public constant WETH_SEPOLIA =
        0xf531B8F309Be94191af87605CfBf600D71C2cFe0;
    address public constant USDC_SEPOLIA =
        0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address public constant WBTC_SEPOLIA =
        0xDfBBF048075D9db3c34aB34a0843bC16De8c3B3D;
    address public constant LINK_SEPOLIA =
        0x779877A7B0D9E8603169DdbD7836e478b4624789;

    // Pricefeeds Asset/USD Contracts
    address public constant WETH_USD_PRICEFEED_SEPOLIA =
        0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address public constant USDC_USD_PRICEFEED_SEPOLIA =
        0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address public constant WBTC_USD_PRICEFEED_SEPOLIA =
        0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
    address public constant LINK_USD_PRICEFEED_SEPOLIA =
        0xc59E3633BAAC79493d908e63626716e204A45EdF;

    uint8 public constant PRICE_FEED_DECIMALS = 8;

    // Uniswap V4 addresses
    address public constant UNISWAP_V4_UNIVERSAL_ROUTER_SEPOLIA =
        0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b;

    // deployer accounts
    address public constant SEPOLIA_DEPLOYER =
        0xB7bC9D74681eB832902d1B7464F695F6F9546de7;

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

    address public constant MAINNET_DEPLOYER =
        0xB7bC9D74681eB832902d1B7464F695F6F9546de7;
    // @audit-issue set deployer account with .env file
    address public constant ANVIL_DEPLOYER =
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
}
