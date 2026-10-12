// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUpgraderAuth} from "./IUpgraderAuth.sol";

interface IRouter is IUpgraderAuth {
    /**
     * @notice Initializes the proxy storage.
     * @dev Called once by the IndexManager constructor through the ERC1967Proxy deployment.
     *      Reverts with Router__ZeroAddress if `_indexManager` or `_usdc` is zero,
     *      and with UpgraderAuth__ZeroAddress if `_upgrader` is zero.
     * @param _indexManager The IndexManager address, used to validate indexes.
     * @param _usdc The USDC token address, used for balance checks and permit.
     * @param _upgrader The only account allowed to upgrade the proxy (the TimelockController).
     */
    function initialize(
        address _indexManager,
        address _usdc,
        address _upgrader
    ) external;

    // External state-changing functions
    function buyExactUsdcAmountOfShares(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    ) external;

    function sellExactAmountOfSharesForUsdc(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) external;

    // External view functions
    function getMinRedeemPreview(
        address _indexAddress,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) external view returns (uint256 minUsdcAmount);

    function getMinMintPreview(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance
    ) external view returns (uint256 minSharesAmount);

    // Getter functions
    function getIndexManager() external view returns (address);

    function getMaxTolerance() external pure returns (uint256);

    function getUsdc() external view returns (address);

    /**
     * @notice Returns the current implementation address of the proxy.
     * @return The implementation address stored in the ERC-1967 implementation slot.
     */
    function getImplementation() external view returns (address);
}
