// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SwapManager} from "../../src/SwapManager.sol";
import {SwapType, SwapRoute} from "../../src/types.sol";

/**
 * @dev Test harness exposing SwapManager internals. Deployed behind an ERC1967Proxy in tests.
 */
contract SwapManagerHarness is SwapManager {
    function exposed_storageLocation() external pure returns (bytes32 slot) {
        SwapManagerStorage storage $ = _getSwapManagerStorage();
        assembly {
            slot := $.slot
        }
    }

    function exposed_validateRoute(
        SwapRoute memory _route,
        address _tokenA,
        address _tokenB
    ) external pure {
        _validateRoute(_route, _tokenA, _tokenB);
    }

    /**
     * @dev Calls _validateRoute with a route whose `version` holds a raw value that may lie outside
     *      the PoolVersion enum range. ABI decoding rejects such values on external entry points;
     *      this probes the in-memory path: since `_validateRoute` treats every non-V4 version as V3
     *      (plain if/else), it proves an out-of-range value can never silently fall into the V3
     *      branch, because reading the out-of-range enum from memory panics with 0x21 first.
     */
    function exposed_validateRouteWithRawVersion(
        SwapRoute memory _route,
        uint8 _rawVersion,
        address _tokenA,
        address _tokenB
    ) external pure {
        assembly {
            // first word of the in-memory struct is `version`
            mstore(_route, _rawVersion)
        }
        _validateRoute(_route, _tokenA, _tokenB);
    }

    function exposed_getExpectedRouteTokens(
        address _indexAddress,
        SwapType _swapType
    ) external view returns (address, address) {
        return _getExpectedRouteTokens(_indexAddress, _swapType);
    }

    function exposed_checkIfRegisteredIndex(
        address _indexAddress
    ) external view {
        _checkIfRegisteredIndex(_indexAddress);
    }

    /// @dev Directly writes a route into storage, bypassing validation.
    function forceSetRoute(
        address _indexAddress,
        SwapType _swapType,
        bytes memory _rawRoute
    ) external {
        SwapRoute memory route = abi.decode(_rawRoute, (SwapRoute));
        _getSwapManagerStorage().routes[_indexAddress][_swapType] = route;
    }
}
