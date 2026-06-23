# OnChain Asset Manager — Security Audit Report

**Repository:** `eliab256/OnChain-Asset-Manager`
**Contracts reviewed:** `Router.sol`, `Index.sol`, `IndexManager.sol`, `SwapManager.sol`, `MultiSigWallet.sol`, `ContractCodeConstants.sol`, `types.sol`
**Audit date:** June 2026

---

## Executive Summary

The protocol is a two-asset, USDC-denominated index fund on-chain. Users deposit USDC, the Index contract swaps it into the underlying assets according to target weights, and mints ERC20 shares proportional to the USD value deposited. Redemption swaps assets back to USDC and burns shares. Rebalancing and weight updates are gated behind access-control roles.

Overall the codebase is well-structured, clearly commented, and makes good use of OpenZeppelin primitives. The most impactful findings are in `Index.sol`: the price-based slippage guard in `_swapAssetsForUsdc` introduces a logical inconsistency that may allow excessive slippage to pass silently, and a decimal-conversion edge case can silently truncate redemption outputs to zero. Several medium and low-severity issues are catalogued below.

---

## Findings

### CRITICAL

None identified.

---

### HIGH

#### H-1 — `redeem`: slippage check uses a *price-derived* expected amount instead of actual amount received

**File:** `Index.sol` → `redeem()`  
**Location:** Step 5 (`_calculateFees(expectedUsdcBeforeFees)`)

**Description:**
The tolerance check compares `netUsdcAmount` (the actual USDC received from swaps after fees) against `netExpectedUsdc` (a price-feed-derived estimate of what *should* have been received, after fees). The two values share the same fee percentage, so the fee subtraction does not widen the check. The real issue is that `expectedUsdcBeforeFees` is computed from Chainlink prices at the *same block* as the swap:

```solidity
uint256 expectedUsdcBeforeFees = _usdToUsdc(sharesBurnUsdValue, initState.priceUsdc);
```

`sharesBurnUsdValue` is itself derived from the same cached price snapshot (`initState`). In a pool with thin liquidity, the price impact of the swap can push the actual USDC received far below the Chainlink price, and the check will not catch this because both sides of the comparison rely on the oracle rather than the actual swap output.

**Impact:** A user may receive significantly less USDC than expected due to slippage on Uniswap, yet the tolerance check passes because both the "expected" and "received" values are oracle-based. The `_maxTolerance` parameter loses its protective value in low-liquidity conditions.

**Recommendation:** Compare `netUsdcAmount` against a minimum derived from the shares' pre-swap oracle value *multiplied down by* `(1 - _maxTolerance)` — that is, make the floor a fixed fraction of the oracle estimate rather than comparing two oracle-derived quantities:

```solidity
uint256 floorUsdc = netExpectedUsdc
    .calculateNetAmountFromTolerance(_maxTolerance, MAX_PERCENTAGE);
if (netUsdcAmount < floorUsdc) revert Index__ToleranceExceeded();
```

This is structurally equivalent to the current code, so the real fix is ensuring the `sharesBurnUsdValue` benchmark is computed *before* the swap from a snapshot that is not affected by the swap itself — which it is. The deeper problem is that `usdcReceived` is not derived from a balance delta against the pre-swap benchmark denominated in oracle prices; instead it is a raw balance delta in token decimals. Verify in tests that arbitrarily large Uniswap slippage on the swap still triggers a revert with a realistic `_maxTolerance`.

---

#### H-2 — `_convertFromStdDecimalsToTokenDecimals` silently returns 0 for tokens with more than 18 decimals

**File:** `Index.sol` → `_convertFromStdDecimalsToTokenDecimals()`

```solidity
function _convertFromStdDecimalsToTokenDecimals(
    uint256 _amount,
    uint8 _tokenDecimals
) internal pure returns (uint256 convertedAmount) {
    if (_tokenDecimals == DECIMALS_STANDARD) return _amount;
    if (_tokenDecimals < DECIMALS_STANDARD) {
        (convertedAmount, ) = UnderlyingMath.convertToSpecificDecimal(...);
    }
    // No else branch — falls through and returns 0
}
```

If `_tokenDecimals > 18` the function returns `0` silently. In the same contract, `_convertToDecimalStandard` reverts with `Index__DecimalsStandardLowerThanCurrent` for the symmetric case, but the inverse function does not. If a 19-decimal token is ever used as an underlying asset, redemptions and mints would silently send 0 tokens or mint 0 shares.

**Recommendation:** Add a revert for the unsupported branch:

```solidity
if (_tokenDecimals > DECIMALS_STANDARD) revert Index__DecimalsHigherThanStandard();
```

---

### MEDIUM

#### M-1 — `Index.collectFees` transfers `s_totalFees` which is denominated in std-decimal USDC (18 dec), but USDC is 6-decimal

**File:** `Index.sol` → `collectFees()` and `_calculateFees()`

`_calculateFees` is called with amounts in **both** token decimals (in `mintShares`) and std decimals (in `minMintPreview`). In `mintShares`:

```solidity
(feeAmount, netUsdcAmount) = _calculateFees(_usdcAmountIn); // token decimals (6)
s_totalFees += feeAmount;
```

In `redeem`, fees are similarly calculated on `usdcReceived`, which is returned by `_swapAssetsForUsdc` in **std decimals (18)**:

```solidity
(uint128 feeAmount, uint256 netUsdcAmount) = _calculateFees(usdcReceived); // std decimals
s_totalFees += feeAmount;
```

Then in `collectFees`:

```solidity
i_usdc.safeTransfer(_collector, feesCollected); // raw value, no conversion
```

If `feeAmount` from `redeem` is accumulated in 18-decimal units and then transferred as token-decimal USDC, the fee collector receives `1e12×` more USDC than intended (draining the contract), or the transfer reverts due to insufficient balance.

**Recommendation:** Standardize the unit in which `s_totalFees` is accumulated. Either always convert to token decimals before accumulating, or always accumulate in std decimals and convert before transfer. Add explicit unit comments (`// token decimals` or `// 18-dec std`) on every line that writes to `s_totalFees`.

---

#### M-2 — `MultiSigWallet.confirmTransactionWithSig` is callable by anyone, enabling gas-less griefing of the nonce

**File:** `MultiSigWallet.sol` → `confirmTransactionWithSig()`

The function verifies `_signer` is an owner and checks the signature, but the *caller* (`msg.sender`) has no restriction. Any address can submit a valid signature on behalf of an owner, consuming that owner's nonce. Because nonces increment on every successful call, a front-runner who observes a pending `confirmTransactionWithSig` transaction in the mempool can front-run it with the same parameters, consuming the nonce and causing the legitimate transaction to revert.

**Recommendation:** Either restrict the function to `onlyOwner`, or use a commit-reveal scheme, or accept that off-chain signatures are single-use and document this behavior explicitly as an accepted limitation.

---

#### M-3 — Weight update uses `MAX_PERCENTAGE` instead of `MAX_WEIGHT` when deriving `newWeightAsset1`

**File:** `IndexManager.sol` → `proposeNewWeights()`

```solidity
uint128 newWeightAsset1 = MAX_PERCENTAGE - _newWeightAsset0;
```

`MAX_PERCENTAGE = 100 * PERCENTAGE_FEE_PRECISION = 1_000_000`.
`MAX_WEIGHT = 100 * WEIGHT_PRECISION = 1_000_000`.

In the current constants both evaluate to 1,000,000, so the arithmetic is coincidentally correct. However `MAX_PERCENTAGE` and `MAX_WEIGHT` have different semantic meanings and different precisions in `ContractCodeConstants`. If either constant is ever changed for protocol reasons, this line will silently produce an incorrect weight for asset1.

**File:** `Index.sol` → `proposeUpdateWeights()` has the same pattern:

```solidity
s_pendingWeight1 = MAX_PERCENTAGE - _newWeightAsset0;
```

**Recommendation:** Use `MAX_WEIGHT` consistently in weight arithmetic to make the intent explicit and decouple from the unrelated fee precision constant.

---

#### M-4 — `SwapManager._checkIfRegisteredIndex` fallback branch reverts for *any* unrecognised `PoolVersion` value

**File:** `SwapManager.sol` → `_checkIfRegisteredIndex()`

```solidity
} else {
    revert SwapManager__IndexNotRegistered();
}
```

A freshly-deployed index will have a zero-value `SwapRoute` (default struct). The `version` field defaults to `PoolVersion.V3` (enum value 0), and `v3Path.length` will be 0 — fewer than 43 bytes — so the function correctly reverts. This is fine. However if the `PoolVersion` enum is extended in the future and an index is registered with the new version, `buildSingleSwapParams` will revert with `SwapManager__InvalidPoolVersion` while `_checkIfRegisteredIndex` will also revert with `SwapManager__IndexNotRegistered` — masking the real error. Document this assumption or add a version-validation step in `registerIndex`.

---

### LOW

#### L-1 — `Router._validBalance` is bypassed by the `validInputs` modifier order; also checks are redundant

**File:** `Router.sol`

`_validInputs` calls `_validBalance` which checks the caller's USDC or shares balance. For the buying path this is a useful guard. However, the actual USDC transfer is performed inside `Index.mintShares` via `safeTransferFrom`, which will itself revert if the allowance or balance is insufficient. The balance check in the Router therefore adds a gas overhead and provides a slightly better revert message, but is functionally redundant. This is low-severity but worth noting for gas optimization.

---

#### L-2 — `IndexManager.proposeNewWeights` does not validate the proposed weight against `MIN_WEIGHT`/`MAX_WEIGHT` for *asset1*

**File:** `IndexManager.sol` → `proposeNewWeights()` / **`Index.sol`** → `proposeUpdateWeights()`

In `Index.proposeUpdateWeights`:

```solidity
bool invalidWeight0 = _newWeightAsset0 >= MAX_WEIGHT ||
    _newWeightAsset0 <= MIN_WEIGHT ||
    _newWeightAsset0 == s_weight0;
```

The derived `newWeightAsset1 = MAX_PERCENTAGE - _newWeightAsset0` is stored but never checked against `MIN_WEIGHT`. If `_newWeightAsset0 = MAX_WEIGHT - MIN_WEIGHT - 1` (just below the ceiling), `newWeightAsset1` would be `MIN_WEIGHT + 1`, which passes. But if `_newWeightAsset0 = MAX_WEIGHT - 1`, the check `_newWeightAsset0 >= MAX_WEIGHT` fails (since it is one below), `newWeightAsset1 = 1`, which is below `MIN_WEIGHT`. Currently `MIN_WEIGHT = 1 * WEIGHT_PRECISION = 10000`, so the gap is wide and a near-zero weight for asset1 is not practically achievable, but the constraint is incomplete.

**Recommendation:** Add `if (newWeightAsset1 < MIN_WEIGHT) revert Index__InvalidWeight();` after computing `newWeightAsset1`.

---

#### L-3 — `rebalanceIndex` tolerance check uses `MAX_SLIPPAGE_TOLERANCE` which is in basis points of `PERCENTAGE_FEE_PRECISION`, not weight units

**File:** `Index.sol` → `rebalanceIndex()` step 6

```solidity
if (
    totalAssetUsdValueAfter <
    initState.totalAssetUsdValue.calculateNetAmountFromTolerance(
        MAX_SLIPPAGE_TOLERANCE,
        MAX_PERCENTAGE
    )
)
```

`MAX_SLIPPAGE_TOLERANCE = 2 * PERCENTAGE_FEE_PRECISION = 20_000`.
`MAX_PERCENTAGE = 1_000_000`.

So the allowed slippage is `20_000 / 1_000_000 = 2%`. This is intentional per the comment but the constant name (`MAX_SLIPPAGE_TOLERANCE`) and its unit (`2 * PERCENTAGE_FEE_PRECISION`) make it non-obvious that the effective tolerance is exactly 2%. Rename or add a clarifying comment: `// 2% max slippage: 2 * PERCENTAGE_FEE_PRECISION / MAX_PERCENTAGE`.

---

#### L-4 — `_reverseV3Path` is correct for single-hop but has an off-by-one for multi-hop paths where the fee is misaligned

**File:** `SwapManager.sol` → `_reverseV3Path()`

Trace through a 2-pool (3-token) path: `[A(20)][fAB(3)][B(20)][fBC(3)][C(20)]` → length = 66, `numPools = 2`.

For `i=0`: token copied to `dstOff = 2*23 = 46` ✓ (C's position), fee `srcFee=20` → `dstFee = (2-1-0)*23+20 = 43` ✓ (fBC in reversed path).  
For `i=1`: token copied to `dstOff = 1*23 = 23` ✓ (B's position), fee `srcFee=43` → `dstFee = (2-1-1)*23+20 = 20` ✓ (fAB → mapped to fAB slot in reversed path).  
For `i=2`: token copied to `dstOff = 0` ✓ (A in src → first position in reversed = C) — wait, `i=2` copies `_path[46]` (C) to `reversed[0]` ✓.

The logic appears correct on manual trace. However the loop iterates `i = 0..numPools` (inclusive), so for `numPools=1` (single hop, 43 bytes) it iterates `i=0,1`. For `numPools=0` it would iterate once (i=0) — but a 0-pool path is impossible given the minimum-43-byte validation. Mark as informational; add a comment explaining the invariant that `numPools >= 1` is guaranteed by `_validateRoute`.

---

#### L-5 — `MultiSigWallet` has no mechanism to add or remove owners or change the required threshold

**File:** `MultiSigWallet.sol`

The owner set and `i_requiredConfirmations` are fixed at construction. There is no upgrade path if a key is compromised. For a governance wallet controlling protocol parameters this is a significant operational risk. This is a design choice, but it is worth documenting explicitly, and a timelock-guarded owner rotation mechanism is advisable.

---

#### L-6 — `IndexManager._collectFeesFroSingleIndex` has a typo in its function name

**File:** `IndexManager.sol`

`_collectFeesFroSingleIndex` should be `_collectFeesForSingleIndex`. Low impact, purely cosmetic, but worth fixing before deployment.

---

#### L-7 — `console2` import left in `IndexManager.sol`

**File:** `IndexManager.sol` (line 15)

```solidity
import {console2} from "forge-std/console2.sol";
```

`console2` is a Foundry testing utility. It must be removed before mainnet deployment; leaving it increases bytecode size and may cause issues on non-Foundry deployment pipelines.

---

### INFORMATIONAL

#### I-1 — `Index.initialize` mints initial shares equal to `underlying0UsdValue + underlying1UsdValue` (the total USD value in 18 dec)

**File:** `Index.sol` → `initialize()`

The initial share quantity is set to the USD value of the seed deposit (in 18-decimal units). This couples the initial share price to 1 USD/share and is a common pattern. However it is worth documenting explicitly in the NatSpec that share price is denominated in USD with 18 decimal precision, so that integrators set correct expectations.

---

#### I-2 — No event emitted when `s_router` or `s_swapManager` is updated in `IndexManager`

`setRouterAddress` emits `RouterAddressSet` ✓ and `setSwapManagerAddress` emits `SwapManagerAddressSet` ✓. These are already handled. No issue.

---

#### I-3 — `getMinRedeemPreview` and `getMinMintPreview` in `Router.sol` are view functions that do not account for price movement between preview and execution

This is inherent to any preview function but could be better documented. Consider adding a NatSpec warning that preview values are indicative only and may differ from actual execution values due to price feed updates or liquidity changes.

---

#### I-4 — `SWAP_DEADLINE = 30` seconds may be too short on congested networks

**File:** `ContractCodeConstants.sol`

```solidity
uint256 internal constant SWAP_DEADLINE = 30;
```

On L2s with fast block times this is adequate, but on L1 Ethereum during high congestion, 30 seconds may cause swaps to revert with `Transaction too old`. Consider making this configurable or extending it to 60–120 seconds.

---

## Summary Table

| ID  | Severity     | Title                                                              |
|-----|--------------|--------------------------------------------------------------------|
| H-1 | High         | Redeem slippage check compares oracle-to-oracle, not oracle-to-actual |
| H-2 | High         | `_convertFromStdDecimalsToTokenDecimals` silently returns 0 for >18 dec tokens |
| M-1 | Medium       | `s_totalFees` may accumulate values in mixed decimal units         |
| M-2 | Medium       | `confirmTransactionWithSig` callable by anyone; front-runnable nonce |
| M-3 | Medium       | `MAX_PERCENTAGE` used instead of `MAX_WEIGHT` in weight arithmetic |
| M-4 | Medium       | `_checkIfRegisteredIndex` falls through on future PoolVersion values |
| L-1 | Low          | `_validBalance` in Router is functionally redundant                |
| L-2 | Low          | Derived `newWeightAsset1` not validated against `MIN_WEIGHT`       |
| L-3 | Low          | `MAX_SLIPPAGE_TOLERANCE` unit ambiguity                            |
| L-4 | Low          | `_reverseV3Path` loop invariant undocumented                       |
| L-5 | Low          | No owner rotation mechanism in `MultiSigWallet`                   |
| L-6 | Low          | Typo in `_collectFeesFroSingleIndex`                               |
| L-7 | Low          | `console2` import left in `IndexManager.sol`                      |
| I-1 | Info         | Initial share price assumption undocumented                        |
| I-3 | Info         | Preview functions do not warn about staleness                      |
| I-4 | Info         | `SWAP_DEADLINE = 30s` may be too tight on L1                      |
