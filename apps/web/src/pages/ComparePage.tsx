import { useMemo } from "react";
import { useSearchParams } from "react-router";
import { LineChart } from "../components/charts/LineChart";
import { Banner } from "../components/ui/Banner";
import { Card, CardHeader } from "../components/ui/Card";
import { Change } from "../components/ui/Change";
import { PageHeader } from "../components/ui/PageHeader";
import { Segmented } from "../components/ui/Tabs";
import { cx } from "../components/ui/cx";
import { useI18n } from "../i18n/context";
import { useFormat } from "../lib/format";
import { PERIODS, isPeriod, slicePeriod, type Period } from "../lib/periods";
import { correlation, rebase, seriesStats, type SeriesStats } from "../lib/stats";
import { ASSETS, ASSET_HISTORY, COMPARABLE_ASSETS, INDEXES, findIndex, type AssetSymbol } from "../mock/market";

type Comparable = Exclude<AssetSymbol, "USDC">;

function isComparable(value: string | null): value is Comparable {
  return COMPARABLE_ASSETS.some((a) => a === value);
}

export function ComparePage() {
  const { t } = useI18n();
  const f = useFormat();
  const [params, setParams] = useSearchParams();

  // Selection lives in the URL, so a comparison can be shared as a link.
  const fallbackIndex = INDEXES[0];
  const index = findIndex(params.get("index") ?? undefined) ?? fallbackIndex;
  const assetParam = params.get("asset");
  const asset: Comparable = isComparable(assetParam) ? assetParam : "WBTC";
  const periodParam = params.get("period");
  const period: Period = isPeriod(periodParam) ? periodParam : "90d";

  const update = (key: string, value: string) => {
    const next = new URLSearchParams(params);
    next.set(key, value);
    setParams(next, { replace: true });
  };

  const data = useMemo(() => {
    if (!index) return null;
    const indexPoints = rebase(slicePeriod(index.history, period));
    const assetPoints = rebase(slicePeriod(ASSET_HISTORY[asset], period));
    return {
      indexPoints,
      assetPoints,
      indexStats: seriesStats(indexPoints),
      assetStats: seriesStats(assetPoints),
      corr: correlation(indexPoints, assetPoints),
    };
  }, [index, asset, period]);

  if (!index || !data) return null;

  const ticker = ASSETS[asset].ticker;
  const diff = data.indexStats.totalReturn - data.assetStats.totalReturn;

  const rows: { label: string; key: keyof SeriesStats; higherIsBetter: boolean }[] = [
    { label: t.compare.totalReturn, key: "totalReturn", higherIsBetter: true },
    { label: t.compare.volatility, key: "volatility", higherIsBetter: false },
    { label: t.compare.maxDrawdown, key: "maxDrawdown", higherIsBetter: true },
    { label: t.compare.bestDay, key: "bestDay", higherIsBetter: true },
    { label: t.compare.worstDay, key: "worstDay", higherIsBetter: true },
  ];

  const signed = (key: keyof SeriesStats) => key !== "volatility";

  return (
    <>
      <PageHeader title={t.compare.title} subtitle={t.compare.subtitle} />

      <Card className="mb-6">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-[1fr_1fr_auto] lg:items-end">
          <label className="block">
            <span className="mb-1.5 block text-xs font-medium text-navy-500">{t.compare.index}</span>
            <select value={index.address} onChange={(e) => update("index", e.target.value)} className="w-full">
              {INDEXES.map((i) => (
                <option key={i.address} value={i.address}>
                  {i.name} ({i.symbol})
                </option>
              ))}
            </select>
          </label>
          <label className="block">
            <span className="mb-1.5 block text-xs font-medium text-navy-500">{t.compare.asset}</span>
            <select value={asset} onChange={(e) => update("asset", e.target.value)} className="w-full">
              {COMPARABLE_ASSETS.map((a) => (
                <option key={a} value={a}>
                  {ASSETS[a].ticker} · {ASSETS[a].name}
                </option>
              ))}
            </select>
          </label>
          <div className="sm:col-span-2 lg:col-span-1">
            <span className="mb-1.5 block text-xs font-medium text-navy-500">{t.compare.period}</span>
            <Segmented
              label={t.compare.period}
              value={period}
              onChange={(p) => update("period", p)}
              items={PERIODS.map((p) => ({ id: p, label: t.compare.periods[p] }))}
            />
          </div>
        </div>
      </Card>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_360px]">
        <Card className="min-w-0">
          <CardHeader
            title={t.compare.performance}
            subtitle={
              diff >= 0
                ? t.compare.summaryBetter(index.symbol, ticker, f.pct(diff, false))
                : t.compare.summaryWorse(index.symbol, ticker, f.pct(-diff, false))
            }
          />
          <LineChart
            baseline={100}
            formatValue={(v) => f.number(v, 1)}
            series={[
              { id: "index", label: index.symbol, points: data.indexPoints, stroke: "stroke-brand-600", dot: "bg-brand-600", area: true },
              { id: "asset", label: ticker, points: data.assetPoints, stroke: "stroke-amber-500", dot: "bg-amber-500" },
            ]}
          />
        </Card>

        <Card className="min-w-0">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-navy-100 text-xs tracking-wide text-navy-500 uppercase">
                <th className="py-2 text-left font-medium">{t.compare.metric}</th>
                <th className="py-2 text-right font-medium">
                  <span className="inline-flex items-center gap-1.5">
                    <span className="size-2 rounded-full bg-brand-600" />
                    {index.symbol}
                  </span>
                </th>
                <th className="py-2 text-right font-medium">
                  <span className="inline-flex items-center gap-1.5">
                    <span className="size-2 rounded-full bg-amber-500" />
                    {ticker}
                  </span>
                </th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => {
                const a = data.indexStats[r.key];
                const b = data.assetStats[r.key];
                const indexWins = r.higherIsBetter ? a > b : a < b;
                return (
                  <tr key={r.key} className="border-b border-navy-100 last:border-0">
                    <td className="py-3 text-navy-700">{r.label}</td>
                    <td className={cx("py-3 text-right tabular-nums", indexWins && "font-semibold")}>
                      {signed(r.key) ? <Change value={a} /> : f.pct(a, false)}
                    </td>
                    <td className={cx("py-3 text-right tabular-nums", !indexWins && "font-semibold")}>
                      {signed(r.key) ? <Change value={b} /> : f.pct(b, false)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          <dl className="mt-4 grid grid-cols-2 gap-3">
            <div className="rounded-xl bg-navy-50 p-3">
              <dt className="text-xs text-navy-500">{t.compare.difference}</dt>
              <dd className="mt-1 text-lg">
                <Change value={diff} />
              </dd>
            </div>
            <div className="rounded-xl bg-navy-50 p-3">
              <dt className="text-xs text-navy-500">{t.compare.correlation}</dt>
              <dd className="mt-1 text-lg font-semibold text-navy-900 tabular-nums">{f.fixed(data.corr, 2)}</dd>
            </div>
          </dl>
        </Card>
      </div>

      <Banner tone="navy" icon="globe" title={t.common.demoData} className="mt-6">
        {t.compare.sourceNote}
      </Banner>
    </>
  );
}
