// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IndexDeployParams} from "../types.sol";

interface IIndexFactory {
    /**
     * @notice Deploys a new Index with CREATE2.
     * @dev Permissionless: the Index constructor always receives msg.sender as its IndexManager, so a caller
     *      only gets an Index managed by itself, never one registered in the official IndexManager.
     *      The initcode is re-assembled in memory from the two data contracts, followed by the ABI-encoded
     *      constructor arguments. Reverts with IndexFactory__IndexDeployFailed if CREATE2 returns address(0)
     *      (the Index constructor reverted or the target address is already in use). Emits no event.
     * @param _params The Index constructor arguments, IndexManager excluded. Check types.sol
     * @param _salt The CREATE2 salt.
     * @return index The address of the deployed Index.
     */
    function deployIndex(
        IndexDeployParams calldata _params,
        bytes32 _salt
    ) external returns (address index);

    /**
     * @notice Returns the Index creation code stored by the factory, without constructor arguments.
     * @dev Equal to type(Index).creationCode passed to the constructor.
     * @return The Index creation code.
     */
    function getIndexCreationCode() external view returns (bytes memory);

    /**
     * @notice Returns the two data contracts holding the halves of the Index creation code.
     * @dev Each data contract runtime is a STOP byte followed by its half.
     * @return The data contract holding the first half.
     * @return The data contract holding the second half.
     */
    function getCodePointers() external view returns (address, address);
}
