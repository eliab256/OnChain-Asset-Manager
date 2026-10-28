# SDK (`@oam/sdk`)

Regole e struttura dell'SDK TypeScript del progetto. `CLAUDE.md` rimanda qui per tutto ciò che riguarda `packages/sdk`. Se cambi una convenzione descritta in questo file, aggiornalo nello stesso commit.

Struttura ricavata dalla skill `web3-sdk-structure`, con le deviazioni del §10.

## 1. Il principio: nessun I/O

L'SDK conosce il protocollo e non parla mai con la chain. Non crea client, non legge, non simula, non firma, non invia, non aspetta ricevute, non usa `fetch` né l'orologio.

Produce quattro cose:

- **calldata** per le scritture: `{ to, calldata, value }`;
- **descrittori di lettura**: `{ address, abi, functionName, args }`, che si passano così come sono a viem `readContract` / `multicall` o a wagmi `useReadContract` / `useReadContracts`;
- **typed data** EIP-712 per il permit, da firmare con il wallet;
- **parser** per i risultati: log della ricevuta, revert data, snapshot dello stato.

Chi esegue è il chiamante: il front-end con wagmi, il keeper e gli script con viem. Così il front-end usa un solo client (quello di wagmi), le calldata finiscono anche nelle proposte del MultiSig e del Timelock, e quasi tutto si testa senza chain.

## 2. Pacchetti

| Pacchetto | Ruolo | Dipende da |
|---|---|---|
| `@oam/abi` (`packages/abi`) | ABI generate da `wagmi generate` (`generated.ts`, non si modifica a mano) e indirizzi per chain letti da `deployments/<chainId>.json` (`addresses.ts`) | `viem` (peer) |
| `@oam/sdk` (`packages/sdk`) | costanti, errori, utils, entità, encoder, manager | `@oam/abi`, `viem` (peer) |

`@wagmi/cli` è solo una devDependency di `@oam/abi` e serve solo a generare le ABI.

## 3. Strati

Direzione unica, mai al contrario: `constants / errors / abis → utils → entities → encoders → managers`.

| Cartella | Contenuto |
|---|---|
| `src/constants/` | `public.ts` (decimali, scala 1e6, `MAX_TOLERANCE`, `REBALANCE_THRESHOLD`, `MIN_WEIGHT`/`MAX_WEIGHT`, `MIN_FEE_PERCENTAGE`/`MAX_FEE_PERCENTAGE`, `MAX_FEED_DELAY`, `INDEX_ACTIONS`), `chains.ts` (anvil 31337, fork 31338), `addresses.ts` (`getProtocolAddresses`), `internal.ts` (non esportato) |
| `src/errors.ts` | `SdkError` e una classe per ogni caso di errore |
| `src/abis/` | frammenti che non stanno in `@oam/abi`: `protocolErrorsAbi`, ABI di Router, IndexManager, Index, MultiSig e PriceFeedManager unite a tutti gli errori del protocollo, `latestRoundData` del feed, `nonces` / `version` / `eip712Domain` |
| `src/utils/` | funzioni pure: decimali, percentuali, età del feed, `ceilDiv`, rotte di swap (`swapRoutes.ts`), porting della matematica dei contratti (`underlyingMath.ts`) |
| `src/entities/` | `Index`: modello immutabile di un Index a un blocco |
| `src/encoders/` | permit (typed data ↔ firma), MultiSig (typed data della conferma, eventi, decoder delle proposte), eventi dell'Index e dell'IndexManager (log ↔ oggetto), revert data (errore ↔ bytes) |
| `src/managers/` | una classe statica per contratto: `RouterManager`, `IndexManagerCalls`, `IndexManager`, `PriceFeedReads`, `PriceFeedManagerCalls`, `MultiSigCalls`, `Erc20Manager` |

Nomi dei file: `camelCase.ts` per i moduli, `PascalCase.ts` per le classi. Ogni cartella ha un `index.ts`, tranne `entities/`: `entities/Index.ts` e `entities/index.ts` differiscono solo per le maiuscole e TypeScript rifiuta di averli entrambi (TS1261). `src/index.ts` importa l'entità direttamente da `./entities/Index.js`.

Attenzione ai nomi: la classe `IndexManager` è il manager del contratto **Index** (letture e snapshot); il contratto **IndexManager** si usa con `IndexManagerCalls`.

## 4. Cosa c'è oggi

**`Index`** (`entities/Index.ts`). Si costruisce da uno snapshot (riserve, decimali, pesi, fee, supply, inizializzazione, prezzi a 18 decimali). Offre:

- `getValuation()`: valori USD, pesi effettivi, prezzo della share;
- `needsRebalance()`: stessa regola di `Index._checkIfRebalanceNeeded`;
- `minMintPreview` / `minRedeemPreview`: replicano `Index.minMintPreview` / `minRedeemPreview` con lo stesso ordine di operazioni e gli stessi troncamenti, quindi danno lo stesso numero del contratto a parità di stato;
- `estimateUsdcForShares` / `estimateSharesForUsdc`: il più piccolo input che fa arrivare la preview al valore voluto. Il Router ha solo funzioni a input esatto, quindi "voglio N shares" passa da qui;
- `withPrices()`: stessa entità con prezzi nuovi.

Le preview ignorano il price impact degli swap, come quelle del contratto: il mint e il redeem reali vengono controllati on-chain contro questi minimi.

**Manager**:

| Classe | Scritture (`…CallParameters`) | Letture (`…Read`) e parser |
|---|---|---|
| `RouterManager` | `buy`, `buyWithPermit`, `sell` | `minMintPreviewRead`, `minRedeemPreviewRead`, `maxToleranceRead`, `usdcRead`, `indexManagerRead`; `checkBuy` / `checkSell` su stato già letto |
| `IndexManagerCalls` | `rebalance`, `executeWeightUpdate`, `collectFees` (singoli e `…Many`), `proposeNewWeights`, `cancelWeightUpdate`; admin (tramite MultiSig): `createIndex`, `initializeIndex`, `grantRole`, `revokeRole` | `deployedIndexesRead`, `initializedIndexesRead`, `isIndexInitializedRead`, `indexByAssetsRead`, `hasRoleRead`; `roleHash`; `checkInitialized` su `initializedIndexesRead` già letto (stesso controllo dei modificatori: un indirizzo non inizializzato fa revert di tutta la batch) |
| `IndexManager` | nessuna: sull'Index si scrive solo via Router e IndexManager | `snapshotReads` + `toSnapshot`, `pendingWeightsRead` + `toPendingWeightUpdate`, `usdValueRead`, `effectiveWeightsRead` |
| `PriceFeedManagerCalls` | `registerPriceFeed`, `proposePriceFeedUpdate`, `executePriceFeedUpdate`, `cancelPriceFeedUpdate` (tramite MultiSig) | nessuna: sono in `PriceFeedReads` |
| `MultiSigCalls` | `submit` (avvolge qualunque `MethodParameters`), `confirm`, `confirmWithSig`, `execute`, `revoke` | `transactionRead`, `transactionCountRead`, `ownersRead`, `isOwnerRead`, `requiredConfirmationsRead`, `isConfirmedRead`, `confirmNonceRead`, `confirmDigestRead`, `eip712DomainRead`; `checkExecutable` su stato già letto |
| `PriceFeedReads` | nessuna: sono in `PriceFeedManagerCalls` | `priceRead`, `hasPriceFeedRead`, `feedConfigRead`, `pendingFeedUpdateRead` + `toPendingFeedUpdate`, `latestRoundDataRead` |
| `Erc20Manager` | `approve` | `balanceOfRead`, `allowanceRead`, `noncesRead`, `eip712DomainRead`, `nameRead`, `versionRead` |

**Encoder**: `buildPermitTypedData`, `permitDomainFromEip712Domain` (vale per qualunque contratto ERC-5267, anche il MultiSig), `splitPermitSignature` / `joinPermitSignature`; `buildConfirmTypedData` e `assertConfirmSignature` (conferme EIP-712 del MultiSig); `parseTransactionSubmitted`, `parseTransactionConfirmed`, `parseConfirmationRevoked`, `parseTransactionExecuted`; `decodeProposal` (cosa chiama una proposta, da mostrare prima di firmare); `parseSharesMinted`, `parseSharesBurned`, `parseIndexActionFailure`, `parseIndexCreated` e i rispettivi `encode…Log`; `parseRebalanceBatch`, `parseWeightUpdateBatch`, `parseCollectFeesBatch` (esito per index delle batch) e `failureReasonOf` (classifica il revert data); `decodeProtocolError` / `encodeProtocolError`; `toSdkError`, che trasforma quello che lancia il client del chiamante in un errore dell'SDK.

**Utils delle rotte** (`utils/swapRoutes.ts`): `v3Route(tokens, fees)`, `v4Route(poolKey)`, `routeEndpoints`, `assertRouteConnects` (stesso controllo di `SwapManager._validateRoute`), per `initializeIndexCallParameters`.

Fuori dall'SDK per scelta: Timelock e upgrade. La raccolta delle firme off-chain del MultiSig (dove si conservano finché non bastano) non è dell'SDK: spetta al backend.

## 5. Unità di misura

- Percentuali (fee, tolleranze, pesi) sulla scala 1e6 dei contratti: `10_000` = 1%. `toleranceFromBasisPoints(50n)` = `5_000n`.
- Importi in decimali del token: USDC 6, shares 18, asset quelli del token (WBTC 8, WETH 18).
- Prezzi e valori USD a 18 decimali, come li restituisce il `PriceFeedManager`.
- Tempi in secondi unix, come `bigint`. L'SDK non ha orologio: le funzioni che controllano una scadenza ricevono `nowSeconds`, che deve essere il timestamp dell'ultimo blocco (sul fork il tempo della chain è diverso da quello del computer).
- Tutti gli importi on-chain sono `bigint`.

## 6. Come si usa

**Front-end (wagmi)**:

```ts
import { getProtocolAddresses, IndexManager, RouterManager, Erc20Manager } from "@oam/sdk";

const { router, usdc } = getProtocolAddresses(chainId);

// lettura: il descrittore va direttamente a wagmi
const { data: minShares } = useReadContract(
  RouterManager.minMintPreviewRead({ router, index, usdcAmount, tolerance }),
);

// scrittura: approve verso l'Index, poi buy
const approve = Erc20Manager.approveCallParameters({ token: usdc, spender: index, amount: usdcAmount });
const buy = RouterManager.buyCallParameters({ router, index, usdcAmount, tolerance });
await sendTransactionAsync({ to: buy.to, data: buy.calldata, value: buy.value });
```

**Keeper (viem)**: il ciclo leggi → costruisci → invia → ricevuta lo scrive il keeper, una volta sola in `apps/keeper`.

```ts
const results = await publicClient.multicall({ contracts: IndexManager.snapshotReads(index), allowFailure: false });
const prices = await readPrices(results);          // tre PriceFeedReads.priceRead
const fund = Index.fromSnapshot(IndexManager.toSnapshot(index, results, prices));

if (fund.needsRebalance()) {
  const call = IndexManagerCalls.rebalanceCallParameters({ indexManager, index });
  const hash = await walletClient.sendTransaction({ to: call.to, data: call.calldata, value: call.value });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  // sui custom error dell'Index l'IndexManager non fa revert: emette IndexActionFailed. Contano solo i log emessi da indexManager
  const failure = parseIndexActionFailure(receipt.logs, { indexManager, index });
}

// batch: gas limit esplicito, poi un elenco per esito, nell'ordine di `indexes`
const many = IndexManagerCalls.rebalanceManyCallParameters({ indexManager, indexes });
const batchHash = await walletClient.sendTransaction({ to: many.to, data: many.calldata, gas: KEEPER_GAS_LIMIT });
const batchReceipt = await publicClient.waitForTransactionReceipt({ hash: batchHash });
const { rebalanced, notNeeded, failed } = parseRebalanceBatch(batchReceipt.logs, { indexManager, indexes });
// failed[i].reason.kind: "protocol" (errorName, args), "unknownCustomError", "errorString", "panic", "empty" (di solito gas finito: ritentare con più gas)
```

Le batch hanno tre parser, uno per azione. Ogni index della lista finisce in un solo elenco:
- `parseRebalanceBatch`: `rebalanced` (con le riserve di `IndexRebalanced`), `notNeeded` (`Index__RebalanceNotNeeded`), `failed`;
- `parseWeightUpdateBatch`: `updated` (pesi nuovi ed esito del rebalance interno: `rebalanced`, `skipped` o `failed` con il motivo), `failed` (pesi non applicati, proposta ancora pendente);
- `parseCollectFeesBatch`: `collected` (`feeAmount` in USDC), `noFees` (`Index__NoFeesToCollect`), `failed`.

Contano solo gli eventi dell'IndexManager con l'azione della batch. Gli eventi dell'Index si assegnano all'esito successivo dello stesso index, quindi un index ripetuto nella lista funziona. Gli esiti devono corrispondere uno a uno, nell'ordine, a `indexes`, altrimenti il parser lancia `EventNotFoundError`. Una tx annullata non ha log: in quel caso si passa l'errore del client a `toSdkError`.

**Owner del MultiSig (viem)**: proposta → conferme (on-chain o con firma) → execute.

```ts
const { multiSigWallet: multiSig, indexManager, usdc } = getProtocolAddresses(chainId);

// 1. un owner propone: qualunque builder dell'SDK si avvolge in submit
const create = IndexManagerCalls.createIndexCallParameters({
  indexManager, feePercentage: 5_000n, usdc,
  assetA: { asset: WBTC, weight: 500_000n }, assetB: { asset: WETH, weight: 500_000n },
});
const submit = MultiSigCalls.submitCallParameters({ multiSig, call: create });
const { txId } = parseTransactionSubmitted((await send(submit)).logs, multiSig);

// 2. un altro owner firma off-chain dopo aver controllato cosa firma
const [target, value, data] = await publicClient.readContract(MultiSigCalls.transactionRead({ multiSig, txId }));
console.log(decodeProposal({ target, value, data }, getProtocolAddresses(chainId)));
const domain = permitDomainFromEip712Domain(await publicClient.readContract(MultiSigCalls.eip712DomainRead(multiSig)));
const nonce = await publicClient.readContract(MultiSigCalls.confirmNonceRead({ multiSig, txId, owner: signer }));
const signature = await walletClient.signTypedData(buildConfirmTypedData({ domain, txId, target, value, data, nonce }));

// 3. chiunque registra la firma, un owner conferma ed esegue
await send(MultiSigCalls.confirmWithSigCallParameters({ multiSig, txId, signer, signature }));
const executed = await send(MultiSigCalls.executeCallParameters({ multiSig, txId }));
const { index } = parseIndexCreated(executed.logs, indexManager);
```

`initializeIndex` richiede che il depositor abbia approvato l'Index per entrambi gli asset: se il depositor è il MultiSig, anche gli `approve` sono proposte. Un `revokeConfirmation` aumenta il nonce del firmatario e invalida le sue firme raccolte prima.

I parser degli eventi accettano solo i log del contratto atteso (l'Index per `SharesMinted` / `SharesBurned`, l'IndexManager per `IndexActionFailed` e `IndexCreated`, il MultiSig per i suoi eventi). Qualunque contratto toccato nella stessa transazione può emettere un evento con la stessa firma.

Su anvil puro Multicall3 non è deployato: lì si usa `Promise.all` di `readContract`. Sul fork 31338 c'è quello di mainnet.

I dati dell'indexer (via API) servono solo a trovare i candidati. Prima di inviare una tx il keeper ricostruisce lo snapshot dalla chain, perché l'indexer può essere qualche blocco indietro.

## 7. Errori

- Ogni errore estende `SdkError`, ha una classe sua e conserva l'errore originale in `cause`. Il messaggio dice cosa fare e cita i valori.
- Nel sorgente non c'è mai `throw new Error(...)`, e nessuno confronta i messaggi: si usa `instanceof`.
- Ogni funzione che lancia lo dichiara con `@throws`.
- I revert si decodificano su tutte le ABI del protocollo. Una chiamata al Router può fallire dentro l'Index o il `PriceFeedManager`: per questo i descrittori del Router usano `routerWithErrorsAbi`.

Classi attuali: `ZeroAmountError`, `InvalidToleranceError`, `InvalidDeadlineError`, `InvalidWeightError`, `ValueOutOfRangeError`, `InvalidSignatureError`, `ZeroAddressError`, `InvalidIndexAssetsError`, `InvalidFeePercentageError`, `InvalidSwapRouteError`, `InvalidMaxDelayError`, `MultiSigNotExecutableError`, `UnknownProposalError`, `EmptyIndexListError`, `InsufficientBalanceError`, `InsufficientAllowanceError`, `IndexNotInitializedError`, `InvalidPriceError`, `InvalidDecimalsError`, `EstimateNotFoundError`, `UnsupportedChainError`, `UnknownIndexActionError`, `EventNotFoundError`, `ContractRevertError`, `RequestFailedError`.

## 8. Vietato

1. `react`, `wagmi`, `@wagmi/core`, `@tanstack/*` nell'SDK: dipendenze, peer o import.
2. Client, signer, `fetch`, orologio o numeri casuali in `src/`.
3. `any`, `@ts-ignore`, `@ts-expect-error`, `as unknown as` fuori dai test.
4. `throw new Error(...)` e confronti sui messaggi d'errore.
5. Modificare gli argomenti ricevuti: le entità restituiscono istanze nuove.
6. Import profondi da altri pacchetti: si importa da `@oam/abi`, mai da `@oam/abi/src/...`.
7. Modificare `packages/abi/src/generated.ts` a mano. Si cambiano i contratti e si lancia `npm run abi`. Le ABI sono congelate dal 2026-10-24 (vedi `CLAUDE.md`).
8. ABI o indirizzi copiati a mano, indirizzi scritti nella logica.
9. Nuove dipendenze runtime senza una motivazione scritta.
10. API pubblica implicita: `src/index.ts` elenca ogni export per nome, e quello che non c'è è interno (per esempio `utils/underlyingMath.ts` e `constants/internal.ts`).

## 9. Test

**Stato (2026-10-28, dopo il modulo MultiSig).** Unit e property: 713 test su 24 file, tutti verdi (anche con `FC_SEED` fissi). Fork: 90 test in un solo file di ingresso (`test/sdk.integration.test.ts`, che carica `test/suites/*.ts`, compresa `multiSig.ts`); su anvil 31337 ne passano 83 e 7 si saltano, sul fork 31338 ne passano 79 e 11 si saltano (i test che hanno senso solo sull'altra chain).

I test del modulo MultiSig hanno trovato 3 bug, corretti lo stesso giorno: firme high-s e firme con v = 0/1 accettate da `confirmWithSigCallParameters` (on-chain `ECDSA.recover` le rifiuta), `value` della proposta fuori da uint256 che lasciava uscire un errore di viem. Senza nodo attivo la suite fork si salta da sola.

I bug trovati dai primi test (`toSdkError` sui revert di `sendTransaction`, stime non minime e `EstimateNotFoundError` con USDC a 18 decimali, firme malformate, importi oltre uint256 che lasciavano uscire errori di viem) sono stati corretti il 2026-10-27 e i test che li fissavano con `it.fails` ora sono test normali. Le stime cercano il minimo con raddoppio dalla stima lineare e bisezione (`searchMinimum` in `entities/Index.ts`), contando sul fatto che le preview sono monotone.

Note per i fork test:

- un solo file di ingresso perché i file del progetto `fork` girano in parallelo sullo stesso anvil e si annullerebbero a vicenda gli `evm_snapshot`; per dividerli serve `fileParallelism: false` in `vitest.config.ts`;
- i client viem usano `cacheTime: 0`, altrimenti dopo `evm_revert` il numero di blocco in cache dà `BlockOutOfRange`;
- su 31337 il deploy lascia `UniversalRouterMock` senza tassi né liquidità e i feed mock scadono dopo 1h15m di tempo della chain: gli helper impostano tassi e liquidità e aggiornano i feed all'avvio;
- sul fork gli account di default di anvil hanno una delega EIP-7702 al blocco fissato, e USDC verifica i loro permit via ERC-1271 rifiutandoli: i compratori usano chiavi derivate da un'etichetta;
- gas delle azioni dell'IndexManager: dal 2026-10-28 le varianti singole (`rebalance`, `collectFees`, `executeWeightUpdate`) fanno revert sugli errori comuni (out-of-gas compreso) e `Index.executeWeightUpdate` ripropaga quelli del rebalance interno: la stima basta per tutte le azioni singole, e sotto la stima la tx fa revert con pesi e proposta invariati. Serve ancora un gas limit esplicito (`KEEPER_GAS_LIMIT` nei test) solo per le batch, che assorbono qualunque fallimento (con poco gas `executeWeightUpdateMany` può riuscire lasciando la proposta pendente);
- sul fork COMP salva allowance e saldi in uint96: `approve(maxUint256)` si rilegge come 2^96 - 1 e gli importi dati con `dealErc20` devono restare sotto 2^96;
- owner del MultiSig su 31337 e 31338: account 1, 2 e 3 di anvil. L'account 0 è il deployer e non è owner;
- firme delle conferme del MultiSig: `confirmTransactionWithSig` riceve i byte grezzi e `ECDSA.recover` di OpenZeppelin accetta solo v = 27/28 e `s` basso. `confirmWithSigCallParameters` riscrive v 0/1 in 27/28 (`normalizeConfirmSignature`) e rifiuta le firme high-s; il permit non ha il problema perché il Router riceve `v` separato;
- dopo un `increaseTime` oltre il `maxDelay` i feed sono scaduti: su 31337 si riaggiornano con `refreshMockFeeds`, sul fork no, quindi lì il rebalance dentro `executeWeightUpdate` fallisce sempre per prezzo scaduto.
- sul fork, dopo il warp di `proposeAndWait`, `loadIndex` fa revert con `PriceFeedManager__PriceIsStale` perché legge i prezzi: per confrontare lo stato si leggono direttamente `getAssetsWeights` / `getAssetsReserves`;
- quando cambia il bytecode dell'Index, a ogni redeploy cambiano l'indirizzo dell'Index (CREATE2) e il `block` in `deployments/<chainId>.json`; i test leggono l'Index da `initializedIndexesRead`, quindi non dipendono da quel file;
- batch con più Index su 31337 (`test/suites/batches.ts`): `test/helpers/indexes.ts` crea LINK/COMP e WETH/LINK dai mock di `deployments/31337.json` via MultiSig impersonato. I feed LINK/COMP vanno aggiornati tramite il loro indirizzo mock, perché prima della registrazione `getPriceFeedConfig` restituisce `address(0)`. Sul fork 31338 i feed non si spostano e un warp li rende tutti scaduti, quindi lì non c'è un caso `rebalanced`. Un fallimento `empty` (gas finito) dentro una batch non si è riprodotto on-chain: `empty` e `panic` sono coperti solo dagli unit test.

Regole:

- unit test accanto al file (`foo.ts` + `foo.test.ts`) per ogni export, errori verificati per classe;
- property test (`@fast-check/vitest`) sulla matematica di `utils/` e `Index` e sui round-trip degli encoder (`parse(encode(x))` uguale a `x`);
- fork test in `test/*.integration.test.ts`: eseguono le calldata di ogni manager e controllano lo stato risultante (saldi, shares, allowance), non solo i byte. Confrontano anche `Index.minMintPreview` / `minRedeemPreview` con `Router.getMinMintPreview` / `getMinRedeemPreview` sullo stesso blocco;
- i fork test girano su anvil (`make anvil && make deploy-anvil`, chain 31337) e sul fork di mainnet (`make anvil-fork && make deploy-fork`, chain 31338, blocco fissato 26.178.000 in `test/integration/ForkConstants.sol`). Gli helper vanno in `test/helpers/`;
- niente wagmi nei test: client viem diretti.

Test da nominare esplicitamente: tolleranza fuori dai limiti, importo zero, deadline scaduta, direzione degli arrotondamenti nelle preview, spender del permit uguale all'Index.

Comandi (da `packages/sdk`):

```bash
npm run typecheck    # tsc --noEmit
npm test             # unit e property
npm run test:fork    # fork test, con anvil acceso e deploy fatto (anche `make dev` dalla root)
```

Lint dalla root: `npm run lint` (ESLint 10, `typescript-eslint` `recommendedTypeChecked`, configurazione in `eslint.config.mjs`; il `tsconfig.json` dell'SDK estende `tsconfig.base.json`). Deve dare 0 segnalazioni. Dopo `npx eslint --fix` rilanciare sempre `npm run typecheck`: togliere un cast "inutile" può lasciare un import di tipo inutilizzato, o allargare un letterale in una tabella di `it.each` senza `as const`. In quel caso la tabella si tipizza con `satisfies` invece di rimettere il cast. I metodi statici dei manager non si passano come valore (`unbound-method`): nelle tabelle dei test si avvolgono in una arrow function, con il tipo del parametro preso da `Parameters<typeof X.metodo>[0]`.

## 10. Deviazioni dalla skill `web3-sdk-structure`

| Skill | Qui | Motivo |
|---|---|---|
| Pacchetto ABI `packages/contracts` | `packages/abi` (`@oam/abi`) | Nome legato al congelamento delle ABI, al pre-commit e a `CLAUDE.md`. Lo script `check-no-framework-deps.mjs` della skill segnala `@wagmi/cli` in `@oam/abi` perché accetta solo un pacchetto chiamato `contracts`: è atteso |
| Build tsup (ESM + CJS + `.d.ts`), changesets, turbo, syncpack, husky | Nessuno | I pacchetti sono `private` e non si pubblicano su npm: si esporta il sorgente TS, come `@oam/abi`. Da rivedere se un giorno l'SDK si pubblica |
| `AGENTS.md` alla root e per pacchetto | Questo file, richiamato da `CLAUDE.md` | Decisione dell'utente del 2026-10-27 |
| Indirizzi in `src/addresses.ts` scritto a mano | `addresses.ts` legge `deployments/*.json` | I file di deploy sono la fonte unica e li scrivono gli script Foundry |

## 11. Aggiungere un contratto o una funzione

1. Modifica il contratto in `src/` (con il subagent `solidity-developer`), poi `npm run abi`. Se cambia l'ABI serve prima la decisione dell'utente (congelamento).
2. Se servono nuovi stati o nuova matematica: entità o `utils/`, con unit e property test.
3. Se ci sono eventi o firme nuove: encoder e parser, con test di round-trip.
4. Nel manager del contratto: `…CallParameters` per le scritture, con validazione degli input ed errori tipizzati; `…Read` per le letture.
5. Fork test che esegue la chiamata e controlla lo stato.
6. Export per nome in `src/index.ts`, JSDoc con unità di misura e `@throws`.
7. Aggiorna questo file e lancia i controlli:

```bash
npx tsc --noEmit -p packages/sdk
node ~/.claude/skills/web3-sdk-structure/assets/scripts/check-no-framework-deps.mjs packages
node ~/.claude/skills/web3-sdk-structure/assets/scripts/check-typed-errors.mjs packages
```
