# Event check: audit degli eventi per l'indexer

**Prima versione:** 2026-10-08, sul commit `07bba933`.
**Aggiornato:** 2026-10-12, dopo il refactor degli eventi, l'aggiunta di `IndexActionTriggered` e il passaggio degli upgrade al `TimelockController` di OpenZeppelin (modifiche non ancora committate).
**Ambito:** `src/` (Index, IndexManager, SwapManager, PriceFeedManager, MultiSigWallet, Router, eventi, interfacce).
**Verifica:** `forge test` passa 878 test su 878, inclusi i fork test su mainnet. 56 test sono dedicati agli eventi:
- `test/unit/IndexUnitTest/Index.Events.t.sol`
- `test/unit/IndexmanagerUnitTest/IndexManager.Events.t.sol`
- `test/unit/IndexmanagerUnitTest/IndexManager.ActionTriggered.t.sol`
- `test/unit/PriceFeedManagerUnitTest/PriceFeedManagerUpdateEvents.t.sol`
- `test/unit/MultiSigWallet.Events.t.sol`
- `test/unit/UpgraderAuthUnitTest/UpgraderAuthTimelockEvents.t.sol`

## Sommario

**Scelte di design adottate:**
- **Una sola fonte per i dati di stato.** L'Index emette gli eventi con i dati (init, mint, redeem, rebalance, pesi, fee). L'IndexManager emette solo:
  - `IndexCreated`;
  - `IndexActionTriggered(index, caller, action)` per ogni azione riuscita, senza ripetere i dati dell'Index;
  - gli esiti falliti delle operazioni batch (`...Failed`);
- **Upgrade dei proxy fuori dall'IndexManager.** Gli upgrade di SwapManager, PriceFeedManager e Router passano dal `TimelockController` di OpenZeppelin: gli eventi sono quelli del timelock (`CallScheduled`, `CallSalt`, `CallExecuted`, `Cancelled`) più `Upgraded` di ERC-1967 sul proxy (sezione 1.6).
- **`reasonData` è sempre il revert data originale:**
  - un errore custom porta selector e argomenti;
  - un `revert("x")` porta `Error(string)` codificato ABI;
  - un revert vuoto porta byte vuoti.
- **Le unità sono documentate in NatSpec su ogni parametro:**
  - decimali del token per gli importi degli asset;
  - decimali USDC per importi e fee in USDC;
  - 18 decimali per i valori in USD;
  - unità di peso con 1.000.000 = 100%.

**Aperto (vedi sezione 4):**
- SwapManager non emette eventi.
- Lo schema Prisma dell'indexer va rigenerato e ripensato.
- Nessun evento riporta più chi ha lanciato un'operazione dall'IndexManager.

---

## 1. Inventario attuale

### 1.1 Index (`src/events/IndexEvents.sol`, eventi a livello di file)

| Evento | Parametri (`indexed` in grassetto) | Emesso in | Note sui valori |
|---|---|---|---|
| `IndexInitialized` | **depositor**, asset0Amount, asset1Amount, asset0UsdValue, asset1UsdValue, sharesMinted | `initialize` | Importi in decimali del token, valori USD a 18 decimali |
| `SharesMinted` | **user**, sharesMinted, asset0Amount, asset1Amount, usdcAmountIn, feeAmount | `mintShares` | `usdcAmountIn` è il lordo pagato, `feeAmount` è l'importo aggiunto alle fee accumulate |
| `SharesBurned` | **user**, sharesBurned, asset0Amount, asset1Amount, usdcAmountOut, feeAmount | `redeem` | `usdcAmountOut` è il netto ricevuto dall'utente; stesso ordine di `SharesMinted` |
| `IndexRebalanced` | asset0ReserveBefore, asset1ReserveBefore, asset0ReserveAfter, asset1ReserveAfter | `rebalanceIndex` | Riserve in decimali del token |
| `WeightsUpdateProposed` | oldAsset0Weight, oldAsset1Weight, newAsset0Weight, newAsset1Weight, executableAt | `proposeUpdateWeights` | Include i pesi correnti, prima nell'evento rimosso del Manager |
| `WeightsUpdated` | asset0Weight, asset1Weight | `executeWeightUpdate` | Emesso **prima** del tentativo di rebalance |
| `WeightsUpdateRebalanceFailed` | reasonData | `executeWeightUpdate` | Revert data originale |
| `WeightsUpdateRebalanceSkipped` | – | `executeWeightUpdate` | Il rebalance non serve (`Index__RebalanceNotNeeded`): non è un fallimento |
| `WeightsUpdateCancelled` | cancelledAsset0Weight, cancelledAsset1Weight | `cancelWeightUpdate`; `proposeUpdateWeights` | Nel secondo caso è emesso quando una nuova proposta sostituisce una pendente già eseguibile o scaduta |
| `FeesCollected` | **feeCollector**, feeAmount | `collectFees` | In decimali USDC (C-01 risolto) |

### 1.2 IndexManager (`src/events/IndexManagerEvents.sol`)

| Evento | Parametri (`indexed` in grassetto) | Emesso in |
|---|---|---|
| `IndexCreated` | **indexAddress**, **asset0**, **asset1**, asset0Weight, asset1Weight, feePercentage, assetManager | `createIndex` |
| `IndexActionTriggered` | **indexAddress**, **caller**, **action** (enum `IndexAction`) | Solo in caso di successo:<br>• `initializeIndex` (INITIALIZE)<br>• `proposeNewWeights` (PROPOSE_WEIGHTS)<br>• `cancelWeightUpdate` (CANCEL_WEIGHTS)<br>• rebalance (REBALANCE)<br>• esecuzione dei pesi (EXECUTE_WEIGHTS)<br>• raccolta fee (COLLECT_FEES)<br><br>Le ultime tre azioni passano dagli helper interni comuni alle varianti single, multiple e all: nei batch c'è un evento per ogni index riuscito |
| `IndexRebalanceFailed` | **indexAddress**, reasonData | Le tre funzioni di rebalance |
| `WeightsUpdateFailed` | **indexAddress**, reasonData | Le tre funzioni di esecuzione dei pesi |
| `FeesCollectionFailed` | **indexAddress**, **feeCollector**, reasonData | Le tre funzioni di raccolta fee |

**Rimossi perché duplicavano l'Index:**
- `IndexInitialized`, `IndexRebalanced`, `FeesCollected`, che avevano lo stesso nome degli eventi dell'Index ma firma diversa;
- `NewIndexWeightsProposed`, `WeightUpdateExecuted`, `WeightUpdateCancelled`.

**Rimossi con il passaggio al `TimelockController`:** i 9 eventi `{SwapManager,PriceFeedManager,Router}{UpgradeProposed,Upgraded,UpgradeCancelled}`, insieme alle funzioni di upgrade dell'IndexManager.

**Rimosso perché il setter non esiste più:** `SwapManagerAddressSet`.

### 1.3 PriceFeedManager (`src/events/PriceFeedManagerEvents.sol`, library)

| Evento | Parametri (`indexed` in grassetto) | Emesso in |
|---|---|---|
| `PriceFeedRegistered` | **asset**, **feed**, maxDelay | `registerPriceFeed` |
| `PriceFeedUpdateProposed` | **asset**, **feed**, maxDelay, executableAt | `proposePriceFeedUpdate` |
| `PriceFeedUpdated` | **asset**, **oldFeed**, **newFeed**, maxDelay | `executePriceFeedUpdate` |
| `PriceFeedUpdateCancelled` | **asset**, **cancelledFeed**, cancelledMaxDelay | `cancelPriceFeedUpdate`; `proposePriceFeedUpdate`, quando sostituisce una proposta pendente eseguibile o scaduta |

### 1.4 MultiSigWallet (`src/events/MultiSigWalletEvents.sol`)

| Evento | Parametri (`indexed` in grassetto) | Emesso in |
|---|---|---|
| `MultiSigInitialized` | owners, requiredConfirmations | costruttore |
| `Deposit` | **sender**, value | `receive`, solo se `msg.value > 0`. Funziona anche con lo stipend di 2300 gas di `transfer`/`send` |
| `TransactionSubmitted` | **txId**, **proposer**, **target**, value, data | `submitTransaction` |
| `TransactionConfirmed` | **txId**, **owner** | `confirmTransaction`, `confirmTransactionWithSig` |
| `ConfirmationRevoked` | **txId**, **owner** | `revokeConfirmation` |
| `TransactionExecuted` | **txId**, **executor** | `executeTransaction` |

### 1.5 Contratti senza eventi custom

- `SwapManager`: solo `OwnershipTransferred` e `Initialized` di OpenZeppelin all'inizializzazione, più `Upgraded` sul proxy.
- `Router`: solo `Initialized` all'inizializzazione e `Upgraded` sul proxy (non ha più `Ownable`).
- Librerie, `UpgraderAuth`, `types.sol`, costanti: nessun evento.

### 1.6 Upgrade dei proxy (`TimelockController` di OpenZeppelin + ERC-1967)

L'unico `upgrader` dei tre proxy è il `TimelockController`; il MultiSig è proposer, executor e canceller.

| Fase | Contratto | Evento | Note per l'indexer |
|---|---|---|---|
| Proposta | Timelock | `CallScheduled(`**id**`, `**index**`, target, value, data, predecessor, delay)` | `target` è il proxy; `data` è `upgradeToAndCall(newImplementation, initData)` da decodificare. Eseguibile da `block.timestamp + delay` |
| Proposta | Timelock | `CallSalt(`**id**`, salt)` | Solo con salt diverso da zero |
| Esecuzione | Proxy | `Upgraded(`**implementation**`)` | Fonte affidabile dell'implementation attiva. Eventuali eventi dell'init (per esempio `Initialized(version)`) seguono nello stesso tx |
| Esecuzione | Timelock | `CallExecuted(`**id**`, `**index**`, target, value, data)` | Chiude l'operazione `id` |
| Cancellazione | Timelock | `Cancelled(`**id**`)` | Chiude l'operazione `id` |
| Configurazione | Timelock | `MinDelayChange(oldDuration, newDuration)` | Al deploy e a ogni cambio del delay (solo tramite il timelock stesso) |

I ruoli del timelock emettono `RoleGranted`/`RoleRevoked` di `AccessControl`. Nella stessa transazione il MultiSig emette `TransactionExecuted`.


---

## 2. Problemi della prima versione: stato

| # | Problema | Stato |
|---|---|---|
| 1 | Tre collisioni di nome fra Index e IndexManager | **Risolto**: gli eventi del Manager sono stati rimossi |
| 2 | Doppia emissione per init, rebalance, pesi e fee | **Risolto**: la fonte unica è l'Index |
| 3 | `FeesCollected.feeAmount` in unità miste | **Risolto** (C-01): tutte le fee sono in decimali USDC |
| 4 | `WeightUpdateExecuted` anche con rebalance fallito | **Risolto**: l'evento è stato rimosso; l'esito è in `WeightsUpdateRebalanceFailed`/`Skipped` |
| 5 | "Rebalance non necessario" segnalato come fallimento dopo l'aggiornamento dei pesi | **Risolto**: nuovo `WeightsUpdateRebalanceSkipped` |
| 6 | Ordine dei log: rebalance prima di `IndexWeightsUpdated` | **Risolto**: `WeightsUpdated` è emesso prima |
| 7 | `IndexCreated` con `address(0)` se `create2` fallisce | **Risolto**: `_deployIndex` reverte (`IndexManager__IndexDeployFailed`) |
| 8 | `reasonData` a volte stringa nuda o `"Unknown error"` | **Risolto**: sempre il revert data originale |
| 9 | Fee per operazione mai emessa | **Risolto**: `feeAmount` in `SharesMinted`/`SharesBurned` |
| 10 | `IndexCreated` senza configurazione | **Risolto**: aggiunti pesi e fee. I feed stanno nel `PriceFeedManager` e hanno i loro eventi |
| 11 | Proposta sovrascritta senza segnale di chiusura | **Risolto** per pesi e feed: evento `...Cancelled` prima della nuova proposta. Per gli upgrade non si applica più: nel `TimelockController` ogni operazione ha il suo `id` e si chiude con `CallExecuted` o `Cancelled` |
| 12 | Timestamp `indexed` e ridondanti | **Risolto**: rimossi da `IndexRebalanced` e `WeightsUpdated`; `executableAt` non è più indexed |
| 13 | Naming incoerente (`Weight`/`Weights`, `token0`/`asset0`) e ordine dei parametri di `SharesMinted`/`SharesBurned` | **Risolto** |
| 14 | `RouterAddressSet` senza valore precedente | **Superato**: `setRouterAddress` e `RouterAddressSet` sono stati rimossi. Il Router è un proxy UUPS unico e i suoi upgrade passano dal `TimelockController` (sezione 1.6) |
| 15 | MultiSig senza evento con owner e soglia, e senza `Deposit` | **Risolto** |
| 16 | Unità non documentate | **Risolto**: NatSpec su ogni parametro |
| 17 | Proposta di upgrade senza la calldata | **Risolto**: `CallScheduled.data` contiene l'intera calldata `upgradeToAndCall` |
| 18 | SwapManager senza eventi su `registerIndex`/`updateRoute` | **Non previsto**: per decisione di design SwapManager non emette eventi |
| 19 | NAV o prezzi non presenti negli eventi | **Aperto** |
| 20 | `confirmTransactionWithSig` indistinguibile da una conferma diretta | **Aperto** (priorità bassa) |

---

## 3. Verifica dei valori emessi

Ogni valore è controllato dai test:
- `SharesMinted.feeAmount` e `SharesBurned.feeAmount` sono uguali alla variazione di `getFeesInfo`. Nel redeem, `feeAmount` corrisponde agli USDC che restano all'Index.
- `usdcAmountIn` è il lordo pagato dall'utente e `usdcAmountOut` è il netto ricevuto.
- Gli importi degli asset di `SharesMinted`/`SharesBurned` coincidono con la variazione delle riserve.
- `IndexInitialized.depositor` è il depositante effettivo, non l'IndexManager.
- `IndexCreated` riporta i pesi dopo l'ordinamento degli asset.
- `reasonData` è uguale byte per byte a `abi.encodeWithSelector(...)` dell'errore atteso, sia per errori senza argomenti (`Index__NoFeesToCollect`, `Index__RebalanceNotNeeded`) sia con argomenti.
- Quando un'azione riesce, l'IndexManager emette esattamente un `IndexActionTriggered` con index, caller e azione corretti, dopo l'evento dell'Index nella stessa transazione, e nessun altro log.
- Quando un'azione fallisce, viene emesso solo l'evento `...Failed`, mai `IndexActionTriggered`. Nei batch con un index riuscito e uno fallito ognuno ha il suo evento.
- `EXECUTE_WEIGHTS` è emesso anche quando il rebalance interno viene saltato o fallisce: l'esito del rebalance sta negli eventi dell'Index.
- La multisig non emette `Deposit` per invii da 0 ETH (call semplice, `transfer`, `send`).

---

## 4. Punti aperti e note per l'indexer

1. **Chiamante.** `IndexActionTriggered` riporta il `msg.sender` dell'IndexManager. Per le azioni dell'asset manager è la multisig: il singolo firmatario si ricava dagli eventi della multisig nella stessa transazione.
2. **SwapManager non emette eventi** (decisione di design). Le route registrate (V3 path o V4 PoolKey) si leggono con `getRoute`.
3. **`IndexRebalanceFailed` con `Index__RebalanceNotNeeded`.** Quando il rebalance è chiamato direttamente dall'IndexManager, il caso "non necessario" è ancora un evento di fallimento. Il selector nel `reasonData` permette all'indexer di riconoscerlo.
4. **`Deposit` con valore 0: risolto.** `receive()` emette solo se `msg.value > 0`. Gli invii da 0 ETH riescono comunque, ma non lasciano log.
5. **`setRouterAddress` non valida l'input: non più applicabile.** La funzione è stata rimossa: il Router è un proxy creato dal costruttore dell'IndexManager.
6. **NAV.** Né i prezzi né il valore totale sono negli eventi. Lo storico del prezzo delle share richiede chiamate di lettura o la lettura degli aggregator Chainlink.
7. **Schema dell'indexer.** Da non rigenerare finché l'utente non lo chiede.
   - `indexer/prisma/schema.prisma` è stato generato dai vecchi ABI e va rigenerato.
   - Restano i problemi del generatore (`indexer/scripts/generatePrismaModels.ts`):
     - legge tutto `out/`, compresi mock, forge-std e Uniswap;
     - deduplica per nome invece che per firma;
     - non salva `contractAddress` e `chainId`;
     - genera campi `id` doppi.
   - Con gli eventi del `PriceFeedManager` dichiarati in una library, l'ABI li espone comunque sul contratto che li emette.
8. **Ordine dei log nella creazione di un index.** Il costruttore dell'Index emette i `RoleGranted` prima di `IndexCreated`. Un indexer che aggiunge l'Index agli indirizzi ascoltati solo dopo `IndexCreated` deve riprocessare i log della transazione di creazione. Gli indirizzi sono deterministici (`create2`, salt = `keccak256(asset0, asset1)`).
9. **Upgrade da decodificare.** Gli eventi del `TimelockController` sono generici: per riconoscere un upgrade l'indexer deve controllare che `target` sia uno dei tre proxy e che `data` inizi con il selector di `upgradeToAndCall`. Un `CallScheduled` senza `CallExecuted` né `Cancelled` resta eseguibile per sempre (nessuna scadenza). Con `scheduleBatch` ci sono più `CallScheduled` con lo stesso `id` e `index` diversi.

---

## 5. Mapping entità → eventi

| Entità | Chiave | Eventi sorgente |
|---|---|---|
| `Index` | indirizzo dell'index | `IndexCreated` (asset, pesi, fee), `IndexInitialized`, `WeightsUpdated` |
| `IndexAction` | (txHash, logIndex) | `IndexActionTriggered`: index, chiamante, tipo di azione; si collega all'evento dell'Index della stessa transazione |
| `IndexReserveSnapshot` | (index, block, logIndex) | `IndexInitialized`, `SharesMinted`, `SharesBurned` (variazioni); `IndexRebalanced` (valori assoluti) |
| `WeightProposal` | (index, txHash, logIndex) | Apertura con `WeightsUpdateProposed`; chiusura con `WeightsUpdated` o `WeightsUpdateCancelled` |
| `Deposit` / `Redemption` | (txHash, logIndex) | `SharesMinted` / `SharesBurned`, con la fee |
| `ShareBalance` | (index, account) | `Transfer` dell'Index |
| `Rebalance` | (txHash, logIndex) | `IndexRebalanced`; fallimenti da `IndexRebalanceFailed` e `WeightsUpdateRebalanceFailed`; casi saltati da `WeightsUpdateRebalanceSkipped` |
| `FeeAccrual` / `FeeCollection` | (txHash, logIndex) | Maturate: `feeAmount` di `SharesMinted`/`SharesBurned`; raccolte: `FeesCollected`; fallimenti: `FeesCollectionFailed` |
| `PriceFeed` | asset | `PriceFeedRegistered`, `PriceFeedUpdated`; proposte con `PriceFeedUpdateProposed`/`Cancelled` |
| `ProxyUpgrade` | id dell'operazione del timelock | Apertura con `CallScheduled` (proxy = `target`, implementation da `data`); chiusura con `CallExecuted` o `Cancelled`; implementation attiva da `Upgraded` sul proxy |
| `MultisigWallet` | indirizzo | `MultiSigInitialized`, `Deposit` |
| `MultisigTransaction` | (wallet, txId) | `TransactionSubmitted`, `TransactionConfirmed`, `ConfirmationRevoked`, `TransactionExecuted` |

Dai soli eventi ora si ricostruiscono:
- la lista degli index con la loro configurazione;
- riserve, pesi e proposte pendenti;
- fee maturate e raccolte;
- feed e upgrade;
- owner e soglia della multisig.

Non si ricostruiscono le route di swap (SwapManager senza eventi per scelta) e il NAV.

**Dimensione dei contratti:** `Index` e `IndexManager` restano sopra il limite EIP-170. Il problema è rimandato per decisione dell'utente.
