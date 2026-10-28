// Public API of @oam/sdk. Anything not listed here is internal. The SDK does no I/O: it builds
// calldata, read descriptors and typed data, and parses results; the caller's client executes them.

// constants
export {
  INDEX_ACTIONS,
  MAX_FEE_PERCENTAGE,
  MAX_FEED_DELAY,
  MAX_TOLERANCE,
  MAX_WEIGHT,
  MIN_FEE_PERCENTAGE,
  MIN_WEIGHT,
  PERCENTAGE_SCALE,
  REBALANCE_THRESHOLD,
  SHARES_DECIMALS,
  STANDARD_DECIMALS,
  USDC_DECIMALS,
  type IndexAction,
} from "./constants/public.js";
export { ANVIL_CHAIN_ID, MAINNET_FORK_CHAIN_ID, anvil, mainnetFork, supportedChains } from "./constants/chains.js";
export { getProtocolAddresses, type ProtocolAddresses, type SupportedChainId } from "./constants/addresses.js";

// errors
export {
  ContractRevertError,
  EmptyIndexListError,
  EstimateNotFoundError,
  EventNotFoundError,
  IndexNotInitializedError,
  InsufficientAllowanceError,
  InsufficientBalanceError,
  InvalidDeadlineError,
  InvalidDecimalsError,
  InvalidFeePercentageError,
  InvalidIndexAssetsError,
  InvalidMaxDelayError,
  InvalidPriceError,
  InvalidSignatureError,
  InvalidSwapRouteError,
  InvalidToleranceError,
  InvalidWeightError,
  MultiSigNotExecutableError,
  RequestFailedError,
  SdkError,
  UnknownIndexActionError,
  UnknownProposalError,
  UnsupportedChainError,
  ValueOutOfRangeError,
  ZeroAddressError,
  ZeroAmountError,
} from "./errors.js";

// abis
export { protocolErrorsAbi } from "./abis/fragments.js";

// utils
export {
  convertDecimals,
  formatShares,
  formatUsdc,
  formatUsdValue,
  parseShares,
  parseUsdc,
} from "./utils/decimals.js";
export { isValidTolerance, isValidWeight, toleranceFromBasisPoints } from "./utils/percentages.js";
export { isPriceFeedStale } from "./utils/priceFeed.js";
export {
  assertRouteConnects,
  POOL_VERSION,
  routeEndpoints,
  v3Route,
  v4Route,
  type PoolKey,
  type SwapRoute,
} from "./utils/swapRoutes.js";

// entities
export { Index, type IndexPrices, type IndexSnapshot, type IndexValuation } from "./entities/Index.js";

// encoders
export {
  buildPermitTypedData,
  joinPermitSignature,
  PERMIT_TYPES,
  permitDomainFromEip712Domain,
  splitPermitSignature,
  type PermitDomain,
  type PermitSignature,
} from "./encoders/permit.js";
export {
  encodeIndexActionFailedLog,
  encodeIndexCreatedLog,
  encodeSharesBurnedLog,
  encodeSharesMintedLog,
  failureReasonOf,
  parseCollectFeesBatch,
  parseIndexActionFailure,
  parseIndexCreated,
  parseRebalanceBatch,
  parseSharesBurned,
  parseSharesMinted,
  parseWeightUpdateBatch,
  type BatchActionFailure,
  type CollectFeesBatchResult,
  type FailureReason,
  type IndexActionFailure,
  type IndexCreatedEvent,
  type RebalanceBatchResult,
  type RebalanceReserves,
  type WeightUpdateBatchResult,
  type WeightUpdateRebalance,
  type SharesBurnedEvent,
  type SharesMintedEvent,
} from "./encoders/indexEvents.js";
export {
  assertConfirmSignature,
  buildConfirmTypedData,
  CONFIRM_TYPES,
  decodeProposal,
  encodeConfirmationRevokedLog,
  encodeTransactionConfirmedLog,
  encodeTransactionExecutedLog,
  encodeTransactionSubmittedLog,
  normalizeConfirmSignature,
  parseConfirmationRevoked,
  parseTransactionConfirmed,
  parseTransactionExecuted,
  parseTransactionSubmitted,
  type ConfirmationRevokedEvent,
  type DecodedProposal,
  type ProposalContract,
  type TransactionConfirmedEvent,
  type TransactionExecutedEvent,
  type TransactionSubmittedEvent,
} from "./encoders/multiSig.js";
export {
  decodeProtocolError,
  encodeProtocolError,
  toSdkError,
  type DecodedProtocolError,
} from "./encoders/revertData.js";

// managers
export type { MethodParameters } from "./managers/types.js";
export {
  RouterManager,
  type BuyParams,
  type BuyWithPermitParams,
  type SellParams,
} from "./managers/RouterManager.js";
export {
  IndexManagerCalls,
  type IndexAssetParams,
  type IndexManagerRole,
  type IndexRoutes,
} from "./managers/IndexManagerCalls.js";
export { MultiSigCalls } from "./managers/MultiSigCalls.js";
export { PriceFeedManagerCalls } from "./managers/PriceFeedManagerCalls.js";
export {
  IndexManager,
  type IndexSnapshotResults,
  type PendingWeightUpdate,
} from "./managers/IndexManager.js";
export { PriceFeedReads, type PendingFeedUpdate } from "./managers/PriceFeedReads.js";
export { Erc20Manager } from "./managers/Erc20Manager.js";
