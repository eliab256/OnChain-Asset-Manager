//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CodeConstants} from "./CodeConstants.sol";

/**
 * @notice Gives an account WETH, WBTC and USDC balances on the local anvil fork of mainnet.
 * @dev Finds the balance slot locally with forge-std stdStorage, then writes it on the node with
 *      `anvil_setStorageAt`. No swap is made, so the WBTC/WETH pool stays aligned with the Chainlink
 *      price. Token totalSupply is not adjusted.
 */
contract FundForkAccount is Script, CodeConstants {
    using stdStorage for StdStorage;

    error FundForkAccount__NotOnFork(uint256 chainId);
    error FundForkAccount__SetStorageFailed(address token);
    error FundForkAccount__BalanceNotSet(address token);

    StdStorage private s_stdstore;

    /**
     * @notice Sets the WETH, WBTC and USDC balances of the account on the fork node.
     * @dev Env vars, amounts in whole tokens: FUND_ACCOUNT (default ANVIL_DEPLOYER), FUND_WETH
     *      (default 100), FUND_WBTC (default 5), FUND_USDC (default 1_000_000). The balance is set,
     *      not added. Needs `--rpc-url` pointing at the fork node; `--broadcast` is not needed.
     *      Reverts with FundForkAccount__NotOnFork outside FORK_CHAIN_ID.
     */
    function run() external {
        if (block.chainid != FORK_CHAIN_ID) {
            revert FundForkAccount__NotOnFork(block.chainid);
        }
        address account = vm.envOr("FUND_ACCOUNT", ANVIL_DEPLOYER);

        _setBalance(
            WETH_MAINNET,
            account,
            vm.envOr("FUND_WETH", uint256(100)) * 1e18
        );
        _setBalance(
            WBTC_MAINNET,
            account,
            vm.envOr("FUND_WBTC", uint256(5)) * 1e8
        );
        // USDC is a proxy: the slot is found through the proxy, where the balances live.
        _setBalance(
            USDC_MAINNET,
            account,
            vm.envOr("FUND_USDC", uint256(1_000_000)) * 1e6
        );
    }

    /**
     * @notice Writes the ERC20 balance of an account on the fork node.
     * @dev The slot is found during the local simulation; the node is updated through `vm.rpc`
     *      with 32-byte hex slot and value, then the slot is read back from the node to check the write.
     * @param _token The token whose balance is written.
     * @param _account The account to fund.
     * @param _amount The balance to set, in the native decimals of the token.
     */
    function _setBalance(
        address _token,
        address _account,
        uint256 _amount
    ) internal {
        uint256 slot = s_stdstore
            .target(_token)
            .sig(IERC20.balanceOf.selector)
            .with_key(_account)
            .find();

        string memory tokenAndSlot = string.concat(
            '["',
            vm.toString(_token),
            '","',
            vm.toString(bytes32(slot)),
            '","'
        );

        // Low-level call: for a non-hex JSON result (`true`) vm.rpc returns a raw ABI-encoded bool
        // instead of ABI-encoded bytes, and the high-level `bytes` return decoding reverts.
        (bool success, ) = address(vm).call(
            abi.encodeWithSignature(
                "rpc(string,string)",
                "anvil_setStorageAt",
                string.concat(
                    tokenAndSlot,
                    vm.toString(bytes32(_amount)),
                    '"]'
                )
            )
        );
        if (!success) revert FundForkAccount__SetStorageFailed(_token);

        bytes memory stored = vm.rpc(
            "eth_getStorageAt",
            string.concat(tokenAndSlot, 'latest"]')
        );
        if (bytes32(stored) != bytes32(_amount)) {
            revert FundForkAccount__BalanceNotSet(_token);
        }

        console.log("Token:", _token);
        console.log("Balance set:", _amount);
    }
}
