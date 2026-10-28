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
 * @notice Emitted when an action triggered through the manager on an index succeeds.
 * @dev Not emitted when the call to the index reverts (see IndexActionFailed).
 *      Carries no state data: amounts, weights, reserves and fees are in the event emitted by the index in the same transaction.
 *      For EXECUTE_WEIGHTS the rebalance outcome is in the Index events WeightsUpdateRebalanceFailed (custom error),
 *      WeightsUpdateRebalanceSkipped or IndexRebalanced; a common error in the inner rebalance makes the whole
 *      executeWeightUpdate revert, so this event is not emitted.
 * @param indexAddress Address of the index the action was triggered on.
 * @param caller msg.sender of the IndexManager call (the multisig or the EOA holding the required role).
 * @param action Action triggered on the index.
 */
event IndexActionTriggered(
    address indexed indexAddress,
    address indexed caller,
    IndexAction indexed action
);

/**
 * @notice Emitted when a rebalance, weights update execution or fee collection triggered by the manager reverts.
 * @dev The manager call does not revert. Batch variants emit it for any failure and continue with the next index.
 *      Single variants emit it only for custom errors; on a common error (revert data shorter than 4 bytes, e.g. out of
 *      gas, Error(string) or Panic(uint256)) they revert with the original revert data and this event is not emitted.
 *      Never emitted for INITIALIZE, PROPOSE_WEIGHTS and CANCEL_WEIGHTS, which revert on failure.
 * @param indexAddress Address of the index whose call failed.
 * @param caller msg.sender of the IndexManager call; for COLLECT_FEES, the address that would have received the fees.
 * @param action Action that failed (REBALANCE, EXECUTE_WEIGHTS or COLLECT_FEES).
 * @param reasonData Raw revert data of the call to the index, unchanged. For single variants always a custom error
 *        (at least 4 bytes, selector other than Error(string) and Panic(uint256)); for batch variants any revert data,
 *        possibly empty.
 */
event IndexActionFailed(
    address indexed indexAddress,
    address indexed caller,
    IndexAction indexed action,
    bytes reasonData
);
