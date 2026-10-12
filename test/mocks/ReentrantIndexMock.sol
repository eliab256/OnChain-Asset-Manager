// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRouter} from "../../src/Interface/IRouter.sol";

/**
 * @dev Malicious "index" exposing the IIndex selectors the Router calls (mintShares, redeem, balanceOf).
 *      mintShares and redeem call back into the Router with this contract as index, reproducing a
 *      reentrancy attempt. Used together with a mocked IndexManager.checkIsIndexInitialized(this) == true.
 *      balanceOf always returns type(uint256).max so the Router share-balance check never blocks the sell path.
 */
contract ReentrantIndexMock {
    IRouter private immutable i_router;

    constructor(address _router) {
        i_router = IRouter(_router);
    }

    function mintShares(
        address,
        uint256 _usdcAmountIn,
        uint256 _maxTolerance
    ) external {
        i_router.buyExactUsdcAmountOfShares(
            address(this),
            _usdcAmountIn,
            _maxTolerance
        );
    }

    function redeem(
        address,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) external {
        i_router.sellExactAmountOfSharesForUsdc(
            address(this),
            _sharesAmount,
            _maxTolerance
        );
    }

    function balanceOf(address) external pure returns (uint256) {
        return type(uint256).max;
    }
}
