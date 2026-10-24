//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VmSafe} from "forge-std/Vm.sol";

/**
 * @notice Location and write policy of the deployment files `deployments/<chainId>.json`.
 * @dev The directory must match the `fs_permissions` entry in foundry.toml.
 */
library DeploymentFile {
    VmSafe private constant VM =
        VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant DIRECTORY = "./deployments";

    /**
     * @notice Returns the path of the deployment file of the current chain.
     * @return The relative path `./deployments/<block.chainid>.json`.
     */
    function getPath() internal view returns (string memory) {
        return
            string.concat(
                DIRECTORY,
                "/",
                VM.toString(block.chainid),
                ".json"
            );
    }

    /**
     * @notice Tells whether the deployment file must be written.
     * @dev True only under `forge script --broadcast`: dry runs and `forge test` never write files.
     * @return True if the current execution is a real broadcast.
     */
    function shouldWrite() internal view returns (bool) {
        return VM.isContext(VmSafe.ForgeContext.ScriptBroadcast);
    }
}
