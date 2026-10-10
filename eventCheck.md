# Event check: audit degli eventi per l'indexer

Data: 2026-10-08. Ambito: `src/` (Index, IndexManager, SwapManager, MultiSigWallet, Router, types, ContractCodeConstants, libraries, events, Interface). Gli ABI di riferimento sono quelli in `out/`, verificati con `jq` e coerenti con i sorgenti.

## Sommario

- **23 eventi custom** dichiarati in 3 file (8 Index, 11 IndexManager, 4 MultiSig) (`src/events/*`), **tutti emessi** almeno una volta. Router, SwapManager, librerie, interfacce e `types.sol` non dichiarano né emettono eventi.
- **3 collisioni di nome** tra `IndexEvents.sol` e `IndexManagerEvents.sol`: `IndexInitialized`, `IndexRebalanced`, `FeesCollected`. Firme diverse, quindi topic0 diversi, ma il generatore di schema dell'indexer deduplica per nome e ha già perso le tre varianti di IndexManager (`indexer/prisma/schema.prisma`).
- **Doppie emissioni** per la stessa azione: rebalance, proposta pesi, initialize e fee collection emettono un evento sia in Index sia in IndexManager. Per le fee si arriva a 3 log (Transfer USDC + 2 eventi custom).
- **SwapManager non emette nulla**: le route di swap registrate in `registerIndex` non sono ricostruibili dagli eventi.
- **Le fee per singola operazione non sono mai emesse** e `feePercentage` non compare in nessun evento: l'indexer non può ricostruire `s_totalFees`.
- **Bug di unità sulle fee** (fuori dallo scope eventi, ma rende sbagliato `FeesCollected.feeAmount`): `mintShares` accumula fee in decimali USDC (6), `redeem` in 18 decimali.
- `WeightUpdateExecuted` viene emesso anche quando il rebalance interno fallisce, e `WeightUpdateRebalanceFailed` scatta anche nel caso normale "rebalance non necessario".
- `IndexCreated` non porta i parametri di configurazione (fee, pesi, price feed): l'indexer deve fare chiamate `eth_call` per completare l'entità Index.
- Lo schema Prisma attuale non ha una colonna con l'indirizzo del contratto emittente: con N contratti Index che emettono gli stessi eventi, le righe non sono attribuibili all'indice giusto.

---

## 1. Inventario

### 1.1 Index (`src/Index.sol`, eventi in `src/events/IndexEvents.sol`)

| Evento | Dichiarazione | Parametri (indexed in grassetto) | Emit | Funzione | Valori passati |
|---|---|---|---|---|---|
| `IndexInitialized` | IndexEvents.sol:4 | underlyingAmount0, underlyingAmount1, underlying0UsdValue, underlying1UsdValue, initialShares (nessuno indexed) | Index.sol:223 | `initialize` (153) | `_underlyingAmount0` (input), `underlyingAmount1TokenDec`, USD value 18 dec, `initialShares` |
| `SharesMinted` | IndexEvents.sol:12 | **user**, usdcAmountIn, sharesMinted, token0Added, token1Added | Index.sol:367 | `mintShares` (239) | `_to`, `_usdcAmountIn` lordo (pre-fee, decimali USDC), `sharesToMint`, delta reserve in decimali token |
| `SharesBurned` | IndexEvents.sol:20 | **user**, sharesBurned, token0Removed, token1Removed, usdcAmountOut | Index.sol:485 | `redeem` (382) | `_from`, `_sharesAmount`, delta di balance reale, `netUsdcAmountTokenDec` netto (post-fee) |
| `IndexRebalanced` | IndexEvents.sol:28 | initAsset0Reserve, initAsset1Reserve, newAsset0Reserve, newAsset1Reserve, **rebalanceTimestamp** | Index.sol:787 | `rebalanceIndex` (682) | reserve prima/dopo (decimali token), `block.timestamp` |
| `WeightsUpdateProposed` | IndexEvents.sol:36 | newWeightAsset0, newWeightAsset1, **implementationTimestamp** | Index.sol:615 | `proposeUpdateWeights` (587) | letti dallo storage appena scritto |
| `IndexWeightsUpdated` | IndexEvents.sol:42 | newWeightAsset0, newWeightAsset1, **updateTimestamp** | Index.sol:647 | `executeWeightUpdate` (626) | `s_weight0`, `s_weight1`, `block.timestamp` |
| `WeightUpdateRebalanceFailed` | IndexEvents.sol:48 | reasonData (bytes) | Index.sol:644 | `executeWeightUpdate` (626) | revert data da `_tryRebalanceIndex` (1230) |
| `FeesCollected` | IndexEvents.sol:50 | **feeCollector**, feeAmount | Index.sol:673 | `collectFees` (656) | `_collector`, `s_totalFees` azzerato |

Eventi ereditati presenti nell'ABI di Index (OpenZeppelin, non auditati):

| Evento | Origine | Quando scatta in questo progetto |
|---|---|---|
| `Transfer(from, to, value)` | ERC20 | `_mint` in `initialize` (Index.sol:220) e `mintShares` (350), `_burn` in `redeem` (483), transfer utente |
| `Approval(owner, spender, value)` | ERC20 / ERC20Permit | `approve`, `permit` sulle share, `transferFrom` |
| `RoleGranted` | AccessControl | 4 volte nel costruttore (Index.sol:137-140): DEFAULT_ADMIN e INDEX_MANAGER a IndexManager, INDEX_MANAGER a `address(this)`, ROUTER_ROLE al router |
| `RoleRevoked`, `RoleAdminChanged` | AccessControl | In pratica mai: l'admin è IndexManager, che non espone `grantRole`/`revokeRole` verso Index |
| `EIP712DomainChanged` | EIP712 | Mai (nessun upgrade) |

Anche i token sottostanti e USDC emettono `Transfer` durante mint, redeem, rebalance e collect: sono log di altri contratti, utili per riconciliare ma non necessari.

### 1.2 IndexManager (`src/IndexManager.sol`, eventi in `src/events/IndexManagerEvents.sol`)

| Evento | Dichiarazione | Parametri (indexed in grassetto) | Emit | Funzione |
|---|---|---|---|---|
| `RouterAddressSet` | IndexManagerEvents.sol:4 | **newRouter**, **setter** | :96 | `setRouterAddress` (91) |
| `SwapManagerAddressSet` | :6 | **newSwapManager**, **setter** | :108 | `setSwapManagerAddress` (103) |
| `IndexCreated` | :8 | **indexAddress**, **asset0**, **asset1**, assetManager | :194 | `createIndex` (119) |
| `IndexInitialized` | :15 | **indexAddress**, **assetManager** | :238 | `initializeIndex` (208) |
| `IndexRebalanced` | :19 | **indexAddress**, **rebalancer** | :303, :329, :352 | `rebalanceSingleIndex` (289), `rebalanceMultipleIndexes` (313), `rebalanceAllIndexes` (338) |
| `IndexRebalanceFailed` | :21 | **indexAddress**, reasonData | :301, :327, :350 | stesse tre funzioni |
| `NewIndexWeightsProposed` | :23 | **indexAddress**, **assetManager**, oldWeightAsset0, oldWeightAsset1, newWeightAsset0, newWeightAsset1, implementationTimestamp | :376 | `proposeNewWeights` (362) |
| `FeesCollected` | :32 | **indexAddress**, **feeCollector**, feeAmount | :473, :502, :530 | `collectFeesFromSingleIndex` (463), `...MultipleIndexes` (484), `...AllIndexes` (518) |
| `FeesCollectionFailed` | :38 | **indexAddress**, **feeCollector**, reasonData | :475, :504, :532 | stesse tre funzioni |
| `WeightUpdateExecuted` | :44 | **indexAddress** | :405, :431, :454 | `executeSingleWeightUpdate` (391), `executeWeightUpdateForMultipleIndexes` (414), `executeWeightUpdateForAllIndexes` (440) |
| `WeightUpdateFailed` | :46 | **indexAddress**, reasonData | :403, :429, :452 | stesse tre funzioni |

Ereditati: `RoleGranted` x4 nel costruttore (IndexManager.sol:81-84), poi `RoleGranted`/`RoleRevoked` su ogni `grantRole`/`revokeRole`/`renounceRole` (AccessControl pubblico, quindi questi sì possono scattare). `RoleAdminChanged` mai.

### 1.3 MultiSigWallet (`src/MultiSigWallet.sol`, eventi in `src/events/MultiSigWalletEvents.sol`)

| Evento | Dichiarazione | Parametri (indexed in grassetto) | Emit | Funzione |
|---|---|---|---|---|
| `TransactionSubmitted` | MultiSigWalletEvents.sol:4 | **txId**, **proposer**, **target**, value, data | :108 | `submitTransaction` (91) |
| `TransactionConfirmed` | :11 | **txId**, **owner** | :128, :209 | `confirmTransaction` (115), `confirmTransactionWithSig` (174) |
| `ConfirmationRevoked` | :12 | **txId**, **owner** | :165 | `revokeConfirmation` (155) |
| `TransactionExecuted` | :13 | **txId**, **executor** | :148 | `executeTransaction` (135) |

Ereditato: `EIP712DomainChanged`, mai emesso.

### 1.4 SwapManager, Router, librerie, interfacce, types, constants

- `SwapManager` (`src/SwapManager.sol`): nessun evento custom. Unico evento è `OwnershipTransferred(address(0), indexManager)` dal costruttore `Ownable` (:32). `transferOwnership`/`renounceOwnership` sono chiamabili solo da IndexManager, che non le espone: in pratica l'evento scatta una volta sola.
- `Router` (`src/Router.sol`): nessun evento, ABI eventi vuoto. Non ha storage mutabile. Il permit su USDC (:97) fa emettere `Approval` al contratto USDC.
- `src/libraries/*`, `src/types.sol`, `src/ContractCodeConstants.sol`: nessun evento.
- `src/Interface/*`: nessuna interfaccia dichiara eventi. Chi usa l'ABI di `IIndex`/`IIndexManager`/`IMultiSigWallet` (per esempio l'SDK) non riceve le definizioni degli eventi.

---

## 2. Duplicati

### 2.1 Stesso nome, firme diverse (collisione)

| Nome | IndexEvents.sol | IndexManagerEvents.sol |
|---|---|---|
| `IndexInitialized` | :4 `(uint256,uint256,uint256,uint256,uint256)` | :15 `(address indexed,address indexed)` |
| `IndexRebalanced` | :28 `(uint256,uint256,uint256,uint256,uint256 indexed)` | :19 `(address indexed,address indexed)` |
| `FeesCollected` | :50 `(address indexed,uint256)` | :32 `(address indexed,address indexed,uint256)` |

Conseguenze concrete:

1. Gli eventi sono dichiarati a livello di file. Un file che fa `import "./events/IndexEvents.sol"` e `import "./events/IndexManagerEvents.sol"` non compila ("Identifier already declared"). Oggi i test aggirano il problema importandone uno per volta.
2. `indexer/scripts/generatePrismaModels.ts` deduplica per `event.name` (`seenEvents`). `out/Index.sol` viene letto prima di `out/IndexManager.sol`, quindi nello schema generato i modelli `IndexInitialized`, `IndexRebalanced`, `FeesCollected` hanno i campi di Index e le varianti di IndexManager sono sparite.
3. Con ethers v6, un `Interface` costruito su ABI uniti richiede la firma completa per risolvere il nome (`getEvent("FeesCollected")` è ambiguo).

### 2.2 Doppia emissione per la stessa azione

| Azione | Log emessi nella stessa tx (in ordine) | Informazione ridondante |
|---|---|---|
| Inizializzazione | `Transfer(0 → depositor)` (Index), `IndexInitialized` Index (Index.sol:223), `IndexInitialized` Manager (IndexManager.sol:238) | Il primo porta importi, il secondo porta indirizzo e caller. Nessuno porta il depositor: si recupera solo dal `Transfer` di mint |
| Rebalance manuale | `IndexRebalanced` Index (Index.sol:787), `IndexRebalanced` Manager (IndexManager.sol:303/329/352) | Il Manager aggiunge solo il `rebalancer` |
| Rebalance da weight update | solo `IndexRebalanced` Index | Il Manager non emette `IndexRebalanced` in questo caso, quindi l'evento del Manager non è una fonte completa dei rebalance |
| Proposta pesi | `WeightsUpdateProposed` Index (Index.sol:615), `NewIndexWeightsProposed` Manager (IndexManager.sol:376) | Pesi nuovi e timestamp identici. Il Manager aggiunge pesi vecchi e assetManager |
| Esecuzione pesi | `IndexWeightsUpdated` Index (Index.sol:647), `WeightUpdateExecuted` Manager (:405/431/454) | Il Manager non aggiunge nulla oltre l'indirizzo, che è già `log.address` dell'evento Index |
| Fee collection | `Transfer` USDC (Index → collector), `FeesCollected` Index (Index.sol:673), `FeesCollected` Manager (:473/502/530) | Stesso importo 3 volte |
| Mint / redeem | `Transfer` share + `SharesMinted`/`SharesBurned` | Parzialmente ridondante (user e shares). Accettabile: l'evento custom porta importi sottostanti e USDC che `Transfer` non ha |
| Router + Index | nessun duplicato: Router non emette eventi | ok |

Indicazione: tenere un solo livello come fonte di verità per ogni azione. Index è il livello giusto per i dati di stato (reserve, pesi, fee), perché emette sempre, anche quando l'azione parte da un percorso interno come `_tryRebalanceIndex`. Gli eventi del Manager servono solo per gli esiti `...Failed` e per l'attore (caller).

---

## 3. Incoerenze

### 3.1 Valori emessi che non corrispondono allo stato

1. **`FeesCollected.feeAmount` su unità miste** (Index.sol:673). In `mintShares` la fee è calcolata su `_usdcAmountIn` in decimali USDC (Index.sol:265-266). In `redeem` è calcolata su `usdcReceived`, che `_swapAssetsForUsdc` restituisce in 18 decimali (Index.sol:1145, 446, 473). `s_totalFees` somma le due cose, `collectFees` trasferisce quel numero come importo USDC grezzo (Index.sol:670). L'evento riporta un valore senza unità definita, e il transfer probabilmente revertisce o drena USDC appena c'è una redeem. È un bug di logica, segnalato qui perché rende inutilizzabile il dato dell'evento e `IndexManager.s_totalFeesCollected` (IndexManager.sol:472, 511, 539).
2. **`WeightUpdateExecuted` anche con rebalance fallito** (IndexManager.sol:405). `Index.executeWeightUpdate` cattura il fallimento del rebalance (Index.sol:643-644) e ritorna normalmente, quindi il Manager vede successo. L'unico segnale è `WeightUpdateRebalanceFailed` dell'Index nella stessa tx.
3. **`WeightUpdateRebalanceFailed` nel caso normale** (Index.sol:644). Se dopo il cambio pesi la deviazione è sotto `REBALANCE_THRESHOLD`, `rebalanceIndex` revertisce con `Index__RebalanceNotNeeded` (Index.sol:702) e l'evento dice "failed". L'indexer deve decodificare il selector per distinguerlo da un fallimento vero.
4. **Ordine dei log in `executeWeightUpdate`**: il rebalance (con il suo `IndexRebalanced`) viene eseguito prima di emettere `IndexWeightsUpdated` (Index.sol:643 vs 647). Un indexer che processa in ordine di `logIndex` vede un rebalance verso pesi che, secondo il suo stato, non sono ancora attivi.
5. **`IndexCreated` con `address(0)`**. `_deployIndex` usa `create2` in assembly senza controllare il risultato (IndexManager.sol:635-637). Se il costruttore di Index revertisce, `index` è zero, viene salvato nei mapping ed emesso in `IndexCreated` (:194). L'indexer creerebbe una data source su `0x0`.
6. **`IndexInitialized` (Index) emette l'input** `_underlyingAmount0` (Index.sol:224) invece del delta di balance. Coincide finché l'asset non è fee-on-transfer. Rischio basso, da documentare.
7. **`SharesMinted.usdcAmountIn` è lordo, `SharesBurned.usdcAmountOut` è netto** (Index.sol:369 e 490). Nessuno dei due riporta la fee. Il dato è corretto, ma l'asimmetria va documentata nello schema.
8. **`RouterAddressSet` e `SwapManagerAddressSet` hanno effetto solo sui futuri Index**. Ogni Index riceve `ROUTER_ROLE` e `i_swapManager` immutabile nel costruttore (Index.sol:122, 140). Un indexer che aggiorna "il router di tutti gli indici" a ogni `RouterAddressSet` sbaglia.

### 3.2 Formato di `reasonData` incoerente

| Sorgente | `catch Error(string)` | `catch (bytes)` / `catch` |
|---|---|---|
| `Index._tryRebalanceIndex` (Index.sol:1236-1248) | riencodato con selector `Error(string)` | revert data grezzo, oppure `"Unknown error"` |
| `IndexManager._rebalanceSingleIndex` (IndexManager.sol:689-696) | `bytes(_reason)`: stringa UTF-8 senza selector | revert data grezzo, oppure `"Unknown error"` |
| `IndexManager._collectFeesFroSingleIndex` (:723-730) | `bytes(_reason)` senza selector | `_getErrorData()` |
| `IndexManager._executeSingleWeightUpdate` (:749-754) | `bytes(_reason)` senza selector | `_getErrorData()` |

Lo stesso campo `reasonData` contiene quindi a volte ABI-encoding con selector, a volte testo nudo. Una stringa di 4+ byte può essere scambiata per un selector. Uniformare: sempre il revert data grezzo (`catch (bytes memory data)` unico) e lasciare la decodifica all'indexer.

### 3.3 `indexed`

- `rebalanceTimestamp` (IndexEvents.sol:33), `implementationTimestamp` (:39), `updateTimestamp` (:45) sono indexed. Filtrare per timestamp esatto non serve a nessuno e `block.timestamp` è già nel blocco. Togliere `indexed`; per `IndexRebalanced` e `IndexWeightsUpdated` il timestamp si può eliminare del tutto.
- Gli eventi di Index non hanno l'indirizzo dell'indice come parametro. Va bene (è `log.address`), ma rende il filtro "tutti gli eventi di tutti gli Index" dipendente da una lista di indirizzi, quindi dalla factory.
- Nessun tipo dinamico è indexed: `data` e `reasonData` sono correttamente non indexed.
- Tutti gli altri `indexed` (indirizzi, `txId`) sono scelti bene e nessun evento supera i 3 topic.

### 3.4 Naming

- Singolare/plurale: `WeightsUpdateProposed`, `IndexWeightsUpdated`, `NewIndexWeightsProposed` contro `WeightUpdateExecuted`, `WeightUpdateFailed`, `WeightUpdateRebalanceFailed`. Scegliere una forma (`Weights...`).
- Prefisso `Index`: presente in `IndexRebalanced`, `IndexWeightsUpdated`, `IndexInitialized`, assente in `SharesMinted`, `FeesCollected`, `WeightsUpdateProposed` dello stesso contratto.
- Stessa azione, nomi diversi tra livelli: `WeightsUpdateProposed` (Index) e `NewIndexWeightsProposed` (Manager); `IndexWeightsUpdated` (Index) e `WeightUpdateExecuted` (Manager).
- Tempo verbale: tutti al participio passato, coerente.

### 3.5 Nomi e ordine dei parametri

- Gli asset sono chiamati `asset0` (IndexCreated), `token0Added`/`token0Removed` (Shares*), `underlyingAmount0` (IndexInitialized), `newAsset0Reserve` (IndexRebalanced), `newWeightAsset0` (pesi). Proposta: `asset0Amount`, `asset0Reserve`, `asset0Weight`.
- L'attore ha 8 nomi: `user`, `setter`, `assetManager`, `rebalancer`, `feeCollector`, `proposer`, `owner`, `executor`. Accettabile quando il ruolo è semantico, ma `setter`/`rebalancer`/`assetManager` sono tutti `msg.sender`: un nome unico (`caller`) semplifica lo schema.
- `SharesMinted(user, usdcIn, shares, a0, a1)` e `SharesBurned(user, shares, a0, a1, usdcOut)`: ordine diverso. Proposta: stesso ordine `(user, shares, asset0Amount, asset1Amount, usdcAmount, feeAmount)`.
- `IndexCreated` ha `indexAddress`, `FeesCollected` di Index usa `feeCollector`, mentre `collectFees` riceve `_collector`. Dettaglio, ma i nomi finiscono come colonne nel DB.
- Unità miste non documentate negli eventi: decimali token (reserve, Shares*), decimali USDC (usdcAmountIn/Out), 18 decimali USD (IndexInitialized), 4 decimali di precisione (pesi, base 1_000_000). Aggiungere NatSpec `@param` con l'unità su ogni campo.

---

## 4. Eventi mancanti (funzioni che cambiano stato senza evento)

| Priorità | Dove | Stato modificato | Impatto per l'indexer |
|---|---|---|---|
| Alta | `SwapManager.registerIndex` (SwapManager.sol:44-57) | `s_routes[index][*]` per 3 swap type | Route (V3 path o V4 PoolKey) non ricostruibili. Servono per spiegare slippage e per una UI |
| Alta | `Index.mintShares` (Index.sol:266) e `Index.redeem` (:473) | `s_totalFees += feeAmount` | Fee per operazione assente dagli eventi. Aggiungere `feeAmount` a `SharesMinted`/`SharesBurned` |
| Alta | `Index` costruttore (Index.sol:106-141) / `IndexManager.createIndex` (:119) | pesi iniziali, `s_feePercentage`, price feed, router, swapManager, name/symbol | `IndexCreated` ha solo indirizzi degli asset. Senza `feePercentage` e pesi iniziali l'entità Index richiede `eth_call` |
| Media | `SwapManager.updateRoute` (SwapManager.sol:65-72) | `s_routes[index][swapType]` | Nessun evento. Oggi è irraggiungibile (owner è IndexManager, che non la espone), ma va coperta prima di renderla raggiungibile |
| Media | `Index.mintShares` / `redeem` / `rebalanceIndex` | nessuno stato di prezzo, ma i prezzi Chainlink letti (`_initFunctionValues`, Index.sol:895) determinano share e allocazione | Il NAV al momento dell'operazione non è negli eventi. Aggiungere `totalUsdValueBefore` (o i 3 prezzi) a `SharesMinted`, `SharesBurned`, `IndexRebalanced` |
| Media | `MultiSigWallet` costruttore (MultiSigWallet.sol:61-78) | `s_owners`, `s_isOwner`, `i_requiredConfirmations` | Owner e soglia leggibili solo via call. Sono immutabili, quindi basta un evento `MultiSigInitialized(owners, required)` |
| Media | `MultiSigWallet.receive` (:333) | balance ETH | Nessun `Deposit(sender, value)`: i fondi in ingresso non sono tracciabili come eventi |
| Bassa | `MultiSigWallet.confirmTransactionWithSig` (:202) | `s_nonces[_signer]++` | `TransactionConfirmed` non distingue conferma diretta da conferma con firma, né chi ha inviato la tx (relayer). Valutare `TransactionConfirmedWithSig(txId, signer, relayer, nonce)` |
| Bassa | `IndexManager.setRouterAddress` (:91) / `setSwapManagerAddress` (:103) | `s_router`, `s_swapManager` | Evento presente, manca il valore precedente (`oldRouter`) |
| Bassa | `IndexManager` costruttore (:72-85) | `i_usdc`, `i_usdcPriceFeed`, `i_uniswapUniversalRouter` | Immutabili, una call a deploy basta |
| Bassa | `Index.proposeUpdateWeights` (Index.sol:595-612) | sovrascrive una proposta scaduta e non eseguita | La nuova proposta emette evento, ma non c'è un segnale di "proposta precedente annullata". L'indexer deve chiudere la pending precedente a mano |

Nessuna funzione Chainlink di callback (Automation, Functions, VRF) è presente in `src/`: i price feed sono solo letti.

---

## 5. Eventi dichiarati ma non emessi

- **Custom**: nessuno. Tutti i 23 eventi in `src/events/*` hanno almeno un `emit`.
- **Ereditati da OpenZeppelin**, presenti nell'ABI ma di fatto mai emessi:
  - `RoleAdminChanged` in Index e IndexManager (nessuna chiamata a `_setRoleAdmin`).
  - `RoleRevoked` in Index (l'admin è IndexManager, che non ha funzioni per revocare ruoli sugli Index).
  - `EIP712DomainChanged` in Index e MultiSigWallet (solo in caso di upgrade, non previsto).
  - `OwnershipTransferred` in SwapManager oltre al costruttore.

Non serve rimuoverli. Basta non creare handler e tabelle per loro.

---

## 6. Indexer: stato attuale e prontezza

### 6.1 Cosa c'è oggi in `indexer/`

- Stack: Node + ethers v6 + Prisma/Postgres + Express. `src/index.ts`, listener, service, repository e route sono file vuoti. `indexer/index.ts` avvia solo Express.
- `src/config/ContractsABIs.ts` importa gli ABI da `../out` per Index, IndexManager, Router, SwapManager, MultiSigWallet.
- `prisma/schema.prisma` è generato da `scripts/generatePrismaModels.ts`, che legge **tutto** `out/` e crea un modello per ogni nome di evento. Problemi:
  1. Deduplica per nome: le varianti IndexManager di `IndexInitialized`, `IndexRebalanced`, `FeesCollected` mancano.
  2. Include eventi di forge-std (`log_*`, `SlotFound`, `WARNING_UninitedSlot`), di mock e di Uniswap v4 (`Swap`, `Donate`, `Initialize`, `ModifyLiquidity`, `RateSet`, `SwapExecuted`...).
  3. Genera schema non valido: `Donate`, `Initialize`, `ModifyLiquidity`, `ProtocolFeeUpdated`, `Swap` hanno due campi `id`; i parametri senza nome (`log`, `log_address`, `logs`...) producono righe senza nome di campo.
  4. **Manca `contractAddress`** (e `chainId`) in ogni modello: le righe di `SharesMinted` di indici diversi sono indistinguibili.
  5. Nessuna gestione della factory: non c'è logica per aggiungere un Index alla lista dei contratti ascoltati dopo `IndexCreated`.

### 6.2 Si può ricostruire lo stato dai soli eventi?

| Stato | Ricostruibile? | Come / cosa manca |
|---|---|---|
| Lista indici e asset | Sì | `IndexManager.IndexCreated` |
| Config indice (fee %, pesi iniziali, price feed, name/symbol, router) | No | Assente da `IndexCreated`. Oggi serve `eth_call` a `getFeesInfo`, `getAssetsWeights`, `getAsset*PriceFeed`, `name`, `symbol`. `ROUTER_ROLE` si ricava dai `RoleGranted` del costruttore |
| Stato inizializzato | Sì | `IndexManager.IndexInitialized` o `Index.IndexInitialized` |
| Reserve `s_asset0Reserve`/`s_asset1Reserve` | Sì, in modo esatto | `IndexInitialized` (valori assoluti) + `SharesMinted` (+) + `SharesBurned` (-) + `IndexRebalanced` (valori assoluti nuovi) |
| Total supply e balance delle share | Sì | `Transfer` dell'Index |
| Pesi target e pending | Sì | `WeightsUpdateProposed` + `IndexWeightsUpdated`, attenzione all'ordine (3.1 punto 4) e alle proposte sovrascritte |
| Fee accumulate `s_totalFees` | No | Fee per operazione mai emessa, `feePercentage` mai emesso, e unità miste (3.1 punto 1) |
| Fee raccolte totali | In teoria sì | Somma di `FeesCollected`, ma il valore è inaffidabile finché il bug di unità resta |
| NAV / prezzo share nel tempo | No | Mancano prezzi o `totalUsdValue` negli eventi. Alternativa: ascoltare gli aggregator Chainlink, che è complesso (i proxy non emettono, gli aggregator cambiano) |
| Route di swap | No | SwapManager senza eventi |
| Transazioni multisig | Sì | `TransactionSubmitted` (target, value, data) + conteggio `TransactionConfirmed`/`ConfirmationRevoked` + `TransactionExecuted` |
| Owner e soglia multisig | No | Nessun evento nel costruttore |
| Ruoli IndexManager | Sì | `RoleGranted`/`RoleRevoked` |
| Esiti falliti batch (rebalance/fee/weights) | Sì | Eventi `...Failed` del Manager, con il problema di formato di `reasonData` (3.2) |

### 6.3 Mapping entità → eventi suggerito

| Entità | Chiave | Eventi sorgente |
|---|---|---|
| `Protocol` / `IndexManager` | indirizzo | `RouterAddressSet`, `SwapManagerAddressSet`, `RoleGranted`, `RoleRevoked` |
| `Index` | indirizzo Index | create: `IndexCreated` (+ `eth_call` per config finché l'evento non la porta); update: `IndexInitialized` (entrambi), `IndexRebalanced` (Index), `IndexWeightsUpdated` |
| `IndexReserveSnapshot` | (index, block, logIndex) | `IndexInitialized`, `SharesMinted`, `SharesBurned`, `IndexRebalanced` di Index |
| `WeightProposal` | (index, implementationTimestamp) | `WeightsUpdateProposed` (Index) + `NewIndexWeightsProposed` (Manager, per i pesi vecchi e l'attore); chiusura con `IndexWeightsUpdated` o con una nuova proposta |
| `Deposit` / `Redemption` | (txHash, logIndex) | `SharesMinted` / `SharesBurned` |
| `ShareBalance` | (index, account) | `Transfer` dell'Index |
| `Rebalance` | (txHash, logIndex) | `IndexRebalanced` di Index; attore da `IndexRebalanced` del Manager quando presente; fallimenti da `IndexRebalanceFailed` e `WeightUpdateRebalanceFailed` |
| `FeeCollection` | (txHash, logIndex) | `FeesCollected` di Index (unica fonte; ignorare quello del Manager o usarlo solo per verifica) + `FeesCollectionFailed` |
| `MultisigTransaction` | (wallet, txId) | `TransactionSubmitted`, `TransactionConfirmed`, `ConfirmationRevoked`, `TransactionExecuted` |
| `MultisigConfirmation` | (wallet, txId, owner) | `TransactionConfirmed` / `ConfirmationRevoked` |

Correlazione utile: gli script (`script/DeployAndInitNewIndex.s.sol`) creano e inizializzano gli indici passando dal MultiSig. `TransactionExecuted` e `IndexCreated`/`IndexInitialized` stanno nella stessa tx: l'indexer può collegare l'Index alla proposta multisig tramite `txHash`.

### 6.4 Pattern factory / data source dinamiche

- `IndexManager` è la factory: `IndexCreated.indexAddress` (indexed) è il segnale per registrare un nuovo Index tra gli indirizzi ascoltati. Con ethers: tenere in DB la lista degli Index, ricaricarla all'avvio, e per ogni blocco interrogare `getLogs` con `address: [manager, ...indici]`.
- Il costruttore di Index emette 4 `RoleGranted` **prima** di `IndexCreated`, nella stessa tx. Un indexer che aggiunge l'Index solo dopo aver visto `IndexCreated` li perde, se filtra per indirizzo noto. Con The Graph il comportamento sulle template create nello stesso blocco va verificato; con un indexer custom basta riprocessare i log della tx di creazione.
- Gli indirizzi sono deterministici (`create2`, salt = `keccak256(asset0, asset1)`, IndexManager.sol:632-634), quindi l'indexer può verificare l'indirizzo emesso.
- `SwapManager` e `Router` sono singoli e cambiabili via `RouterAddressSet` / `SwapManagerAddressSet`. Un nuovo SwapManager va aggiunto ai contratti ascoltati se in futuro emetterà eventi.

---

## 7. Raccomandazioni

### Priorità alta

1. **Correggere l'unità delle fee in `redeem`** (Index.sol:446, 473) prima di indicizzare `FeesCollected`. Tutte le fee in decimali USDC.
2. **Risolvere le collisioni di nome**: rinominare gli eventi del Manager (`IndexInitializedByManager` o meglio eliminarli, vedi punto 3) oppure spostare le dichiarazioni dentro le interfacce (`IIndexEvents`, `IIndexManagerEvents`) così che siano scoped e finiscano anche negli ABI delle interfacce usati dall'SDK.
3. **Una sola fonte per azione**: tenere su Index gli eventi di stato. Sul Manager eliminare `IndexRebalanced`, `FeesCollected`, `WeightUpdateExecuted`, `IndexInitialized` (o ridurli ai casi in cui portano un dato in più) e mantenere solo i `...Failed` e `IndexCreated`.
4. **Aggiungere `feeAmount`** a `SharesMinted` e `SharesBurned`.
5. **Arricchire `IndexCreated`**: `feePercentage`, `weight0`, `weight1`, `priceFeed0`, `priceFeed1`, `router`, `swapManager`. In alternativa un evento `IndexConfigured` emesso dal costruttore di Index.
6. **Eventi in SwapManager**: `RouteRegistered(index indexed, swapType indexed, version, poolKey/v3Path)` in `registerIndex` e `updateRoute`.
7. **Indexer**: aggiungere `contractAddress` e `chainId` a ogni modello; generare lo schema solo dagli ABI dei 5 contratti in scope (non da tutto `out/`) e usare la firma completa (o il topic0) come chiave di dedup; correggere i conflitti su `id`.
8. **Controllare il risultato di `create2`** (IndexManager.sol:635-637) e revertire se `index == address(0)`, per non emettere `IndexCreated` con indirizzo nullo.

### Priorità media

9. Spostare `emit IndexWeightsUpdated` prima di `_tryRebalanceIndex` (Index.sol:643-647), così l'ordine dei log segue la logica.
10. Distinguere il "rebalance non necessario" dal fallimento: controllare `_checkIfRebalanceNeeded` prima del try, oppure emettere un evento `WeightUpdateRebalanceSkipped`.
11. Propagare l'esito del rebalance a `WeightUpdateExecuted` (campo `rebalanceSucceeded`) se l'evento del Manager resta.
12. Uniformare `reasonData`: sempre revert data grezzo, senza `bytes(_reason)` né `"Unknown error"` (IndexManager.sol:689-696, 723-730, 749-754; Index.sol:1236-1248).
13. Aggiungere un valore di NAV (`totalUsdValueBefore` o i prezzi usati) a `SharesMinted`, `SharesBurned`, `IndexRebalanced`.
14. MultiSig: evento con owner e soglia nel costruttore, `Deposit(sender, value)` in `receive`.
15. Togliere `indexed` dai timestamp (IndexEvents.sol:33, 39, 45) ed eliminare i timestamp ridondanti con il blocco.

### Priorità bassa

16. Uniformare naming (`Weights...`, prefissi, nomi asset e attori) e ordine dei parametri di `SharesMinted`/`SharesBurned`.
17. Aggiungere il valore precedente a `RouterAddressSet`/`SwapManagerAddressSet` e documentare che valgono solo per i nuovi Index.
18. Aggiungere `rebalancer`/`caller` a `Index.IndexRebalanced` se si eliminano gli eventi del Manager.
19. NatSpec con le unità di misura su ogni parametro degli eventi.
20. Valutare un evento dedicato per `confirmTransactionWithSig` con signer, relayer e nonce.
