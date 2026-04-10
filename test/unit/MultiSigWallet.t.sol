// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MultiSigWallet} from "../../src/MultiSigWallet.sol";
import {BaseTest} from "./Base.t.sol";
import {IIndexManager} from "../../src/IndexManager.sol";

contract MultiSigWalletTest {
    MultiSigWallet multiSigWallet;
    IIndexManager indexManager;
    address deployer;
    address owner1;
    address owner2;
    address owner3;
    address nonOwner;
}