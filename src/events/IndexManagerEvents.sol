// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IndexAction} from "../types.sol";

/**
 * @notice Emitted when a new index is deployed.
 * @param indexAddress Address of the deployed index.
 * @param asset0 Address of asset0 (the lower of the two sorted asset addresses).
 * @param asset1 Address of asset1 (the higher of the two sorted asset addresses).
 * @param asset0Weight Initial asset0 target weight, in weight units (1_000_000 = 100%).
 * @param asset1Weight Initial asset1 target weight, in weight units (1_000_000 = 100%).
 * @param feePercentage Fee charged on mint and redeem, in percentage units (1_000_000 = 100%).
 * @param assetManager Address that created the index.
 */
event IndexCreated(
    address indexed indexAddress,
    address indexed asset0,
    address indexed asset1,
    uint128 asset0Weight,
    uint128 asset1Weight,
    uint32 feePercentage,
    address assetManager
);

/**
 * @notice Emitted when a rebalance triggered by the manager reverts; the batch continues.
 * @param indexAddress Address of the index whose rebalance failed.
 * @param reasonData Raw revert data of the rebalance call, unchanged (may be empty).
 */
event IndexRebalanceFailed(address indexed indexAddress, bytes reasonData);

/**
 * @notice Emitted when a fee collection triggered by the manager reverts; the batch continues.
 * @param indexAddress Address of the index whose fee collection failed.
 * @param feeCollector Address that would have received the fees.
 * @param reasonData Raw revert data of the collectFees call, unchanged (may be empty).
 */
event FeesCollectionFailed(
    address indexed indexAddress,
    address indexed feeCollector,
    bytes reasonData
);

/**
 * @notice Emitted when a weights update execution triggered by the manager reverts; the batch continues.
 * @param indexAddress Address of the index whose weights update failed.
 * @param reasonData Raw revert data of the executeWeightUpdate call, unchanged (may be empty).
 */
event WeightsUpdateFailed(address indexed indexAddress, bytes reasonData);

/**
 * @notice Emitted when an action triggered through the manager on an index succeeds.
 * @dev Not emitted when the call to the index reverts (see IndexRebalanceFailed, WeightsUpdateFailed, FeesCollectionFailed).
 *      Carries no state data: amounts, weights, reserves and fees are in the event emitted by the index in the same transaction.
 *      For EXECUTE_WEIGHTS the rebalance outcome is in the Index events WeightsUpdateRebalanceFailed, WeightsUpdateRebalanceSkipped or IndexRebalanced.
 * @param indexAddress Address of the index the action was triggered on.
 * @param caller msg.sender of the IndexManager call (the multisig or the EOA holding the required role).
 * @param action Action triggered on the index.
 */
event IndexActionTriggered(
    address indexed indexAddress,
    address indexed caller,
    IndexAction indexed action
);
