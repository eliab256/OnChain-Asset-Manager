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
| `IndexInitialized` | Index | `Trade` (`SEED`), `Index` (inizializzato, riserve, supply), `Position.seedUsdValue` |
| `SharesMinted` / `SharesBurned` | Index | `Trade` (`MINT` / `REDEEM`), `Index` (riserve, `accruedFees`), `Position` (USDC, shares, fee) |
| `Transfer` | Index | `ShareTransfer`, `Position.balance`, `Index.totalSupply` (mint/burn), `Index.holderCount`, `Allowance` (riduzione con `transferFrom`) |
| `Approval` | Index | `Allowance` |
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

`NavSnapshot` si aggiorna (una riga per Index e per blocco) a ogni evento che cambia riserve o supply. `Notification` la scrive l'indexer insieme all'evento che la causa; `MultisigSignature` la scrive l'API; `KeeperAttempt` il keeper.

## Reorg

1. Il `parentHash` del blocco nuovo non coincide con l'hash salvato in `Block`: si risale fino all'ultimo blocco comune.
2. Si cancellano le righe con `blockNumber` maggiore di quel blocco in `Block`, `RawEvent` e in tutte le tabelle di eventi (`Trade`, `ShareTransfer`, `Rebalance`, `WeightProposal`, `FeeCollection`, `IndexActionLog`, `NavSnapshot`, `PricePoint`, `PriceFeedProposal`, `ProxyUpgrade`, `Notification`, `MultisigTransaction`, `TimelockOperation`) e gli `Index` creati dopo (a cascata se ne vanno i figli).
3. Le tabelle di stato corrente (`Index`, `Position`, `Allowance`, `RoleMember`, `PriceFeed`, `MultisigConfirmation`, `TimelockConfig`) si ricalcolano per le entità toccate a partire dalle tabelle di eventi rimaste.
4. `MultisigSignature` non si cancella: le firme non sono dati della chain. Si ricalcola lo stato contro le conferme rimaste.
5. `Checkpoint` torna al blocco comune.
