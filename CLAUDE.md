# CLAUDE.md

Guida per Claude Code su questo repository. Progetto didattico, non auditato, non destinato a mainnet.

## Progetto

Index fund on-chain a due asset, denominato in USDC. Foundry, solc 0.8.26, `evm_version = cancun`, **optimizer acceso (100 runs), `via_ir` disattivato** (attenzione allo stack-too-deep: usare scoping a blocchi). OpenZeppelin `contracts` e `contracts-upgradeable` v5.5.0.

Cartelle:
- `src/`: contratti. `script/`: deploy (`DeployPeriphery.s.sol`, `DeployAndInitNewIndex.s.sol`, `HelperConfig.s.sol`, `CodeConstants.sol`). `test/`: unit (`test/unit/`) e fork su mainnet (`test/integration/`).
- `indexer/` (Node + Prisma) e `sdk/` (Node): componenti off-chain.
- Documenti: `README.md` (architettura e uso), `invariant.md` (invarianti per contratto). In `localHelpers/`: `roadmap.md` (piano di lavoro off-chain: monorepo, SDK, indexer, API, keeper, notifiche, front-end), `codeReview.md` (security review corrente), `eventCheck.md` (audit degli eventi per l'indexer), `sdkModify.md` (modifiche da fare all'SDK, non ancora applicate), `TODO.md`.

## Architettura

- **IndexManager** (non aggiornabile): valida e registra gli Index (li crea tramite `IndexFactory`), orchestra init, rebalance, pesi e fee. Nel costruttore crea tre proxy ERC1967 e ne salva gli indirizzi come immutabili:
  - **SwapManager** (UUPS): costruisce i parametri di swap V3/V4 per il Universal Router. Owner = IndexManager.
  - **PriceFeedManager** (UUPS): un feed Chainlink per asset con `maxDelay`; sostituzione con timelock 2 giorni + 3 di finestra. Owner = IndexManager.
  - **Router** (UUPS): entry point degli utenti. Tutti gli Index salvano lo stesso proxy come immutabile `i_router`. Nessun owner.
- **IndexFactory** (non aggiornabile, nessun evento, senza permessi): split-code factory. Il costruttore riceve `type(Index).creationCode`, lo divide in due contratti dati (`src/libraries/SplitCode.sol`, runtime = `0x00` + metà) e `deployIndex` lo ricompone con `extcodecopy` e fa CREATE2 (salt `keccak256(asset0, asset1)`). Passa sempre `msg.sender` come `_indexManager` del nuovo Index: chi la chiama direttamente ottiene un Index gestito da sé e non registrato. Indirizzo immutabile nell'IndexManager (`getIndexFactory()`); deployata da `DeployPeriphery` prima dell'IndexManager.
- **Index**: vault ERC20 (shares + permit), senza `AccessControl` (modificatori `onlyIndexManager`/`onlyRouter` su immutabili), riserve interne `s_asset*Reserve` (non `balanceOf`), NAV da Chainlink, swap tramite il Universal Router di mainnet (immutabile).
- **Upgrade**: solo tramite il `TimelockController` di OpenZeppelin, unico `upgrader` dei tre proxy via `src/UpgraderAuth.sol` (slot ERC-7201, nessun setter). Delay minimo 2 giorni, MultiSig proposer/executor/canceller, admin = nessuno, nessuna finestra di scadenza. L'IndexManager **non** ha funzioni di upgrade.
- **MultiSigWallet** 2-di-3 con conferme EIP-712. Riceve `DEFAULT_ADMIN_ROLE` e `ASSET_MANAGER_ROLE` sull'IndexManager.
- Storage dei proxy: solo ERC-7201 (`onchainassetmanager.storage.<Contratto>`), niente variabili negli slot sequenziali.
- Eventi: l'Index è la fonte unica dei dati di stato; l'IndexManager emette solo `IndexCreated`, `IndexActionTriggered(index, caller, action)` e `IndexActionFailed(index, caller, action, reasonData)` con il revert data originale.

## Comandi

```bash
forge build                # compila
forge build --sizes        # dimensioni: tutti i contratti di src/ sotto EIP-170
forge test                 # suite completa, fork inclusi (richiede MAINNET_RPC_URL in .env)
forge test --match-path "test/unit/**"   # solo unit test, senza RPC
make test / make unittest / make integrationtest / make coverage
forge install              # reinstalla le librerie ai commit di foundry.lock
```

Stato atteso: 950 test passati su 48 suite.

Attenzione: `forge lint` può lasciare in `out/` artefatti senza bytecode. Il `forge test` successivo salta la compilazione e perde in silenzio alcune suite (fork comprese) senza segnalare errori. Dopo un `forge lint` lanciare `forge build --force` prima dei test, e controllare sempre il numero di suite.

## Regole di lavoro

- **Delega obbligatoria del codice**:
  - contratti e script (`src/`, `script/`) → subagent `solidity-developer`;
  - test e mock (`test/`) → subagent `foundry-test-writer`;
  - l'agente principale pianifica, legge il codice, esegue build e test, scrive la documentazione (`README.md`, `invariant.md`, i file in `localHelpers/`, questo file) e verifica i risultati.
- **Security review** → subagent `solidity-security-reviewer`, **solo** su richiesta esplicita dell'utente. Il reviewer è in sola lettura: build, test, `forge inspect` e `cast` li esegue poi l'agente principale.
- Dopo ogni modifica a `src/` o `test/`: `forge test` completo e aggiornamento dei documenti interessati (conteggio test incluso).
- Convenzioni Solidity: prefissi `i_` (immutabili) e `s_` (storage), errori `Contratto__Nome`, codice e commenti in inglese, NatSpec su funzioni ed eventi con le unità di misura. La documentazione del progetto è in italiano (tranne il README, in inglese).
- Non committare se non richiesto.

## Decisioni dell'utente da rispettare

- **SwapManager non emette eventi.**
- **Schema Prisma** (`indexer/prisma/schema.prisma`): non modificarlo né rigenerarlo finché l'utente non lo chiede, anche se gli eventi sono cambiati.
- **EIP-170 / EIP-3860**: risolto il 2026-10-14 con optimizer acceso (100 runs) e `IndexFactory` split-code. Runtime: `Index` 17.645 B, `SwapManager` 10.012, `IndexManager` 9.407, `IndexFactory` 1.737 (limite 24.576). Non rimettere `type(Index).creationCode` nell'IndexManager.
- **Timelock degli upgrade senza finestra di esecuzione**: le operazioni superate si cancellano a mano.
- **Fork test fissati** al blocco `MAINNET_FORK_BLOCK` (`test/integration/ForkConstants.sol`, oggi 26.178.000). Serve un RPC archive. Se si cambia blocco, il pool WBTC/WETH deve restare entro l'1% dal prezzo Chainlink, altrimenti i test di rebalance falliscono con `V3TooLittleReceived`.
- **`lib/v4-periphery` fissata a `5da22e60`** (in `foundry.lock` e nel gitlink). Non aggiornarla alla punta di `main`: le versioni successive cambiano `IV4Router.ExactInputSingleParams` (campo `minHopPriceX36`) e diventano incompatibili con il Universal Router deployato su mainnet (`0x66a9893c…8Af`, che usa v4-periphery `3779387e`). Un aggiornamento va allineato alla versione del Universal Router usato.
- Ignorare i pacchetti Node.js (`node_modules`, `indexer/`, `sdk/`) quando si lavora sulle dipendenze Foundry.

## Stato della security review

Vedi `localHelpers/codeReview.md` (2026-10-12). Nessun Critical o High aperto. Aperti: M-02 (nessuna uscita senza swap né pausa, `updateRoute` irraggiungibile), M-04 (arbitraggio sul ritardo dell'oracolo), Low L-01…L-03 e L-07…L-11, vari Informational e Gas. La checklist pre-deploy è nella sezione 11. `IndexFactory` e `SplitCode` (2026-10-14) non sono ancora stati revisionati.
