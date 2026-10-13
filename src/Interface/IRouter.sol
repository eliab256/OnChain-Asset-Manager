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

    /**
     * @notice Buys index shares with an exact USDC amount, approving the index through a USDC EIP-2612 permit
     *         signature in the same transaction.
     * @dev The permit is signed by `msg.sender` with the index as spender and `_usdcAmount` as value.
     *      The tolerance protects the caller from front-running and price manipulation: if the shares
     *      received are fewer than the minimum computed with `_maxTolerance`, the transaction reverts.
     *      Reverts with Router__InvalidIndexAddress (index not initialized), Router__InvalidAmounts (zero amount),
     *      Router__InvalidTolerance (zero or >= MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION) or
     *      Router__InsufficientUsdcBalance, and with the USDC permit error if the signature is invalid or expired.
     * @param _indexAddress The address of the index.
     * @param _usdcAmount The amount of USDC to spend, in USDC token decimals (6).
     * @param _maxTolerance The maximum tolerance allowed (e.g. 10_000 = 1%, 50_000 = 5%). Must be < MAX_TOLERANCE * PERCENTAGE_FEE_PRECISION.
     * @param _deadline The permit signature deadline, as a Unix timestamp in seconds.
     * @param _v The v component of the permit signature.
     * @param _r The r component of the permit signature.
     * @param _s The s component of the permit signature.
     */
    function buyExactUsdcAmountOfSharesWithPermit(
        address _indexAddress,
        uint256 _usdcAmount,
        uint256 _maxTolerance,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
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
