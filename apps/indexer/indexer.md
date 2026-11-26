# Indexer (`@oam/indexer`)

Regole e struttura dell'indexer off-chain. Legge i blocchi della chain, decodifica gli eventi del protocollo e scrive le tabelle di `@oam/db`. Se cambi una convenzione descritta in questo file, aggiornalo nello stesso commit.

**Stato (2026-11-25): passi 1-4 di `localHelpers/indexer-roadmap.md` fatti** (configurazione, logger, layer `chain/`, repository di base, `processBlock`, `processRange`, bootstrap e backfill, Index scoperti durante il range con l'handler minimo di `IndexCreated`, con unit test e test d'integrazione anche contro anvil). `npm start` fa il backfill dal checkpoint all'head ed esce; il live arriva al passo 5. Al 2026-11-15 c'erano solo `package.json` e `tsconfig.json`. Questo file descrive come va scritto il codice della Fase 4 di `localHelpers/roadmap.md` e sostituisce `blockchain-indexer-roadmap.md`, una guida generica per un indexer di un solo evento `Transfer`, scritta prima dello schema del DB e tolta lo stesso giorno. Da lì resta solo la regola dei layer (§3).

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
| `viem` | client HTTP per tutte le letture (`getBlockNumber`, `getBlock`, `getLogs`, `readContract`, `multicall`) e `decodeEventLog`; client WebSocket solo per l'`eth_subscribe` a `newHeads` (`transport.subscribe`, §4, "Live") |
| `@oam/abi` | ABI tipizzate e `protocolAddresses[chainId]` (indirizzi dei contratti fissi e `startBlock`) |
| `@oam/db` | `createPrismaClient` e i tipi generati |
| `@oam/sdk` | solo costanti, selettori degli errori e la matematica dei contratti quando serve (per esempio il NAV) |

I log si decodificano con `decodeEventLog` e le ABI di `@oam/abi`. I parser dell'SDK (`parseSharesMinted` e simili) non si usano: leggono la ricevuta di una tx cercando un evento preciso, mentre l'indexer deve decodificare qualunque log gli arrivi.

Variabili in `apps/indexer/.env` (modello in `.env.example`), validate all'avvio:

| Variabile | Significato |
|---|---|
| `RPC_URL` | RPC HTTP della chain (anvil `http://127.0.0.1:8545`). Tutte le letture passano da qui |
| `RPC_FALLBACK_URLS` | RPC HTTP di riserva della stessa chain, separati da virgola, provati in ordine solo quando `RPC_URL` fallisce. Facoltativa. Un URL ripetuto, o uguale a `RPC_URL`, è un errore di configurazione |
| `RPC_FALLBACK_URLS` | **dal passo 5, non ancora letta.** Uno o più RPC HTTP di riserva della stessa chain, separati da virgola, usati in ordine solo quando quelli prima non rispondono. Facoltativa. Regole sotto, "RPC di riserva" |
| `RPC_WS_URL` | RPC WebSocket della stessa chain (anvil `ws://127.0.0.1:8545`, stessa porta). Serve solo ad avvisare dei blocchi nuovi. Facoltativa: senza, resta solo il polling |
| `CHAIN_ID` | 31337 (anvil) o 31338 (fork). All'avvio si confronta con `eth_chainId`: se non coincidono il processo si ferma |
| `DATABASE_URL` | Postgres di `docker-compose.yml`, lo stesso di `packages/db/.env` |
| `BATCH_SIZE` | blocchi per chiamata `getLogs` nel backfill (default 2000) |
| `TEST_DATABASE_URL` | solo per i test d'integrazione (§3): il database `oam_test` dello stesso Postgres. Il nome deve finire in `_test`. Non la legge il processo dell'indexer |
| `POLL_INTERVAL_MS` | durata del timer di guardia del live (§4, "Live"): senza avvisi del WebSocket per questo tempo parte un giro via HTTP (default 30000). Senza `RPC_WS_URL` scatta a ogni intervallo e fa da polling (in quel caso conviene 1000) |

**Segreti negli URL** (2026-11-17). I provider RPC mettono la API key nell'URL (Alchemy e Infura nel percorso, altri nella query o come password), e `DATABASE_URL` contiene la password. Due difese, in `src/secrets.ts`:

- `describeConfig` stampa degli URL RPC solo protocollo, host e porta (`https://eth-mainnet.g.alchemy.com/***`); dell'URL del DB maschera solo la password, perché il nome del database non è un segreto.
- All'avvio `logger.redact(configSecrets(config))` registra le parti segrete (percorso e query degli URL RPC, segmenti lunghi almeno 16 caratteri, password), e il logger le sostituisce con `***` in **ogni** riga. Serve perché viem scrive l'URL completo nei messaggi di errore HTTP (`URL: https://…/v2/<KEY>`), che arrivano al log da `errorMessage`, non da `describeConfig`. I valori sotto 6 caratteri non si redigono in tutta la riga (la password locale `oam` cancellerebbe `@oam/abi`).

Regola per il codice futuro: niente `console.log` diretti, tutto passa dal `logger`, altrimenti la redazione non si applica.

**RPC di riserva** (deciso il 2026-11-24, codice del 2026-11-25: parte 2 del passo 5 della roadmap). Con un solo RPC, se il provider cade l'indexer smette di avanzare. I dati restano corretti: alla ripresa riparte dal `Checkpoint` e recupera i blocchi persi, ma nel frattempo il DB resta indietro (l'API risponde con dati vecchi, il keeper della Fase 7 è il più esposto). Un secondo provider risolve la disponibilità, però due nodi non vedono sempre la stessa chain: possono essere a head diverse, vedere un reorg in momenti diversi, indicizzare i log con ritardo (un `getLogs` vuoto per un blocco che `getBlock` vede già) e avere limiti diversi (range di `eth_getLogs`, dimensione delle `eth_call`, letture a blocchi vecchi solo da un nodo archive). Regole:

- transport `fallback` di viem con gli URL in ordine (`RPC_URL`, poi `RPC_FALLBACK_URLS`): si resta sul primo finché risponde e si passa al successivo solo su errore. Niente `rank`, che misura la latenza di tutti con richieste di prova e riordina i provider anche quando il primo funziona, creando proprio i salti fra nodi che si vogliono evitare;
- i segreti degli URL di riserva si registrano nel logger come quelli di `RPC_URL`, e `describeConfig` li maschera allo stesso modo;
- all'avvio ogni provider passa i controlli di `RPC_URL`, più due prove: una multicall deployless e una lettura allo `startBlock`. Un provider che non le passa si scopre all'avvio e non a metà backfill: il processo si ferma con un messaggio che lo nomina (URL mascherato);
- il WebSocket resta uno solo: se cade c'è già il polling di riserva, che con il fallback passa anche lui al provider successivo;
- le incoerenze fra nodi le coprono i controlli che ci sono già (numero di blocco obbligatorio nelle letture, `parentHash` contro `Block[n − 1]`, checkpoint: un provider indietro dà un head sotto il checkpoint e `catchUp()` non fa niente) più il controllo del `blockHash` dei log (§4, `processBlock`).

Prova in locale: primo URL su una porta chiusa, secondo su anvil, e l'indexer deve passare al secondo e indicizzare normalmente. Fatta il 2026-11-25 con `npm start` (`RPC_URL` su una porta chiusa con una chiave finta nel percorso, anvil in `RPC_FALLBACK_URLS`): primo provider segnalato come irraggiungibile, secondo controllato, backfill completo, chiave mai nel log.

Come è scritto (2026-11-25):

- `createChainClients` (`chain/clients.ts`) costruisce il client HTTP con `fallback([http(RPC_URL), http(...RPC_FALLBACK_URLS)])`, senza `rank`. Un dettaglio del transport di viem da sapere: **ogni richiesta riparte dal primo provider**, non c'è memoria di quello che ha funzionato. Mentre `RPC_URL` è giù, ogni chiamata aspetta prima il suo errore: immediato con una connessione rifiutata, fino a `RPC_TIMEOUT_MS` (10 s) con un provider che non risponde. I retry sono del fallback, che chiama ogni provider una volta per tentativo e ripete l'intera lista `RPC_RETRY_COUNT` volte. Senza `RPC_FALLBACK_URLS` la lista ha un solo provider e si comporta come un `http` normale. Un revert (`execution reverted`) non passa al provider successivo: il fallback di viem lo rilancia subito;
- `createChainClients` restituisce anche `providers`: un client per ogni URL, da solo e senza fallback, per i controlli. I controlli non passano dal client col fallback, perché il fallback nasconderebbe quale provider ha risposto;
- `checkProviders` (`chain/providers.ts`, chiamata da `index.ts` al posto del vecchio `assertChainId`) controlla ogni provider in ordine: chain id; una multicall deployless all'head di `getIndexFactory()` dell'IndexManager, che deve restituire l'IndexFactory del file di deploy (prova insieme che il provider accetta una `eth_call` senza `to` e che il file di deploy descrive questa chain); una lettura di stato (`eth_getBalance` dell'IndexManager) allo `startBlock`, che un nodo senza storico rifiuta. Un provider che risponde ma non passa un controllo ferma l'avvio con `ProviderCheckError`, che dice quale controllo (`chainId`, `deployment`, `archive`) e nomina il provider con l'URL mascherato. Un provider che non risponde (errore transitorio, `chain/errors.ts`) non ferma l'avvio: è segnalato con un `warn` e non controllato, e il fallback lo salta finché resta giù. Se non risponde nessuno, `NoProviderReachableError`;
- il limite di questa regola: un provider di riserva giù all'avvio e tornato più tardi entra in uso senza essere stato controllato. Gli altri controlli (`parentHash`, `blockHash` dei log, numero di blocco obbligatorio) restano, ma un nodo senza storico si scoprirebbe solo alla prima lettura a un blocco vecchio.

Scoperto scrivendo i test (2026-11-25): **anvil caricato con `--load-state` non aveva lo storico**. Lo snapshot di `make snapshot` salvava solo lo stato dell'ultimo blocco, e ogni lettura a un blocco precedente falliva con `BlockOutOfRangeError`, comprese le `eth_call`. Il controllo `archive` fermava l'avvio su `make dev`, e il problema sarebbe arrivato comunque al passo 6 (`name()` e `symbol()` letti al blocco di `IndexCreated`). Risolto con `--preserve-historical-states` in `bin/snapshot.sh`: lo snapshot conserva gli stati di ogni blocco (il file passa da circa 1,5 a 11,6 MB) e le letture ai blocchi vecchi funzionano dopo il caricamento. `deployments/31337.json` rigenerato è rimasto identico.

## 3. Layer

Ogni layer usa solo quelli sotto di lui, mai quelli sopra. È l'unica regola ripresa dalla vecchia guida, precisata il 2026-11-22: le dipendenze formano un albero, non una scala. `index.ts` → `runner.ts` → `pipeline.ts` → `handlers/`; gli handler stanno sopra **due** layer, `chain/` per le letture e `repositories/` per le scritture, e anche la pipeline li usa tutti e due (log e blocchi da `chain/`, `Block`, `RawEvent` e `Checkpoint` da `repositories/`). `chain/` e `repositories/` invece non si conoscono: `chain/` non importa niente di Prisma, `repositories/` niente di viem o dei tipi di `chain/`. `config.ts`, `logger.ts` e `secrets.ts` sono trasversali, li può usare qualunque layer.

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
    consistency.ts    assertLogsBelongToBlock: log e blocco della stessa versione della chain
    blocks.ts         fetchBlockHeader: numero, hash in minuscolo, timestamp come Date
    errors.ts         isTransientRpcError: errori RPC per cui ha senso aspettare e riprovare
    providers.ts      checkProviders: controlli all'avvio di ogni provider HTTP
  handlers/         un file per contratto, una funzione per evento
    types.ts          Handler, HandlerMap, HandlerContext, AddedContract (la pipeline li riesporta)
    index.ts          handlers: la HandlerMap dell'indexer
    indexManager.ts   indexCreated (minimo: riga Contract dell'Index)
  repositories/     l'unico layer che usa Prisma: non conosce la chain
    db.ts             tipo Db: client Prisma o client della transazione
    json.ts           toJsonArgs: args decodificati → JSON (bigint in stringa)
    checkpoint.ts     getCheckpoint, setCheckpoint
    errors.ts         recordIndexerError
    blocks.ts         insertBlock, getStoredBlock
    contracts.ts      insertFixedContracts, insertIndexContract, loadContractKinds
    rawEvents.ts      insertRawEvents
  pipeline.ts       processRange(from, to) e processBlock
  runner.ts         bootstrap, backfill, giri di catch-up (catchUpRound, createCatchUp)
  live.ts           segnali del live: WebSocket (wsBlockWatch) e timer di guardia (startLive)
  index.ts          avvio, live e chiusura pulita su SIGINT / SIGTERM
```

- `chain/` restituisce log già decodificati e normalizzati: `{ address, eventName, args, blockNumber, blockHash, txHash, logIndex }`, indirizzi in minuscolo (anche dentro `args`). Il tipo è un'unione discriminata su `eventName`, quindi un handler che legge un campo inesistente non compila. Un log che non corrisponde a nessun evento del protocollo torna con `kind: "unknown"` (con `reason` e `detail` dell'errore di decodifica) invece di lanciare. Gli indirizzi in `args` si mettono in minuscolo guardando il tipo dell'ABI, non la forma della stringa.
- Le letture si fanno con `readContractAt` e `multicallAt` di `chain/reads.ts`, dove `blockNumber` è obbligatorio nei tipi. Il multicall è deployless: il codice dell'aggregatore viaggia dentro la `eth_call`, perché anvil puro non ha Multicall3.
- I test unitari stanno accanto ai sorgenti (`src/**/*.test.ts`) e girano con `npm test --workspace @oam/indexer`, senza RPC né DB.
- **Test d'integrazione** (2026-11-20, dal passo 3 della roadmap). Stanno in `test/**/*.integration.test.ts` e girano con `npm run test:integration --workspace @oam/indexer`, con Postgres e anvil accesi. Lo schema è quello dell'SDK (`packages/sdk/vitest.config.ts`):
  - due progetti vitest, `unit` e `integration`; `npm test` lancia solo `unit`, così resta valida la regola sopra;
  - database `oam_test` sullo stesso Postgres di `docker-compose.yml`, separato da `oam` perché i test svuotano le tabelle. L'URL è in `TEST_DATABASE_URL` (in `apps/indexer/.env`). Il controllo è in `test/helpers/env.ts` (`assertTestDatabaseUrl`): il setup si rifiuta di partire se il nome del database non finisce in `_test` o se coincide con `DATABASE_URL`, così un errore di configurazione non svuota il DB di sviluppo;
  - setup globale (`test/setup/globalSetup.ts`): `prisma migrate deploy` su `oam_test` (applica le migrazioni esistenti senza crearne). Se il database non esiste lo crea `migrate deploy` stesso, provato il 2026-11-22: non serve un `CREATE DATABASE` a mano. Basta `make db`;
  - fra un test e l'altro `resetDatabase` di `test/helpers/db.ts`: un solo `TRUNCATE … RESTART IDENTITY CASCADE` di tutte le tabelle tranne `_prisma_migrations`. Il client sul DB dei test si crea con `createTestPrisma`. Un file d'integrazione chiama `useTestDatabase()` dentro il suo `describe`: registra client, reset prima di ogni test e chiusura, e restituisce la funzione che dà il client;
  - l'indexer intero, come lo lancia `npm start`, si prova come processo figlio (`startIndexer` di `test/helpers/indexerProcess.ts`, 2026-11-26): le variabili passate vincono su `apps/indexer/.env` (dotenv non sovrascrive, nemmeno una stringa vuota, ed è così che si toglie `RPC_WS_URL`), le righe del logger si leggono come JSON e `stop(signal)` restituisce l'exit code. Il processo si ferma sempre aspettandone l'uscita (SIGTERM, e SIGKILL solo se non esce), così un test non lascia processi vivi al successivo. Col WebSocket il test aspetta la riga `websocket subscribed` e non solo `live`: la seconda arriva prima della conferma dell'abbonamento. Il mint vero su anvil puro è `prepareMint` di `test/helpers/mint.ts`, che rinfresca i feed mock e dà tassi e liquidità al Universal Router mock come gli helper dell'SDK; le sue transazioni vanno prese dopo un `evm_snapshot`;
  - i provider "sbagliati" dei test sulla riserva (`test/fallback.integration.test.ts`) sono un proxy JSON-RPC locale davanti ad anvil (`startRpcProxy` di `test/helpers/rpcServer.ts`), che cambia la risposta di un metodo preciso: un altro chain id, una `eth_call` senza `to` rifiutata, nessuno stato ai blocchi vecchi. Così basta un solo anvil. `closedPortUrl()` dà una porta locale su cui non ascolta nessuno;
  - anvil si accende da fuori (`make dev`, o `anvil --load-state .anvil/31337.json`), il test non lo avvia. L'URL è `TEST_RPC_URL` (default `http://127.0.0.1:8545`), non `RPC_URL`, che può puntare al fork. `probeAnvil()` di `test/helpers/anvil.ts` controlla chain id 31337 e il codice dell'IndexManager di `deployments/31337.json`; se manca qualcosa le suite anvil si saltano con `describe.skipIf` e il motivo nel titolo, come nell'SDK. Va quindi controllato che non risultino `skipped`: `npm run test:integration` verde con anvil spento non dice niente su quei test. I test che mandano transazioni usano `evm_snapshot` / `evm_revert`. I file d'integrazione girano uno alla volta in un solo processo (`pool: "forks"` con `poolOptions.forks.singleFork`), perché condividono DB e anvil e si svuoterebbero le tabelle (o annullerebbero gli snapshot) a vicenda. `fileParallelism: false`, quello che suggerisce `packages/sdk/sdk.md`, in vitest 3 non è un'opzione del singolo progetto.
  
  Perché contro un Postgres vero e non con Prisma finto: `skipDuplicates` e il suo `count`, i tipi (`BigInt`, `Char(66)`, `Json`), l'annullamento della transazione e il suo timeout sono comportamenti del DB, e un mock confermerebbe solo quello che pensiamo faccia. Molti casi non hanno bisogno della chain: `processBlock` riceve blocco e log come argomenti (§4), quindi log `unknown`, emittente di tipo non atteso, `parentHash` sbagliato e blocco elaborato due volte si provano con dati costruiti nel test. Anvil serve per la prova d'insieme (backfill dello snapshot) e, dal passo 6, per le transazioni vere.
- Un handler riceve la transazione Prisma del blocco, l'evento e il contesto del blocco (numero, hash, timestamp, gli altri log della stessa tx). Decide cosa scrivere e chiama i repository. In codice (`pipeline.ts`, 2026-11-24) è un oggetto `{ kinds, handle }` registrato nella `HandlerMap` sotto il nome dell'evento; `handle` riceve `{ db, chainId, client, block, log, txLogs }`, con `log` già ristretto al tipo di quell'evento, e restituisce eventualmente `{ addedContracts }` (gli Index aggiunti a `Contract`, per il passo 4 della roadmap). Le letture RPC le fa attraverso `chain/`, sempre con `blockNumber` del blocco che sta processando, mai `latest`: così un blocco riprocessato dà lo stesso risultato.
- **Dispatch degli handler** (2026-11-20). La pipeline sceglie l'handler solo per `eventName`: basta, perché gli eventi con lo stesso nome in più contratti (`RoleGranted`/`RoleRevoked` di IndexManager e Timelock, `Upgraded` dei tre proxy) si scrivono allo stesso modo e l'emittente lo dà `address` del log (`RoleMember.contract`, `ProxyUpgrade.proxy`). Gli altri doppioni (`Initialized`, `OwnershipTransferred`, `RoleAdminChanged`, `EIP712DomainChanged`) vanno solo in `RawEvent`. Ogni handler dichiara però da quali `ContractKind` si aspetta l'evento (`SharesMinted` solo da `INDEX`, `RoleGranted` da `INDEX_MANAGER` o `TIMELOCK`). Se il tipo dell'emittente non è fra quelli, la pipeline non chiama l'handler e scrive una riga in `IndexerError`, mentre il log resta in `RawEvent` perché è decodificato. È una difesa contro un upgrade che dà a un proxy un evento con un nome già usato, o contro un indirizzo finito per errore in `Contract`: senza il controllo l'handler scriverebbe righe sbagliate, o violerebbe una foreign key e bloccherebbe il blocco a ogni tentativo.
- I repository espongono operazioni di dominio (`insertTrade`, `applyShareTransfer`), non query generiche. Regole dei repository di base (2026-11-22):
  - il primo argomento è sempre `db: Db` (`repositories/db.ts`, cioè `Prisma.TransactionClient`): la pipeline passa la transazione del blocco, un test o una lettura isolata il `PrismaClient`, che ha lo stesso tipo;
  - gli input sono tipi del repository (`RawEventInput`, `StoredBlock`, `FixedContracts`), mai i tipi di `chain/`: i log decodificati hanno già quella forma e si passano così come sono, ma il layer resta senza import dalla chain;
  - indirizzi e hash si mettono in minuscolo anche qui, prima di scrivere, oltre che in `chain/`: la convenzione di `db.md` non dipende da chi chiama;
  - gli inserimenti di righe che nascono da un evento o da un blocco usano `createMany({ skipDuplicates: true })` e restituiscono quante righe sono entrate davvero (`count`, o un booleano per una riga sola). È la base degli incrementi solo su righe nuove (§5). Provato su Postgres: un secondo `insertRawEvents` sullo stesso blocco più un log nuovo restituisce 1;
  - `insertFixedContracts` scrive i sei contratti con eventi (IndexManager, Router, PriceFeedManager, SwapManager, MultiSig, Timelock) e lascia fuori IndexFactory (nessun evento) e USDC (non è del protocollo, e il suo `Transfer` verrebbe preso per quello di un Index). Le righe già presenti restano com'erano, così il bootstrap gira a ogni avvio;
  - `toJsonArgs` converte i `bigint` in stringhe decimali e lancia un errore su valori che viem non produce mai (`null`, funzioni, istanze di classe, `NaN`), invece di salvarli in silenzio.
- L'API (Fase 5) è un servizio separato: l'indexer non espone HTTP.

## 4. Ciclo

**Bootstrap.** Upsert in `Contract` dei contratti fissi di `protocolAddresses[chainId]` con il loro `startBlock`. Poi si legge `Checkpoint`: se manca si parte da `startBlock`, altrimenti da `lastBlockNumber + 1`. Il bootstrap viene prima di qualunque `processRange`, perché gli indirizzi da ascoltare si leggono da `Contract`: con la tabella vuota `getLogs` non avrebbe indirizzi e `RawEvent` resterebbe vuota (per questo nella roadmap sta nel passo 3, non in quello del live).

Il codice è `bootstrap(db, chainId, fixed)` in `src/runner.ts` (2026-11-24), con `fixed = protocolAddresses[chainId]`. Restituisce `fromBlock` (il primo blocco da elaborare), il `checkpoint` letto (il suo hash è quello con cui va confrontato il `parentHash` di `fromBlock`: così si vede un reorg avvenuto mentre l'indexer era fermo) e quanti contratti ha inserito (6 al primo avvio, poi 0). Prima scrive i contratti e poi legge il checkpoint, senza transazione: le due operazioni sono indipendenti e tutte e due ripetibili. Un caso da sapere in locale: un anvil ripartito da zero (`make anvil` e un nuovo deploy) riusa il chain id 31337, ma i suoi blocchi hanno hash diversi da quelli salvati. Il bootstrap riparte comunque dal checkpoint vecchio, e il primo blocco nuovo si ferma sul controllo del `parentHash` (§6). Si risolve svuotando le righe di quella chain dal DB prima di riavviare l'indexer. Se il checkpoint è oltre l'head di più di `MAX_HEAD_BEHIND_CHECKPOINT` = 64 blocchi (anvil nuovo con meno blocchi), il backfill si ferma subito con `CheckpointAheadOfHeadError`, senza scrivere niente. Fino a 64 blocchi (soglia del 2026-11-25, scelta dell'utente) è un provider di riserva un po' indietro: una riga di `warn`, nessun blocco elaborato, e il live recupera quando il provider arriva.

**Backfill** (2026-11-25, `backfill(deps, fixed)` di `src/runner.ts`). Bootstrap, poi l'head letto una volta via HTTP (`getBlockNumber` con `cacheTime: 0`, perché viem tiene in cache il numero di blocco per qualche secondo), poi `processRange(fromBlock, head)`. I blocchi usciti durante il backfill restano alla chiamata successiva (al live, dal passo 5). Restituisce `{ bootstrap, head, range }`. Con niente di nuovo non scrive niente: `fromBlock` = head + 1 e il range è vuoto. Il `parentHash` di `fromBlock` si confronta con il blocco del checkpoint dentro `processBlock`, che legge `Block[n − 1]` dal DB: un reorg avvenuto a indexer fermo si vede lì senza codice in più. `src/index.ts` fa configurazione, controllo del chain id, backfill e uscita, e chiude Prisma e i client anche quando fallisce (un errore di chiusura non copre quello che ha fermato il processo).

**`processRange(from, to)`.**

1. Indirizzi da ascoltare: tutte le righe di `Contract` della chain (i fissi e gli Index già scoperti), caricate una volta a inizio range in una mappa in memoria `address → ContractKind`. La stessa mappa serve al controllo del tipo nel dispatch (§3). Non si rilegge la tabella a ogni pezzo: `processBlock` restituisce `{ addedContracts }`, i contratti aggiunti a `Contract` nel blocco (oggi solo gli Index di `IndexCreated`), e `processRange` li aggiunge alla mappa. Il valore di ritorno esiste dal passo 3 della roadmap, anche quando è sempre vuoto, così il passo 4 (log dei nuovi Index nello stesso pezzo) non cambia la firma.
2. `getLogs` su quegli indirizzi, a pezzi di `BATCH_SIZE` blocchi. Con `Contract` vuota non si chiama il nodo: i blocchi si elaborano comunque, senza log.
3. Log raggruppati per blocco e ordinati per `logIndex`.
4. Per ogni blocco del range, in ordine, `processBlock`, anche per i blocchi senza log. I contratti di `addedContracts` entrano nel filtro dal pezzo successivo.

Il codice è `processRange(deps, from, to)` in `pipeline.ts` (2026-11-24). Restituisce `{ lastBlock, blocksProcessed, addedContracts }`; con `from > to` non fa niente e non chiama il nodo, e un `batchSize` che non è un intero positivo è un errore. Se un blocco fallisce, l'errore risale così com'è: i blocchi prima sono già scritti e il checkpoint punta all'ultimo di loro, quindi la chiamata successiva riparte da lì. I retry e lo stop sono del runner (passo 5). Il limite noto del §4, "Index creati a metà range", vale finché il passo 4 della roadmap non è scritto.

**`processBlock(n)`.** Prima della transazione, `getBlock(n)` via RPC (numero, hash, `parentHash`, timestamp). I log del blocco arrivano già da `processRange`.

**Controllo del `blockHash` dei log** (2026-11-24, `assertLogsBelongToBlock` di `chain/consistency.ts`). Prima di aprire la transazione, ogni log del blocco deve avere `blockNumber` e `blockHash` uguali a numero e hash del blocco appena letto. I log di un pezzo arrivano da una `getLogs` fatta prima delle `getBlock` dei singoli blocchi: se in mezzo c'è un reorg vicino all'head, o se le due chiamate le serve un nodo diverso (RPC di riserva, §2), il blocco `n` avrebbe i log di un'altra versione della chain. Il `parentHash` non se ne accorge, perché confronta solo i blocchi fra loro. Per questo il controllo serve anche con un solo RPC. Se fallisce (`LogBlockMismatchError`): niente scritture, si rileggono blocco e log del solo blocco `n` (`getLogs` da `n` a `n`) e si riprova, fino a 3 volte; poi `IndexerError` scritto fuori dalla transazione e stop, come per un `parentHash` diverso. Un blocco senza log non ha niente da confrontare: un provider che indicizza i log in ritardo resta un limite noto, coperto solo dalla scelta di provider affidabili.

**Controllo del `parentHash`** (spostato fuori dalla transazione il 2026-11-24, scrivendo il codice). Si legge `Block[n − 1]` e lo si confronta con il `parentHash` del blocco appena letto **prima** di aprire la transazione. Se non coincidono, `IndexerError` si scrive da sola, fuori dalla transazione, e poi si lancia `ParentHashMismatchError`: scritta dentro, il rollback che segue l'errore la cancellerebbe. Se `Block[n − 1]` non c'è il controllo si salta: è il primo blocco della chain (`startBlock`). Un buco in mezzo non può esistere, perché `Block` e `Checkpoint` si scrivono nella stessa transazione e si riparte sempre da checkpoint + 1. L'indexer è l'unico processo che scrive `Block`, quindi fra la lettura e la transazione la riga non può cambiare.

Nello stesso punto si controlla il blocco `n` stesso (2026-11-24, emerso dai test di `processRange`): se è già salvato con un hash diverso da quello letto, `IndexerError` fuori dalla transazione e `StoredBlockMismatchError`. Succede quando si rielabora un blocco già scritto e la chain nel frattempo è cambiata. Senza il controllo `insertBlock` terrebbe la riga vecchia (salta i doppioni), il checkpoint prenderebbe l'hash nuovo, e l'incoerenza verrebbe fuori solo al blocco dopo, come `parentHash` sbagliato.

Poi, in una `prisma.$transaction` (`timeout` 30 s e `maxWait` 10 s, costanti `BLOCK_TX_TIMEOUT_MS` e `BLOCK_TX_MAX_WAIT_MS` di `pipeline.ts`):

1. riga `Block`;
2. `RawEvent` di tutti i log decodificati del blocco, in un solo `createMany`. Scriverli tutti prima degli handler invece che uno per volta non cambia niente: è la stessa transazione, e nessun handler legge `RawEvent`;
3. per ogni log `unknown`, una riga in `IndexerError` (§5, "Log non decodificabili");
4. per ogni log decodificato, in ordine di `logIndex`, l'handler se esiste e se il tipo dell'emittente è fra quelli attesi (§3, "Dispatch degli handler"). Gli eventi senza handler restano solo in `RawEvent`;
5. passi di fine blocco: prezzi dei feed e `NavSnapshot` (regole in `db.md`, "Prezzi"). Oggi non ce ne sono: il posto è segnato in `pipeline.ts`, prima del checkpoint;
6. `Checkpoint` a `n`.

I log di avviso (log sconosciuto, emittente inatteso) si scrivono dopo il commit: un avviso su un blocco poi annullato descriverebbe righe che non esistono. `processBlock` restituisce `{ block, blockInserted, rawEventsInserted, addedContracts }`; `blockInserted` è `false` quando il blocco era già nel DB.

**RPC e transazione** (2026-11-20). La transazione interattiva di Prisma tiene riservata una connessione del pool per tutta la sua durata e ha un timeout (default 5 secondi, `maxWait` 2 secondi per avere la connessione). Il tempo di una chiamata RPC non lo controlliamo (retry dopo un 429, il fork che inoltra la richiesta upstream, rete lenta): dentro la transazione si mangia il timeout, il blocco fallisce con un errore del DB anche se il DB non c'entra, e la connessione resta occupata ad aspettare. Regole:

- `getBlock` e `getLogs` stanno sempre fuori dalla transazione. Non dipendono da niente di quello che si scrive, e con un `parentHash` diverso la transazione non serve nemmeno. Il confronto con `Block[n − 1]` si fa comunque dentro, con il blocco già letto.
- Le letture RPC degli handler (`name()`, `symbol()`, `decimals`) per ora restano dentro: dipendono dall'evento, sono rare, e portarle fuori vorrebbe dire dividere ogni handler in una fase "prepara" (letture) e una "scrivi" (solo DB). Per coprirle, `timeout` e `maxWait` della transazione si alzano (ordine di 30 secondi) con due costanti definite in un solo punto di `pipeline.ts`.
- Le letture che girano a **ogni** blocco, come `latestRoundData()` dei feed (passo 12 della roadmap), si fanno prima della transazione: sono una multicall che non dipende dai log, e dentro peserebbero su ogni blocco.
- Se più avanti un handler ha bisogno di letture frequenti o lente, si passa alla divisione "prepara / scrivi" per quell'handler, non si alza ancora il timeout.

**Live.** Finito il backfill l'indexer aspetta i blocchi nuovi con due segnali, e tutti e due fanno la stessa cosa: chiamano `catchUp()`, che legge l'head via HTTP e, se è oltre il checkpoint, lancia `processRange(checkpoint + 1, head)`.

- **WebSocket, il segnale principale.** `eth_subscribe` a `newHeads` sul client WebSocket: il nodo avvisa appena esce un blocco.
- **Timer di guardia, la riserva** (deciso il 2026-11-25, al posto del polling fisso). Dura `POLL_INTERVAL_MS` (30 secondi) e si azzera a ogni avviso del WebSocket; se scade parte un `catchUp()` via HTTP e il timer riparte. Con il WebSocket sano non ci sono richieste HTTP periodiche. Senza WebSocket non si azzera mai, quindi scatta a ogni intervallo come un polling.

Perché il WebSocket: il blocco arriva nel DB subito invece che dopo l'intervallo di polling, così il front-end vede un mint appena confermato, e non si fanno richieste a vuoto quando la chain è ferma (su un RPC a pagamento un polling al secondo sono circa 86.000 chiamate al giorno).

Perché non il WebSocket da solo: una connessione può cadere, e nel caso peggiore resta aperta ma smette di consegnare blocchi. L'indexer sembrerebbe vivo e resterebbe indietro senza nessun errore. Il timer di guardia mette un tetto a quel ritardo, 30 secondi, e lo fa senza dover capire se il socket funziona: guarda l'assenza di avvisi, gli errori non gli servono. Copre anche il tempo di riconnessione e i provider che chiudono le subscription dopo un po'.

Perché questo non complica il codice: il WebSocket porta solo l'avviso, mai i dati. Il numero di blocco ricevuto non si usa nemmeno: `catchUp()` rilegge l'head e riparte dal checkpoint, quindi un avviso perso, doppio o fuori ordine non fa danni, e i blocchi usciti durante una caduta si recuperano al segnale dopo. Log, blocchi e letture passano sempre dal client HTTP (regola del §1: niente eventi consegnati uno alla volta).

Regole:

- un solo `catchUp()` alla volta: se arriva un segnale mentre uno è in corso si segna che ce n'è un altro da fare e lo si esegue alla fine, senza code;
- **come è scritto** (2026-11-25, parte 4 del passo 5 per i giri, parte 5 il 2026-11-26 per i segnali). I giri stanno in `src/runner.ts`. `catchUpRound(deps, startBlock)` è il giro: legge il checkpoint dal DB e l'head via HTTP (`cacheTime: 0`), e lancia `processRange(checkpoint + 1, head)` con il segnale di stop; senza blocchi nuovi non fa niente, e un head sotto il checkpoint (provider indietro, di qualunque distanza: nel live non c'è soglia) scrive una riga di `info` e aspetta il segnale dopo. `createCatchUp(round, options)` è il meccanismo, e non conosce né DB né chain: `trigger()` avvia un giro se non ce n'è uno in corso, altrimenti segna `pending`, e alla fine del giro ne parte **uno solo** in più, comunque siano arrivati i trigger. È ciò che impedisce a WebSocket e timer di guardia di far partire due `processRange` sugli stessi blocchi. I segnali stanno in `src/live.ts`: `wsBlockWatch(client)` è `client.transport.subscribe({ params: ["newHeads"] })` sul client WebSocket, `startLive({ trigger, watch, guardMs })` collega l'abbonamento e il timer a `trigger()` e restituisce `stop()`. `index.ts` li unisce: finito il backfill crea il catch-up, avvia il live e chiama subito un `trigger()`, perché i blocchi usciti durante il backfill altrimenti aspetterebbero il primo avviso o il timer;
- **abbonamento attivo, un giro in più** (2026-11-26). L'`eth_subscribe` è asincrono: fra il `trigger()` dopo il backfill e la conferma del nodo passa del tempo, e un blocco minato lì non lo annuncia nessuno. Arriverebbe solo con il blocco dopo (circa 12 s su mainnet) o con il timer di guardia (fino a 30 s; su anvil, che mina solo con le transazioni, è il caso normale). Per questo `wsBlockWatch` usa `transport.subscribe` e non `watchBlockNumber`, che fa la stessa chiamata ma non dice quando l'abbonamento è attivo: la promise di `subscribe` si risolve sulla conferma, lì parte `onSubscribed`, e `startLive` scrive `websocket subscribed` e chiede un giro. Vale anche per il riabbonamento dopo una caduta. Trovato col test del riavvio (parte 6), che falliva circa una volta su dieci; con un blocco minato subito dopo la riga `live` si perdeva 8 volte su 45 senza il giro e 0 su 45 con il giro. Dopo una riconnessione interna viem rifà l'`eth_subscribe` senza avvisare: lì la finestra resta, coperta dal blocco dopo o dal timer;
- **errori di un giro**: un errore RPC transitorio (`isTransientRpcError`) fa aspettare e riprovare il giro, con una pausa che parte da `CATCH_UP_RETRY_INITIAL_MS` = 1 s, raddoppia a ogni fallimento consecutivo fino a `CATCH_UP_RETRY_MAX_MS` = 30 s e riparte da 1 s dopo un giro riuscito. Qualunque altro errore (reorg, DB, errore RPC permanente) va a `onFatal` una volta sola, e dopo il runner non accetta più giri: chi lo usa (`index.ts`, parte 5) ferma il processo. Un errore permanente arrivato mentre ci si sta fermando si riporta comunque: uno stop non fa mai lanciare `processRange`, quindi un errore in quel momento è vero;
- **stop**: `stop()` ferma il segnale (il giro in corso si ferma fra due blocchi, §4 "Chiusura"), interrompe subito una pausa di retry, scarta il giro in attesa e si risolve quando il giro in corso è finito;
- **caduta del WebSocket** (2026-11-26). viem si riconnette da solo: 5 tentativi a 2 secondi di distanza, e dopo la riconnessione rifà l'`eth_subscribe` (letto nel codice di viem 2.58). Dopo l'ultimo tentativo fallito butta via l'abbonamento per sempre, senza avvisare. Regole di `startLive`: al primo errore una riga di `warn`, una sola anche se viem segnala l'errore, la chiusura e ogni riconnessione fallita; il timer continua a chiedere giri via HTTP; quando scade dopo un errore senza che sia arrivato un blocco, l'abbonamento si chiude e si riapre, e così viem apre un socket nuovo. Un blocco arrivato dopo l'errore vuol dire che viem si è ripreso: una riga di `info` e nessun riabbonamento. Un WebSocket sano su una chain ferma (anvil senza transazioni) non si riabbona mai, perché non ha errori;
- **errori RPC** (2026-11-25, parte 1 del passo 5). Due livelli. Il primo è dentro viem: ogni richiesta si riprova fino a `RPC_RETRY_COUNT` = 3 volte con pause di 150, 300 e 600 ms (`RPC_RETRY_DELAY_MS` raddoppiato), con un limite di `RPC_TIMEOUT_MS` = 10 s per richiesta. Sono i valori di default di viem, scritti in `chain/clients.ts` perché un aggiornamento di viem non li cambi senza che ce ne accorgiamo, e valgono sia per l'HTTP sia per il WebSocket. Assorbe un singhiozzo del provider. Il secondo livello è del runner (parte 4): un errore che arriva fin lì dopo i retry di viem passa da `isTransientRpcError` di `chain/errors.ts`. Se è transitorio, il runner aspetta con una pausa crescente e riprova il `catchUp()`; altrimenti il processo si ferma, come per un reorg o un errore del DB;
- cosa conta come transitorio: `TimeoutError`; una richiesta senza risposta HTTP (connessione rifiutata, DNS, reset: `HttpRequestError` senza `status`); gli status HTTP 408, 429, 500, 502, 503 e 504; i codici JSON-RPC di rate limit in una risposta 200, cioè -32005 (standard), 429 (Alchemy in batch) e -32007 (QuickNode); il WebSocket chiuso. La funzione segue la catena dei `cause`, perché viem incapsula l'errore della richiesta in quello dell'azione (per esempio `CallExecutionError`). Restano fuori, apposta, tre casi che viem invece riprova: 403 e 413, che sui provider usati vogliono dire chiave rifiutata o richiesta troppo grande (un range di `getLogs` oltre il limite) e tornano uguali a ogni tentativo, e -32603 ("internal error"), che anvil restituisce anche per errori che un nuovo tentativo non risolve. Un errore permanente preso per transitorio lascerebbe l'indexer ad aspettare per sempre invece di fermarsi con un messaggio;
- senza `RPC_WS_URL` (un RPC che non offre WebSocket) il timer di guardia è l'unico segnale e l'intervallo va abbassato.

**Chiusura** (2026-11-25, parte 3 del passo 5; SIGINT / SIGTERM collegati il 2026-11-26, parte 5). `processRange` accetta un `AbortSignal` facoltativo in `RangeDeps.signal` e lo controlla in due punti soli: prima della `getLogs` di ogni pezzo e prima di ogni blocco. Mai dentro un blocco: il blocco in corso quando arriva lo stop finisce sempre, scritto per intero o fallito per intero, perché è una sola transazione. Con il segnale fermato `processRange` restituisce `stopped: true` con `lastBlock` sull'ultimo blocco scritto: uno stop non è un errore, e la chiamata successiva riparte da checkpoint + 1 senza buchi né doppioni. Il segnale non si passa alle chiamate RPC: una `getLogs` o una `getBlock` già partita finisce (al massimo `RPC_TIMEOUT_MS` per tentativo), e solo dopo il ciclo vede lo stop. Interromperla a metà non farebbe risparmiare niente di importante, e terrebbe aperta la domanda di cosa sia stato scritto.

I segnali (2026-11-26, in `index.ts`). Il primo SIGINT o SIGTERM scrive una riga e ferma un `AbortController`, già attivo durante il backfill: se arriva lì, il backfill finisce con `stopped: true` e il live non parte. Nel live fa chiudere abbonamento e timer (`live.stop()`) e aspetta il giro in corso (`catchUp.stop()`); poi il `finally` chiude Prisma e il WebSocket e il processo esce con 0. Un errore permanente di un giro (`onFatal`) passa dalla stessa strada, poi viene rilanciato e il processo esce con 1. Un secondo segnale mentre si aspetta esce subito con 130, senza aspettare il blocco: serve quando una chiamata RPC è appesa e non si vuole aspettare il timeout. Il blocco a metà non si scrive (è una transazione) e il riavvio riparte dal checkpoint. Provato su anvil il 2026-11-26: un blocco minato arriva nel DB in 169 ms col WebSocket e in 782 ms senza (`POLL_INTERVAL_MS=1000`); dopo Ctrl-C, 3 blocchi minati a indexer spento e il riavvio, `Block` ha 52 righe distinte da 0 a 51.

**Index creati a metà range** (punto 3 della Fase 4, codice del 2026-11-25). `IndexCreated` aggiunge l'Index a `Contract`, ma il filtro di `getLogs` del pezzo in corso era già fissato e i log del nuovo Index in quel pezzo non sono arrivati. Regola: subito dopo la `getLogs` del pezzo, **prima di elaborarne i blocchi**, `withDiscoveredIndexLogs` di `pipeline.ts` cerca fra i log decodificati gli `IndexCreated` emessi da un contratto di kind `INDEX_MANAGER` con un `indexAddress` non ancora in `Contract`. Per quegli indirizzi fa una sola `getLogs` in più, dal blocco di creazione più basso alla fine del pezzo, tiene nel blocco di creazione solo i log con `logIndex` maggiore dell'`IndexCreated` e unisce tutto, ordinato per `(blockNumber, logIndex)`. Dai pezzi successivi l'Index è nel filtro normale, perché l'handler l'ha messo in `Contract` e `processRange` l'ha aggiunto alla mappa.

Perché prima di elaborare il pezzo e non dopo il blocco di creazione (scelta del 2026-11-25, la roadmap diceva il contrario): dopo `processBlock(n)` il blocco `n` è già scritto, e i log dell'Index nello stesso blocco dopo l'`IndexCreated` (un `initializeIndex` incluso nello stesso blocco di `createIndex`, normale su una chain pubblica) andrebbero persi. Così tutte le chiamate RPC restano fuori dalle transazioni (§4, "RPC e transazione"). Il prezzo è che la pipeline conosce un evento per nome, `IndexCreated`, e legge il suo `indexAddress`; la riga di `Contract` la scrive comunque l'handler (`handlers/indexManager.ts`), che restituisce l'Index in `addedContracts`.

Altre due regole nate scrivendolo:

- dentro `processBlock` il dispatch usa una copia della mappa `address → kind` aggiornata dopo ogni handler: un evento dell'Index nello stesso blocco della creazione arriva al suo handler invece di finire in `IndexerError` come emittente non atteso;
- la rilettura di un blocco dopo un `blockHash` sbagliato passa dalla stessa funzione (`getLogs` dei contratti noti più la scoperta), così il blocco di creazione riletto ha ancora i log del nuovo Index.

Un `IndexCreated` da un emittente che non è l'IndexManager non fa scoprire niente e finisce in `IndexerError` dal dispatch. L'Index non emette eventi nel costruttore, quindi nel blocco di creazione non ci sono suoi log prima dell'`IndexCreated`: il filtro sul `logIndex` lo dice in modo esplicito.

## 5. Come si scrive un handler

- **Chiave unica.** Ogni riga nata da un log è unica su `(chainId, txHash, logIndex)`. `chainId` c'è sempre: 31337 e 31338 stanno nello stesso DB.
- **Incrementi solo su righe nuove.** `Position`, `Index` e le altre tabelle di stato si aggiornano per incrementi (`balance += value`). L'incremento si applica solo se la riga dell'evento è stata davvero inserita (`createMany` con `skipDuplicates` e controllo del `count`, oppure `insert … on conflict do nothing returning`). Un `upsert` con `update: {}` sull'evento non basta: rielaborare il blocco raddoppierebbe i saldi.
- **Tipi.** `uint256` e `int256` a Prisma come stringhe decimali (`Decimal(78, 0)`), numeri di blocco come `bigint`, indirizzi in minuscolo, `args` di `RawEvent` con i `bigint` convertiti in stringa.
- **Tempo.** Solo il timestamp del blocco, mai l'orologio del server.
- **Errori.** Una lettura RPC secondaria che fallisce (per esempio `latestRoundData`) scrive una riga in `IndexerError` e il blocco prosegue. Un errore su `getLogs` o `getBlock` (prima della transazione) o sul DB (dentro) fa fallire il blocco, che non lascia scritture a metà e si riprova.
- **Log non decodificabili** (2026-11-20). Un log da un indirizzo del protocollo che `decodeLog` restituisce come `unknown` vuol dire che l'ABI dell'indexer non corrisponde più a quello che il contratto emette: un upgrade UUPS con un evento nuovo, lo stesso evento con `indexed` su parametri diversi, un deploy fatto senza rigenerare `@oam/abi`. Regole:
  - non va in `RawEvent`: `eventName` è obbligatorio e `args` contiene solo argomenti decodificati per nome. Una riga con un nome finto (`UNKNOWN`) costringerebbe ogni lettore di `RawEvent` a filtrarla, compresa la ricostruzione di `TimelockOperation` dopo un reorg (`db.md`, "Reorg", punto 3);
  - scrive una riga in `IndexerError`, nella stessa transazione del blocco: `blockNumber` del blocco, `context` con indirizzo e `txHash:logIndex`, `message` con `reason`, `detail`, `topics` e `data`. I dati grezzi servono per esaminare il log senza rileggere la chain;
  - scrive anche una riga di log a livello `error`: qualcuno deve aggiornare l'ABI;
  - il blocco prosegue e il checkpoint avanza. Fermare il processo bloccherebbe tutto il protocollo per un evento che magari nessun handler usa (scelta del passo 2 della roadmap). Il prezzo è che l'evento non arriva alle tabelle di dominio: per recuperarlo si aggiorna `@oam/abi` e si reindicizza da zero, che il criterio di replay (§8) rende sicuro;
  - un blocco fallito e riprovato non lascia doppioni, perché la riga di `IndexerError` si annulla con il resto della transazione.

Primi handler (punto 2 della Fase 4):

| Evento | Scritture |
|---|---|
| `IndexCreated` (minimo) | `Index` (con `name()` e `symbol()` letti al blocco), `Contract` kind `INDEX`. Serve subito perché `Trade`, `ShareTransfer` e `Position` hanno la foreign key su `Index` |
| `SharesMinted` | `Trade` (`MINT`), `Position` (`sharesMinted`, `usdcIn`, `feesPaid`), `Index.accruedFees` |
| `Transfer` di un Index | `ShareTransfer`, `Position.balance` di `from` e `to` (non per l'indirizzo zero), `Index.totalSupply` su mint e burn, `Index.holderCount` quando un saldo passa da zero a positivo o torna a zero |

Il resto della mappa evento → tabella è in `db.md` e si aggiunge un handler alla volta.

## 6. Reorg

Le regole sono in `db.md`, sezione "Reorg". Nel ciclo il punto di ingresso è il controllo del `parentHash` in `processBlock`: se non coincide si risale all'ultimo blocco comune, si applicano quelle regole e si riparte da lì. Finché il punto 5 della Fase 4 non è scritto, un `parentHash` diverso (o un blocco già salvato con un altro hash) scrive una riga in `IndexerError` (fuori dalla transazione del blocco, §4) e ferma il processo con `ParentHashMismatchError` (o `StoredBlockMismatchError`). Su anvil un reorg si provoca con `anvil_reorg` o con `evm_snapshot` / `evm_revert`.

## 7. Stato dei lavori

Lo stato di ogni passo (e dei punti della Fase 4 a cui corrisponde) sta in `localHelpers/indexer-roadmap.md`, non qui. Lo schema del DB (punto 1) è fatto; del codice ci sono i passi 1-4 (configurazione, layer `chain/`, pipeline, backfill e scoperta degli Index).

## 8. Verifica a mano

1. `make dev`, poi l'indexer: il backfill parte da `startBlock` e trova l'`IndexCreated` del deploy.
2. Un mint dal Router: `Trade`, `ShareTransfer` e `Position` si aggiornano, e `Position.balance` coincide con `balanceOf` sulla chain.
3. Indexer fermo, un altro mint, riavvio: riprende dal checkpoint senza duplicati.
4. Tabelle svuotate e nuovo avvio: lo stato ricostruito è identico. È il criterio "fatto quando" della Fase 4, insieme al reorg simulato che lascia il DB coerente.
