# Security Review: On-Chain Asset Manager

**Data:** 2026-10-08 (review iniziale), aggiornato il 2026-10-10
**Commit:** `07bba933` per la review iniziale; stato aggiornato su `0195bec0` con le modifiche non ancora committate
**Revisore:** audit manuale (Claude), sola lettura

> **Nota sull'aggiornamento.** I finding risolti sono stati tolti dal corpo del documento e sono elencati nella sezione 2.1. I riferimenti di riga dei finding ancora aperti si riferiscono al commit `07bba933`, salvo dove indicato, e possono essere spostati nel codice attuale.

---

## 1. Scope e metodologia

### File in scope (`src/`, 4593 righe alla review iniziale, 5874 oggi)

| File | Righe |
|---|---|
| `src/Index.sol` | 1587 |
| `src/IndexManager.sol` | 899 |
| `src/SwapManager.sol` | 422 |
| `src/MultiSigWallet.sol` | 334 |
| `src/Router.sol` | 327 |
| `src/libraries/UnderlyingMath.sol` | 265 |
| `src/libraries/SharesMath.sol` | 39 |
| `src/types.sol` | 116 |
| `src/ContractCodeConstants.sol` | 78 |
| `src/Interface/{IIndex,IIndexManager,IRouter,ISwapManager,IMultiSigWallet}.sol` | 356 |
| `src/PriceFeedManager.sol`, `src/Interface/IPriceFeedManager.sol` (aggiunti dopo la review, non revisionati con la stessa profondità) | 450 |
| `src/events/*.sol`, `src/errors/*.sol` | 170 |

### Metodologia

- Ho letto per intero tutti i file in scope, comprese librerie, interfacce, eventi ed errori.
- Ho seguito i flussi fra contratti: Router → Index (mint/redeem/permit), IndexManager → Index/SwapManager (create, initialize, rebalance, weights, fees), Index → SwapManager → Universal Router, MultiSigWallet → IndexManager.
- Ho confrontato il codice con le intenzioni dichiarate in `README.md`, `invariant.md` e `TODO.md`.
- Ho verificato la codifica dei parametri Uniswap (`IV4Router.ExactInputSingleParams`, `Actions`, `Commands`, `Dispatcher` di V3) sulle versioni presenti in `lib/`.
- Ho letto, senza eseguirli, i test unitari rilevanti per i finding e gli script di deploy, per capire l'assegnazione dei ruoli.
- Non ho eseguito build, test o simulazioni. I finding che richiedono una conferma numerica sono marcati **"da verificare"**.

---

## 2. Sommario

| Severità | Numero |
|---|---|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 3 |
| Informational | 3 |
| Gas | 4 |

| ID | Titolo | Severità |
|---|---|---|
| M-02 | Nessuna uscita senza swap e configurazione parzialmente fissa: `updateRoute` irraggiungibile, Universal Router fisso (parzialmente risolto) | Medium |
| M-04 | NAV calcolato con l'oracolo ma esecuzione su un solo asset: arbitraggio sul ritardo dell'oracolo (da verificare) | Medium |
| L-01 | Il redeem del 100% della supply reverta per arrotondamento (da verificare) | Low |
| L-02 | Griefing tramite front-run della firma permit | Low |
| L-03 | WBTC prezzato con il feed BTC/USD (parzialmente risolto: staleness per feed introdotta) | Low |
| I-01 | Discrepanze fra specifica/NatSpec e codice | Info |
| I-04 | Loop non limitati sugli index | Info |
| I-05 | Ordine CEI in `redeem`, errori inutilizzati, modifier di validazione prima di `nonReentrant` | Info |
| G-01..G-04 | Ottimizzazioni gas | Gas |

### 2.1 Finding risolti

Tutti verificati con la suite completa (`forge test`, inclusi i fork test su mainnet): 878 test passati, 0 falliti.

| ID | Titolo | Correzione |
|---|---|---|
| C-01 | Fee di redeem accumulate con i decimali sbagliati | Le fee di redeem sono calcolate nei decimali del token USDC prima di sommarle all'accumulatore. |
| H-01 | Swap di rebalance senza `minOut` e soglia di perdita tarata sul TVL | `_swapAssetForAsset` passa un `amountOutMinimum` derivato dall'oracolo con `REBALANCE_SWAP_SLIPPAGE` = 1%. `_checkRebalanceSlippage` misura la perdita sul nozionale scambiato e non più sul TVL. |
| M-01 | SwapManager sostituibile fra `createIndex` e `initializeIndex`, con index legati a manager diversi | `s_swapManager` e `setSwapManagerAddress` rimossi. Un unico proxy UUPS (storage ERC-7201) è creato dal costruttore di `IndexManager` e salvato come immutabile. Gli upgrade passano dal `TimelockController` di OpenZeppelin (upgrader unico dei tre proxy tramite `UpgraderAuth`, delay minimo 2 giorni, MultiSig proposer/executor/canceller). |
| M-03 | Controllo del rebalance basato su differenza con segno e pesi non limitati | `_checkIfRebalanceNeeded` usa la differenza assoluta. `createIndex` valida i limiti dei pesi. |
| L-04 | Route di swap registrate senza verificare i token | `SwapManager._validateRoute` controlla che token d'ingresso e d'uscita di ogni route coincidano con gli asset dell'index (`SwapManager__RouteTokensMismatch`). `registerIndex` reverte con `SwapManager__NotAnIndex` se l'indirizzo non espone i getter dell'index. `createIndex` rifiuta asset con `decimals() > 18`. Rami irraggiungibili e `SwapManager__InvalidPoolVersion` rimossi. |
| L-05 | Aggiornamento dei pesi senza scadenza né cancellazione | `executeWeightUpdate` reverte dopo `WEIGHT_UPDATE_EXECUTION_WINDOW` (`Index__WeightUpdateExpired`). Aggiunti `cancelWeightUpdate` sull'Index e il wrapper sull'IndexManager. |
| L-06 | Firme della multisig non legate al contenuto della transazione | Il typehash EIP-712 `Confirm(uint256 txId,address target,uint256 value,bytes32 dataHash,uint256 nonce)` include target, valore e hash dei dati. Il nonce è per coppia (txId, owner) e viene incrementato anche alla revoca. Dominio `("MultiSigWallet","2")`. |
| I-02 | `forge-std/console2` importato in codice di produzione | L'import non è più presente in `src/`. |
| I-03 | Codifica incoerente dei motivi di errore nei try/catch | Tutti i try/catch di Index e IndexManager usano un solo `catch (bytes memory reason)` e passano il revert data originale negli eventi `...Failed`. `_getErrorData` e il segnaposto `"Unknown error"` sono stati rimossi. Dettagli in `eventCheck.md`. |

---

## 3. Findings

### [M-02] Nessuna uscita senza swap e configurazione parzialmente fissa: `updateRoute` irraggiungibile, Universal Router fisso (parzialmente risolto)

**Severità:** Medium
**Stato:** parzialmente risolto
**File (codice attuale):** `src/SwapManager.sol:117` (`updateRoute`), `src/IndexManager.sol` (nessun wrapper), `src/Index.sol:66` (`i_universalRouter`), `src/Index.sol:132-135` (ruoli)

**Già risolto**
- **Feed sostituibili.** I feed non sono più immutabili nell'Index. Stanno in un `PriceFeedManager` condiviso (proxy UUPS, storage ERC-7201, owner `IndexManager`). La prima registrazione è immediata; la sostituzione passa da `propose/execute/cancelPriceFeedUpdate` con 2 giorni di delay e 3 di finestra, gestita da `ASSET_MANAGER_ROLE`. Una sostituzione vale per tutti gli index che usano quell'asset.
- **SwapManager aggiornabile.** È un proxy UUPS unico, aggiornabile solo dal `TimelockController` (vedi M-01 nella sezione 2.1).
- **Router aggiornabile.** Anche il Router è un proxy UUPS unico creato dall'`IndexManager` (`i_router`, immutabile). Ogni index assegna `ROUTER_ROLE` a quel proxy, quindi un upgrade (tramite lo stesso `TimelockController`, 2 giorni di delay) vale anche per gli index già creati, senza migrare ruoli. `setRouterAddress` è stato rimosso.

**Ancora aperto**
1. **Route non aggiornabili.** `SwapManager.updateRoute` è `onlyOwner` e l'owner è `IndexManager`, che non ha nessuna funzione che la chiami. Le route di un index restano fisse. L'unico modo per cambiarle è un upgrade dello SwapManager con calldata di inizializzazione, che però richiede 2 giorni e un'implementazione nuova.
2. **Universal Router immutabile.** `i_universalRouter` è immutabile in ogni Index.
3. **Nessuna uscita senza swap.** Non esiste redeem in-kind né pausa. Se un feed si ferma, mint, redeem e rebalance degli index che lo usano restano bloccati per almeno i 2 giorni del timelock di sostituzione.

**Scenario**
- La liquidità del pool V3 configurato migra altrove, oppure il pool viene manipolato in modo persistente. Ogni redeem supera la tolleranza di slippage dell'utente e reverta, e la route non si può cambiare in tempi brevi.
- Chainlink depreca un feed oppure il feed si ferma oltre il suo `maxDelay`. I fondi degli utenti restano bloccati finché la sostituzione del feed non diventa eseguibile.

**Raccomandazione**
- In `IndexManager`, aggiungere `updateIndexRoute(address index, SwapType t, SwapRoute calldata r) onlyRole(ASSET_MANAGER_ROLE)` che inoltri a `updateRoute`, preferibilmente con lo stesso schema propose/execute/cancel dei feed.
- Nell'Index, aggiungere un `redeemInKind(address from, uint256 shares)` che bruci le shares e trasferisca la quota pro-rata di `s_asset0Reserve` e `s_asset1Reserve`, senza oracolo né swap. È l'uscita di emergenza minima per i fondi degli utenti, e copre anche la finestra di 2 giorni dei feed.

Il trade-off è una maggiore superficie di fiducia verso l'asset manager, da mitigare con i timelock.

---

### [M-04] NAV calcolato con l'oracolo ma esecuzione su un solo asset: arbitraggio sul ritardo dell'oracolo (da verificare)

**Severità:** Medium (da verificare: la redditività dipende da fee, pool e deviation threshold dei feed)
**File:** `src/Index.sol:401-436`, `src/Index.sol:1053-1063`, `src/libraries/UnderlyingMath.sol:161-242`

**Descrizione**
In `redeem`, la quantità di token venduta si calcola con il prezzo Chainlink (`tokens = usd / P_oracle`). L'utente però riceve il ricavato al prezzo di mercato. `calculateWithdrawUnderlyingAmountsInUsd` vende prima, e spesso esclusivamente, l'asset sovrappeso, invece di una fetta pro-rata.

Se l'oracolo dell'asset venduto è sotto il mercato di una percentuale `d` (fino alla deviation threshold, tipicamente 0,5–2%), chi riscatta vende più token del dovuto e incassa circa `usd·(1+d)`. La differenza esce dalla quota degli altri holder. Lo stesso vale in modo simmetrico per `mintShares`, che compra solo l'asset sottopeso valutandolo all'oracolo.

**Scenario**
1. Il mercato LINK sale dello 0,9%, ma il feed LINK/USD non si è ancora aggiornato.
2. L'index è sovrappeso LINK.
3. L'attaccante (già holder, o tramite un mint precedente) riscatta: l'Index vende `usd/P_oracle` LINK, che sul mercato valgono lo 0,9% in più.
4. Il guadagno è circa 0,9% meno la fee di redeem (minimo 0,1%) meno la fee del pool. Lo pagano gli holder rimanenti.

**Raccomandazione**
- Imporre una fee minima superiore alla deviation threshold dei feed usati.
- In alternativa, eseguire il redeem pro-rata su entrambi gli asset (`fraction × reserve`), in modo che la quantità venduta non dipenda dal prezzo dell'oracolo.
- In alternativa, confrontare l'esecuzione con l'oracolo in entrambe le direzioni (revert anche se l'output supera il prezzo oracolo di oltre X).

Va verificata con un fork test su feed reali.

---

### [L-01] Il redeem del 100% della supply reverta per arrotondamento (da verificare)

**Severità:** Low
**File:** `src/libraries/UnderlyingMath.sol:217-241`, `src/Index.sol:1362-1377`, `src/Index.sol:471-472`

**Descrizione**
Se si riscatta tutta la supply, `updatedTotal = 0` e `current0 = floor(T · floor(a0·1e6/T) / 1e6) ≤ a0`. Di conseguenza `token1Usd = T − current0 ≥ a1`, con un eccesso fino a `T/1e6`. La quantità di asset1 da vendere supera `s_asset1Reserve`. Il risultato è un revert su `safeTransfer` per saldo insufficiente, oppure un underflow su `s_asset1Reserve -= ...`. Con un TVL di 1M$ l'errore vale circa 1$, cioè molto più di 1 wei o 1 satoshi.

**Scenario**
L'ultimo holder, per esempio la multisig dopo l'uscita di tutti gli utenti, non riesce a riscattare l'intero saldo e deve lasciare della polvere. Nessun test copre il redeem di `totalSupply()`.

**Raccomandazione**
Quando `_sharesAmount == totalSupply()`, vendere direttamente `s_asset0Reserve` e `s_asset1Reserve`. In generale, limitare la quantità venduta con `min(amount, reserve)`.

---

### [L-02] Griefing tramite front-run della firma permit

**Severità:** Low
**File:** `src/Router.sol:97-105`

**Descrizione**
`buyExactUsdcAmountOfSharesWithPermit` chiama `permit` senza `try/catch`. Un osservatore del mempool può inviare prima la stessa firma direttamente a `USDC.permit`. Il nonce viene consumato e la transazione dell'utente reverta. I fondi non sono a rischio (l'allowance resta impostata), ma l'utente perde gas e deve riprovare con `buyExactUsdcAmountOfShares`.

**Raccomandazione**

```solidity
try IERC20Permit(address(i_usdc)).permit(msg.sender, _indexAddress, _usdcAmount, _deadline, _v, _r, _s) {}
catch {
    if (i_usdc.allowance(msg.sender, _indexAddress) < _usdcAmount) revert Router__PermitFailed();
}
```

---

### [L-03] WBTC prezzato con il feed BTC/USD (parzialmente risolto)

**Severità:** Low
**Stato:** parzialmente risolto
**File (codice attuale):** `src/PriceFeedManager.sol:241-248`, `script/CodeConstants.sol:40-41`, `script/HelperConfig.s.sol:95-99`

**Già risolto**
`MAX_DELAY` e `MAX_USDC_DELAY` globali sono stati rimossi. Ogni feed registrato nel `PriceFeedManager` ha un proprio `maxDelay` (fra 0 e `MAX_FEED_DELAY_LIMIT`). Gli script usano l'heartbeat più un margine: 1 h 15 min per gli asset e 25 h per USDC (`ASSET_USD_PRICEFEED_MAX_DELAY` e `USDC_USD_PRICEFEED_MAX_DELAY`). Un aggiornamento per heartbeat arrivato qualche secondo dopo i 3600 s non blocca più il protocollo.

**Ancora aperto**
- `WBTC_USD_PRICEFEED_MAINNET` punta al feed BTC/USD. Un depeg di WBTC rispetto a BTC non viene rilevato: l'index valuta WBTC al prezzo di BTC e un utente può riscattare a un NAV gonfiato.
- `answeredInRound >= roundId` è ancora controllato, ma il campo è deprecato e non aggiunge protezione.
- I valori di heartbeat sono da confermare su data.chain.link per ogni rete.

**Raccomandazione**
Prezzare WBTC componendo WBTC/BTC × BTC/USD, per esempio estendendo `FeedConfig` con un secondo feed tramite upgrade del `PriceFeedManager`.

---

### [I-01] Discrepanze fra specifica/NatSpec e codice

- `invariant.md` (SwapManager #13) parla di `SETTLE_ALL`, mentre il codice usa `SETTLE` (`SwapManager.sol:219`). Il codice è corretto per `payerIsUser = false`; la documentazione no.
- `_calculateFees` (`Index.sol:866-870`) dichiara input a 18 decimali, ma in `mintShares` riceve 6 decimali.
- `_initFunctionValues` (`Index.sol:889-890`) documenta le riserve "in token decimals", ma restituisce valori in 18 decimali.
- `ContractCodeConstants.sol` descrive `PERCENTAGE_FEE_PRECISION`, il valore percentuale massimo e la soglia di rebalance "in basis points". In realtà 10.000 unità corrispondono all'1%, quindi l'unità è 0,0001%.
- NatSpec di `rebalanceIndex` (`Index.sol:679`): "Reverts if there are no fees to collect" è copiato da `collectFees`.
- NatSpec di `rebalanceMultipleIndexes` e `collectFeesFromMultipleIndexes` (`IndexManager.sol:310, 482`): "the entire transaction will revert", ma il codice cattura gli errori.
- Router (`Router.sol:110, 151`): "Set Allowance to the index contract to spend Shares", ma `redeem` brucia senza allowance.
- Il README, nell'introduzione, parla di soli "Uniswap V3 swaps", mentre il codice supporta anche V4.

### [I-04] Loop non limitati sugli index

`rebalanceAllIndexes`, `executeWeightUpdateForAllIndexes` e `collectFeesFromAllIndexes` iterano su `s_initializedIndexes` senza limite. Le funzioni sono accessibili solo ai ruoli e esistono alternative a sottoinsiemi, ma ogni rebalance include swap costosi e con molti index si supera il block gas limit. Conviene aggiungere una paginazione `(start, end)`.

### [I-05] Ordine CEI in `redeem`, errori inutilizzati, modifier prima di `nonReentrant`

- `redeem` trasferisce gli USDC (`Index.sol:480`) prima di `_burn` (`:483`). Con USDC non è sfruttabile, ma è preferibile bruciare prima della chiamata esterna.
- Gli errori `Index__TransferFailed`, `Index__UnauthorizedCallback`, `Index__DecimalsNotCorrect`, `IndexManager__UnderlyingAssetNotERC20`, `IndexManager__PriceFeedNotAvailable`, `IndexManager__InvalidPercentage` e `Router__CannotSpecifyBothAmounts` non sono mai usati.
- In `Router.sol:66-67, 94-95, 124-125`, `validInputs` (con chiamate esterne) viene eseguito prima di `nonReentrant`. Conviene mettere `nonReentrant` per primo.

### [G-01] Letture ripetute degli oracoli

`_swapAssetsForUsdc` (`Index.sol:1057, 1070`) rilegge `getLatestPrice` già disponibile in `initState`. `rebalanceIndex` (`:777`) richiama `getAssetsUsdValue()`, che rilegge 3 feed. Basta ricalcolare il valore con i prezzi in cache e le nuove riserve.

### [G-02] `_reverseV3Path` copia byte per byte

`SwapManager.sol:396-421` usa un doppio loop sui singoli byte. Conviene salvare entrambe le direzioni in fase di registrazione, oppure invertire con `mcopy`.

### [G-03] Validazioni ridondanti nel Router

`_validBalance` (`Router.sol:240-263`) è ridondante: `safeTransferFrom` e `_burn` revertano comunque. È una chiamata esterna in più per ogni operazione.

### [G-04] SLOAD ripetuti in `rebalanceIndex`

`s_asset0Reserve` e `s_asset1Reserve` vengono letti più volte (`Index.sol:740-772`), anche se sono già disponibili in cache. In `retrieveAmountFromAmount` vengono fatte chiamate esterne a `decimals()`, mentre l'Index espone già `getAssetsAndUsdcDecimals()`.

---

## 3.1 Note emerse durante le correzioni

Non sono finding classificati della review iniziale, ma punti aperti individuati durante l'implementazione delle correzioni.

- **Dimensione dei contratti (EIP-170).** Con la configurazione attuale (nessun optimizer, nessun `via_ir`) `Index` occupa 32.883 byte e `IndexManager` 65.885 byte, entrambi sopra il limite di 24.576 byte. Così come sono, non sono deployabili su mainnet. Il problema esisteva già prima delle correzioni.
- **Upgrade tramite `TimelockController`.** Il timelock custom dell'`IndexManager` è stato sostituito dal `TimelockController` di OpenZeppelin, unico `upgrader` dei tre proxy (`UpgraderAuth`). Conseguenze accettate:
  - **Nessuna finestra di esecuzione.** Un upgrade schedulato resta eseguibile finché non viene eseguito o cancellato; le operazioni superate vanno annullate a mano con `cancel`.
  - **Validazione solo all'esecuzione.** Implementazione senza codice o non UUPS viene rifiutata solo da `upgradeToAndCall` all'`execute`, dopo i 2 giorni. Non c'è controllo di tipo: per errore si potrebbe schedulare l'implementazione del `PriceFeedManager` per lo SwapManager. Il delay lascia tempo per accorgersene e cancellare.
  - **Eventi generici.** La proposta è visibile solo come `CallScheduled` del timelock: proxy in `target`, implementazione e calldata da decodificare da `data`.
  - **Upgrader non modificabile.** Non c'è setter; se il timelock diventa inutilizzabile (per esempio chiavi del MultiSig perse), i proxy non si possono più aggiornare.
- **`getPrice` va in panic con `updatedAt` nel futuro.** `block.timestamp - updatedAt` (`PriceFeedManager.sol:248`) va in underflow invece di revertire con un errore dedicato. Un feed Chainlink reale non lo produce, ma un feed difettoso bloccherebbe le letture con un panic poco leggibile.
- **`IndexManager__IndexDeployFailed` nasconde il motivo.** Se `create2` fallisce, il motivo del revert del costruttore dell'Index va perso.

---

## 4. Note sulla centralizzazione e assunzioni di fiducia

- **ASSET_MANAGER_ROLE (MultiSig 2-di-3 secondo `DeployPeriphery.s.sol`)**
  - Sceglie le route di swap in fase di init. I token di ogni route ora sono verificati contro gli asset dell'index (L-04 risolto), ma la scelta del pool resta libera: può indirizzare gli swap verso pool illiquidi o con hook V4 controllati ed estrarre fino alla tolleranza dell'utente (< 10%) su mint e redeem. Sui rebalance il `minOut` all'1% sotto l'oracolo limita l'estrazione per swap (H-01 risolto).
  - Decide i pesi con 2 giorni di delay, una finestra di esecuzione e la possibilità di cancellare (L-05 risolto).
  - Registra i feed e ne propone la sostituzione, con 2 giorni di delay. Una sostituzione vale per tutti gli index che usano quell'asset.
  - Il parametro `_depositor` di `initializeIndex` è arbitrario: può prelevare `asset0` e `asset1` da qualsiasi indirizzo che abbia dato approve all'Index.
- **TimelockController (MultiSig proposer, executor e canceller, nessun admin)** è l'unico che può fare upgrade di SwapManager, `PriceFeedManager` e Router, con almeno 2 giorni di delay. `DEFAULT_ADMIN_ROLE` dell'IndexManager non ha più poteri di upgrade. Un upgrade può cambiare arbitrariamente la logica di swap, di prezzo e di accesso per tutti gli index. Il Router è il caso più delicato: gli utenti danno l'approve degli USDC all'Index e `redeem` brucia le shares senza allowance, quindi una logica del Router malevola potrebbe mintare con gli USDC approvati da un utente qualsiasi (con una tolleranza a sua scelta) o forzare un redeem. Il delay del timelock e la calldata visibile in `CallScheduled` danno agli utenti il tempo di revocare gli approve o uscire.
- **REBALANCER_ROLE e FEE_COLLECTOR_ROLE restano all'EOA del deployer.** `DeployPeriphery.s.sol` revoca al deployer solo `ASSET_MANAGER_ROLE` e `DEFAULT_ADMIN_ROLE`. Una singola chiave decide quando ribilanciare; con il `minOut` introdotto per H-01 il margine di sandwich è limitato all'1% per swap, ma resta. Le fee arrivano a un EOA.
- **MultiSigWallet:** owner e soglia sono immutabili. Senza rotazione delle chiavi, la perdita o compromissione di 2 chiavi su 3 è irrimediabile.
- **Configurazione degli index.** Feed e logica di swap sono ora aggiornabili con timelock; route, Universal Router e `ROUTER_ROLE` restano fissi e non c'è pausa né redeem in-kind (M-02).
- **Dipendenze esterne:** Chainlink (freschezza, deprecazione dei feed, uso di BTC/USD per WBTC) e Uniswap Universal Router (indirizzo immutabile, `payerIsUser = false` con token pre-trasferiti nello stesso tx). Gli hook V4 delle `PoolKey` configurate sono considerati fidati.

---

## 5. Osservazioni generali

- **Design delle riserve.** La contabilità interna (`s_asset*Reserve`) invece di `balanceOf` neutralizza correttamente gli attacchi di donazione e inflazione delle shares. È una scelta valida.
- **Gestione dei decimali.** È stata la principale fonte di errori: C-01 (ora risolto) nasceva da un valore a 18 decimali finito in un accumulatore a 6, in un codice che alterna continuamente 6, 8 e 18 decimali. Conviene introdurre tipi o suffissi rigorosi (`...Std`, `...TokenDec`) anche per i valori di ritorno di `_swapAssetsForUsdc` e `_calculateFees`, e scrivere test end-to-end che attraversino più operazioni (mint → redeem → collect).
- **Slippage.** Con la correzione di H-01 i rebalance hanno un `minOut` derivato dall'oracolo e un controllo proporzionato al nozionale. Mint e redeem restano protetti dalla tolleranza dell'utente e dipendono comunque dalla freschezza e dall'accuratezza dell'oracolo (L-03, M-04).
- **Test.** Le correzioni hanno aggiunto test per fee raccolte dopo un redeem, scadenza dei feed al limite del `maxDelay`, sostituzione dei feed, upgrade con timelock, validazione delle route e firme della multisig (878 test in totale). Restano scoperti il redeem del 100% della supply (L-01) e i test di invarianti e fuzz su `UnderlyingMath`, già indicati nel README come lavoro futuro.
- **MultiSigWallet.** È un'implementazione minimale corretta nei punti essenziali: `executed` impostato prima della call, ECDSA OpenZeppelin con protezione dalla malleabilità, dominio EIP-712 con chainId e verifyingContract. Le firme ora sono legate al contenuto della transazione (L-06 risolto). Manca la gestione di owner e soglia. In produzione conviene usare Safe.

---

## 6. Fuori scope

- **Non revisionati:** `script/` (letto solo `DeployPeriphery.s.sol`, `DeployAndInitNewIndex.s.sol` e `CodeConstants.sol` per l'assegnazione dei ruoli), `test/` (letti solo i file citati, nessun test eseguito), `sdk/`, `indexer/` e altri componenti off-chain.
- **Dipendenze lette ma non auditate:** OpenZeppelin (`AccessControl`, `ERC20Permit`, `SafeERC20`, `EIP712`, `ECDSA`, `ReentrancyGuard`, `Ownable`), Chainlink `AggregatorV3Interface`, Uniswap `v4-core`, `v4-periphery` (`IV4Router`, `Actions`) e `universal-router` (`Commands`, `Dispatcher`). Sono state consultate solo per confermare la codifica dei parametri e il comportamento atteso.
- **Non verificabile dal codice:** heartbeat e deviation threshold effettivi dei feed mainnet (L-03, M-04), liquidità e fee dei pool configurati in `HelperConfig`, comportamento degli hook V4, configurazione reale delle chiavi della multisig.
- **Review iniziale senza esecuzione** di build, test o fork. Le correzioni successive sono state verificate con `forge test`, ma i finding ancora marcati "da verificare" (M-04, L-01) richiedono un test dedicato prima di essere considerati confermati.

---

## 7. Valutazione complessiva del rischio

**Review iniziale (2026-10-08).** Il rischio era dominato da due fattori: la conversione fra decimali, da cui nasceva l'unico difetto critico (C-01), e una protezione dallo slippage basata solo su controlli a posteriori tarati sul TVL (H-01). A questi si aggiungeva una configurazione completamente immutabile.

**Stato attuale (2026-10-10).** Non restano finding Critical né High. C-01 e H-01 sono corretti e coperti da test; SwapManager e feed sono gestiti da proxy condivisi aggiornabili con timelock; route, pesi e firme della multisig sono validati.

Il rischio residuo principale è operativo: non esiste un'uscita senza swap e le route non si possono cambiare (M-02), quindi un pool svuotato o un feed fermo lasciano i fondi bloccati per giorni o finché non viene fatto un upgrade. Restano da quantificare l'arbitraggio sul ritardo dell'oracolo (M-04) e il redeem dell'intera supply (L-01). Infine, `Index` e `IndexManager` superano il limite EIP-170 e non sono deployabili su mainnet senza optimizer o una divisione del codice.

Prima di un deploy con valore reale servono: un percorso di redeem in-kind, un wrapper con timelock per `updateRoute`, la soluzione del limite di dimensione dei contratti, la verifica di M-04 su fork e una suite di test di invarianti.
