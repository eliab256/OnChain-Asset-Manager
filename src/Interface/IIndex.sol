//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    IERC20Permit
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IIndex is IERC20, IERC20Metadata, IERC20Permit {
    // External functions
    function initialize(
        address _depositor,
        uint256 _underlyingAmount0
    ) external;

    function mintShares(
        address _to,
        uint256 _usdcAmountIn,
        uint256 _maxTolerance
    ) external;

    function minMintPreview(
        uint256 _usdcAmountIn,
        uint256 _maxTolerance
    ) external view returns (uint256 minSharesToMint);

    function redeem(
        address _from,
        uint256 _sharesAmount,
        uint256 _maxTolerance
    ) external;

    function minRedeemPreview(
        uint256 _sharesAmountIn,
        uint256 _maxTolerance
    ) external view returns (uint256 minUsdcToReceive);

    function proposeUpdateWeights(
        uint128 _newWeightAsset0
    ) external returns (uint256 implementationTimestamp);

    function executeWeightUpdate() external;

    function cancelWeightUpdate() external;

    function collectFees(
        address _collector
    ) external returns (uint256 feesCollected);

    function rebalanceIndex() external;

    function getAssetsUsdValue()
        external
        view
        returns (
            uint256 asset0TotalUsdValue,
            uint256 asset1TotalUsdValue,
            uint256 totalUsdValue
        );

    function getAssetsEffectiveWeights()
        external
        view
        returns (uint128 effectiveWeight0, uint128 effectiveWeight1);

    function getAssetsAndUsdcDecimals()
        external
        view
        returns (
            uint8 asset0Decimals,
            uint8 asset1Decimals,
            uint8 usdcDecimals
        );

    function getAssetsWeights() external view returns (uint128, uint128);

    function getAssetsPendingWeights()
        external
        view
        returns (uint128, uint128, uint256);

    function getAssetsReserves() external view returns (uint128, uint128);

    function getAssetsReservesStdDecimals()
        external
        view
        returns (uint256, uint256);

    function getAsset0() external view returns (address);

    function getAsset1() external view returns (address);

    function getUsdc() external view returns (address);

    function getFeesInfo()
        external
        view
        returns (uint32 feePercentage, uint128 totalFees);

    function getInitializationStatus() external view returns (bool);

    /**
     * @notice Returns the address of the IndexManager that deployed this index.
     * @dev Set once in the constructor (msg.sender). Only this address, and the index itself, can call the IndexManager-restricted functions.
     * @return The IndexManager address.
     */
    function getIndexManager() external view returns (address);

    /**
     * @notice Returns the address of the shared Router proxy allowed to call mintShares and redeem.
     * @dev Set once in the constructor; the same proxy address for every index.
     * @return The Router proxy address.
     */
    function getRouter() external view returns (address);
}
