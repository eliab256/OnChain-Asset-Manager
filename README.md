🏗️ 2️⃣ Architettura corretta (pulita)
🔹 1. AdminController.sol

NON deve contenere stato dei vault.
Deve solo orchestrare.

Responsabilità:

createIndex()

updateWeights(vault, newWeights)

triggerRebalance(vault)

collectProtocolFee(vault)

multicall()

⚠️ Non deve detenere asset.
⚠️ Non deve avere logica finanziaria.

È solo governance executor.

Meglio usare:

Ownable

o AccessControl (ruoli granulari)

🔹 2. IndexFactory.sol

Responsabilità:

Deploy nuovo IndexVault

Impostare parametri iniziali

Registrarlo nel Registry

Event emission

Deve essere minimale.

Come Uniswap V2 Factory:

crea

salva

basta

🔹 3. IndexRegistry.sol

Responsabilità:

mapping vaultId => vaultAddress

mapping underlyingToken => vaults[]

array allVaults

funzioni di view

NON deve deployare.
NON deve fare logica economica.

Solo storage + discovery.

🔹 4. IndexVault.sol (il cuore del sistema)

Questo è il “pair” alla Uniswap.

Responsabilità:

Detenere asset (WETH, WBTC, etc.)

Mint shares

Burn shares

Calcolare NAV

Calcolare sharesToMint

Calcolare redeem amounts

Rebalance

Accumulare fee

Contiene:

struct Asset {
address token;
uint256 weight; // in bps (5000 = 50%)
address priceFeed;
}

Mapping:

Asset[] public assets;

🔹 5. Router.sol

Il Router è solo UX layer.

Responsabilità:

depositSingleAsset()

depositMultiAsset()

redeem()

batch operations

eventuali swap via DEX

Come Uniswap Router:
Non ha stato economico.
Non detiene asset.

🔐 3️⃣ Ruoli consigliati

Molto importante separare:

GOVERNANCE_ROLE
REBALANCER_ROLE
FEE_COLLECTOR_ROLE

Non fare un super-admin che fa tutto.

🧠 Evoluzione futura (molto interessante)

Puoi aggiungere:

Protocol-level fee (su mint/redeem)

Performance fee (su profitto)

Timelock governance

Upgradeability via proxy

Ma NON mettere upgradeability in v1 se vuoi tenere il design pulito.
