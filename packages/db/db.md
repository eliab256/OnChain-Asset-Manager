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
| `IndexActionTriggered` | IndexManager | `IndexActionLog` (`success = true`); riempie `caller` / `proposer` / `closedBy` delle righe della stessa tx |
| `IndexActionFailed` | IndexManager | `IndexActionLog` (`success = false`); con `REBALANCE` anche `Rebalance` (`DIRECT`, `FAILED`) |
| `RoleGranted` / `RoleRevoked` | IndexManager, Timelock | `RoleMember` (aggiunta / rimozione) |
| `IndexInitialized` | Index | `Trade` (`SEED`), `Index` (inizializzato, riserve, supply), `Position.seedUsdValue`, `PositionCost` |
| `SharesMinted` / `SharesBurned` | Index | `Trade` (`MINT` / `REDEEM`), `Index` (riserve, `accruedFees`), `Position` (USDC, shares, fee), `PositionCost` |
| `Transfer` | Index | `ShareTransfer`, `Position.balance`, `Index.totalSupply` (mint/burn), `Index.holderCount`, `Allowance` (vedi sotto); fra due utenti anche `TransferCost`, `PositionCost` di mittente e destinatario e, se non sono wallet collegati, `Notification` (`SHARES_RECEIVED`) |
| `Approval` | Index | `Allowance` |

**`Allowance` e `transferFrom`.** In OZ v5 `transferFrom` riduce l'allowance senza emettere `Approval`, e `Transfer` non dice chi è lo spender né distingue `transfer` da `transferFrom`. Il mittente della tx non basta: lo spender di solito è un contratto (un DEX) e la tx la firma l'utente. Regola: per ogni `Transfer` con `from ≠ 0`, se `from` ha righe in `Allowance` con valore maggiore di zero e non illimitato, l'indexer rilegge `allowance(from, spender)` via RPC al numero di quel blocco per ciascuno di quegli spender e salva il valore letto, con `updatedBlock` e `updatedTx` del transfer. Copre i `transferFrom` dei contratti e i `transfer` diretti (il valore riletto non cambia); le allowance illimitate (`type(uint256).max`) non scendono mai e non si rileggono. Sono poche chiamate, solo per i transfer di chi ha allowance aperte. La tabella serve all'avviso "allowance aperte" del front-end (`front-end-ideas.md`), che comunque rilegge i valori on-chain prima di mostrarli.
| `IndexRebalanced` | Index | `Rebalance` (`SUCCESS`), `Index` (riserve) |
| `WeightsUpdateProposed` | Index | `WeightProposal` (`PENDING`) |
| `WeightsUpdated` | Index | `WeightProposal` (`EXECUTED`), `Index` (pesi correnti) |
| `WeightsUpdateCancelled` | Index | `WeightProposal` (`CANCELLED`) |
| `WeightsUpdateRebalanceFailed` / `Skipped` | Index | `Rebalance` (`WEIGHTS_UPDATE`, `FAILED` / `SKIPPED`) |
| `FeesCollected` | Index | `FeeCollection`, `Index.accruedFees = 0` |
| `PriceFeedRegistered` / `PriceFeedUpdated` | PriceFeedManager | `PriceFeed`, `Contract` (aggregatore sotto il proxy); `Updated` chiude anche `PriceFeedProposal` |
| `PriceFeedUpdateProposed` / `Cancelled` | PriceFeedManager | `PriceFeedProposal` |
| `AnswerUpdated` | aggregatore Chainlink | `PricePoint`, `PriceFeed.last*`, `NavSnapshot` (trigger `PRICE`) |
| `MultiSigInitialized` | MultiSigWallet | `MultisigWallet` |
| `TransactionSubmitted` | MultiSigWallet | `MultisigTransaction` |
| `TransactionConfirmed` | MultiSigWallet | `MultisigConfirmation`, `MultisigTransaction.confirmations`, `MultisigSignature` del firmatario → `USED` |
| `ConfirmationRevoked` | MultiSigWallet | `MultisigConfirmation.active = false`, firme dell'owner su quella tx → `INVALIDATED` |
| `TransactionExecuted` | MultiSigWallet | `MultisigTransaction.executed`, firme rimaste → `ARCHIVED` |
| `CallScheduled` / `CallSalt` | Timelock | `TimelockOperation`, `TimelockCall` |
| `CallExecuted` / `Cancelled` | Timelock | `TimelockOperation.status`, `TimelockCall.executed` |
| `MinDelayChange` | Timelock | `TimelockConfig` |
| `Upgraded` | i tre proxy | `ProxyUpgrade` (con `timelockOperationId` se c'è un `CallExecuted` nella stessa tx) |
| `Deposit`, `Initialized`, `OwnershipTransferred`, `RoleAdminChanged` | vari | solo `RawEvent` |

`NavSnapshot` si aggiorna (una riga per Index e per blocco) a ogni evento che cambia riserve o supply. `Notification` la scrive l'indexer insieme all'evento che la causa; `MultisigSignature`, `WalletGroup`, `WalletLink`, `TransferCostDeclaration`, `SiweNonce` e `Session` le scrive l'API; `KeeperAttempt` il keeper. `TransferCost` e `PositionCost` le scrivono l'indexer (eventi nuovi) e l'API (dopo un collegamento o una dichiarazione), con la stessa funzione di ricalcolo.

## Metriche dell'index e metriche personali

Lo schema ha tre livelli:

- **dati della chain**: tutte le tabelle derivate dagli eventi, `Position` compresa (saldo e totali di USDC, shares e fee). Sono l'unica fonte delle metriche dell'index;
- **input degli utenti**, off-chain, scritti dall'API dopo aver verificato una firma EIP-712: `WalletGroup` e `WalletLink` (wallet della stessa persona), `TransferCostDeclaration` (prezzo di acquisto dichiarato da chi riceve shares da un'altra persona);
- **metriche personali derivate**: `TransferCost` (per ogni trasferimento fra utenti: self-transfer sì/no e costo che porta con sé) e `PositionCost` (costo medio, shares a costo sconosciuto, PnL realizzato).

Regola: le API dell'index (`listIndexes`, `getIndex`, `getIndexComposition`, `getIndexNavHistory`, `getIndexStats`, `getIndexHolders`, `getIndexTrades`, `getIndexFeesHistory`) leggono solo le tabelle della chain. Le tabelle degli altri due livelli le leggono solo le API dell'utente. Un prezzo dichiarato cambia il PnL di chi lo dichiara e nient'altro. Le metriche dell'index contano i wallet, non le persone: due wallet collegati restano due holder.

`WalletGroup` e `WalletLink` non hanno `chainId`: una chiave privata controlla lo stesso indirizzo su ogni chain, quindi il collegamento vale per tutte (deroga alla convenzione delle chiavi naturali).

## Sessioni (SIWE)

Login con Sign-In with Ethereum (EIP-4361), senza account né password. `SiweNonce`: nonce monouso emessi da `getSiweNonce`, scadenza 10 minuti, `verifySiwe` cancella la riga quando lo usa. `Session`: una riga per login, chiave = SHA-256 del token casuale del cookie (il token non sta nel DB), scadenza fissa di 7 giorni, `revokedAt` impostato dal logout. Una sessione non è legata a `WalletLink`: il permesso sui dati del gruppo si calcola a ogni richiesta, quindi scollegare un wallet gli toglie subito l'accesso. Nonce scaduti e sessioni scadute si cancellano con un job periodico (indici su `expiresAt`). I dati della chain restano pubblici; i dati personali off-chain (wallet collegati, prezzi dichiarati, `PositionCost`, notifiche) richiedono una sessione del wallet o del suo gruppo. Con la sessione `TransferCostDeclaration.signature` è opzionale.

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
2. Si cancellano le righe con `blockNumber` maggiore di quel blocco in `Block`, `RawEvent` e in tutte le tabelle di eventi (`Trade`, `ShareTransfer`, `Rebalance`, `WeightProposal`, `FeeCollection`, `IndexActionLog`, `NavSnapshot`, `PricePoint`, `PriceFeedProposal`, `ProxyUpgrade`, `Notification`, `MultisigTransaction`, `TimelockOperation`) e gli `Index` creati dopo (a cascata se ne vanno i figli).
3. Le tabelle di stato corrente (`Index`, `Position`, `Allowance`, `RoleMember`, `PriceFeed`, `MultisigConfirmation`, `TimelockConfig`) si ricalcolano per le entità toccate a partire dalle tabelle di eventi rimaste.
4. `MultisigSignature` non si cancella: le firme non sono dati della chain. Si ricalcola lo stato contro le conferme rimaste. Lo stesso per `WalletGroup`, `WalletLink`, `TransferCostDeclaration`, `SiweNonce` e `Session` (le ultime due non hanno legami con la chain): la dichiarazione è legata a `(chainId, txHash, indexAddress, recipient)` e non a `logIndex`, quindi ritrova il suo trasferimento anche se la tx finisce in un altro blocco. `TransferCost` se ne va a cascata con la sua `ShareTransfer`; `TransferCost` e `PositionCost` si ricalcolano per i gruppi toccati come al punto 3.
5. `Checkpoint` torna al blocco comune.
