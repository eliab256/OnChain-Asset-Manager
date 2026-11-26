import type { PricePoint } from "../mock/market";

export function rebase(points: PricePoint[], base = 100): PricePoint[] {
  const first = points[0]?.v ?? 1;
  return points.map((p) => ({ t: p.t, v: (p.v / first) * base }));
}

export function dailyReturns(points: PricePoint[]): number[] {
  const out: number[] = [];
  for (let i = 1; i < points.length; i++) {
    const prev = points[i - 1]?.v;
    const cur = points[i]?.v;
    if (prev && cur) out.push(cur / prev - 1);
  }
  return out;
}

function mean(xs: number[]): number {
  return xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : 0;
}

function std(xs: number[]): number {
  const m = mean(xs);
  return xs.length > 1 ? Math.sqrt(xs.reduce((s, x) => s + (x - m) ** 2, 0) / (xs.length - 1)) : 0;
}

export interface SeriesStats {
  totalReturn: number;
  /** Annualised over 365 days (crypto trades every day). */
  volatility: number;
  /** Negative fraction: -0.25 = the worst peak-to-trough fall was 25%. */
  maxDrawdown: number;
  bestDay: number;
  worstDay: number;
}

export function seriesStats(points: PricePoint[]): SeriesStats {
  const r = dailyReturns(points);
  let peak = points[0]?.v ?? 0;
  let mdd = 0;
  for (const p of points) {
    peak = Math.max(peak, p.v);
    if (peak > 0) mdd = Math.min(mdd, p.v / peak - 1);
  }
  const first = points[0]?.v ?? 1;
  const last = points.at(-1)?.v ?? first;
  return {
    totalReturn: last / first - 1,
    volatility: std(r) * Math.sqrt(365),
    maxDrawdown: mdd,
    bestDay: r.length ? Math.max(...r) : 0,
    worstDay: r.length ? Math.min(...r) : 0,
  };
}

export function correlation(a: PricePoint[], b: PricePoint[]): number {
  const ra = dailyReturns(a);
  const rb = dailyReturns(b);
  const n = Math.min(ra.length, rb.length);
  if (n < 2) return 0;
  const xa = ra.slice(0, n);
  const xb = rb.slice(0, n);
  const ma = mean(xa);
  const mb = mean(xb);
  let cov = 0;
  for (let i = 0; i < n; i++) cov += ((xa[i] ?? 0) - ma) * ((xb[i] ?? 0) - mb);
  const denom = std(xa) * std(xb) * (n - 1);
  return denom ? cov / denom : 0;
}
