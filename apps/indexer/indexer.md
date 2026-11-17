# Indexer (`@oam/indexer`)

Regole e struttura dell'indexer off-chain. Legge i blocchi della chain, decodifica gli eventi del protocollo e scrive le tabelle di `@oam/db`. Se cambi una convenzione descritta in questo file, aggiornalo nello stesso commit.

**Stato (2026-11-17): passi 1 e 2 di `localHelpers/indexer-roadmap.md` fatti** (configurazione, logger e layer `chain/`, con unit test). `src/index.ts` per ora legge la configurazione, controlla il chain id e stampa l'head; repository, pipeline e runner arrivano dal passo 3. Al 2026-11-15 c'erano solo `package.json` e `tsconfig.json`. Questo file descrive come va scritto il codice della Fase 4 di `localHelpers/roadmap.md` e sostituisce `blockchain-indexer-roadmap.md`, una guida generica per un indexer di un solo evento `Transfer`, scritta prima dello schema del DB e tolta lo stesso giorno. Da lì resta solo la regola dei layer (§3).

Cosa sta dove:

- questo file: come è fatto il processo (layer, ciclo dei blocchi, come si scrive un handler);
- `packages/db/db.md`: cosa si scrive, cioè la mappa evento → tabella, le regole di abbinamento, i prezzi, le notifiche e il reorg. Vale quello che c'è scritto lì: qui non si ripete;
- `localHelpers/indexer-roadmap.md`: l'ordine dei lavori, passo per passo, con lo stato di ogni passo. I punti della Fase 4 di `localHelpers/roadmap.md` restano come riferimento.

## 1. Il principio: si lavora per blocco

L'unità di lavoro è il blocco, mai il singolo evento. Per ogni blocco l'indexer prende tutti i log dei contratti del protocollo, li applica in ordine di `logIndex` e scrive tutto in una sola transazione del DB: `Block`, `RawEvent`, tabelle di dominio, notifiche e `Checkpoint`. O il blocco è scritto tutto o non è scritto.

Per questo non si usa `watchContractEvent`, che consegna gli eventi uno alla volta. Le regole di `db.md` dipendono dall'ordine dei log dentro la tx e dentro il blocco: l'abbinamento del `caller` con `IndexActionTriggered`, l'origine di un `Rebalance`, `overwritten` delle proposte, chi è holder quando parte una notifica. Un listener a eventi non le può applicare, e non vede né l'hash né il `parentHash` del blocco, che servono al reorg.

Conseguenze:

- backfill e live sono lo stesso codice (`processRange`): il live è un backfill di pochi blocchi;
- si processano anche i blocchi senza log, perché i prezzi si leggono a ogni blocco e il reorg si riconosce dal `parentHash` blocco per blocco;
- dopo uno stop si riparte da `Checkpoint`, senza perdere né duplicare niente.

## 2. Pacchetti e configurazione

| Dipendenza | Uso |
|---|---|
| `viem` | client HTTP per tutte le letture (`getBlockNumber`, `getBlock`, `getLogs`, `readContract`, `multicall`) e `decodeEventLog`; client WebSocket solo per `watchBlockNumber` (§4, "Live") |
| `@oam/abi` | ABI tipizzate e `protocolAddresses[chainId]` (indirizzi dei contratti fissi e `startBlock`) |
| `@oam/db` | `createPrismaClient` e i tipi generati |
| `@oam/sdk` | solo costanti, selettori degli errori e la matematica dei contratti quando serve (per esempio il NAV) |

I log si decodificano con `decodeEventLog` e le ABI di `@oam/abi`. I parser dell'SDK (`parseSharesMinted` e simili) non si usano: leggono la ricevuta di una tx cercando un evento preciso, mentre l'indexer deve decodificare qualunque log gli arrivi.

Variabili in `apps/indexer/.env` (modello in `.env.example`), validate all'avvio:

| Variabile | Significato |
|---|---|
| `RPC_URL` | RPC HTTP della chain (anvil `http://127.0.0.1:8545`). Tutte le letture passano da qui |
| `RPC_WS_URL` | RPC WebSocket della stessa chain (anvil `ws://127.0.0.1:8545`, stessa porta). Serve solo ad avvisare dei blocchi nuovi. Facoltativa: senza, resta solo il polling |
| `CHAIN_ID` | 31337 (anvil) o 31338 (fork). All'avvio si confronta con `eth_chainId`: se non coincidono il processo si ferma |
| `DATABASE_URL` | Postgres di `docker-compose.yml`, lo stesso di `packages/db/.env` |
| `BATCH_SIZE` | blocchi per chiamata `getLogs` nel backfill (default 2000) |
| `POLL_INTERVAL_MS` | intervallo del polling HTTP dell'head nel live: di riserva con il WebSocket (default 30000), unico segnale senza `RPC_WS_URL` (in quel caso conviene 1000) |

**Segreti negli URL** (2026-11-17). I provider RPC mettono la API key nell'URL (Alchemy e Infura nel percorso, altri nella query o come password), e `DATABASE_URL` contiene la password. Due difese, in `src/secrets.ts`:

- `describeConfig` stampa degli URL RPC solo protocollo, host e porta (`https://eth-mainnet.g.alchemy.com/***`); dell'URL del DB maschera solo la password, perché il nome del database non è un segreto.
- All'avvio `logger.redact(configSecrets(config))` registra le parti segrete (percorso e query degli URL RPC, segmenti lunghi almeno 16 caratteri, password), e il logger le sostituisce con `***` in **ogni** riga. Serve perché viem scrive l'URL completo nei messaggi di errore HTTP (`URL: https://…/v2/<KEY>`), che arrivano al log da `errorMessage`, non da `describeConfig`. I valori sotto 6 caratteri non si redigono in tutta la riga (la password locale `oam` cancellerebbe `@oam/abi`).

Regola per il codice futuro: niente `console.log` diretti, tutto passa dal `logger`, altrimenti la redazione non si applica.

## 3. Layer

Ogni layer conosce solo quello sotto. È l'unica regola ripresa dalla vecchia guida.

```
src/
  config.ts         variabili d'ambiente validate
  logger.ts         log in righe JSON, con redazione dei segreti
  secrets.ts        maschera degli URL e parti segrete da redigere
  chain/            client viem e decodifica dei log: non conosce il DB
    clients.ts        client HTTP e WebSocket, controllo del chain id
    abi.ts            ABI unione dei soli eventi del protocollo
    logs.ts           fetchLogs, decodeLog: log normalizzati, "decoded" o "unknown"
    reads.ts          readContractAt, multicallAt (blockNumber obbligatorio)
  handlers/         un file per contratto, una funzione per evento
  repositories/     l'unico layer che usa Prisma: non conosce la chain
  pipeline.ts       processRange(from, to) e processBlock
  runner.ts         bootstrap, backfill, ciclo live
  index.ts          avvio e chiusura pulita su SIGINT / SIGTERM
```

- `chain/` restituisce log già decodificati e normalizzati: `{ address, eventName, args, blockNumber, blockHash, txHash, logIndex }`, indirizzi in minuscolo (anche dentro `args`). Il tipo è un'unione discriminata su `eventName`, quindi un handler che legge un campo inesistente non compila. Un log che non corrisponde a nessun evento del protocollo torna con `kind: "unknown"` (con `reason` e `detail` dell'errore di decodifica) invece di lanciare. Gli indirizzi in `args` si mettono in minuscolo guardando il tipo dell'ABI, non la forma della stringa.
- Le letture si fanno con `readContractAt` e `multicallAt` di `chain/reads.ts`, dove `blockNumber` è obbligatorio nei tipi. Il multicall è deployless: il codice dell'aggregatore viaggia dentro la `eth_call`, perché anvil puro non ha Multicall3.
- I test unitari stanno accanto ai sorgenti (`src/**/*.test.ts`) e girano con `npm test --workspace @oam/indexer`, senza RPC né DB.
- Un handler riceve la transazione Prisma del blocco, l'evento e il contesto del blocco (numero, hash, timestamp, gli altri log della stessa tx). Decide cosa scrivere e chiama i repository. Le letture RPC le fa attraverso `chain/`, sempre con `blockNumber` del blocco che sta processando, mai `latest`: così un blocco riprocessato dà lo stesso risultato.
- I repository espongono operazioni di dominio (`insertTrade`, `applyShareTransfer`), non query generiche.
- L'API (Fase 5) è un servizio separato: l'indexer non espone HTTP.

## 4. Ciclo

**Bootstrap.** Upsert in `Contract` dei contratti fissi di `protocolAddresses[chainId]` con il loro `startBlock`. Poi si legge `Checkpoint`: se manca si parte da `startBlock`, altrimenti da `lastBlockNumber + 1`.

**`processRange(from, to)`.**

1. Indirizzi da ascoltare: tutte le righe di `Contract` della chain (i fissi e gli Index già scoperti).
2. `getLogs` su quegli indirizzi, a pezzi di `BATCH_SIZE` blocchi.
3. Log raggruppati per blocco e ordinati per `logIndex`.
4. Per ogni blocco del range, in ordine, `processBlock`.

**`processBlock(n)`**, tutto in una `prisma.$transaction`:

1. `getBlock(n)` e controllo del `parentHash` contro la riga `Block` di `n − 1` (reorg, §6);
2. riga `Block`;
3. per ogni log: `RawEvent`, poi l'handler se esiste. Gli eventi senza handler restano solo in `RawEvent`;
4. passi di fine blocco: prezzi dei feed e `NavSnapshot` (regole in `db.md`, "Prezzi");
5. `Checkpoint` a `n`.

**Live.** Finito il backfill l'indexer aspetta i blocchi nuovi con due segnali, e tutti e due fanno la stessa cosa: chiamano `catchUp()`, che legge l'head via HTTP e, se è oltre il checkpoint, lancia `processRange(checkpoint + 1, head)`.

- **WebSocket, il segnale principale.** `watchBlockNumber` sul client WebSocket (`eth_subscribe` a `newHeads`): il nodo avvisa appena esce un blocco.
- **Polling HTTP lento, la riserva.** Ogni `POLL_INTERVAL_MS` (30 secondi) parte comunque un `catchUp()`.

Perché il WebSocket: il blocco arriva nel DB subito invece che dopo l'intervallo di polling, così il front-end vede un mint appena confermato, e non si fanno richieste a vuoto quando la chain è ferma (su un RPC a pagamento un polling al secondo sono circa 86.000 chiamate al giorno).

Perché non il WebSocket da solo: una connessione può cadere, e nel caso peggiore resta aperta ma smette di consegnare blocchi. L'indexer sembrerebbe vivo e resterebbe indietro senza nessun errore. Il polling di riserva mette un tetto a quel ritardo, 30 secondi, e lo fa senza dover capire se il socket funziona. Copre anche il tempo di riconnessione e i provider che chiudono le subscription dopo un po'.

Perché questo non complica il codice: il WebSocket porta solo l'avviso, mai i dati. Il numero di blocco ricevuto non si usa nemmeno: `catchUp()` rilegge l'head e riparte dal checkpoint, quindi un avviso perso, doppio o fuori ordine non fa danni, e i blocchi usciti durante una caduta si recuperano al segnale dopo. Log, blocchi e letture passano sempre dal client HTTP (regola del §1: niente eventi consegnati uno alla volta).

Regole:

- un solo `catchUp()` alla volta: se arriva un segnale mentre uno è in corso si segna che ce n'è un altro da fare e lo si esegue alla fine, senza code;
- se il WebSocket cade, viem si riconnette da solo; l'indexer scrive un log e continua con il polling;
- senza `RPC_WS_URL` (un RPC che non offre WebSocket) il polling è l'unico segnale e l'intervallo va abbassato.

**Index creati a metà range.** `IndexCreated` aggiunge l'Index a `Contract`, ma il filtro di `getLogs` del pezzo in corso era già fissato e i log del nuovo Index in quel pezzo non sono arrivati. Regola (punto 3 della Fase 4): dopo un `IndexCreated` al blocco `n` si richiedono i log del nuovo indirizzo da `n` alla fine del pezzo e si uniscono agli altri prima di proseguire. Finché non è scritta vale un limite noto: funziona solo se nessun evento dell'Index cade nello stesso pezzo della sua creazione dopo il blocco di creazione.

## 5. Come si scrive un handler

- **Chiave unica.** Ogni riga nata da un log è unica su `(chainId, txHash, logIndex)`. `chainId` c'è sempre: 31337 e 31338 stanno nello stesso DB.
- **Incrementi solo su righe nuove.** `Position`, `Index` e le altre tabelle di stato si aggiornano per incrementi (`balance += value`). L'incremento si applica solo se la riga dell'evento è stata davvero inserita (`createMany` con `skipDuplicates` e controllo del `count`, oppure `insert … on conflict do nothing returning`). Un `upsert` con `update: {}` sull'evento non basta: rielaborare il blocco raddoppierebbe i saldi.
- **Tipi.** `uint256` e `int256` a Prisma come stringhe decimali (`Decimal(78, 0)`), numeri di blocco come `bigint`, indirizzi in minuscolo, `args` di `RawEvent` con i `bigint` convertiti in stringa.
- **Tempo.** Solo il timestamp del blocco, mai l'orologio del server.
- **Errori.** Una lettura RPC secondaria che fallisce (per esempio `latestRoundData`) scrive una riga in `IndexerError` e il blocco prosegue. Un errore su `getLogs`, `getBlock` o sul DB annulla la transazione del blocco e il blocco si riprova.

Primi handler (punto 2 della Fase 4):

| Evento | Scritture |
|---|---|
| `IndexCreated` (minimo) | `Index` (con `name()` e `symbol()` letti al blocco), `Contract` kind `INDEX`. Serve subito perché `Trade`, `ShareTransfer` e `Position` hanno la foreign key su `Index` |
| `SharesMinted` | `Trade` (`MINT`), `Position` (`sharesMinted`, `usdcIn`, `feesPaid`), `Index.accruedFees` |
| `Transfer` di un Index | `ShareTransfer`, `Position.balance` di `from` e `to` (non per l'indirizzo zero), `Index.totalSupply` su mint e burn, `Index.holderCount` quando un saldo passa da zero a positivo o torna a zero |

Il resto della mappa evento → tabella è in `db.md` e si aggiunge un handler alla volta.

## 6. Reorg

Le regole sono in `db.md`, sezione "Reorg". Nel ciclo il punto di ingresso è il controllo del `parentHash` in `processBlock`: se non coincide si risale all'ultimo blocco comune, si applicano quelle regole e si riparte da lì. Finché il punto 5 della Fase 4 non è scritto, un `parentHash` diverso scrive una riga in `IndexerError` e ferma il processo. Su anvil un reorg si provoca con `anvil_reorg` o con `evm_snapshot` / `evm_revert`.

## 7. Stato dei lavori

Lo stato di ogni passo (e dei punti della Fase 4 a cui corrisponde) sta in `localHelpers/indexer-roadmap.md`, non qui. Lo schema del DB (punto 1) è fatto; del codice ci sono i passi 1 e 2 (configurazione e layer `chain/`).

## 8. Verifica a mano

1. `make dev`, poi l'indexer: il backfill parte da `startBlock` e trova l'`IndexCreated` del deploy.
2. Un mint dal Router: `Trade`, `ShareTransfer` e `Position` si aggiornano, e `Position.balance` coincide con `balanceOf` sulla chain.
3. Indexer fermo, un altro mint, riavvio: riprende dal checkpoint senza duplicati.
4. Tabelle svuotate e nuovo avvio: lo stato ricostruito è identico. È il criterio "fatto quando" della Fase 4, insieme al reorg simulato che lascia il DB coerente.
