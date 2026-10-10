// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SwapManager} from "../../src/SwapManager.sol";

/**
 * @dev SwapManager V2 used to test UUPS upgrades. Inherits the storage layout unchanged and adds
 *      a `version()` getter to prove the proxy now delegates to the new implementation.
 */
contract SwapManagerV2Mock is SwapManager {
    function version() external pure returns (uint256) {
        return 2;
    }
}
