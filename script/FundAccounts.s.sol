//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DeploymentFile} from "./DeploymentFile.sol";
import {CodeConstants} from "./CodeConstants.sol";
import {HelperConfigFromDeployment} from "./HelperConfigFromDeployment.s.sol";
import {NetworkConfig} from "./HelperConfig.s.sol";
import {AssetTokenMock} from "../test/mocks/AssetTokenMock.sol";

/**
 * @notice Brings the WETH, WBTC and USDC balances of a list of accounts up to a target, and the ETH
 *         balance of the keeper accounts (rebalancer and fee collector) up to a gas target, on the
 *         local anvil fork of mainnet or on a plain anvil node with the mocks deployed.
 * @dev On the fork the balance slot is found locally with forge-std stdStorage and written on the node
 *      with `anvil_setStorageAt`: no swap is made, so the WBTC/WETH pool stays aligned with the
 *      Chainlink price, and token totalSupply is not adjusted. On plain anvil the shortfall is minted
 *      on the mock tokens listed in `deployments/31337.json`. The keeper ETH, for gas, is written with
 *      `anvil_setBalance` on the fork (no transaction, so the deployer nonce and the addresses of the
 *      deployment that follows are unchanged) and sent from the broadcasting account on plain anvil.
 */
contract FundAccounts is Script, CodeConstants {
    using stdStorage for StdStorage;

    error FundAccounts__UnsupportedChain(uint256 chainId);
    error FundAccounts__DeploymentFileNotFound(string path);
    error FundAccounts__SetStorageFailed(address token);
    error FundAccounts__BalanceNotSet(address token);
    error FundAccounts__EthTransferFailed(address account);
    error FundAccounts__SetEthBalanceFailed(address account);
    error FundAccounts__EthBalanceNotSet(address account);

    uint256 private constant DEFAULT_ACCOUNT_COUNT = 10;
    uint256 private constant DEFAULT_WETH = 100;
    uint256 private constant DEFAULT_WBTC = 5;
    uint256 private constant DEFAULT_USDC = 1_000_000;
    /// @dev ETH balance, in wei, the rebalancer and the fee collector are topped up to for gas.
    uint256 private constant KEEPER_ETH_TARGET = 10 ether;

    StdStorage private s_stdstore;

    ////////////////////////////////////////////////////////////////////
    ///////////////////////////// entry point //////////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice Brings the WETH, WBTC and USDC balance of every account up to its target, and funds the
     *         keeper accounts (rebalancer and fee collector) with ETH for gas.
     * @dev Env vars: FUND_ACCOUNTS (comma-separated addresses; default the first FUND_ACCOUNT_COUNT
     *      accounts of the anvil mnemonic, FUND_ACCOUNT_COUNT default 10), and targets in whole tokens
     *      FUND_WETH (default 100), FUND_WBTC (default 5), FUND_USDC (default 1_000_000). A balance
     *      already at or above its target is left untouched, so the script is idempotent.
     *      The keeper addresses come from HelperConfigFromDeployment (on the fork the HelperConfig
     *      fork config, which reads no deployment file, so it works before the deploy; on anvil
     *      `deployments/31337.json`), and each keeper is topped up to KEEPER_ETH_TARGET wei.
     *      On FORK_CHAIN_ID token balances are written with `anvil_setStorageAt` and keeper balances
     *      with `anvil_setBalance`: no transaction is sent, so `--broadcast` is harmless and the
     *      deployer nonce is untouched. On ANVIL_CHAIN_ID the mocks are read from the deployment file,
     *      the shortfall is minted and the keeper ETH is sent from the broadcaster, all in a broadcast
     *      (`--broadcast --private-key` needed); a keeper equal to the broadcaster is skipped there.
     *      The fee collector is skipped when it equals the rebalancer.
     *      Reverts with FundAccounts__UnsupportedChain on any other chain.
     */
    function run() external {
        address[] memory accounts = _getAccounts();
        uint256 wethTarget = vm.envOr("FUND_WETH", DEFAULT_WETH);
        uint256 wbtcTarget = vm.envOr("FUND_WBTC", DEFAULT_WBTC);
        uint256 usdcTarget = vm.envOr("FUND_USDC", DEFAULT_USDC);

        if (block.chainid == FORK_CHAIN_ID) {
            // USDC is a proxy: the slot is found through the proxy, where the balances live.
            for (uint256 i = 0; i < accounts.length; i++) {
                _fundAccount(WETH_MAINNET, accounts[i], wethTarget, true);
                _fundAccount(WBTC_MAINNET, accounts[i], wbtcTarget, true);
                _fundAccount(USDC_MAINNET, accounts[i], usdcTarget, true);
            }
            _fundKeepers(_getNetworkConfig(), true);
        } else if (block.chainid == ANVIL_CHAIN_ID) {
            string memory path = DeploymentFile.getPath();
            if (!vm.exists(path)) {
                revert FundAccounts__DeploymentFileNotFound(path);
            }
            // forge-lint: disable-next-line(unsafe-cheatcode)
            string memory json = vm.readFile(path);
            address weth = vm.parseJsonAddress(json, ".mocks.WETH.token");
            address wbtc = vm.parseJsonAddress(json, ".mocks.WBTC.token");
            address usdc = vm.parseJsonAddress(json, ".config.usdc");

            vm.startBroadcast();
            for (uint256 i = 0; i < accounts.length; i++) {
                _fundAccount(weth, accounts[i], wethTarget, false);
                _fundAccount(wbtc, accounts[i], wbtcTarget, false);
                _fundAccount(usdc, accounts[i], usdcTarget, false);
            }
            vm.stopBroadcast();

            NetworkConfig memory config = _getNetworkConfig();
            vm.startBroadcast();
            _fundKeepers(config, false);
            vm.stopBroadcast();
        } else {
            revert FundAccounts__UnsupportedChain(block.chainid);
        }
    }

    ////////////////////////////////////////////////////////////////////
    /////////////////////////////// helpers ////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice Returns the accounts to fund.
     * @dev FUND_ACCOUNTS when set, otherwise the first FUND_ACCOUNT_COUNT (default 10) accounts
     *      derived from the anvil default mnemonic.
     * @return The list of accounts to fund.
     */
    function _getAccounts() internal view returns (address[] memory) {
        uint256 count = vm.envOr("FUND_ACCOUNT_COUNT", DEFAULT_ACCOUNT_COUNT);
        address[] memory defaultAccounts = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            defaultAccounts[i] = vm.addr(vm.deriveKey(ANVIL_MNEMONIC, uint32(i)));
        }
        return vm.envOr("FUND_ACCOUNTS", ",", defaultAccounts);
    }

    /**
     * @notice Brings the token balance of an account up to the target, if it is below.
     * @dev The target is scaled by the token decimals. On the fork the balance slot is overwritten
     *      with the target; elsewhere the shortfall is minted on the mock token, which must happen
     *      inside a broadcast.
     * @param _token The token to fund.
     * @param _account The account to fund.
     * @param _wholeTarget The target balance, in whole tokens.
     * @param _isFork True on the mainnet fork (storage write), false on plain anvil (mock mint).
     */
    function _fundAccount(address _token, address _account, uint256 _wholeTarget, bool _isFork) internal {
        uint256 target = _wholeTarget * 10 ** IERC20Metadata(_token).decimals();
        uint256 balance = IERC20Metadata(_token).balanceOf(_account);

        if (balance < target) {
            if (_isFork) {
                _setBalance(_token, _account, target);
            } else {
                AssetTokenMock(_token).mint(_account, target - balance);
            }
            balance = target;
        }

        console.log(
            string.concat(vm.toString(_account), " ", IERC20Metadata(_token).symbol(), " ", vm.toString(balance))
        );
    }

    /**
     * @notice Returns the network config holding the keeper addresses.
     * @dev Called only after the chain guard of `run`: the helper reverts on unknown chains, and on
     *      anvil it needs the deployment file checked there. Must be called outside a broadcast, so
     *      the helper contract is not deployed on the node.
     * @return The active network config of HelperConfigFromDeployment.
     */
    function _getNetworkConfig() internal returns (NetworkConfig memory) {
        return new HelperConfigFromDeployment().getActiveNetworkConfig();
    }

    /**
     * @notice Brings the ETH balance of the rebalancer and of the fee collector up to KEEPER_ETH_TARGET.
     * @dev The fee collector is skipped when it is the rebalancer. On the fork the balances are written
     *      with `anvil_setBalance` and no transaction is sent. On plain anvil this must run inside a
     *      broadcast, the broadcaster pays, and a keeper equal to the broadcaster is skipped.
     * @param _config The network config holding the rebalancer and fee collector addresses.
     * @param _isFork True on the mainnet fork (balance write), false on plain anvil (value transfer).
     */
    function _fundKeepers(NetworkConfig memory _config, bool _isFork) internal {
        address funder;
        if (!_isFork) {
            (, funder,) = vm.readCallers();
        }
        if (_isFork || _config.rebalancer != funder) {
            _fundEth(_config.rebalancer, _isFork);
        }
        if (_config.feeCollector != _config.rebalancer && (_isFork || _config.feeCollector != funder)) {
            _fundEth(_config.feeCollector, _isFork);
        }
    }

    /**
     * @notice Brings the ETH balance of an account up to KEEPER_ETH_TARGET, if it is below.
     * @dev A balance at or above the target is never lowered. On the fork the balance is set to the
     *      target with `anvil_setBalance`; on plain anvil the shortfall is a value transfer from the
     *      broadcaster, meant for EOAs, reverting with FundAccounts__EthTransferFailed if it fails
     *      (for example when the broadcaster lacks the ETH).
     * @param _account The keeper account to fund.
     * @param _isFork True on the mainnet fork (balance write), false on plain anvil (value transfer).
     */
    function _fundEth(address _account, bool _isFork) internal {
        uint256 balance = _account.balance;

        if (balance < KEEPER_ETH_TARGET) {
            if (_isFork) {
                _setEthBalance(_account, KEEPER_ETH_TARGET);
            } else {
                (bool success,) = payable(_account).call{value: KEEPER_ETH_TARGET - balance}("");
                if (!success) revert FundAccounts__EthTransferFailed(_account);
            }
            balance = KEEPER_ETH_TARGET;
        }

        console.log(string.concat(vm.toString(_account), " ETH (keeper gas) ", vm.toString(balance)));
    }

    /**
     * @notice Writes the ETH balance of an account on the fork node.
     * @dev Sends `anvil_setBalance` through `vm.rpc` with the amount as a JSON-RPC hex quantity, then
     *      reads the balance back from the node with `eth_getBalance` to check the write. Only the
     *      node is updated: the local simulation keeps the balance read at the start of the script.
     * @param _account The account to fund.
     * @param _amount The balance to set, in wei.
     */
    function _setEthBalance(address _account, uint256 _amount) internal {
        string memory account = vm.toString(_account);

        // Low-level call: the JSON result is `null`, which vm.rpc does not return as ABI-encoded
        // bytes, so the high-level `bytes` return decoding would revert.
        (bool success,) = address(vm)
            .call(
                abi.encodeWithSignature(
                    "rpc(string,string)",
                    "anvil_setBalance",
                    string.concat('["', account, '","', _toHexQuantity(_amount), '"]')
                )
            );
        if (!success) revert FundAccounts__SetEthBalanceFailed(_account);

        bytes memory stored = vm.rpc("eth_getBalance", string.concat('["', account, '","latest"]'));
        if (stored.length > 32 || uint256(bytes32(stored)) >> (256 - 8 * stored.length) != _amount) {
            revert FundAccounts__EthBalanceNotSet(_account);
        }
    }

    /**
     * @notice Encodes a value as a JSON-RPC hex quantity.
     * @dev Quantities, unlike 32-byte storage words, have no leading zeros: `0x0` for zero, otherwise
     *      `0x` followed by the significant hex digits (for example `0x8ac7230489e80000` for 10 ether).
     * @param _value The value to encode.
     * @return The hex quantity string.
     */
    function _toHexQuantity(uint256 _value) internal pure returns (string memory) {
        if (_value == 0) return "0x0";

        bytes memory word = bytes(vm.toString(bytes32(_value)));
        uint256 start = 2;
        while (word[start] == "0") {
            start++;
        }

        bytes memory quantity = new bytes(word.length - start + 2);
        quantity[0] = "0";
        quantity[1] = "x";
        for (uint256 i = start; i < word.length; i++) {
            quantity[i - start + 2] = word[i];
        }
        return string(quantity);
    }

    /**
     * @notice Writes the ERC20 balance of an account on the fork node.
     * @dev The slot is found during the local simulation; the node is updated through `vm.rpc`
     *      with 32-byte hex slot and value, then the slot is read back from the node to check the write.
     * @param _token The token whose balance is written.
     * @param _account The account to fund.
     * @param _amount The balance to set, in the native decimals of the token.
     */
    function _setBalance(address _token, address _account, uint256 _amount) internal {
        uint256 slot = s_stdstore.target(_token).sig(IERC20.balanceOf.selector).with_key(_account).find();

        string memory tokenAndSlot = string.concat('["', vm.toString(_token), '","', vm.toString(bytes32(slot)), '","');

        // Low-level call: for a non-hex JSON result (`true`) vm.rpc returns a raw ABI-encoded bool
        // instead of ABI-encoded bytes, and the high-level `bytes` return decoding reverts.
        (bool success,) = address(vm)
            .call(
                abi.encodeWithSignature(
                    "rpc(string,string)",
                    "anvil_setStorageAt",
                    string.concat(tokenAndSlot, vm.toString(bytes32(_amount)), '"]')
                )
            );
        if (!success) revert FundAccounts__SetStorageFailed(_token);

        bytes memory stored = vm.rpc("eth_getStorageAt", string.concat(tokenAndSlot, 'latest"]'));
        if (bytes32(stored) != bytes32(_amount)) {
            revert FundAccounts__BalanceNotSet(_token);
        }
    }
}
