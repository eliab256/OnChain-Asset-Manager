# @oam/db

Schema Prisma, migrazioni e client del database condiviso da indexer, API e keeper. Postgres locale da `docker-compose.yml` (porta host 5434). Schema deciso il 2026-11-03 (roadmap, Fase 4 punto 1). Il ragionamento dietro le scelte è in `localHelpers/prisma-explain.md`.

## Comandi

Da `packages/db`, con `.env` copiato da `.env.example` e `make db` acceso:

```bash
npm run validate          # prisma validate
npm run generate          # client in src/generated/prisma (fuori da git, lo rifà anche npm install)
npm run migrate           # prisma migrate dev: crea e applica una migrazione nuova
npm run migrate:deploy    # applica le migrazioni esistenti senza crearne
npm run studio            # interfaccia web sul DB
```

Le migrazioni sono state compattate il 2026-11-12 in una sola `20261112000000_init` (DB ancora senza dati), rigenerata il 2026-11-14 con i due tipi nuovi di `NotificationType`. Un DB locale creato prima va resettato una volta (`npx prisma migrate reset` in `packages/db`); da lì solo migrazioni nuove, mai modifiche a quelle esistenti.

Dagli altri workspace: dipendenza `"@oam/db": "*"`, poi `createPrismaClient(process.env.DATABASE_URL)`. Prisma 7 passa dal driver adapter `@prisma/adapter-pg`, già incluso nella factory.

## Convenzioni

- Indirizzi in minuscolo (`VarChar(42)`), hash e `bytes32` in `Char(66)`, `bytes` in esadecimale `0x…` (`Text`).
- `uint256` e `int256` in `Decimal(78, 0)`, nelle unità on-chain senza scala: USDC 6 decimali, shares e valori USD 18, asset nei propri decimali. Pesi (1.000.000 = 100%), `feePercentage` e `maxDelay` in `Int`.
- Ogni riga che viene da un log ha `chainId`, `blockNumber`, `txHash`, `logIndex`, `timestamp` ed è unica su `(chainId, txHash, logIndex)`. L'indexer fa upsert su questa chiave.
- Le chiavi naturali comprendono `chainId` (31337 e 31338 nello stesso DB).
- Tutto ciò che deriva da un blocco si scrive in una sola transazione del DB, notifiche comprese.

## Evento → tabella

Tutti gli eventi decodificati finiscono anche in `RawEvent`.

| Evento | Contratto | Tabelle |
|---|---|---|
| `IndexCreated` | IndexManager | `Index` (nuova riga, pesi iniziali), `Contract` (kind `INDEX`), `Token` (lettura RPC dei metadati) |
| `IndexActionTriggered` | IndexManager | `IndexActionLog` (`success = true`); riempie `caller` / `proposer` / `closedBy` delle righe della stessa tx (abbinamento sotto la tabella) |
| `IndexActionFailed` | IndexManager | `IndexActionLog` (`success = false`); con `REBALANCE` anche `Rebalance` (`DIRECT`, `FAILED`, oppure `SKIPPED` se il revert è `Index__RebalanceNotNeeded`) |
| `RoleGranted` / `RoleRevoked` | IndexManager, Timelock | `RoleMember` (aggiunta / rimozione) |
| `IndexInitialized` | Index | `Trade` (`SEED`), `Index` (inizializzato, riserve, supply), `Position.seedUsdValue`, `PositionCost` |
| `SharesMinted` / `SharesBurned` | Index | `Trade` (`MINT` / `REDEEM`), `Index` (riserve, `accruedFees`), `Position` (USDC, shares, fee), `PositionCost` |
| `Transfer` | Index | `ShareTransfer`, `Position.balance`, `Index.totalSupply` (mint/burn), `Index.holderCount`, `Allowance` (vedi sotto); fra due utenti anche `TransferCost`, `PositionCost` di mittente e destinatario e, se non sono wallet collegati, `Notification` (`SHARES_RECEIVED`) |
| `Approval` | Index | `Allowance` |
| `IndexRebalanced` | Index | `Rebalance` (`SUCCESS`, `origin` come sotto), `Index` (riserve) |
| `WeightsUpdateProposed` | Index | `WeightProposal` (`PENDING`) |
| `WeightsUpdated` | Index | `WeightProposal` (`EXECUTED`), `Index` (pesi correnti) |
| `WeightsUpdateCancelled` | Index | `WeightProposal` (`CANCELLED`) |
| `WeightsUpdateRebalanceFailed` / `Skipped` | Index | `Rebalance` (`WEIGHTS_UPDATE`, `FAILED` / `SKIPPED`) |
| `FeesCollected` | Index | `FeeCollection`, `Index.accruedFees = 0` |
| `PriceFeedRegistered` / `PriceFeedUpdated` | PriceFeedManager | `PriceFeed` (`decimals` letti via RPC); `Updated` chiude anche `PriceFeedProposal` |
| `PriceFeedUpdateProposed` / `Cancelled` | PriceFeedManager | `PriceFeedProposal` |
| nessun evento: lettura per blocco | proxy dei feed Chainlink | `PricePoint`, `PriceFeed.last*`, `NavSnapshot` (trigger `PRICE`), vedi "Prezzi" sotto la tabella |
| `MultiSigInitialized` | MultiSigWallet | `MultisigWallet` |
| `TransactionSubmitted` | MultiSigWallet | `MultisigTransaction` |
| `TransactionConfirmed` | MultiSigWallet | `MultisigConfirmation`, `MultisigTransaction.confirmations`, `MultisigSignature` del firmatario → `USED` o `INVALIDATED` (vedi "Firme del MultiSig" sotto la tabella) |
| `ConfirmationRevoked` | MultiSigWallet | `MultisigConfirmation.active = false`, firme dell'owner su quella tx → `INVALIDATED` |
| `TransactionExecuted` | MultiSigWallet | `MultisigTransaction.executed`, firme ancora `VALID` → `ARCHIVED` |
| `CallScheduled` / `CallSalt` | Timelock | `TimelockOperation`, `TimelockCall` (schedule ripetuto dopo un cancel: vedi "Operazioni del Timelock" sotto la tabella) |
| `CallExecuted` / `Cancelled` | Timelock | `TimelockOperation.status`, `TimelockCall.executed` (sempre uguale a `status = EXECUTED`) |
| `MinDelayChange` | Timelock | `TimelockConfig` |
| `Upgraded` | i tre proxy | `ProxyUpgrade` (`timelockOperationId` dal `CallExecuted` abbinato, vedi "Operazioni del Timelock") |
| `Deposit`, `Initialized`, `OwnershipTransferred`, `RoleAdminChanged` | vari | solo `RawEvent` |

**`Allowance` e `transferFrom`.** In OZ v5 `transferFrom` riduce l'allowance senza emettere `Approval`, e `Transfer` non dice chi è lo spender né distingue `transfer` da `transferFrom`. Il mittente della tx non basta: lo spender di solito è un contratto (un DEX) e la tx la firma l'utente. Regola: per ogni `Transfer` con `from ≠ 0`, se `from` ha righe in `Allowance` con valore maggiore di zero e non illimitato, l'indexer rilegge `allowance(from, spender)` via RPC al numero di quel blocco per ciascuno di quegli spender e salva il valore letto, con `updatedBlock` e `updatedTx` del transfer. Copre i `transferFrom` dei contratti e i `transfer` diretti (il valore riletto non cambia); le allowance illimitate (`type(uint256).max`) non scendono mai e non si rileggono. Sono poche chiamate, solo per i transfer di chi ha allowance aperte. La tabella serve all'avviso "allowance aperte" del front-end (`front-end-ideas.md`), che comunque rilegge i valori on-chain prima di mostrarli.

**Origine ed esito di `Rebalance`.** `IndexRebalanced` ha la stessa firma nel rebalance diretto e in quello dopo un cambio pesi. Regola: se nella stessa tx, con `logIndex` minore, c'è un `WeightsUpdated` dello stesso Index, `origin = WEIGHTS_UPDATE`; altrimenti `DIRECT`. Per `IndexActionFailed` con `REBALANCE` l'indexer guarda i primi 4 byte di `reasonData`: se sono il selettore di `Index__RebalanceNotNeeded` la riga è `SKIPPED` (Index già entro soglia, capita a ogni giro di `rebalanceMultipleIndexes`), altrimenti `FAILED`. È lo stesso criterio con cui `executeWeightUpdate` sceglie fra `WeightsUpdateRebalanceSkipped` e `WeightsUpdateRebalanceFailed`. La riga in `IndexActionLog` resta `success = false` (è quello che dice l'evento), ma `getFailedActions` e le notifiche agli holder la escludono.

**Prezzi.** I prezzi non arrivano da eventi. A ogni blocco processato N l'indexer chiama `latestRoundData()` con `blockTag = N` sul proxy di ogni `PriceFeed` (una sola multicall), cioè lo stesso indirizzo che legge `PriceFeedManager.getPrice`. Se `roundId` è diverso da `PriceFeed.lastRoundId` scrive una riga `PricePoint` (con `asset`, `blockNumber` e `timestamp` di N), aggiorna `PriceFeed.last*` e scrive `NavSnapshot` (trigger `PRICE`) per gli Index che usano quell'asset. Se la lettura fa revert scrive una riga in `IndexerError` e il blocco prosegue. `roundId` del proxy è `phaseId << 64 | round dell'aggregatore`, quindi resta unico anche quando Chainlink cambia l'aggregatore sotto il proxy, e `PricePoint` è unica su `(chainId, feed, roundId)`. Due round nello stesso blocco: si vede solo l'ultimo. Lo storico prima del primo blocco indicizzato richiede, su mainnet, un RPC archive. Deciso il 2026-11-12 al posto di `AnswerUpdated`: i `MockV3Aggregator` di anvil non emettono eventi, sul fork nessuno trasmette, e su mainnet l'evento lo emette l'aggregatore, che cambia sotto il proxy.

**Abbinamento del `caller`.** L'IndexManager emette `IndexActionTriggered` dopo la chiamata all'Index, quindi nella tx l'evento dell'Index (`IndexRebalanced`, `WeightsUpdate*`, `FeesCollected`, `IndexInitialized`) viene prima. Regola: ogni evento dell'Index si lega al primo `IndexActionTriggered` dello stesso Index con `logIndex` maggiore nella stessa tx, e da lì prende `caller`, `proposer` o `closedBy`. L'abbinamento è posizionale perché nei batch lo stesso Index può comparire due volte. Si completa dentro la transazione del DB del blocco, quindi le API non vedono mai righe senza `caller`. Le righe `Rebalance` nate da `IndexActionFailed` prendono il `caller` dall'evento stesso.

**`reasonData` vuoto.** Nelle varianti batch `IndexActionFailed` può avere revert data vuoto (out-of-gas). In `IndexActionLog` e `Rebalance` si salva `'0x'`, mai null: null vuol dire solo "nessun fallimento".

**Firme del MultiSig.** `TransactionConfirmed(txId, owner)` è identico se l'owner conferma con `confirmTransaction` o se qualcuno usa la sua firma con `confirmTransactionWithSig`. Il contratto incrementa `getConfirmNonce(txId, owner)` solo quando una firma viene usata e a ogni `revokeConfirmation`. Regola: a ogni `TransactionConfirmed`, se il firmatario ha una `MultisigSignature` `VALID` per quella tx, l'indexer rilegge `getConfirmNonce(txId, owner)` via RPC al numero di quel blocco. Se è maggiore del `nonce` della firma, la firma è stata consumata: `USED`, con `usedTxHash` della tx. Se è uguale, la conferma è diretta e la firma non serve più: `INVALIDATED`, `usedTxHash` resta null. La lettura del nonce funziona anche quando la conferma passa da un multicall o da un relayer, dove il selettore dell'input della tx non direbbe niente. `ConfirmationRevoked` porta a `INVALIDATED` le firme `VALID` dell'owner su quella tx (il nonce è cambiato). `TransactionExecuted` porta a `ARCHIVED` le firme rimaste `VALID`.

**ETH del MultiSig.** `Deposit` va solo in `RawEvent` e il saldo del wallet non si ricostruisce dagli eventi (le uscite stanno nel `value` delle transazioni eseguite, i trasferimenti con valore zero non emettono niente). `getMultisigInfo` lo legge con `eth_getBalance`, e `getMultisigTransactions` segnala come non eseguibile una proposta con `value` maggiore del saldo. Un `executeTransaction` la cui chiamata al target fallisce fa revert (`MultiSig__TxFailed`) e non lascia eventi: la proposta resta non eseguita.

**Operazioni del Timelock.** `operationId` è l'hash di chiamate, predecessor e salt, quindi un id che ricompare ha le stesse chiamate. `Cancelled` libera l'id on-chain e lo stesso id si può schedulare di nuovo; un'operazione eseguita invece resta `Done` per sempre. Regola: un `CallScheduled` su un id già presente (per forza `CANCELLED`) non tocca le `TimelockCall` e aggiorna la riga: `delay`, `readyAt`, `scheduledBlock`, `scheduledTxHash`, `scheduledAt` nuovi, `salt` dal `CallSalt` della stessa tx (null se manca), `status = SCHEDULED`, campi `closed*` a null. Nel DB resta l'ultimo ciclo; i cancel precedenti li legge `getTimelockOperations` da `RawEvent`. Lo stato "pronta" non è nell'enum: si calcola con `status = SCHEDULED` e `readyAt <= now` (come `isOperationReady` di OZ), e non scade mai. `execute` ed `executeBatch` sono atomici: tutte le chiamate emettono `CallExecuted` o la tx fa revert, quindi `TimelockCall.executed` vale sempre come `status = EXECUTED` dell'operazione. `MinDelayChange(0, minDelay)` arriva già dal costruttore del Timelock: serve lo `startBlock` del deploy anche per `TimelockConfig`.

**`Upgraded` e operazione del Timelock.** Nell'execute OZ fa la chiamata e poi emette `CallExecuted`, quindi `Upgraded` del proxy viene prima. Regola posizionale, come per il `caller`: ogni `Upgraded` si lega al primo `CallExecuted` della stessa tx con `logIndex` maggiore e `target` uguale al proxy, e da lì prende `timelockOperationId`. Così un batch che aggiorna due proxy assegna a ciascuno la sua chiamata. Senza `CallExecuted` abbinato (la creazione del proxy nel costruttore dell'IndexManager) `timelockOperationId` resta null. Fuori dalla tx di deploy dell'IndexManager un `Upgraded` senza `CallExecuted` non dovrebbe esistere, perché `_authorizeUpgrade` accetta solo l'upgrader (il Timelock): si salva comunque, con `timelockOperationId` null, e si scrive una riga in `IndexerError` (implementazione che ha cambiato l'upgrader nello storage, o evento perso). A ogni `Upgraded` dopo la creazione l'indexer rilegge anche `getUpgrader()` sul proxy via RPC al numero di quel blocco; se non è più il Timelock del deploy scrive un altro `IndexerError`.

**Fee da raccogliere a zero.** Con `collectFeesFromMultipleIndexes` un Index senza fee maturate fa revert con `Index__NoFeesToCollect`, e il batch emette `IndexActionFailed` con `COLLECT_FEES`. Non nasce nessuna `FeeCollection`. La riga in `IndexActionLog` resta `success = false`, ma `getFailedActions` e le notifiche la escludono: non è un fallimento, l'Index non aveva niente da dare. Il keeper lo evita a monte mettendo nel batch solo gli Index con `Index.accruedFees > 0`.

**Controllo sulle fee.** A ogni `FeesCollected`, `amount` deve essere uguale alla somma dei `feeAmount` delle righe `Trade` di quell'Index dopo la `FeeCollection` precedente (cioè a `Index.accruedFees` prima dell'azzeramento). Se non coincide, l'indexer ha perso un evento: scrive una riga in `IndexerError` e salva comunque il valore dell'evento.

`NavSnapshot` si aggiorna (una riga per Index e per blocco) a ogni evento che cambia riserve o supply. Se nello stesso blocco cambiano sia le riserve o la supply sia un prezzo, la riga è una sola, calcolata con i valori di fine blocco, e prende `trigger = EVENT`. Con `totalSupply = 0` (prima di `IndexInitialized`, o dopo il riscatto di tutte le shares) non si scrive nessuna riga: `sharePriceUsd` non esiste, e il buco nel grafico è il dato vero. `Notification` la scrive l'indexer insieme all'evento che la causa; `MultisigSignature`, `WalletGroup`, `WalletLink`, `TransferCostDeclaration`, `SiweNonce` e `Session` le scrive l'API; `KeeperAttempt` il keeper. `TransferCost` e `PositionCost` le scrivono l'indexer (eventi nuovi) e l'API (dopo un collegamento o una dichiarazione), con la stessa funzione di ricalcolo.

## Notifiche

`Notification` ha una riga per destinatario (un wallet, mai un gruppo). Tipi, eventi e destinatari:

| Tipo | Evento | Destinatari |
|---|---|---|
| `TRADE_CONFIRMED` | `SharesMinted` / `SharesBurned` | `user` dell'evento |
| `SHARES_RECEIVED` | `Transfer` fra persone diverse (non wallet collegati, non mint/burn) | destinatario |
| `REBALANCE_EXECUTED` | `IndexRebalanced` | holder dell'Index |
| `REBALANCE_FAILED` | `WeightsUpdateRebalanceFailed`, `IndexActionFailed(REBALANCE)` tranne `Index__RebalanceNotNeeded` | holder dell'Index |
| `WEIGHTS_PROPOSED` / `WEIGHTS_UPDATED` / `WEIGHTS_CANCELLED` | `WeightsUpdateProposed` / `WeightsUpdated` / `WeightsUpdateCancelled` | holder dell'Index |
| `PRICE_FEED_STALE` | nessuno (controllo per blocco) | holder degli Index che usano quell'asset |
| `PRICE_FEED_PROPOSED` | `PriceFeedUpdateProposed` | holder degli Index che usano quell'asset |
| `UPGRADE_SCHEDULED` | `CallScheduled` con `target` uno dei tre proxy e selettore `upgradeToAndCall` (`0x4f1ef286`) | holder di tutti gli Index |
| `MULTISIG_TO_SIGN` | `TransactionSubmitted` | owner del MultiSig |
| `MULTISIG_READY` | `TransactionConfirmed` che porta `confirmations` alla soglia | owner del MultiSig |

`dedupKey` = `txHash:logIndex` del log che causa la notifica, tranne `PRICE_FEED_STALE` (`stale:<feed>:<lastUpdatedAt>`). Regole:

- **Holder.** È holder chi ha `Position.balance > 0` nel momento in cui l'indexer applica quel log: il blocco si processa in una transazione del DB in ordine di `logIndex`, quindi chi riscatta tutto prima del rebalance nella stessa tx non riceve la notifica. Il costo è una riga per holder per evento; per il progetto va bene.
- **Wallet collegati.** Due wallet dello stesso gruppo con shares dello stesso Index ricevono due righe con la stessa `(type, dedupKey)`. `getUserNotifications` legge le notifiche di tutto il gruppo e raggruppa per `(type, dedupKey)`; `markNotificationsRead` segna come lette tutte le righe del gruppo con quella coppia. `recipient` resta il wallet perché un collegamento si può togliere.
- **`PRICE_FEED_STALE`.** A ogni blocco, dopo la lettura dei prezzi: feed vecchio se `timestamp del blocco − PriceFeed.lastUpdatedAt > maxDelay`, mai con l'orologio del server, così un blocco riprocessato dà la stessa `dedupKey`. `blockNumber` è il blocco in cui il feed risulta vecchio la prima volta (`txHash` null), quindi il reorg la cancella come le altre.
- **Chiusura delle notifiche del MultiSig.** Quando un owner conferma on-chain o manda una firma con `submitMultisigSignature`, la sua `MULTISIG_TO_SIGN` per quella tx passa a `read = true` (la scrive l'indexer o l'API, a seconda di chi vede la conferma). Con `TransactionExecuted` passano a `read = true` le `MULTISIG_TO_SIGN` e `MULTISIG_READY` di quella tx per tutti gli owner.
- **Payload.** Il Json ha un tipo: union discriminata su `type` in `@oam/db` (`NotificationPayload`), scritta dall'indexer e letta da API e front-end. `UPGRADE_SCHEDULED`: proxy, nuova implementazione (decodificata da `data`), `operationId`, `readyAt`. `PRICE_FEED_PROPOSED`: asset, feed vecchio e nuovo, `maxDelay`, `executableAt`.

I due timelock (2 giorni per gli upgrade, 2 giorni per i feed) servono a lasciare agli holder il tempo di uscire: `UPGRADE_SCHEDULED` e `PRICE_FEED_PROPOSED` (aggiunti il 2026-11-14, nella `20261112000000_init` rigenerata) li avvisano quando l'attesa parte.

## Keeper

`KeeperAttempt` la scrive solo il keeper, una riga per tentativo. Stati:

- `PENDING`: tx inviata, ricevuta non ancora arrivata.
- `SUCCESS`: ricevuta con status 1 e nessun `IndexActionFailed` reale. Gli skip (`Index__RebalanceNotNeeded`, `Index__NoFeesToCollect`) non sono fallimenti, come in `getFailedActions`.
- `PARTIAL`: solo per i batch (`indexAddress` null). Ricevuta con status 1 e almeno un `IndexActionFailed` reale nel batch.
- `FAILED`: `eth_estimateGas` fa revert e la tx non parte (`txHash` null, `reasonData` dall'errore della stima); oppure ricevuta con status 0 (errore comune, per esempio out-of-gas: `reasonData` si ricava rifacendo la chiamata con `eth_call` al blocco della tx); oppure azione singola con `IndexActionFailed` (la tx riesce, l'azione no: `reasonData` dall'evento).

L'esito per Index di un batch non si salva qui: si legge da `IndexActionLog` con un join su `txHash`. Una tx rimandata con la stessa nonce e più gas aggiorna la stessa riga (`txHash` = ultimo invio); un retry con una nonce nuova (per esempio dopo un revert data vuoto, di solito gas finito) è una riga nuova.

## Metriche dell'index e metriche personali

Lo schema ha tre livelli:

- **dati della chain**: tutte le tabelle derivate dagli eventi, `Position` compresa (saldo e totali di USDC, shares e fee). Sono l'unica fonte delle metriche dell'index;
- **input degli utenti**, off-chain, scritti dall'API dopo aver verificato una firma EIP-712: `WalletGroup` e `WalletLink` (wallet della stessa persona), `TransferCostDeclaration` (prezzo di acquisto dichiarato da chi riceve shares da un'altra persona);
- **metriche personali derivate**: `TransferCost` (per ogni trasferimento fra utenti: self-transfer sì/no e costo che porta con sé) e `PositionCost` (costo medio, shares a costo sconosciuto, PnL realizzato).

Regola: le API dell'index (`listIndexes`, `getIndex`, `getIndexComposition`, `getIndexNavHistory`, `getIndexStats`, `getIndexHolders`, `getIndexTrades`, `getIndexFeesHistory`) leggono solo le tabelle della chain. Le tabelle degli altri due livelli le leggono solo le API dell'utente. Un prezzo dichiarato cambia il PnL di chi lo dichiara e nient'altro. Le metriche dell'index contano i wallet, non le persone: due wallet collegati restano due holder.

`WalletGroup` e `WalletLink` non hanno `chainId`: una chiave privata controlla lo stesso indirizzo su ogni chain, quindi il collegamento vale per tutte (deroga alla convenzione delle chiavi naturali).

## Sessioni (SIWE)

Login con Sign-In with Ethereum (EIP-4361), senza account né password. `SiweNonce`: nonce monouso emessi da `getSiweNonce`, scadenza 10 minuti, `verifySiwe` cancella la riga quando lo usa. `Session`: una riga per login, chiave = SHA-256 del token casuale del cookie (il token non sta nel DB), scadenza fissa di 7 giorni, `revokedAt` impostato dal logout. Una sessione non è legata a `WalletLink`: il permesso sui dati del gruppo si calcola a ogni richiesta, quindi scollegare un wallet gli toglie subito l'accesso. Nonce scaduti e sessioni scadute si cancellano con un job periodico (indici su `expiresAt`), che per i nonce gira ogni pochi minuti. Consumo del nonce: `verifySiwe` fa prima i controlli che non scrivono (parsing, `domain` e `uri` uguali all'origine del front-end, `chainId` fra 31337, 31338 e 1, `expirationTime` e `notBefore` del messaggio se presenti, firma), poi `DELETE FROM "SiweNonce" WHERE nonce = $1 AND "expiresAt" > now()` e la creazione della `Session` nella stessa transazione del DB. Se il delete non tocca righe (nonce già usato, scaduto o mai emesso) risponde 401: due `verifySiwe` in parallelo con lo stesso messaggio aprono una sola sessione. `Session.address` si salva in minuscolo: il messaggio SIWE porta l'indirizzo in EIP-55, e salvato così i confronti con `WalletLink`, `Position` e `Notification` fallirebbero senza errori. Se la richiesta di `verifySiwe` porta già un cookie di sessione valido, quella sessione si revoca (`revokedAt`) nella stessa transazione, prima di aprire la nuova. Una sessione è valida se `revokedAt` è null e `expiresAt > now()`; `lastSeenAt` si aggiorna solo se il valore salvato ha più di 5 minuti, per non trasformare ogni lettura in una scrittura. `logoutAll` imposta `revokedAt` su tutte le sessioni ancora valide dell'indirizzo (indice su `address`). I dati della chain restano pubblici; i dati personali off-chain (wallet collegati, prezzi dichiarati, `PositionCost`, notifiche) richiedono una sessione del wallet o del suo gruppo. Con la sessione `TransferCostDeclaration.signature` è opzionale.

## Costo delle posizioni

Metodo del costo medio, per wallet, in `PositionCost`. Gli eventi di una posizione si applicano in ordine `(blockNumber, logIndex)`. Gli USDC si portano a USD con 18 decimali moltiplicando per 10¹².

- **Seed**: `costBasisUsd += seedUsdValue`.
- **Mint**: `costBasisUsd += usdcIn` (lordo: la fee fa parte del costo).
- **Uscita di `s` shares** (redeem o trasferimento): esce in proporzione dalla parte a costo noto e da quella a costo sconosciuto. `known = balance − unknownCostShares`, `knownOut = s × known / balance`, `costOut = costBasisUsd × knownOut / known`; poi `unknownCostShares −= s − knownOut` e `costBasisUsd −= costOut`. Infine:
  - redeem: `realizedPnlUsd += usdcOut × knownOut / s − costOut`;
  - verso un wallet collegato (`TransferCost.selfTransfer = true`): `costOut` e la quota a costo sconosciuto passano al destinatario, `TransferCost.costBasisUsd = costOut`. Il totale del gruppo non cambia;
  - verso un'altra persona: le shares escono al costo, senza PnL realizzato.
- **Entrata da un'altra persona**: se esiste una `TransferCostDeclaration` per `(chainId, txHash, indexAddress, recipient)`, `costBasisUsd += pricePerShareUsd × value / 10¹⁸` e `TransferCost.costBasisUsd` prende lo stesso valore; altrimenti `unknownCostShares += value` e `TransferCost.costBasisUsd` resta `null` (trasferimento in attesa di prezzo, letto da `getPendingTransferCosts`).
- **PnL di un wallet**: `realizedPnlUsd + (known × sharePrice / 10¹⁸ − costBasisUsd)`, con `sharePrice` da `NavSnapshot`. È parziale se `unknownCostShares > 0`. Il totale del gruppo è la somma sui wallet collegati e lo calcola l'API.

Ricalcolo da zero, per (index, gruppo di wallet), sulle righe di `Trade` e `ShareTransfer`: dopo un reorg, quando un collegamento si crea o si toglie, quando una dichiarazione si crea o cambia. Un wallet senza collegamenti è un gruppo da solo. La funzione è una sola, condivisa da indexer e API.

## Reorg

1. Il `parentHash` del blocco nuovo non coincide con l'hash salvato in `Block`: si risale fino all'ultimo blocco comune.
2. Si cancellano le righe con `blockNumber` maggiore di quel blocco in `Block`, `RawEvent` e in tutte le tabelle di eventi (`Trade`, `ShareTransfer`, `Rebalance`, `WeightProposal`, `FeeCollection`, `IndexActionLog`, `NavSnapshot`, `PricePoint` (per il blocco in cui il round è stato letto; la lettura successiva lo ricrea), `PriceFeedProposal`, `ProxyUpgrade`, `Notification`, `MultisigTransaction`) e gli `Index` creati dopo (a cascata se ne vanno i figli). `TimelockOperation` si tratta al punto 3.
   Alcune righe di eventi nascono in un blocco e si chiudono in uno successivo. Se l'apertura è prima del blocco comune e la chiusura dopo, la riga sopravvive ma con uno stato che non esiste più. Per queste righe si rimette lo stato aperto e si azzerano i campi di chiusura; se la tx di chiusura ricompare nei blocchi nuovi, l'indexer le richiude:
   - `WeightProposal` e `PriceFeedProposal` con `closedBlock` dopo il blocco comune: `status = PENDING`, `closedBy` (solo `WeightProposal`), `closedBlock`, `closedTxHash`, `closedAt` a null;
   - `MultisigTransaction` con `executedBlock` dopo il blocco comune: `executed = false`, `executor`, `executedBlock`, `executedTxHash`, `executedAt` a null;
3. Le tabelle di stato corrente (`Index`, `Position`, `Allowance`, `RoleMember`, `PriceFeed`, `MultisigConfirmation`, `TimelockConfig`) si ricalcolano per le entità toccate a partire dalle tabelle di eventi rimaste. `TimelockOperation` si ricalcola allo stesso modo, perché un id cancellato e schedulato di nuovo riusa la riga e cancellarla per `scheduledBlock` perderebbe il ciclo precedente: per ogni id con eventi dopo il blocco comune si ricostruisce la riga (con le `TimelockCall`) rigiocando i `CallScheduled`, `CallSalt`, `CallExecuted` e `Cancelled` rimasti in `RawEvent`, e la si cancella solo se non resta nessun `CallScheduled`.
4. `KeeperAttempt` non si cancella: i tentativi con `txHash` in un blocco annullato tornano `PENDING` e il keeper ricontrolla la ricevuta (spesso la tx rientra dalla mempool in un blocco nuovo). `MultisigSignature` non si cancella: le firme non sono dati della chain. Si ricalcola lo stato delle firme delle tx toccate: una firma `USED` o `INVALIDATED` torna `VALID` se al blocco comune `getConfirmNonce(txId, signer)` è di nuovo uguale al suo `nonce`, il firmatario non risulta confermato e la tx non è eseguita (`usedTxHash` torna null); una firma `ARCHIVED` torna `VALID` se il reorg ha annullato l'esecuzione e valgono le stesse condizioni. Lo stesso per `WalletGroup`, `WalletLink`, `TransferCostDeclaration`, `SiweNonce` e `Session` (le ultime due non hanno legami con la chain): la dichiarazione è legata a `(chainId, txHash, indexAddress, recipient)` e non a `logIndex`, quindi ritrova il suo trasferimento anche se la tx finisce in un altro blocco. `TransferCost` se ne va a cascata con la sua `ShareTransfer`; `TransferCost` e `PositionCost` si ricalcolano per i gruppi toccati come al punto 3.
5. `Checkpoint` torna al blocco comune.
