// Static demo data for the market pages. Nothing here comes from the chain or the API:
// series are generated with a seeded PRNG so every reload shows the same numbers.

export type AssetSymbol = "WBTC" | "WETH" | "LINK" | "COMP" | "USDC";

export interface Asset {
  symbol: AssetSymbol;
  name: string;
  /** Short ticker shown to users (BTC rather than WBTC). */
  ticker: string;
  decimals: number;
  feed: string;
}

export const ASSETS: Record<AssetSymbol, Asset> = {
  WBTC: { symbol: "WBTC", name: "Wrapped Bitcoin", ticker: "BTC", decimals: 8, feed: "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c" },
  WETH: { symbol: "WETH", name: "Wrapped Ether", ticker: "ETH", decimals: 18, feed: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419" },
  LINK: { symbol: "LINK", name: "Chainlink", ticker: "LINK", decimals: 18, feed: "0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c" },
  COMP: { symbol: "COMP", name: "Compound", ticker: "COMP", decimals: 18, feed: "0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5" },
  USDC: { symbol: "USDC", name: "USD Coin", ticker: "USDC", decimals: 6, feed: "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6" },
};

/** Assets that have a price history and can be compared against an index. */
export const COMPARABLE_ASSETS: AssetSymbol[] = ["WBTC", "WETH", "LINK", "COMP"];

/** Reference "now" of the demo, so nothing depends on the real clock during render. */
export const MOCK_NOW = new Date("2026-11-25T12:00:00Z").getTime();
const DAY = 86_400_000;
export const HISTORY_DAYS = 365;

export interface PricePoint {
  t: number;
  v: number;
}

function mulberry32(seed: number) {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Daily geometric random walk ending at `last`, with a shared market factor so assets are correlated.
const market = (() => {
  const rnd = mulberry32(7);
  return Array.from({ length: HISTORY_DAYS }, () => (rnd() - 0.5) * 2);
})();

function walk(seed: number, last: number, vol: number, drift: number, beta: number): PricePoint[] {
  const rnd = mulberry32(seed);
  const returns = market.map((m) => drift + vol * (beta * m + (1 - beta) * (rnd() - 0.5) * 2));
  const out: PricePoint[] = new Array<PricePoint>(HISTORY_DAYS + 1);
  let price = last;
  out[HISTORY_DAYS] = { t: MOCK_NOW, v: price };
  for (let i = HISTORY_DAYS - 1; i >= 0; i--) {
    price = price / (1 + (returns[i] ?? 0));
    out[i] = { t: MOCK_NOW - (HISTORY_DAYS - i) * DAY, v: price };
  }
  return out;
}

export const ASSET_HISTORY: Record<Exclude<AssetSymbol, "USDC">, PricePoint[]> = {
  WBTC: walk(11, 97_420, 0.028, 0.0014, 0.75),
  WETH: walk(23, 3_612, 0.034, 0.0009, 0.8),
  LINK: walk(37, 21.84, 0.045, 0.0011, 0.6),
  COMP: walk(41, 58.3, 0.05, -0.0004, 0.55),
};

export function latestPrice(symbol: AssetSymbol): number {
  if (symbol === "USDC") return 1;
  return ASSET_HISTORY[symbol].at(-1)?.v ?? 0;
}

export type ActivityType = "MINT" | "REDEEM" | "REBALANCE" | "FEES";

export interface Activity {
  type: ActivityType;
  account: string;
  usd: number;
  t: number;
  tx: string;
}

export interface IndexInfo {
  address: string;
  name: string;
  symbol: string;
  assets: [AssetSymbol, AssetSymbol];
  /** Basis points, sum 10 000. */
  targetWeights: [number, number];
  currentWeights: [number, number];
  reserves: [number, number];
  navPerShare: number;
  supply: number;
  tvl: number;
  change24h: number;
  holders: number;
  volume24h: number;
  /** Annual management fee, basis points. */
  feeBps: number;
  lastRebalance: number;
  history: PricePoint[];
  activity: Activity[];
}

// NAV of a daily-rebalanced two-asset basket, starting at `start` USDC per share.
function basketHistory(a: PricePoint[], b: PricePoint[], wa: number, start: number): PricePoint[] {
  const out: PricePoint[] = [];
  let nav = start;
  for (let i = 0; i < a.length; i++) {
    const pa = a[i];
    const pb = b[i];
    if (!pa || !pb) break;
    if (i > 0) {
      const prevA = a[i - 1]?.v ?? pa.v;
      const prevB = b[i - 1]?.v ?? pb.v;
      nav *= 1 + wa * (pa.v / prevA - 1) + (1 - wa) * (pb.v / prevB - 1);
    }
    out.push({ t: pa.t, v: nav });
  }
  return out;
}

function makeIndex(params: {
  address: string;
  name: string;
  symbol: string;
  assets: [Exclude<AssetSymbol, "USDC">, Exclude<AssetSymbol, "USDC">];
  targetWeights: [number, number];
  currentWeights: [number, number];
  supply: number;
  holders: number;
  volume24h: number;
  feeBps: number;
  start: number;
  lastRebalanceHoursAgo: number;
  activity: Activity[];
}): IndexInfo {
  const [a0, a1] = params.assets;
  const history = basketHistory(ASSET_HISTORY[a0], ASSET_HISTORY[a1], params.targetWeights[0] / 10_000, params.start);
  const navPerShare = history.at(-1)?.v ?? params.start;
  const prev = history.at(-2)?.v ?? navPerShare;
  const tvl = navPerShare * params.supply;
  const reserves: [number, number] = [
    (tvl * params.currentWeights[0]) / 10_000 / latestPrice(a0),
    (tvl * params.currentWeights[1]) / 10_000 / latestPrice(a1),
  ];
  return {
    address: params.address,
    name: params.name,
    symbol: params.symbol,
    assets: params.assets,
    targetWeights: params.targetWeights,
    currentWeights: params.currentWeights,
    reserves,
    navPerShare,
    supply: params.supply,
    tvl,
    change24h: navPerShare / prev - 1,
    holders: params.holders,
    volume24h: params.volume24h,
    feeBps: params.feeBps,
    lastRebalance: MOCK_NOW - params.lastRebalanceHoursAgo * 3_600_000,
    history,
    activity: params.activity,
  };
}

const H = 3_600_000;

export const INDEXES: IndexInfo[] = [
  makeIndex({
    address: "0x8A791620dd6260079BF849Dc5567aDC3F2FdC318",
    name: "Bitcoin Ether Index",
    symbol: "BTCETH",
    assets: ["WBTC", "WETH"],
    targetWeights: [6_000, 4_000],
    currentWeights: [6_140, 3_860],
    supply: 18_420,
    holders: 214,
    volume24h: 182_400,
    feeBps: 100,
    start: 100,
    lastRebalanceHoursAgo: 19,
    activity: [
      { type: "MINT", account: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", usd: 12_500, t: MOCK_NOW - 0.4 * H, tx: "0x4f1c9a2be7d3" },
      { type: "REDEEM", account: "0x90F79bf6EB2c4f870365E785982E1f101E93b906", usd: 3_120, t: MOCK_NOW - 2.1 * H, tx: "0x9be20c11aa04" },
      { type: "MINT", account: "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65", usd: 840, t: MOCK_NOW - 5.6 * H, tx: "0x1d77e4f0c3b9" },
      { type: "REBALANCE", account: "0x976EA74026E726554dB657fA54763abd0C3a0aa9", usd: 21_300, t: MOCK_NOW - 19 * H, tx: "0x77ac0e52d1f8" },
      { type: "FEES", account: "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955", usd: 410, t: MOCK_NOW - 26 * H, tx: "0xc0fe91bb2047" },
    ],
  }),
  makeIndex({
    address: "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707",
    name: "Chainlink Compound Index",
    symbol: "LINKCOMP",
    assets: ["LINK", "COMP"],
    targetWeights: [5_000, 5_000],
    currentWeights: [5_310, 4_690],
    supply: 9_870,
    holders: 87,
    volume24h: 41_200,
    feeBps: 150,
    start: 100,
    lastRebalanceHoursAgo: 52,
    activity: [
      { type: "MINT", account: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", usd: 2_000, t: MOCK_NOW - 1.3 * H, tx: "0x2bb41fe98c01" },
      { type: "REDEEM", account: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", usd: 760, t: MOCK_NOW - 7.8 * H, tx: "0xd3a1c7e2f650" },
      { type: "REBALANCE", account: "0x976EA74026E726554dB657fA54763abd0C3a0aa9", usd: 6_400, t: MOCK_NOW - 52 * H, tx: "0x6e02bd94a7c3" },
    ],
  }),
  makeIndex({
    address: "0xa513E6E4b8f2a923D98304ec87F64353C4D5C853",
    name: "Ether Chainlink Index",
    symbol: "ETHLINK",
    assets: ["WETH", "LINK"],
    targetWeights: [7_000, 3_000],
    currentWeights: [6_920, 3_080],
    supply: 12_050,
    holders: 132,
    volume24h: 96_800,
    feeBps: 80,
    start: 100,
    lastRebalanceHoursAgo: 7,
    activity: [
      { type: "MINT", account: "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc", usd: 5_400, t: MOCK_NOW - 0.9 * H, tx: "0x81f0aa3c2d9e" },
      { type: "REBALANCE", account: "0x976EA74026E726554dB657fA54763abd0C3a0aa9", usd: 9_150, t: MOCK_NOW - 7 * H, tx: "0xab39e10f6c42" },
      { type: "REDEEM", account: "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65", usd: 1_980, t: MOCK_NOW - 11 * H, tx: "0x5c7d02e8b1fa" },
    ],
  }),
];

export function findIndex(address: string | undefined): IndexInfo | undefined {
  if (!address) return undefined;
  const a = address.toLowerCase();
  return INDEXES.find((i) => i.address.toLowerCase() === a);
}

/** Display label of an index pair: "BTC / ETH". */
export function pairLabel(index: IndexInfo): string {
  return `${ASSETS[index.assets[0]].ticker} / ${ASSETS[index.assets[1]].ticker}`;
}
