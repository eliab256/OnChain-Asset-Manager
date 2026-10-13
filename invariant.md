# Invariant Analysis

## Index.sol

### Invariant di Stato

1. **Supply–Reserve consistency**: Se `totalSupply() > 0`, allora `s_asset0Reserve > 0 && s_asset1Reserve > 0`. Non possono esistere shares senza riserve sottostanti.

2. **Reserve–Balance consistency**: `s_asset0Reserve <= i_asset0.balanceOf(address(this))` e `s_asset1Reserve <= i_asset1.balanceOf(address(this))`. Le riserve contabili non possono mai superare il bilancio effettivo del token.

3. **Weight sum**: `s_weight0 + s_weight1 == MAX_PERCENTAGE` (1_000_000). I pesi devono sempre sommare al 100%.

4. **Pending weight sum**: Se `s_weightUpdateExecutableAt > 0`, allora `s_pendingWeight0 + s_pendingWeight1 == MAX_PERCENTAGE`.

5. **Weight bounds**: `s_weight0 > MIN_WEIGHT && s_weight0 < MAX_WEIGHT` e lo stesso per `s_weight1`. Nessun peso può essere 0% o 100%.

6. **Initialization monotonicity**: `s_initialized` una volta `true`, non torna mai `false`.

7. **No shares before initialization**: Se `!s_initialized`, allora `totalSupply() == 0`.

8. **Fee accumulation non-decreasing** (tra collect): `s_totalFees` può solo aumentare tra due chiamate a `collectFees`. Dopo `collectFees`, `s_totalFees == 0`.

9. **Fee percentage immutability di fatto**: `s_feePercentage` viene settato nel constructor e non viene mai modificato.

10. **Shares value solvency**: Il valore USD totale delle riserve (`getAssetsUsdValue().totalUsdValue`) deve essere ≥ al valore teorico del `totalSupply()` (a meno dello slippage di rebalance).

11. **Decimal standard invariant**: `i_decimals0 <= DECIMALS_STANDARD` e `i_decimals1 <= DECIMALS_STANDARD` e `i_decimalsUsdc <= DECIMALS_STANDARD`. Altrimenti `_convertToDecimalStandard` reverta.

12. **Mint increases supply and reserves**: Dopo `mintShares`, `totalSupply()` e entrambe le riserve devono aumentare (o restare invariate se `sharesToMint == 0` → revert).

13. **Redeem decreases supply and reserves**: Dopo `redeem`, `totalSupply()` e almeno una riserva devono diminuire.

14. **Rebalance preserves total value**: Dopo `rebalanceIndex`, `totalAssetUsdValueBefore - totalAssetUsdValueAfter <= swappedUsdValue * REBALANCE_SWAP_SLIPPAGE / MAX_PERCENTAGE`, dove `swappedUsdValue` è il valore oracolo dell'asset venduto. Lo swap del rebalance ha `amountOutMinimum` = output atteso da oracolo meno `REBALANCE_SWAP_SLIPPAGE`.

15. **Rebalance preserves total supply**: `rebalanceIndex` non minta né brucia shares; `totalSupply()` resta invariato.

16. **Weight update delay**: `executeWeightUpdate` può essere chiamato solo se `s_weightUpdateExecutableAt > 0` e `s_weightUpdateExecutableAt <= block.timestamp <= s_weightUpdateExecutableAt + WEIGHT_UPDATE_EXECUTION_WINDOW`. `cancelWeightUpdate` azzera sempre pesi pendenti e timestamp.

17. **No double pending**: `proposeUpdateWeights` reverta se esiste già un update pendente non ancora eseguibile (`s_weightUpdateExecutableAt != 0 && block.timestamp < s_weightUpdateExecutableAt`).

18. **collectFees drains exactly s_totalFees**: Dopo `collectFees`, l'ammontare trasferito == il valore pre-call di `s_totalFees`, e `s_totalFees == 0`.

19. **Price feed freshness**: `getLatestPrice` accetta solo asset0, asset1 e USDC e delega a `PriceFeedManager.getPrice`, che reverta se il feed non è registrato, `answer <= 0`, `answeredInRound < roundId` o `block.timestamp - updatedAt > maxDelay` del feed.

---

## IndexManager.sol

### Invariant di Stato

1. **Index uniqueness**: Per ogni coppia `(asset0, asset1)` ordinata, esiste al più un index: `s_getIndex[asset0][asset1]` è impostato una sola volta e non viene mai sovrascritto.

2. **Bidirectional mapping consistency**: Se `s_getIndex[a0][a1] == index`, allora `s_indexAssets[index] == (a0, a1)` e `s_isIndex[index] == true`.

3. **isIndex monotonicity**: Una volta `s_isIndex[addr] = true`, non torna mai `false`.

4. **isInitialized monotonicity**: Una volta `s_isInitialized[addr] = true`, non torna mai `false`.

5. **Initialization requires isIndex**: `s_isInitialized[addr] == true` implica `s_isIndex[addr] == true`.

6. **deployedIndexes ⊇ initializedIndexes**: Ogni indirizzo in `s_initializedIndexes` è anche in `s_deployedIndexes`.

7. **No duplicate in deployedIndexes**: Ogni indirizzo appare al più una volta in `s_deployedIndexes` (garantito dal check `IndexAlreadyExists`).

8. **No duplicate in initializedIndexes**: Ogni indirizzo appare al più una volta in `s_initializedIndexes` (garantito dal check `IndexAlreadyInitialized`).

9. **USDC exclusion**: Nessun index può avere `i_usdc` come asset0 o asset1.

10. **Fee percentage bounds**: Ogni index creato ha `MIN_FEES_PERCENTAGE <= feePercentage <= MAX_FEES_PERCENTAGE`.

11. **Weight sum at creation**: Per ogni index creato, `asset0.weightPercentage + asset1.weightPercentage == MAX_WEIGHT`.

12. **Single Router proxy**: `i_router` è il proxy ERC1967 creato nel costruttore, non cambia mai e ogni Index lo salva come immutabile `i_router` (leggibile con `getRouter()`). Un upgrade del Router (solo tramite il `TimelockController`) vale per tutti gli index, compresi quelli già creati.

13. **Single SwapManager proxy**: `i_swapManager` è il proxy ERC1967 creato nel costruttore, non cambia mai ed è lo stesso indirizzo passato a ogni Index (`Index.i_swapManager == IndexManager.getSwapManagerAddress()`). L'owner del proxy è l'IndexManager.

14. **totalFeesCollected monotonicity**: `s_totalFeesCollected` può solo aumentare (mai decrementato).

15. **totalFeesCollected consistency**: `s_totalFeesCollected == Σ` di tutti i `feeAmount` raccolti con successo dai singoli index.

16. **sortAssets determinism**: `_sortAssets(a, b) == _sortAssets(b, a)` e `token0 < token1` sempre (funzione interna dell'IndexManager).

17. **No self-pair index**: `createIndex` reverta se `_assetA.asset == _assetB.asset`.

18. **ERC20 validation**: la fa il PriceFeedManager in `registerPriceFeed`: l'asset deve rispondere a `symbol()` con dati (`PriceFeedManager__InvalidAsset`) e a `decimals()` con un valore ≤ 18 (`PriceFeedManager__InvalidAssetDecimals`). Dato che `createIndex` richiede un feed registrato per entrambi gli asset (invariante 19), ogni asset di un index è stato validato.

19. **Price feed registration**: `createIndex` reverta se asset0, asset1 o USDC non hanno un feed registrato nel PriceFeedManager.

20. **Rebalance/fee collection non-reverting batch**: rebalance, esecuzione dei pesi e raccolta fee (varianti single e multiple, tutte via `_tryIndexAction`) non revertano se un index fallisce: emettono `IndexActionFailed(index, caller, action, reasonData)` con il revert data originale. Le varianti multiple revertano solo se un indirizzo della lista non è un index inizializzato.

21. **Proxy upgrade timelock**: SwapManager, PriceFeedManager e Router hanno come `upgrader` (`UpgraderAuth`, storage ERC-7201 `onchainassetmanager.storage.UpgraderAuth`) il `TimelockController` passato al costruttore dell'IndexManager (mai zero, `IndexManager__ZeroAddress`). Solo l'upgrader può chiamare `upgradeToAndCall`: IndexManager, owner, admin o chiunque altro ricevono `UpgraderAuth__Unauthorized(caller)`. Ogni upgrade richiede quindi `schedule` + attesa di almeno `getMinDelay()` (2 giorni) + `execute` da parte del MultiSig; `cancel` è possibile finché non è eseguito. L'upgrader non ha setter: cambia solo con un upgrade. L'IndexManager non ha più funzioni di upgrade.

---

## Router.sol

### Invariant di Stato

1. **Storage e proxy**: indexManager e usdc vivono nello storage ERC-7201 `onchainassetmanager.storage.Router`, sono impostati una sola volta da `initialize` (mai zero) e restano invariati dopo un upgrade. L'implementation non è inizializzabile; solo l'upgrader (`TimelockController`) può chiamare `upgradeToAndCall`. Il Router non ha owner.

2. **USDC consistency**: `getUsdc() == IIndexManager(getIndexManager()).getUsdc()`.

3. **Valid index gate**: Ogni operazione `buy/sell` richiede che l'index sia inizializzato in `IndexManager`.

4. **Non-zero amount**: `buyExactUsdcAmountOfShares` e `sellExactAmountOfSharesForUsdc` revertano se `_amount == 0`.

5. **Tolerance bounds**: `0 < _maxTolerance < 10_000`. Valori fuori range revertano.

6. **Sufficient balance (buy)**: `buyExactUsdcAmountOfShares` reverta se `i_usdc.balanceOf(msg.sender) < _usdcAmount`.

7. **Sufficient balance (sell)**: `sellExactAmountOfSharesForUsdc` reverta se `index.balanceOf(msg.sender) < _sharesAmount`.

8. **Reentrancy protection**: Nessuna chiamata rientrante è possibile grazie a `ReentrancyGuard.nonReentrant`.

9. **Router is stateless**: Oltre alla configurazione scritta da `initialize` (e allo stato del `ReentrancyGuard`), il Router non mantiene stato mutabile proprio; funge da puro dispatcher.

10. **Preview consistency**: `getMinMintPreview` e `getMinRedeemPreview` restituiscono valori coerenti con la logica di `Index.minMintPreview` / `Index.minRedeemPreview` per gli stessi input.

---

## SwapManager.sol

### Invariant di Stato

1. **Route registration completeness**: Dopo `registerIndex`, tutte e tre le route (`ASSET0_USDC`, `ASSET1_USDC`, `ASSET0_ASSET1`) sono settate per quell'index.

2. **V4 route validity**: Ogni route V4 registrata ha `currency0 != address(0) || currency1 != address(0)` (almeno una currency non-zero).

3. **V3 route validity**: Ogni route V3 registrata ha `v3Path.length >= 43`.

4. **Index registration check**: `buildSingleSwapParams` e `buildDoubleSwapParams` revertano con `SwapManager__IndexNotRegistered` se l'index non ha route registrate.

5. **updateRoute requires prior registration**: `updateRoute` reverta se l'index non è registrato.

6. **Route update atomicity**: `updateRoute` modifica solo lo `SwapType` specificato; le altre due route restano invariate.

7. **Command byte correctness**: Per route V4, il command byte è `0x10` (`V4_SWAP`). Per route V3, è `0x00` (`V3_SWAP_EXACT_IN`).

8. **Token direction correctness (V4)**: Se `tokenIn == currency0`, `tokenOut == currency1` e viceversa. Il flag `zeroForOne` è coerente.

9. **Token direction correctness (V3)**: `tokenOut` è sempre estratto dagli ultimi 20 bytes di `v3Path`.

10. **Double swap decomposition**: `buildDoubleSwapParams` produce `commands` e `inputs` tali che `commands[i]` e `inputs[i]` corrispondono esattamente a `buildSingleSwapParams` con i rispettivi parametri.

11. **Owner-only registration**: Solo l'indirizzo con il ruolo appropriato (IndexManager) può chiamare `registerIndex` e `updateRoute`.

11b. **Upgrade e storage**: Solo l'upgrader (`TimelockController`) può chiamare `upgradeToAndCall`; l'owner (IndexManager) resta per le funzioni operative. Le route vivono nello storage ERC-7201 `onchainassetmanager.storage.SwapManager` e restano invariate dopo un upgrade. L'implementation non è inizializzabile (`_disableInitializers`) e `initialize` sul proxy si chiama una volta sola.

12. **V3 input encoding**: L'input V3 codifica `payerIsUser == false` e `amountOutMin` uguale al `_amountOutMinimum` passato (V4: `ExactInputSingleParams.amountOutMinimum`).

13. **V4 action count**: L'input V4 decodificato contiene esattamente 3 action: `SWAP_EXACT_IN_SINGLE`, `SETTLE_ALL`, `TAKE_ALL`.

---

## PriceFeedManager.sol

### Invariant di Stato

1. **Un feed per asset**: Ogni asset ha al più una `FeedConfig`; tutti gli index con lo stesso asset leggono lo stesso feed.

2. **Validità della configurazione**: Ogni feed registrato ha codice, ha restituito `answer > 0` alla registrazione, ha `decimals() <= 18`, e `0 < maxDelay <= MAX_FEED_DELAY_LIMIT`.

3. **Registrazione una sola volta**: `registerPriceFeed` riesce solo se l'asset non ha già un feed; ogni sostituzione passa da `proposePriceFeedUpdate` → `executePriceFeedUpdate`.

4. **Timelock sui feed**: `executePriceFeedUpdate` riesce solo se `executableAt <= block.timestamp <= executableAt + PRICE_FEED_UPDATE_EXECUTION_WINDOW`; il feed proposto viene ri-validato all'esecuzione. Dopo execute o cancel la proposta è azzerata.

5. **Autorizzazioni**: register/propose/execute/cancel richiedono `ASSET_MANAGER_ROLE` sull'IndexManager (owner); `upgradeToAndCall` solo l'upgrader (`TimelockController`).

6. **Prezzi normalizzati**: `getPrice` restituisce sempre il prezzo a 18 decimali.

7. **Storage e proxy**: La configurazione vive nello storage ERC-7201 `onchainassetmanager.storage.PriceFeedManager` e resta invariata dopo un upgrade; il proxy è unico e il suo indirizzo è immutabile in IndexManager e in ogni Index.

