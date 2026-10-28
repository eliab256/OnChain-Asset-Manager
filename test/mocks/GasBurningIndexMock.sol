// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Stand-in for an Index exposing the selectors the IndexManager calls in _tryIndexAction
 *      (rebalanceIndex, executeWeightUpdate, collectFees). Each of them runs a fixed-length loop that
 *      consumes a bounded, deterministic amount of gas and then succeeds, so a call with too little gas
 *      fails with a real out-of-gas (empty revert data) and a call with enough gas succeeds.
 *      Meant to be deployed and then vm.etch'ed over a registered and initialized index, so the
 *      IndexManager modifiers still pass. The iteration count is immutable, hence part of the runtime code.
 */
contract GasBurningIndexMock {
    error GasBurningIndexMock__Unreachable();

    uint256 private immutable i_iterations;

    constructor(uint256 _iterations) {
        i_iterations = _iterations;
    }

    function rebalanceIndex() external view {
        _burn();
    }

    function executeWeightUpdate() external view {
        _burn();
    }

    function collectFees(address) external view returns (uint256) {
        _burn();
        return 0;
    }

    /// @dev The final check depends on every iteration, so the optimizer cannot drop the loop.
    function _burn() private view {
        uint256 acc = 1;
        uint256 iterations = i_iterations;
        unchecked {
            for (uint256 i = 0; i < iterations; i++) {
                acc = acc * 31 + i;
            }
        }
        if (acc == 0) revert GasBurningIndexMock__Unreachable();
    }
}
