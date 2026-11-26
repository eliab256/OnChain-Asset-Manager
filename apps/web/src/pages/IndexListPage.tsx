import { useState } from "react";
import { useNavigate } from "react-router";
import { AssetPair } from "../components/charts/AssetPair";
import { WeightBar } from "../components/charts/WeightBar";
import { Card } from "../components/ui/Card";
import { Change } from "../components/ui/Change";
import { Icon } from "../components/ui/Icon";
import { PageHeader } from "../components/ui/PageHeader";
import { ResponsiveTable, type Column } from "../components/ui/ResponsiveTable";
import { StatTile } from "../components/ui/StatTile";
import { useI18n } from "../i18n/context";
import { useFormat } from "../lib/format";
import { ASSETS, INDEXES, pairLabel, type IndexInfo } from "../mock/market";

function Sparkline({ index }: { index: IndexInfo }) {
  const points = index.history.slice(-30);
  const values = points.map((p) => p.v);
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const d = points.map((p, i) => `${i === 0 ? "M" : "L"}${(i / (points.length - 1)) * 100},${30 - ((p.v - lo) / (hi - lo || 1)) * 28 - 1}`).join("");
  const up = (values.at(-1) ?? 0) >= (values[0] ?? 0);
  return (
    <svg viewBox="0 0 100 30" preserveAspectRatio="none" className="h-8 w-24" aria-hidden="true">
      <path d={d} fill="none" className={up ? "stroke-brand-600" : "stroke-loss-600"} strokeWidth={1.5} vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

export function IndexListPage() {
  const { t } = useI18n();
  const f = useFormat();
  const navigate = useNavigate();
  const [query, setQuery] = useState("");

  const q = query.trim().toLowerCase();
  const rows = INDEXES.filter(
    (i) =>
      !q ||
      [i.name, i.symbol, ...i.assets, ...i.assets.map((a) => ASSETS[a].ticker)].some((s) => s.toLowerCase().includes(q)),
  );

  const totalTvl = INDEXES.reduce((s, i) => s + i.tvl, 0);
  const holders = INDEXES.reduce((s, i) => s + i.holders, 0);
  const volume = INDEXES.reduce((s, i) => s + i.volume24h, 0);

  const nameCell = (i: IndexInfo) => (
    <div className="flex items-center gap-3">
      <AssetPair index={i} />
      <div className="min-w-0">
        <div className="truncate font-semibold text-navy-900">{i.name}</div>
        <div className="text-xs text-navy-500">
          {i.symbol} · {pairLabel(i)}
        </div>
      </div>
    </div>
  );

  const columns: Column<IndexInfo>[] = [
    { key: "name", header: t.indexList.title, cell: nameCell, hideOnMobile: true },
    { key: "nav", header: t.indexList.nav, align: "right", cell: (i) => <span className="font-semibold">{f.usd(i.navPerShare)}</span> },
    { key: "change", header: t.indexList.change24h, align: "right", cell: (i) => <Change value={i.change24h} /> },
    { key: "tvl", header: t.indexList.tvl, align: "right", cell: (i) => f.usdCompact(i.tvl) },
    {
      key: "composition",
      header: t.indexList.composition,
      mobileFull: true,
      cell: (i) => (
        <div className="w-full md:w-48">
          <WeightBar weights={i.currentWeights} labels={[ASSETS[i.assets[0]].ticker, ASSETS[i.assets[1]].ticker]} />
        </div>
      ),
    },
    { key: "spark", header: "30D", align: "right", cell: (i) => <Sparkline index={i} />, hideOnMobile: true },
  ];

  return (
    <>
      <PageHeader title={t.indexList.title} subtitle={t.indexList.subtitle} />

      <div className="mb-6 grid grid-cols-2 gap-3 sm:mb-8 lg:grid-cols-4">
        <StatTile label={t.indexList.totalTvl} value={f.usdCompact(totalTvl)} />
        <StatTile label={t.indexList.indexCount} value={INDEXES.length} />
        <StatTile label={t.indexList.holders} value={f.number(holders, 0)} />
        <StatTile label={t.indexList.volume24h} value={f.usdCompact(volume)} />
      </div>

      <Card padded={false} className="p-0 md:p-2">
        <div className="p-4 md:p-3">
          <label className="relative block sm:max-w-xs">
            <span className="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-navy-300">
              <Icon name="search" className="size-4" />
            </span>
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t.indexList.searchPlaceholder} className="w-full pl-9" />
          </label>
        </div>
        <div className="px-4 pb-4 md:px-0 md:pb-0">
          {rows.length === 0 ? (
            <p className="py-10 text-center text-sm text-navy-500">{t.indexList.noResults}</p>
          ) : (
            <ResponsiveTable
              columns={columns}
              rows={rows}
              rowKey={(i) => i.address}
              mobileTitle={nameCell}
              onRowClick={(i) => void navigate(`/index/${i.address}`)}
            />
          )}
        </div>
      </Card>
    </>
  );
}
