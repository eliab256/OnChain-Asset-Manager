# Blockchain Indexer con Node.js — Roadmap completa

## Contesto

Un custom indexer è un processo che si connette a un nodo blockchain via RPC, legge blocchi ed eventi in tempo reale, li trasforma e li salva in un database relazionale. Il risultato finale è un servizio con API REST che espone i dati indicizzati.

Equivale funzionalmente a quello che rindexer genera automaticamente — ma scritto da te, con controllo totale su logica, storage e API.

---

## Struttura del progetto

```
blockchain-indexer/
├── src/
│   ├── config/
│   │   └── index.ts              # env vars, RPC url, chain id
│   │
│   ├── listeners/
│   │   └── transferListener.ts   # WebSocket → eventi raw dalla chain
│   │
│   ├── services/
│   │   └── transferService.ts    # logica: trasforma e filtra gli eventi
│   │
│   ├── repositories/
│   │   └── transferRepository.ts # solo query al DB, nient'altro
│   │
│   ├── models/
│   │   └── transfer.ts           # tipi TypeScript
│   │
│   ├── api/
│   │   ├── routes/
│   │   │   └── transfers.ts      # GET /transfers/:address, ecc.
│   │   └── server.ts             # Express setup
│   │
│   └── index.ts                  # entry point, avvia listener + API
│
├── prisma/
│   └── schema.prisma             # schema del database
│
├── .env                          # RPC_URL, DATABASE_URL
├── package.json
└── tsconfig.json
```

### Regola d'oro dei layer

Ogni layer conosce solo quello immediatamente sotto di lui:

- `listeners` → riceve eventi dalla chain, li passa al service. Non tocca il DB.
- `services` → trasforma i dati grezzi, applica logica di business. Non sa come il DB è fatto.
- `repositories` → l'unico layer che parla con il database. Non conosce la blockchain.
- `api` → espone i dati via HTTP, chiama i repository. Non chiama mai i listener.

Questo rende ogni parte testabile in isolamento e sostituibile senza toccare il resto.

---

## Roadmap

### Fase 1 — Fondamenta: Node.js + TypeScript + DB (settimane 1–2)

Prima di toccare la blockchain, costruisci l'ambiente e il layer di persistenza. Molti commettono l'errore di iniziare dal listener blockchain e poi arrancare su database e API. Se prima costruisci la persistenza su dati finti, quando aggiungi il listener reale sai già che il resto funziona.

**Cosa imparare:**
- TypeScript base: tipi, interfacce, async/await
- npm: installare pacchetti, capire package.json
- Prisma ORM: definire uno schema, eseguire query
- dotenv: leggere variabili d'ambiente da `.env`
- tsx: eseguire TypeScript direttamente senza compilare

**Cosa costruire:**
- Inizializzare il progetto con `npm init`
- Configurare `tsconfig.json`
- Creare il DB locale con Postgres + Prisma
- Modello `Transfer` con campi `from`, `to`, `amount`, `blockNumber`, `txHash`, `logIndex`, `timestamp`
- Script di test: inserisci e leggi un record manualmente

**Dipendenze:**
```
typescript  tsx  @types/node  prisma  @prisma/client  dotenv  zod
```

**Obiettivo:** `npx prisma studio` apre il DB e vedi la tabella transfers vuota e funzionante.

---

### Fase 2 — Listener blockchain + pipeline dati (settimane 3–4)

**Cosa imparare:**
- viem: `createPublicClient`, `watchContractEvent`
- WebSocket vs HTTP RPC: usa WebSocket per eventi real-time, HTTP per query storiche
- ABI: cos'è, come leggerlo, dove trovarlo (Etherscan o direttamente dal tuo progetto)
- Gestione errori async in Node.js
- Logging base con pino

**Cosa costruire:**
- `transferListener.ts`: si connette via WebSocket all'RPC provider
- Ascolta gli eventi dei tuoi contratti
- Passa ogni evento a `transferService`
- Il service normalizza i dati e chiama il repository
- Il repository inserisce su Postgres con Prisma

**Dipendenze aggiuntive:**
```
viem  pino  pino-pretty
```

**Note pratiche:**
- Usa Alchemy (alchemy.com) come RPC provider — tier gratuito con 300M compute units/mese, più che sufficiente per sviluppare
- Per testare usa la testnet del tuo contratto — non servono token reali
- Avendo già i tuoi contratti, parti direttamente dai loro ABI e dai loro eventi

---

### Fase 3 — API REST con Express (settimane 5–6)

**Cosa imparare:**
- Express: router, middleware, gestione errori centralizzata
- Validazione parametri con zod
- Paginazione: `limit` + `offset` nelle query (`skip`/`take` in Prisma)
- Status code HTTP corretti: 200, 400, 404, 500
- CORS: cosa è, come configurarlo per permettere chiamate dal frontend

**Endpoint da costruire:**
```
GET /transfers                    lista paginata di tutti i trasferimenti
GET /transfers/:address           trasferimenti di un wallet specifico
GET /transfers/tx/:hash           trasferimento per transaction hash
GET /health                       status del servizio (uptime, ultimo blocco)
GET /stats                        volume totale, count eventi
```

**Dipendenze aggiuntive:**
```
express  @types/express  cors  helmet
```

**Obiettivo:** listener e API girano in parallelo nello stesso processo. `index.ts` avvia entrambi.

---

### Fase 4 — Produzione e robustezza (settimane 7–8)

**Problemi da risolvere:**

- **Backfill:** come indicizzare i blocchi storici prima dell'avvio del listener. Leggi i blocchi da un `fromBlock` configurabile con `getLogs`.
- **Reconnect automatico:** se il WebSocket cade, il listener deve riconnettersi da solo con exponential backoff.
- **Blocchi mancanti:** salva nel DB l'ultimo blocco processato. Al riavvio, riprendi da lì.
- **Rate limiting:** non spammare l'RPC provider. Usa una queue con concorrenza limitata.
- **Duplicate detection:** la chain può mandare lo stesso evento due volte. Il constraint `@@unique([txHash, logIndex])` in Prisma blocca inserimenti doppi a livello di DB.

**Infrastruttura:**
- Docker + docker-compose per Postgres in locale
- Deploy su Railway o Render (hanno tier gratuiti)
- Prisma migrations in produzione: `prisma migrate deploy`
- Monitoring base: l'endpoint `/health` deve restituire l'ultimo blocco processato

**Dipendenze aggiuntive:**
```
p-queue  express-rate-limit
```

---

## Conoscenze di database necessarie

Non serve diventare un DBA. Con Prisma la maggior parte del lavoro è astratta — non scrivi SQL a mano. Però devi capire quattro concetti:

### 1. Modellare gli eventi blockchain

Un evento del contratto diventa una riga in una tabella. Identifica i campi dell'evento e aggiungici sempre i metadati della chain: `blockNumber`, `txHash`, `logIndex`, `timestamp`.

### 2. Index (il più importante)

Senza index su `from` e `to`, la query per indirizzo scansiona tutta la tabella — lentissima con milioni di righe. In Prisma:

```prisma
model Transfer {
  id          Int      @id @default(autoincrement())
  from        String
  to          String
  amount      String
  blockNumber BigInt
  txHash      String
  logIndex    Int
  timestamp   DateTime

  @@index([from])
  @@index([to])
  @@unique([txHash, logIndex])
}
```

### 3. Unique constraint per i duplicati

`@@unique([txHash, logIndex])` garantisce che lo stesso evento non venga mai inserito due volte, anche in caso di reconnect o riavvio del listener.

### 4. Query base con Prisma

Tutto quello che usi nel progetto:

```typescript
// Inserimento (con gestione duplicato)
await prisma.transfer.upsert({
  where: { txHash_logIndex: { txHash, logIndex } },
  update: {},
  create: { from, to, amount, blockNumber, txHash, logIndex, timestamp },
});

// Query per indirizzo con paginazione
await prisma.transfer.findMany({
  where: { OR: [{ from: address }, { to: address }] },
  orderBy: { blockNumber: 'desc' },
  skip: offset,
  take: limit,
});
```

---

## Stack tecnologico completo

| Categoria | Tecnologia | Perché |
|---|---|---|
| Linguaggio | TypeScript | Tipi forti, meno bug runtime |
| Runtime | Node.js | Ecosistema blockchain maturo |
| Blockchain client | viem | Moderno, TypeScript-native, performante |
| Database | PostgreSQL | Affidabile, ottimo con dati time-series |
| ORM | Prisma | Schema dichiarativo, migrations automatiche |
| API | Express | Standard de facto, semplice |
| Validazione | zod | Schema validation type-safe |
| Logging | pino | Veloce, strutturato in JSON |
| Queue | p-queue | Controllo concorrenza per RPC calls |

---

## Note finali

**Sul colloquio:** con questo progetto in portfolio puoi rispondere "sì" a quasi tutte le domande tecniche blockchain backend. La distinzione da comunicare è: sai costruire un indexer da zero (custom), sai quando usare rindexer (velocità, EVM standard), sai quando usare The Graph (decentralizzazione richiesta dal progetto).

**Sul prossimo passo:** avendo già i contratti, il primo passo concreto è aprire l'ABI, identificare gli eventi che vuoi indicizzare, e costruire lo schema Prisma attorno a quelli. Il resto della struttura rimane identica indipendentemente dagli eventi specifici.
