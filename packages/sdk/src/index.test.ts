import { describe, expect, it, vi } from "vitest";

// The public surface is a contract with every consumer (front-end, keeper, indexer): this list
// changes only together with src/index.ts and sdk.md.
const expectedValueExports = [
  "ANVIL_CHAIN_ID",
  "CONFIRM_TYPES",
  "ContractRevertError",
  "EmptyIndexListError",
  "Erc20Manager",
  "EstimateNotFoundError",
  "EventNotFoundError",
  "INDEX_ACTIONS",
  "Index",
  "IndexManager",
  "IndexManagerCalls",
  "IndexNotInitializedError",
  "InsufficientAllowanceError",
  "InsufficientBalanceError",
  "InvalidDeadlineError",
  "InvalidDecimalsError",
  "InvalidFeePercentageError",
  "InvalidIndexAssetsError",
  "InvalidMaxDelayError",
  "InvalidPriceError",
  "InvalidSignatureError",
  "InvalidSwapRouteError",
  "InvalidToleranceError",
  "InvalidWeightError",
  "MAINNET_FORK_CHAIN_ID",
  "MAX_FEED_DELAY",
  "MAX_FEE_PERCENTAGE",
  "MAX_TOLERANCE",
  "MAX_WEIGHT",
  "MIN_FEE_PERCENTAGE",
  "MIN_WEIGHT",
  "MultiSigCalls",
  "MultiSigNotExecutableError",
  "PERCENTAGE_SCALE",
  "PERMIT_TYPES",
  "POOL_VERSION",
  "PriceFeedManagerCalls",
  "PriceFeedReads",
  "REBALANCE_THRESHOLD",
  "RequestFailedError",
  "RouterManager",
  "SHARES_DECIMALS",
  "STANDARD_DECIMALS",
  "SdkError",
  "USDC_DECIMALS",
  "UnknownIndexActionError",
  "UnknownProposalError",
  "UnsupportedChainError",
  "ValueOutOfRangeError",
  "ZeroAddressError",
  "ZeroAmountError",
  "anvil",
  "assertConfirmSignature",
  "assertRouteConnects",
  "buildConfirmTypedData",
  "buildPermitTypedData",
  "convertDecimals",
  "decodeProposal",
  "decodeProtocolError",
  "encodeConfirmationRevokedLog",
  "encodeIndexActionFailedLog",
  "encodeIndexCreatedLog",
  "encodeProtocolError",
  "encodeSharesBurnedLog",
  "encodeSharesMintedLog",
  "encodeTransactionConfirmedLog",
  "encodeTransactionExecutedLog",
  "encodeTransactionSubmittedLog",
  "failureReasonOf",
  "formatShares",
  "formatUsdValue",
  "formatUsdc",
  "getProtocolAddresses",
  "isPriceFeedStale",
  "isValidTolerance",
  "isValidWeight",
  "joinPermitSignature",
  "mainnetFork",
  "normalizeConfirmSignature",
  "parseCollectFeesBatch",
  "parseConfirmationRevoked",
  "parseIndexActionFailure",
  "parseIndexCreated",
  "parseRebalanceBatch",
  "parseShares",
  "parseSharesBurned",
  "parseSharesMinted",
  "parseTransactionConfirmed",
  "parseTransactionExecuted",
  "parseTransactionSubmitted",
  "parseUsdc",
  "parseWeightUpdateBatch",
  "permitDomainFromEip712Domain",
  "protocolErrorsAbi",
  "routeEndpoints",
  "splitPermitSignature",
  "supportedChains",
  "toSdkError",
  "toleranceFromBasisPoints",
  "v3Route",
  "v4Route",
];

describe("public export surface", () => {
  it("exports exactly the documented names", async () => {
    const sdk = await import("./index.js");
    expect(Object.keys(sdk).sort()).toEqual([...expectedValueExports].sort());
  });

  it("no export is undefined (a broken re-export)", async () => {
    const sdk: Record<string, unknown> = await import("./index.js");
    for (const name of expectedValueExports) expect(sdk[name], name).toBeDefined();
  });

  it("security: internal constants and the contract math port are not exported", async () => {
    const sdk: Record<string, unknown> = await import("./index.js");
    for (const name of [
      "STANDARD_UNIT",
      "MAX_ESTIMATE_DOUBLINGS",
      "ceilDiv",
      "absDiff",
      "applyFee",
      "applyTolerance",
      "sharesToMintFromUsd",
      "shareValueInUsd",
      "usdValueOfAmount",
      "routerWithErrorsAbi",
      "indexWithErrorsAbi",
      "indexManagerWithErrorsAbi",
      "multiSigWalletWithErrorsAbi",
      "priceFeedManagerWithErrorsAbi",
    ]) {
      expect(sdk, name).not.toHaveProperty(name);
    }
  });
});

describe("import", () => {
  it("has no side effects: no new globals, no timers, no network", async () => {
    vi.resetModules();
    const globalsBefore = new Set(Object.getOwnPropertyNames(globalThis));
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const timerSpy = vi.spyOn(globalThis, "setTimeout");
    const intervalSpy = vi.spyOn(globalThis, "setInterval");
    await import("./index.js");
    const added = Object.getOwnPropertyNames(globalThis).filter((name) => !globalsBefore.has(name));
    expect(added).toEqual([]);
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(timerSpy).not.toHaveBeenCalled();
    expect(intervalSpy).not.toHaveBeenCalled();
    vi.restoreAllMocks();
  });
});
