# Security Review: On-Chain Asset Manager

**Data:** 2026-10-08
**Commit:** `07bba933` (branch `master`, working tree pulito)
**Revisore:** audit manuale (Claude), sola lettura

---

## 1. Scope e metodologia

### File in scope (`src/`, 4593 righe)

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
| Informational | 5 |
| Gas | 4 |

| ID | Titolo | Severità |
|---|---|---|
| M-02 | Configurazione degli index non modificabile e nessuna uscita senza swap: `updateRoute` irraggiungibile, feed e router immutabili | Medium |
| M-04 | NAV calcolato con l'oracolo ma esecuzione su un solo asset: arbitraggio sul ritardo dell'oracolo (da verificare) | Medium |
| L-01 | Il redeem del 100% della supply reverta per arrotondamento (da verificare) | Low |
| L-02 | Griefing tramite front-run della firma permit | Low |
| L-03 | `MAX_DELAY` uguale all'heartbeat dei feed: DoS transitorio (da verificare per ogni feed) | Low |
| I-01 | Discrepanze fra specifica/NatSpec e codice | Info |
| I-02 | `forge-std/console2` importato in codice di produzione | Info |
| I-03 | Codifica incoerente dei motivi di errore nei try/catch | Info |
| I-04 | Loop non limitati sugli index | Info |
| I-05 | Ordine CEI in `redeem`, errori inutilizzati, modifier di validazione prima di `nonReentrant` | Info |
| G-01..G-04 | Ottimizzazioni gas | Gas |

---

## 3. Findings

### [M-02] Configurazione degli index non modificabile e nessuna uscita senza swap: `updateRoute` irraggiungibile, feed e router immutabili

**Severità:** Medium
**File:** `src/SwapManager.sol:32-34`, `src/SwapManager.sol:65-72`, `src/IndexManager.sol` (assenza di wrapper), `src/Index.sol:56-69`, `src/Index.sol:137-140`

**Descrizione**
La radice comune è che, per un index già deployato, nessuna dipendenza esterna può essere cambiata, e l'unico modo di uscire passa da oracolo e swap.

1. `SwapManager` è `Ownable(_indexManager)` e `updateRoute` è `onlyOwner`, ma `IndexManager` non ha nessuna funzione che chiami `updateRoute` o `transferOwnership`. Le route sono quindi **fisse per sempre**, nonostante l'invariante SwapManager #5/#6 ne presupponga l'aggiornabilità.
2. I price feed (`i_asset0PriceFeed`, `i_asset1PriceFeed`, `i_usdcPriceFeed`), `i_swapManager` e `i_universalRouter` sono immutabili.
3. `DEFAULT_ADMIN_ROLE` sull'Index appartiene a `IndexManager`, che non espone `grantRole`/`revokeRole` sugli index. `ROUTER_ROLE` non può quindi passare a un nuovo Router.
4. Non esiste un redeem in-kind né una pausa o un'uscita di emergenza: `redeem` richiede sempre feed validi e swap riusciti.

**Scenario**
- La liquidità del pool V3 configurato migra altrove, oppure il pool viene manipolato in modo persistente. Ogni redeem subisce slippage superiore alla tolleranza massima (< 10%) e reverta, e le route non si possono cambiare. Gli utenti possono uscire solo accettando perdite elevate, o non possono uscire affatto.
- Chainlink depreca un feed (è già successo per diversi asset) oppure il feed si ferma oltre `MAX_DELAY`. `getLatestPrice` reverta, quindi mint, redeem e rebalance si bloccano permanentemente e i fondi degli utenti restano congelati.

**Raccomandazione**
- In `IndexManager`, aggiungere `updateIndexRoute(address index, SwapType t, SwapRoute calldata r) onlyRole(ASSET_MANAGER_ROLE)` che inoltri a `updateRoute`.
- Nell'Index, aggiungere un `redeemInKind(address from, uint256 shares)` che bruci le shares e trasferisca la quota pro-rata di `s_asset0Reserve` e `s_asset1Reserve`, senza oracolo né swap. È l'uscita di emergenza minima per i fondi degli utenti.
- Valutare se rendere i feed sostituibili con timelock.

Il trade-off è una maggiore superficie di fiducia verso l'asset manager. Va mitigata con un timelock sulle modifiche di route e feed.

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

### [L-03] `MAX_DELAY` uguale all'heartbeat dei feed: DoS transitorio (da verificare per ogni feed)

**Severità:** Low
**File:** `src/ContractCodeConstants.sol:9`, `src/Index.sol:1404-1412`

**Descrizione**
`MAX_DELAY = 1 hours` coincide con l'heartbeat dei feed ETH/USD, BTC/USD, LINK/USD e COMP/USD su mainnet, valore da confermare su data.chain.link. Un aggiornamento per heartbeat arriva spesso qualche secondo o blocco dopo i 3600 s. In quella finestra `getLatestPrice` reverta e blocca mint, redeem e rebalance.

`answeredInRound` è deprecato e non aggiunge protezione. WBTC è prezzato con il feed BTC/USD, quindi un depeg di WBTC non viene rilevato.

**Raccomandazione**
Usare un limite per feed, pari all'heartbeat più un margine (per esempio `heartbeat + 15 min`), passato al costruttore. Valutare un feed WBTC/BTC.

---

### [I-01] Discrepanze fra specifica/NatSpec e codice

- `invariant.md` (SwapManager #13) parla di `SETTLE_ALL`, mentre il codice usa `SETTLE` (`SwapManager.sol:219`). Il codice è corretto per `payerIsUser = false`; la documentazione no.
- `_calculateFees` (`Index.sol:866-870`) dichiara input a 18 decimali, ma in `mintShares` riceve 6 decimali.
- `_initFunctionValues` (`Index.sol:889-890`) documenta le riserve "in token decimals", ma restituisce valori in 18 decimali.
- `ContractCodeConstants.sol:24, 68` descrive `PERCENTAGE_FEE_PRECISION` e `MAX_SLIPPAGE_TOLERANCE` "in basis points". In realtà 10.000 unità corrispondono all'1%, quindi l'unità è 0,0001%.
- NatSpec di `rebalanceIndex` (`Index.sol:679`): "Reverts if there are no fees to collect" è copiato da `collectFees`.
- NatSpec di `rebalanceMultipleIndexes` e `collectFeesFromMultipleIndexes` (`IndexManager.sol:310, 482`): "the entire transaction will revert", ma il codice cattura gli errori.
- Router (`Router.sol:110, 151`): "Set Allowance to the index contract to spend Shares", ma `redeem` brucia senza allowance.
- Il README parla di soli "Uniswap V3 swaps", mentre il codice supporta anche V4.

### [I-02] `forge-std/console2` importato in codice di produzione

`src/IndexManager.sol:20`. Va rimosso: crea una dipendenza da una libreria di test.

### [I-03] Codifica incoerente dei motivi di errore nei try/catch

`IndexManager._rebalanceSingleIndex` (`:689-691`) e gli altri wrapper restituiscono `bytes(_reason)` grezzi per `Error(string)`. Il ramo low-level restituisce invece selector più dati ABI, e `Index._tryRebalanceIndex` ricodifica con il selector. Un indexer o l'SDK non può decodificare gli eventi `*Failed` in modo uniforme. Conviene restituire sempre `returndata` grezzo.

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

## 4. Note sulla centralizzazione e assunzioni di fiducia

- **ASSET_MANAGER_ROLE (MultiSig 2-di-3 secondo `DeployPeriphery.s.sol`)**
  - Sceglie le route di swap in fase di init senza vincoli sui token. Può indirizzare gli swap verso pool illiquidi o controllati ed estrarre fino alla tolleranza dell'utente (< 10%) su mint e redeem, e fino al 2% del TVL per ogni rebalance (H-01).
  - Decide i pesi: il delay è di 2 giorni, ma senza scadenza né cancellazione (L-05).
  - Il parametro `_depositor` di `initializeIndex` è arbitrario: può prelevare `asset0` e `asset1` da qualsiasi indirizzo che abbia dato approve all'Index.
- **REBALANCER_ROLE e FEE_COLLECTOR_ROLE restano all'EOA del deployer.** `DeployPeriphery.s.sol:69-79` revoca solo `ASSET_MANAGER_ROLE` e `DEFAULT_ADMIN_ROLE`. Una singola chiave decide quando ribilanciare e può quindi sandwichare i propri rebalance (H-01). Le fee arrivano a un EOA.
- **MultiSigWallet:** owner e soglia sono immutabili. Senza rotazione delle chiavi, la perdita o compromissione di 2 chiavi su 3 è irrimediabile.
- **Configurazione immutabile per index** (feed, router, swap manager, route), nessuna pausa e nessun upgrade (M-02). Da un lato elimina il rischio di rug tramite riconfigurazione, dall'altro rende impossibile correggere errori o reagire a guasti esterni.
- **Dipendenze esterne:** Chainlink (freschezza, deprecazione dei feed, uso di BTC/USD per WBTC) e Uniswap Universal Router (indirizzo immutabile, `payerIsUser = false` con token pre-trasferiti nello stesso tx). Gli hook V4 delle `PoolKey` configurate sono considerati fidati.

---

## 5. Osservazioni generali

- **Design delle riserve.** La contabilità interna (`s_asset*Reserve`) invece di `balanceOf` neutralizza correttamente gli attacchi di donazione e inflazione delle shares. È una scelta valida.
- **Gestione dei decimali.** È la principale fonte di errori: C-01 nasce da un valore a 18 decimali finito in un accumulatore a 6, in un codice che alterna continuamente 6, 8 e 18 decimali. Conviene introdurre tipi o suffissi rigorosi (`...Std`, `...TokenDec`) anche per i valori di ritorno di `_swapAssetsForUsdc` e `_calculateFees`, e scrivere test end-to-end che attraversino più operazioni (mint → redeem → collect).
- **Slippage.** Il modello "swap con `minOut = 0` + controllo a posteriori sull'oracolo" funziona solo se la soglia è proporzionata al nozionale (H-01) e se l'oracolo è fresco (L-03, M-04).
- **Test.** I test coprono bene i percorsi felici dei singoli contratti, ma mancano le sequenze composite e i casi limite: fee raccolte dopo un redeem, redeem del 100% della supply, pesi sotto il 3%, cambio di SwapManager fra create e initialize, scadenza dei feed al limite dell'heartbeat. Mancano anche test di invarianti e fuzz su `UnderlyingMath`, già indicati nel README come lavoro futuro.
- **MultiSigWallet.** È un'implementazione minimale corretta nei punti essenziali: `executed` impostato prima della call, ECDSA OpenZeppelin con protezione dalla malleabilità, dominio EIP-712 con chainId e verifyingContract. Mancano gestione owner/soglia e il vincolo della firma al contenuto (L-06). In produzione conviene usare Safe.

---

## 6. Fuori scope

- **Non revisionati:** `script/` (letto solo `DeployPeriphery.s.sol`, `DeployAndInitNewIndex.s.sol` e `CodeConstants.sol` per l'assegnazione dei ruoli), `test/` (letti solo i file citati, nessun test eseguito), `sdk/`, `indexer/` e altri componenti off-chain.
- **Dipendenze lette ma non auditate:** OpenZeppelin (`AccessControl`, `ERC20Permit`, `SafeERC20`, `EIP712`, `ECDSA`, `ReentrancyGuard`, `Ownable`), Chainlink `AggregatorV3Interface`, Uniswap `v4-core`, `v4-periphery` (`IV4Router`, `Actions`) e `universal-router` (`Commands`, `Dispatcher`). Sono state consultate solo per confermare la codifica dei parametri e il comportamento atteso.
- **Non verificabile dal codice:** heartbeat e deviation threshold effettivi dei feed mainnet (L-03, M-04), liquidità e fee dei pool configurati in `HelperConfig`, comportamento degli hook V4, configurazione reale delle chiavi della multisig.
- **Nessuna esecuzione** di build, test o fork. I finding marcati "da verificare" richiedono un test dedicato prima di essere considerati confermati.

---

## 7. Valutazione complessiva del rischio

Il rischio è dominato da due fattori. Il primo è la conversione fra decimali, in un codice che passa di continuo da 6 a 8 a 18 cifre: lì nasce l'unico difetto critico (C-01), che blocca in modo deterministico tutte le entrate del protocollo al primo redeem e che i test non intercettano, perché nessun test collega fra loro più operazioni. Il secondo è la protezione dallo slippage, che dipende interamente da controlli a posteriori basati sull'oracolo e tarati sul TVL invece che sul nozionale scambiato: i rebalance, eseguiti per giunta da un singolo EOA, sono così una fonte di valore estraibile dai searcher. A questo si aggiunge una rigidità strutturale: route, feed e router non sono modificabili e non esiste un'uscita senza swap. Un errore di configurazione (M-01) o un guasto esterno (pool svuotato, feed deprecato) si traduce quindi in fondi utente bloccati invece che in un incidente recuperabile. I fondi degli utenti non sono esposti a furto diretto da parte di terzi: la contabilità interna delle riserve e il gating del Router reggono. Prima di qualsiasi deploy con valore reale servono la correzione di C-01, `minOut` derivato dall'oracolo negli swap, un percorso di redeem in-kind e una suite di test di invarianti.
