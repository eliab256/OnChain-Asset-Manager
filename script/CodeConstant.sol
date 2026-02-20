//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract CodeConstant {
    // Chain IDs
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ANVIL_CHAIN_ID = 31337;

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
    address public constant WBTC_USD_PRICEFEED_SEPOLIA =
        0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
    address public constant LINK_USD_PRICEFEED_SEPOLIA =
        0xc59E3633BAAC79493d908e63626716e204A45EdF;
}
