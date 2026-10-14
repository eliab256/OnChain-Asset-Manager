// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IIndexFactory} from "./Interface/IIndexFactory.sol";
import {SplitCode} from "./libraries/SplitCode.sol";
import {IndexDeployParams} from "./types.sol";
import {
    IndexFactory__EmptyCreationCode,
    IndexFactory__IndexDeployFailed
} from "./errors/IndexFactoryErrors.sol";

/**
 * @title IndexFactory
 * @notice Deploys Index contracts with CREATE2, keeping the Index initcode out of the IndexManager bytecode.
 * @dev Split-code factory: the Index creation code is stored as the runtime of two data contracts
 *      (one per half, each below the EIP-170 limit) and re-assembled in memory at deploy time.
 *      Non-upgradeable, permissionless and event-less.
 */
contract IndexFactory is IIndexFactory {
    // Data contract holding the first floor(n/2) bytes of the Index creation code.
    address internal immutable i_codeA;
    // Data contract holding the remaining bytes of the Index creation code.
    address internal immutable i_codeB;
    // Size, in bytes, of the first half (STOP byte excluded).
    uint256 internal immutable i_sizeA;
    // Size, in bytes, of the second half (STOP byte excluded).
    uint256 internal immutable i_sizeB;

    ////////////////////////////////////////////////////////////////////
    /////////////////////////// constructor ////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @param _indexCreationCode The Index creation code (type(Index).creationCode), without constructor arguments.
     */
    constructor(bytes memory _indexCreationCode) {
        uint256 size = _indexCreationCode.length;
        if (size == 0) revert IndexFactory__EmptyCreationCode();

        uint256 sizeA = size / 2;
        uint256 sizeB = size - sizeA;

        i_codeA = SplitCode.write(_slice(_indexCreationCode, 0, sizeA));
        i_codeB = SplitCode.write(_slice(_indexCreationCode, sizeA, sizeB));
        i_sizeA = sizeA;
        i_sizeB = sizeB;
    }

    ////////////////////////////////////////////////////////////////////
    ///////////////////////////// deployment ///////////////////////////
    ////////////////////////////////////////////////////////////////////

    /// @dev Inherit from IIndexFactory. See interface for details.
    function deployIndex(
        IndexDeployParams calldata _params,
        bytes32 _salt
    ) external returns (address index) {
        bytes memory initCode = _assembleCode(
            _encodeConstructorArgs(_params, msg.sender)
        );
        assembly {
            index := create2(0, add(initCode, 0x20), mload(initCode), _salt)
        }
        if (index == address(0)) revert IndexFactory__IndexDeployFailed();
    }

    ////////////////////////////////////////////////////////////////////
    ////////////////////////////// getters /////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /// @dev Inherit from IIndexFactory. See interface for details.
    function getIndexCreationCode() external view returns (bytes memory) {
        return _assembleCode("");
    }

    /// @dev Inherit from IIndexFactory. See interface for details.
    function getCodePointers() external view returns (address, address) {
        return (i_codeA, i_codeB);
    }

    ////////////////////////////////////////////////////////////////////
    ////////////////////////////// internal ////////////////////////////
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice ABI-encodes the Index constructor arguments.
     * @dev The order must match the Index constructor: name, symbol, indexManager, router, usdc,
     *      priceFeedManager, swapManager, universalRouter, asset0, asset1, feePercentage.
     *      The params are copied to memory first to keep the stack shallow (no via_ir).
     * @param _params The Index constructor arguments, IndexManager excluded.
     * @param _indexManager The IndexManager of the new Index (always the factory caller).
     * @return The ABI-encoded constructor arguments.
     */
    function _encodeConstructorArgs(
        IndexDeployParams calldata _params,
        address _indexManager
    ) internal pure returns (bytes memory) {
        IndexDeployParams memory params = _params;
        return
            abi.encode(
                params.name,
                params.symbol,
                _indexManager,
                params.router,
                params.usdc,
                params.priceFeedManager,
                params.swapManager,
                params.universalRouter,
                params.asset0,
                params.asset1,
                params.feePercentage
            );
    }

    /**
     * @notice Builds `codeA || codeB || _suffix` in a single memory buffer.
     * @dev The two halves are copied straight from the data contracts with EXTCODECOPY and the suffix with MCOPY.
     * @param _suffix The bytes appended after the creation code (constructor arguments, or empty).
     * @return code The re-assembled buffer.
     */
    function _assembleCode(
        bytes memory _suffix
    ) internal view returns (bytes memory code) {
        uint256 sizeA = i_sizeA;
        uint256 sizeB = i_sizeB;
        uint256 suffixSize = _suffix.length;
        uint256 total = sizeA + sizeB + suffixSize;
        uint256 dataPtr;

        // Allocated without zeroing: every byte is overwritten below.
        assembly {
            code := mload(0x40)
            mstore(code, total)
            dataPtr := add(code, 0x20)
            mstore(0x40, add(dataPtr, and(add(total, 31), not(31))))
        }

        SplitCode.copyTo(i_codeA, dataPtr, sizeA);
        SplitCode.copyTo(i_codeB, dataPtr + sizeA, sizeB);

        assembly {
            mcopy(add(dataPtr, add(sizeA, sizeB)), add(_suffix, 0x20), suffixSize)
        }
    }

    /**
     * @notice Copies `_length` bytes of `_data` starting at `_start` into a new bytes array.
     * @param _data The source bytes.
     * @param _start The first byte to copy.
     * @param _length The number of bytes to copy.
     * @return slice The copied bytes.
     */
    function _slice(
        bytes memory _data,
        uint256 _start,
        uint256 _length
    ) internal pure returns (bytes memory slice) {
        slice = new bytes(_length);
        assembly {
            mcopy(add(slice, 0x20), add(add(_data, 0x20), _start), _length)
        }
    }
}
